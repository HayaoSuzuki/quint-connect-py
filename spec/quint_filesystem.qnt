// Logical filesystem effects of generation, evidence retention, and cleanup.
// Roots and path spellings are opaque labels. An entry can hold ITF bytes,
// link to another path, or be an opaque private directory or special entry.
// Caller entries are fixed. A call owns its fresh workspace and may exclusively
// reserve a directory under its artifact root.
module quint_filesystem {
  type Bytes = List[int]
  type TraceFiles = int -> Bytes

  type ArtifactDirectory = { root: str, directory: int }
  type ArtifactDirectoryOwner = ExistingArtifactDirectory | OwnedArtifactDirectory(int)
  type ArtifactDirectoryReservation = NoArtifactDirectory | ArtifactDirectoryReserved(int)

  type FilePath =
    | SavedFile(str)
    | WorkingFile({ workspace: int, trace: int })
    | EvidenceFile({ root: str, directory: int, trace: int })

  // A private directory is one cleanup unit, including any contents.
  type WorkspaceNonFile = WorkspaceDirectory | WorkspaceSpecial

  type WorkspaceContents = {
    regular: TraceFiles,
    aliases: int -> FilePath,
    nonFiles: int -> WorkspaceNonFile,
  }

  pure def regularWorkspaceContents(files: TraceFiles): WorkspaceContents =
    { regular: files, aliases: Map(), nonFiles: Map() }

  type ResolutionFailure = MissingFile | AliasCycle
  type FileResolution = ResolvedFile(FilePath) | UnresolvedFile(ResolutionFailure)
  type FileRead = FileBytes(Bytes) | FileUnavailable(ResolutionFailure)

  type GenerationFiles = NoGeneratedFiles | GeneratedFiles(TraceFiles) | AbortedFiles(TraceFiles)

  type Evidence =
    | NoEvidence
    | StagedEvidence({ trace: int, bytes: Bytes })
    | PublishedEvidence(int)
    | AbandonedEvidence(int)

  type CopyOutcome = CopyComplete | CopyInterrupted(int)
  type CleanupOutcome = RemoveComplete | RemoveInterrupted(Set[int])
  type WorkspaceStatus = WorkspaceActive | WorkspaceRemoved | WorkspacePartiallyRemoved

  type WorkspaceFiles = {
    owner: int,
    seed: List[str],
    root: str,
    // Keep the generation manifest for comparison even after work files are gone.
    output: GenerationFiles,
    evidence: Evidence,
    artifactDirectory: ArtifactDirectoryReservation,
    status: WorkspaceStatus,
  }

  type FileSystem = {
    files: FilePath -> Bytes,
    aliases: FilePath -> FilePath,
    nonFiles: FilePath -> WorkspaceNonFile,
    workspaces: int -> WorkspaceFiles,
    artifactDirectories: ArtifactDirectory -> ArtifactDirectoryOwner,
  }

  pure val emptyFileSystem: FileSystem = {
    files: Map(), aliases: Map(), nonFiles: Map(), workspaces: Map(), artifactDirectories: Map(),
  }

  pure def workingPath(workspace: int, trace: int): FilePath =
    WorkingFile({ workspace: workspace, trace: trace })

  pure def evidencePath(root: str, directory: int, trace: int): FilePath =
    EvidenceFile({ root: root, directory: directory, trace: trace })

  pure def resolveFilePath(fs: FileSystem, path: FilePath): FileResolution = {
    val aliasPaths = fs.aliases.keys()
    // Each fold step can follow one alias. A path still pointing at an alias
    // after this many steps must have revisited an alias.
    val target = aliasPaths.fold(path, (current, _) =>
      if (aliasPaths.contains(current)) fs.aliases.get(current) else current
    )
    if (aliasPaths.contains(target)) UnresolvedFile(AliasCycle)
    else if (fs.files.keys().contains(target)) ResolvedFile(target)
    else UnresolvedFile(MissingFile)
  }

  pure def readFileBytes(fs: FileSystem, path: FilePath): FileRead =
    match resolveFilePath(fs, path) {
      | ResolvedFile(target) => FileBytes(fs.files.get(target))
      | UnresolvedFile(reason) => FileUnavailable(reason)
    }

  pure def savedPaths(paths: Set[FilePath]): Set[FilePath] =
    paths.filter(path =>
      match path {
        | SavedFile(_) => true
        | _ => false
      }
    )

  pure def savedFiles(fs: FileSystem): FilePath -> Bytes =
    savedPaths(fs.files.keys()).mapBy(path => fs.files.get(path))

  pure def savedAliases(fs: FileSystem): FilePath -> FilePath =
    savedPaths(fs.aliases.keys()).mapBy(path => fs.aliases.get(path))

  pure def workingTraces(paths: Set[FilePath], workspace: int): Set[int] =
    paths.fold(Set(), (traces, path) =>
      match path {
        | WorkingFile(work) =>
          if (work.workspace == workspace) traces.union(Set(work.trace)) else traces
        | _ => traces
      }
    )

  pure def workingFiles(fs: FileSystem, workspace: int): Set[int] =
    workingTraces(fs.files.keys(), workspace)

  pure def workingEntries(fs: FileSystem, workspace: int): Set[int] =
    workingTraces(fs.files.keys().union(fs.aliases.keys()).union(fs.nonFiles.keys()), workspace)

  pure def workingNonFiles(fs: FileSystem, workspace: int): int -> WorkspaceNonFile =
    workingTraces(fs.nonFiles.keys(), workspace).mapBy(trace => fs.nonFiles.get(workingPath(workspace, trace)))

  pure def workspaceAvailable(fs: FileSystem, workspace: int): bool =
    not(fs.workspaces.keys().contains(workspace))

  pure def canCreateWorkingEntry(fs: FileSystem, workspace: int, owner: int, trace: int): bool =
    if (workspaceAvailable(fs, workspace)) false else {
      val ws = fs.workspaces.get(workspace)
      ws.owner == owner and ws.status == WorkspaceActive and trace >= 0 and
        not(workingEntries(fs, workspace).contains(trace))
    }

  pure def canCreateWorkingAlias(fs: FileSystem, workspace: int, owner: int, trace: int): bool =
    canCreateWorkingEntry(fs, workspace, owner, trace)

  pure def createWorkingAlias(fs: FileSystem, workspace: int, trace: int, target: FilePath): FileSystem =
    { ...fs, aliases: fs.aliases.put(workingPath(workspace, trace), target) }

  pure def canCreateWorkingNonFile(fs: FileSystem, workspace: int, owner: int, trace: int): bool =
    canCreateWorkingEntry(fs, workspace, owner, trace)

  pure def createWorkingNonFile(fs: FileSystem, workspace: int, trace: int, kind: WorkspaceNonFile): FileSystem =
    { ...fs, nonFiles: fs.nonFiles.put(workingPath(workspace, trace), kind) }

  pure def canReserveFiles(fs: FileSystem, workspace: int, owner: int): bool =
    workspaceAvailable(fs, workspace) and
      fs.workspaces.keys().forall(id => fs.workspaces.get(id).owner != owner)

  pure def reserveFiles(fs: FileSystem, workspace: int, owner: int, seed: List[str], root: str): FileSystem =
    { ...fs, workspaces: fs.workspaces.put(workspace, {
      owner: owner, seed: seed, root: root,
      output: NoGeneratedFiles, evidence: NoEvidence, artifactDirectory: NoArtifactDirectory,
      status: WorkspaceActive,
    }) }

  pure def writtenFiles(output: GenerationFiles): TraceFiles =
    match output {
      | NoGeneratedFiles => Map()
      | GeneratedFiles(files) => files
      | AbortedFiles(files) => files
    }

  pure def validBytes(bytes: Bytes): bool =
    bytes.indices().forall(index => 0 <= bytes.nth(index) and bytes.nth(index) <= 255)

  pure def canRecordTraceFiles(fs: FileSystem, workspace: int, output: GenerationFiles): bool =
    if (workspaceAvailable(fs, workspace)) false else {
      val ws = fs.workspaces.get(workspace)
      val files = writtenFiles(output)
      ws.status == WorkspaceActive and ws.output == NoGeneratedFiles and output != NoGeneratedFiles and
        files.keys().intersect(workingEntries(fs, workspace)).size() == 0 and
        files.keys().forall(trace => trace >= 0 and validBytes(files.get(trace)))
    }

  pure def recordTraceFiles(fs: FileSystem, workspace: int, output: GenerationFiles): FileSystem = {
    val emitted = writtenFiles(output)
    val ws = fs.workspaces.get(workspace)
    {
      ...fs,
      files: emitted.keys().fold(fs.files, (files, trace) =>
        files.put(workingPath(workspace, trace), emitted.get(trace))
      ),
      workspaces: fs.workspaces.put(workspace, { ...ws, output: output }),
    }
  }

  pure def canRecordWorkspaceContents(
    fs: FileSystem, workspace: int, owner: int, output: GenerationFiles, contents: WorkspaceContents
  ): bool =
    if (not(canRecordTraceFiles(fs, workspace, output))) false
    else {
      val regular = contents.regular.keys()
      val aliases = contents.aliases.keys()
      val nonFiles = contents.nonFiles.keys()
      and {
        fs.workspaces.get(workspace).owner == owner,
        writtenFiles(output) == contents.regular,
        regular.intersect(aliases.union(nonFiles)).size() == 0,
        aliases.intersect(nonFiles).size() == 0,
        aliases.union(nonFiles).forall(trace => canCreateWorkingEntry(fs, workspace, owner, trace)),
      }
    }

  pure def recordWorkspaceContents(
    fs: FileSystem, workspace: int, output: GenerationFiles, contents: WorkspaceContents
  ): FileSystem = {
    val regular = recordTraceFiles(fs, workspace, output)
    val withAliases = contents.aliases.keys().fold(regular, (snapshot, trace) =>
      createWorkingAlias(snapshot, workspace, trace, contents.aliases.get(trace)))
    contents.nonFiles.keys().fold(withAliases, (snapshot, trace) =>
      createWorkingNonFile(snapshot, workspace, trace, contents.nonFiles.get(trace)))
  }

  // Aborted generation may leave work files, but callers never read them.
  pure def canReadGeneratedFile(fs: FileSystem, workspace: int, trace: int): bool =
    if (workspaceAvailable(fs, workspace)) false else {
      val ws = fs.workspaces.get(workspace)
      ws.status == WorkspaceActive and fs.files.keys().contains(workingPath(workspace, trace)) and
        match ws.output {
          | GeneratedFiles(files) => files.keys().contains(trace)
          | _ => false
        }
    }

  pure def artifactDirectoryAvailable(fs: FileSystem, root: str, candidate: int): bool =
    not(fs.artifactDirectories.keys().contains({ root: root, directory: candidate }))

  pure def canReserveArtifactDirectory(fs: FileSystem, workspace: int, candidate: int): bool =
    if (workspaceAvailable(fs, workspace)) false else {
      val ws = fs.workspaces.get(workspace)
      ws.status == WorkspaceActive and ws.evidence == NoEvidence and
        ws.artifactDirectory == NoArtifactDirectory and artifactDirectoryAvailable(fs, ws.root, candidate)
    }

  pure def reserveArtifactDirectory(fs: FileSystem, workspace: int, candidate: int): FileSystem =
    if (canReserveArtifactDirectory(fs, workspace, candidate)) {
      val ws = fs.workspaces.get(workspace)
      {
        ...fs,
        artifactDirectories: fs.artifactDirectories.put(
          { root: ws.root, directory: candidate }, OwnedArtifactDirectory(workspace)
        ),
        workspaces: fs.workspaces.put(workspace, { ...ws, artifactDirectory: ArtifactDirectoryReserved(candidate) }),
      }
    } else fs

  pure def ownsArtifactDirectory(fs: FileSystem, workspace: int): bool = {
    val ws = fs.workspaces.get(workspace)
    match ws.artifactDirectory {
      | NoArtifactDirectory => false
      | ArtifactDirectoryReserved(directory) => {
        val key = { root: ws.root, directory: directory }
        if (fs.artifactDirectories.keys().contains(key))
          fs.artifactDirectories.get(key) == OwnedArtifactDirectory(workspace)
        else false
      }
    }
  }

  pure def releaseArtifactDirectory(fs: FileSystem, workspace: int): FileSystem = {
    val ws = fs.workspaces.get(workspace)
    match ws.artifactDirectory {
      | NoArtifactDirectory => fs
      | ArtifactDirectoryReserved(directory) => {
        val key = { root: ws.root, directory: directory }
        {
          ...fs,
          artifactDirectories: fs.artifactDirectories.keys().exclude(Set(key))
            .mapBy(remaining => fs.artifactDirectories.get(remaining)),
          workspaces: fs.workspaces.put(workspace, { ...ws, artifactDirectory: NoArtifactDirectory }),
        }
      }
    }
  }

  pure def canStageReservedEvidence(fs: FileSystem, workspace: int, trace: int): bool =
    if (canReadGeneratedFile(fs, workspace, trace))
      fs.workspaces.get(workspace).evidence == NoEvidence and ownsArtifactDirectory(fs, workspace)
    else false

  pure def withEvidence(fs: FileSystem, workspace: int, evidence: Evidence): FileSystem = {
    val ws = fs.workspaces.get(workspace)
    { ...fs, workspaces: fs.workspaces.put(workspace, { ...ws, evidence: evidence }) }
  }

  // Staging has no publicly retained path. Publication exposes the entire copy at once.
  pure def stageReservedEvidence(fs: FileSystem, workspace: int, trace: int): FileSystem =
    if (canStageReservedEvidence(fs, workspace, trace))
      withEvidence(fs, workspace, StagedEvidence({ trace: trace, bytes: List() }))
    else fs

  // The default candidate preserves the one-step staging helper.
  pure def canStageEvidence(fs: FileSystem, workspace: int, trace: int): bool =
    canReadGeneratedFile(fs, workspace, trace) and canReserveArtifactDirectory(fs, workspace, workspace)

  pure def stageEvidence(fs: FileSystem, workspace: int, trace: int): FileSystem =
    if (canStageEvidence(fs, workspace, trace))
      stageReservedEvidence(reserveArtifactDirectory(fs, workspace, workspace), workspace, trace)
    else fs

  pure def canWriteEvidence(fs: FileSystem, workspace: int, count: int): bool =
    if (workspaceAvailable(fs, workspace)) false else
      match fs.workspaces.get(workspace).evidence {
        | StagedEvidence(staged) =>
          ownsArtifactDirectory(fs, workspace) and
            count >= staged.bytes.length() and count <= fs.files.get(workingPath(workspace, staged.trace)).length()
        | _ => false
      }

  pure def writeEvidence(fs: FileSystem, workspace: int, count: int): FileSystem =
    if (canWriteEvidence(fs, workspace, count))
      match fs.workspaces.get(workspace).evidence {
        | StagedEvidence(staged) =>
          withEvidence(fs, workspace, StagedEvidence({
            trace: staged.trace, bytes: fs.files.get(workingPath(workspace, staged.trace)).slice(0, count),
          }))
        | _ => fs
      }
    else fs

  pure def canPublishEvidence(fs: FileSystem, workspace: int): bool =
    if (workspaceAvailable(fs, workspace)) false else
      match fs.workspaces.get(workspace).evidence {
        | StagedEvidence(staged) =>
          ownsArtifactDirectory(fs, workspace) and staged.bytes == fs.files.get(workingPath(workspace, staged.trace))
        | _ => false
      }

  pure def publishEvidence(fs: FileSystem, workspace: int): FileSystem =
    if (canPublishEvidence(fs, workspace)) {
      val ws = fs.workspaces.get(workspace)
      match ws.evidence {
        | StagedEvidence(staged) =>
          match ws.artifactDirectory {
            | ArtifactDirectoryReserved(directory) => {
              val published = withEvidence(fs, workspace, PublishedEvidence(staged.trace))
              { ...published, files: fs.files.put(evidencePath(ws.root, directory, staged.trace), staged.bytes) }
            }
            | NoArtifactDirectory => fs
          }
        | _ => fs
      }
    } else fs

  pure def canAbandonEvidence(fs: FileSystem, workspace: int): bool =
    if (workspaceAvailable(fs, workspace)) false else
      match fs.workspaces.get(workspace).evidence {
        | StagedEvidence(_) => ownsArtifactDirectory(fs, workspace)
        | _ => false
      }

  pure def abandonEvidence(fs: FileSystem, workspace: int): FileSystem =
    if (canAbandonEvidence(fs, workspace))
      match fs.workspaces.get(workspace).evidence {
        | StagedEvidence(staged) => releaseArtifactDirectory(
          withEvidence(fs, workspace, AbandonedEvidence(staged.trace)), workspace
        )
        | _ => fs
      }
    else fs

  pure def copyCountAllowed(fs: FileSystem, workspace: int, trace: int, copy: CopyOutcome): bool =
    match copy {
      | CopyComplete => true
      | CopyInterrupted(count) => 0 <= count and count <= fs.files.get(workingPath(workspace, trace)).length()
    }

  pure def canRetainReservedTraceFile(fs: FileSystem, workspace: int, trace: int, copy: CopyOutcome): bool =
    if (canStageReservedEvidence(fs, workspace, trace)) copyCountAllowed(fs, workspace, trace, copy)
    else false

  pure def canRetainTraceFile(fs: FileSystem, workspace: int, trace: int, copy: CopyOutcome): bool =
    if (canStageEvidence(fs, workspace, trace)) copyCountAllowed(fs, workspace, trace, copy)
    else false

  // The caller-facing storage outcome composes the internal copy transitions.
  pure def retainReservedTraceFile(fs: FileSystem, workspace: int, trace: int, copy: CopyOutcome): FileSystem =
    if (canRetainReservedTraceFile(fs, workspace, trace, copy)) {
      val staged = stageReservedEvidence(fs, workspace, trace)
      match copy {
        | CopyComplete => publishEvidence(
          writeEvidence(staged, workspace, fs.files.get(workingPath(workspace, trace)).length()), workspace
        )
        | CopyInterrupted(count) => abandonEvidence(writeEvidence(staged, workspace, count), workspace)
      }
    } else fs

  pure def retainTraceFile(fs: FileSystem, workspace: int, trace: int, copy: CopyOutcome): FileSystem =
    if (canRetainTraceFile(fs, workspace, trace, copy))
      retainReservedTraceFile(reserveArtifactDirectory(fs, workspace, workspace), workspace, trace, copy)
    else fs

  pure def remainingAfterCleanup(outcome: CleanupOutcome): Set[int] =
    match outcome {
      | RemoveComplete => Set()
      | RemoveInterrupted(remaining) => remaining
    }

  pure def canCleanupFiles(fs: FileSystem, workspace: int, outcome: CleanupOutcome): bool =
    if (workspaceAvailable(fs, workspace)) false else {
      val ws = fs.workspaces.get(workspace)
      ws.status == WorkspaceActive and ws.output != NoGeneratedFiles and
        not(canAbandonEvidence(fs, workspace)) and
        remainingAfterCleanup(outcome).subseteq(workingEntries(fs, workspace))
    }

  // Cleanup removes workspace entries by their own paths. Aliases are
  // unlinked without resolving them. An I/O error can leave any subset behind.
  pure def cleanupFiles(fs: FileSystem, workspace: int, outcome: CleanupOutcome): FileSystem = {
    val withoutEmptyReservation =
      if (fs.workspaces.get(workspace).evidence == NoEvidence) releaseArtifactDirectory(fs, workspace)
      else fs
    val ws = withoutEmptyReservation.workspaces.get(workspace)
    val remove = workingEntries(fs, workspace).exclude(remainingAfterCleanup(outcome))
      .map(trace => workingPath(workspace, trace))
    {
      ...withoutEmptyReservation,
      files: fs.files.keys().exclude(remove).mapBy(path => fs.files.get(path)),
      aliases: fs.aliases.keys().exclude(remove).mapBy(path => fs.aliases.get(path)),
      nonFiles: fs.nonFiles.keys().exclude(remove).mapBy(path => fs.nonFiles.get(path)),
      workspaces: withoutEmptyReservation.workspaces.put(workspace, {
        ...ws,
        status: if (outcome == RemoveComplete) WorkspaceRemoved else WorkspacePartiallyRemoved,
      }),
    }
  }

  pure def workingFilesMatchOutput(fs: FileSystem, workspace: int): bool = {
    val ws = fs.workspaces.get(workspace)
    val traces = workingFiles(fs, workspace)
    val original = writtenFiles(ws.output)
    and {
      traces.subseteq(original.keys()),
      traces.forall(trace => fs.files.get(workingPath(workspace, trace)) == original.get(trace)),
      ws.status == WorkspaceActive implies traces == original.keys(),
      ws.status == WorkspaceRemoved implies traces.size() == 0,
    }
  }

  pure def artifactDirectoryFiles(fs: FileSystem, directory: ArtifactDirectory): Set[FilePath] =
    fs.files.keys().filter(path =>
      match path {
        | EvidenceFile(saved) => saved.root == directory.root and saved.directory == directory.directory
        | _ => false
      }
    )

  pure def evidenceMatchesOutput(fs: FileSystem, workspace: int): bool = {
    val ws = fs.workspaces.get(workspace)
    match ws.artifactDirectory {
      | NoArtifactDirectory =>
        match ws.evidence {
          | NoEvidence => true
          | AbandonedEvidence(_) => true
          | _ => false
        }
      | ArtifactDirectoryReserved(directory) => {
        val entries = artifactDirectoryFiles(fs, { root: ws.root, directory: directory })
        ownsArtifactDirectory(fs, workspace) and
          match ws.evidence {
            | NoEvidence => ws.status == WorkspaceActive and entries.size() == 0
            | StagedEvidence(staged) =>
              entries.size() == 0 and canReadGeneratedFile(fs, workspace, staged.trace) and
                staged.bytes == fs.files.get(workingPath(workspace, staged.trace)).slice(0, staged.bytes.length())
            | AbandonedEvidence(_) => false
            | PublishedEvidence(trace) => {
              val path = evidencePath(ws.root, directory, trace)
              match ws.output {
                | GeneratedFiles(original) =>
                  entries == Set(path) and original.keys().contains(trace) and fs.files.get(path) == original.get(trace)
                | _ => false
              }
            }
          }
      }
    }
  }

  pure def artifactDirectoryIsValid(fs: FileSystem, initial: FileSystem, directory: ArtifactDirectory): bool =
    match fs.artifactDirectories.get(directory) {
      | ExistingArtifactDirectory => {
        val originalEntries = artifactDirectoryFiles(initial, directory)
        initial.artifactDirectories.keys().contains(directory) and
          initial.artifactDirectories.get(directory) == ExistingArtifactDirectory and
          artifactDirectoryFiles(fs, directory) == originalEntries and
          originalEntries.forall(path => fs.files.get(path) == initial.files.get(path))
      }
      | OwnedArtifactDirectory(workspace) =>
        if (workspaceAvailable(fs, workspace)) false else {
          val ws = fs.workspaces.get(workspace)
          ws.root == directory.root and ws.artifactDirectory == ArtifactDirectoryReserved(directory.directory)
        }
    }

  pure def fileDirectoryExists(fs: FileSystem, path: FilePath): bool =
    match path {
      | WorkingFile(work) => fs.workspaces.keys().contains(work.workspace)
      | EvidenceFile(saved) => fs.artifactDirectories.keys().contains({ root: saved.root, directory: saved.directory })
      | SavedFile(_) => true
    }

  pure def workingEntryIsValid(fs: FileSystem, path: FilePath): bool =
    match path {
      | WorkingFile(work) =>
        if (workspaceAvailable(fs, work.workspace)) false else
          work.trace >= 0 and fs.workspaces.get(work.workspace).status != WorkspaceRemoved
      | _ => false
    }

  pure def aliasEntryIsValid(fs: FileSystem, path: FilePath): bool =
    match path {
      | SavedFile(_) => true
      | _ => workingEntryIsValid(fs, path)
    }

  pure def fileSystemSafety(fs: FileSystem, initial: FileSystem): bool =
    and {
      savedFiles(fs) == savedFiles(initial),
      savedAliases(fs) == savedAliases(initial),
      fs.files.keys().intersect(fs.aliases.keys()).size() == 0,
      fs.nonFiles.keys().intersect(fs.files.keys().union(fs.aliases.keys())).size() == 0,
      fs.nonFiles.keys().forall(path => workingEntryIsValid(fs, path)),
      fs.aliases.keys().forall(path => aliasEntryIsValid(fs, path)),
      fs.files.keys().forall(path => fileDirectoryExists(fs, path)),
      initial.artifactDirectories.keys().forall(directory =>
        if (initial.artifactDirectories.get(directory) == ExistingArtifactDirectory)
          not(artifactDirectoryAvailable(fs, directory.root, directory.directory)) and
            fs.artifactDirectories.get(directory) == ExistingArtifactDirectory
        else true
      ),
      fs.artifactDirectories.keys().forall(directory => artifactDirectoryIsValid(fs, initial, directory)),
      fs.workspaces.keys().forall(workspace =>
        workingFilesMatchOutput(fs, workspace) and evidenceMatchesOutput(fs, workspace)
      ),
      fs.workspaces.keys().forall(first =>
        fs.workspaces.keys().forall(second =>
          first != second implies fs.workspaces.get(first).owner != fs.workspaces.get(second).owner
        )
      ),
    }
}

module quint_filesystem_sample {
  import quint_filesystem.*

  pure val root: str = "/artifacts"
  pure val alternateRoot: str = "/alternate"
  pure val occupiedDirectory: int = 3
  pure val emptyOccupiedDirectory: int = 4
  pure val trace: int = 1
  pure val bytesOfFirstCall: Bytes = List(123, 10, 125, 10)
  pure val bytesOfSecondCall: Bytes = List(123, 32, 125)
  pure val initialFiles: FileSystem = {
    ...emptyFileSystem,
    files: Map(
      SavedFile("trace-1.itf.json") -> List(255, 0),
      evidencePath(root, occupiedDirectory, trace) -> List(8, 16),
    ),
    artifactDirectories: Map(
      { root: root, directory: occupiedDirectory } -> ExistingArtifactDirectory,
      { root: root, directory: emptyOccupiedDirectory } -> ExistingArtifactDirectory,
    ),
  }

  var filesystem: FileSystem

  action init: bool = filesystem' = initialFiles

  action reserve(workspace: int, owner: int, seed: List[str], root: str): bool = all {
    canReserveFiles(filesystem, workspace, owner),
    filesystem' = reserveFiles(filesystem, workspace, owner, seed, root),
  }

  action generate(workspace: int, output: GenerationFiles): bool = all {
    canRecordTraceFiles(filesystem, workspace, output),
    filesystem' = recordTraceFiles(filesystem, workspace, output),
  }

  action createWorkspaceAlias(workspace: int, owner: int, trace: int, target: FilePath): bool = all {
    canCreateWorkingAlias(filesystem, workspace, owner, trace),
    filesystem' = createWorkingAlias(filesystem, workspace, trace, target),
  }

  action createWorkspaceNonFile(workspace: int, owner: int, trace: int, kind: WorkspaceNonFile): bool = all {
    canCreateWorkingNonFile(filesystem, workspace, owner, trace),
    filesystem' = createWorkingNonFile(filesystem, workspace, trace, kind),
  }

  action reserveArtifact(workspace: int, candidate: int): bool = all {
    canReserveArtifactDirectory(filesystem, workspace, candidate),
    filesystem' = reserveArtifactDirectory(filesystem, workspace, candidate),
  }

  action stageReserved(workspace: int, trace: int): bool = all {
    canStageReservedEvidence(filesystem, workspace, trace),
    filesystem' = stageReservedEvidence(filesystem, workspace, trace),
  }

  action stage(workspace: int, trace: int): bool = all {
    canStageEvidence(filesystem, workspace, trace),
    filesystem' = stageEvidence(filesystem, workspace, trace),
  }

  action writeCopy(workspace: int, count: int): bool = all {
    canWriteEvidence(filesystem, workspace, count),
    filesystem' = writeEvidence(filesystem, workspace, count),
  }

  action publish(workspace: int): bool = all {
    canPublishEvidence(filesystem, workspace),
    filesystem' = publishEvidence(filesystem, workspace),
  }

  action abandon(workspace: int): bool = all {
    canAbandonEvidence(filesystem, workspace),
    filesystem' = abandonEvidence(filesystem, workspace),
  }

  action retain(workspace: int, trace: int, copy: CopyOutcome): bool = all {
    canRetainTraceFile(filesystem, workspace, trace, copy),
    filesystem' = retainTraceFile(filesystem, workspace, trace, copy),
  }

  action cleanup(workspace: int, outcome: CleanupOutcome): bool = all {
    canCleanupFiles(filesystem, workspace, outcome),
    filesystem' = cleanupFiles(filesystem, workspace, outcome),
  }

  val safety: bool = fileSystemSafety(filesystem, initialFiles)

  action step: bool = {
    nondet workspace = Set(1, 2).oneOf()
    val otherWorkspace = if (workspace == 1) 2 else 1
    val bytes = if (workspace == 1) bytesOfFirstCall else bytesOfSecondCall
    any {
      {
        nondet artifactRoot = Set(root, alternateRoot).oneOf()
        reserve(workspace, workspace, List("4", "2"), artifactRoot)
      },
      generate(workspace, GeneratedFiles(Map(trace -> bytes, 2 -> List(0, 255)))),
      generate(workspace, AbortedFiles(Map(trace -> bytes.slice(0, 1)))),
      createWorkspaceAlias(workspace, workspace, 3, evidencePath(root, otherWorkspace, trace)),
      createWorkspaceNonFile(workspace, workspace, 4, WorkspaceDirectory),
      createWorkspaceNonFile(workspace, workspace, 5, WorkspaceSpecial),
      {
        nondet candidate = Set(1, 2, occupiedDirectory, emptyOccupiedDirectory).oneOf()
        reserveArtifact(workspace, candidate)
      },
      stageReserved(workspace, trace),
      stage(workspace, trace),
      {
        nondet count = 0.to(4).oneOf()
        writeCopy(workspace, count)
      },
      publish(workspace),
      abandon(workspace),
      retain(workspace, trace, CopyComplete),
      {
        nondet count = 0.to(4).oneOf()
        retain(workspace, trace, CopyInterrupted(count))
      },
      cleanup(workspace, RemoveComplete),
      cleanup(workspace, RemoveInterrupted(Set(trace))),
      cleanup(workspace, RemoveInterrupted(Set(3))),
      cleanup(workspace, RemoveInterrupted(Set(4))),
      cleanup(workspace, RemoveInterrupted(Set(3, 4, 5))),
    }
  }
}
