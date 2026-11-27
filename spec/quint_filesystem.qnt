// Logical filesystem effects of generation, evidence retention, and cleanup.
// Roots and path spellings are opaque labels. File entries hold opaque ITF
// bytes or an alias to another path. Caller entries are fixed, and a call owns
// the entries inside its fresh workspace.
module quint_filesystem {
  type Bytes = List[int]
  type TraceFiles = int -> Bytes

  type FilePath =
    | SavedFile(str)
    | WorkingFile({ workspace: int, trace: int })
    | EvidenceFile({ root: str, directory: int, trace: int })

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
    status: WorkspaceStatus,
  }

  type FileSystem = {
    files: FilePath -> Bytes,
    aliases: FilePath -> FilePath,
    workspaces: int -> WorkspaceFiles,
  }

  pure val emptyFileSystem: FileSystem = { files: Map(), aliases: Map(), workspaces: Map() }

  pure def workingPath(workspace: int, trace: int): FilePath =
    WorkingFile({ workspace: workspace, trace: trace })

  pure def evidencePath(root: str, workspace: int, trace: int): FilePath =
    EvidenceFile({ root: root, directory: workspace, trace: trace })

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
    workingTraces(fs.files.keys().union(fs.aliases.keys()), workspace)

  pure def workspaceAvailable(fs: FileSystem, workspace: int): bool =
    not(fs.workspaces.keys().contains(workspace))

  pure def canCreateWorkingAlias(fs: FileSystem, workspace: int, owner: int, trace: int): bool =
    if (workspaceAvailable(fs, workspace)) false else {
      val ws = fs.workspaces.get(workspace)
      ws.owner == owner and ws.status == WorkspaceActive and trace >= 0 and
        not(workingEntries(fs, workspace).contains(trace))
    }

  pure def createWorkingAlias(fs: FileSystem, workspace: int, trace: int, target: FilePath): FileSystem =
    { ...fs, aliases: fs.aliases.put(workingPath(workspace, trace), target) }

  pure def canReserveFiles(fs: FileSystem, workspace: int, owner: int): bool =
    workspaceAvailable(fs, workspace) and
      fs.workspaces.keys().forall(id => fs.workspaces.get(id).owner != owner)

  pure def reserveFiles(fs: FileSystem, workspace: int, owner: int, seed: List[str], root: str): FileSystem =
    { ...fs, workspaces: fs.workspaces.put(workspace, {
      owner: owner, seed: seed, root: root,
      output: NoGeneratedFiles, evidence: NoEvidence, status: WorkspaceActive,
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
        files.keys().forall(trace =>
          trace >= 0 and validBytes(files.get(trace)) and not(fs.aliases.keys().contains(workingPath(workspace, trace)))
        )
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

  pure def canStageEvidence(fs: FileSystem, workspace: int, trace: int): bool =
    if (canReadGeneratedFile(fs, workspace, trace))
      fs.workspaces.get(workspace).evidence == NoEvidence
    else false

  pure def withEvidence(fs: FileSystem, workspace: int, evidence: Evidence): FileSystem = {
    val ws = fs.workspaces.get(workspace)
    { ...fs, workspaces: fs.workspaces.put(workspace, { ...ws, evidence: evidence }) }
  }

  // Staging has no publicly retained path. Publication exposes the entire copy at once.
  pure def stageEvidence(fs: FileSystem, workspace: int, trace: int): FileSystem =
    withEvidence(fs, workspace, StagedEvidence({ trace: trace, bytes: List() }))

  pure def canWriteEvidence(fs: FileSystem, workspace: int, count: int): bool =
    if (workspaceAvailable(fs, workspace)) false else
      match fs.workspaces.get(workspace).evidence {
        | StagedEvidence(staged) =>
          count >= staged.bytes.length() and count <= fs.files.get(workingPath(workspace, staged.trace)).length()
        | _ => false
      }

  pure def writeEvidence(fs: FileSystem, workspace: int, count: int): FileSystem =
    match fs.workspaces.get(workspace).evidence {
      | StagedEvidence(staged) =>
        withEvidence(fs, workspace, StagedEvidence({
          trace: staged.trace, bytes: fs.files.get(workingPath(workspace, staged.trace)).slice(0, count),
        }))
      | _ => fs
    }

  pure def canPublishEvidence(fs: FileSystem, workspace: int): bool =
    if (workspaceAvailable(fs, workspace)) false else
      match fs.workspaces.get(workspace).evidence {
        | StagedEvidence(staged) => staged.bytes == fs.files.get(workingPath(workspace, staged.trace))
        | _ => false
      }

  pure def publishEvidence(fs: FileSystem, workspace: int): FileSystem = {
    val ws = fs.workspaces.get(workspace)
    match ws.evidence {
      | StagedEvidence(staged) => {
        val published = withEvidence(fs, workspace, PublishedEvidence(staged.trace))
        { ...published, files: fs.files.put(evidencePath(ws.root, workspace, staged.trace), staged.bytes) }
      }
      | _ => fs
    }
  }

  pure def canAbandonEvidence(fs: FileSystem, workspace: int): bool =
    if (workspaceAvailable(fs, workspace)) false else
      match fs.workspaces.get(workspace).evidence {
        | StagedEvidence(_) => true
        | _ => false
      }

  pure def abandonEvidence(fs: FileSystem, workspace: int): FileSystem =
    match fs.workspaces.get(workspace).evidence {
      | StagedEvidence(staged) => withEvidence(fs, workspace, AbandonedEvidence(staged.trace))
      | _ => fs
    }

  pure def canRetainTraceFile(fs: FileSystem, workspace: int, trace: int, copy: CopyOutcome): bool =
    if (canStageEvidence(fs, workspace, trace))
      match copy {
        | CopyComplete => true
        | CopyInterrupted(count) => 0 <= count and count <= fs.files.get(workingPath(workspace, trace)).length()
      }
    else false

  // The caller-facing storage outcome composes the internal copy transitions.
  pure def retainTraceFile(fs: FileSystem, workspace: int, trace: int, copy: CopyOutcome): FileSystem = {
    val staged = stageEvidence(fs, workspace, trace)
    match copy {
      | CopyComplete => publishEvidence(
        writeEvidence(staged, workspace, fs.files.get(workingPath(workspace, trace)).length()), workspace
      )
      | CopyInterrupted(count) => abandonEvidence(writeEvidence(staged, workspace, count), workspace)
    }
  }

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

  // Cleanup unlinks workspace entries by their own paths. An I/O error can
  // leave any subset of those entries behind.
  pure def cleanupFiles(fs: FileSystem, workspace: int, outcome: CleanupOutcome): FileSystem = {
    val ws = fs.workspaces.get(workspace)
    val remove = workingEntries(fs, workspace).exclude(remainingAfterCleanup(outcome))
      .map(trace => workingPath(workspace, trace))
    {
      files: fs.files.keys().exclude(remove).mapBy(path => fs.files.get(path)),
      aliases: fs.aliases.keys().exclude(remove).mapBy(path => fs.aliases.get(path)),
      workspaces: fs.workspaces.put(workspace, {
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

  pure def evidenceMatchesOutput(fs: FileSystem, workspace: int): bool = {
    val ws = fs.workspaces.get(workspace)
    val fromWorkspace = fs.files.keys().filter(path =>
      match path {
        | EvidenceFile(saved) => saved.directory == workspace
        | _ => false
      }
    )
    match ws.evidence {
      | NoEvidence => fromWorkspace.size() == 0
      | StagedEvidence(staged) =>
        fromWorkspace.size() == 0 and canReadGeneratedFile(fs, workspace, staged.trace) and
          staged.bytes == fs.files.get(workingPath(workspace, staged.trace)).slice(0, staged.bytes.length())
      | AbandonedEvidence(_) => fromWorkspace.size() == 0
      | PublishedEvidence(trace) => {
        val path = evidencePath(ws.root, workspace, trace)
        match ws.output {
          | GeneratedFiles(original) =>
            fromWorkspace == Set(path) and fs.files.get(path) == original.get(trace)
          | _ => false
        }
      }
    }
  }

  pure def fileWorkspaceExists(fs: FileSystem, path: FilePath): bool =
    match path {
      | WorkingFile(work) => fs.workspaces.keys().contains(work.workspace)
      | EvidenceFile(saved) => fs.workspaces.keys().contains(saved.directory)
      | SavedFile(_) => true
    }

  pure def aliasEntryIsValid(fs: FileSystem, path: FilePath): bool =
    match path {
      | SavedFile(_) => true
      | EvidenceFile(_) => false
      | WorkingFile(work) =>
        if (workspaceAvailable(fs, work.workspace)) false else
          work.trace >= 0 and fs.workspaces.get(work.workspace).status != WorkspaceRemoved
    }

  pure def fileSystemSafety(fs: FileSystem, initial: FileSystem): bool =
    and {
      savedFiles(fs) == savedFiles(initial),
      savedAliases(fs) == savedAliases(initial),
      fs.files.keys().intersect(fs.aliases.keys()).size() == 0,
      fs.aliases.keys().forall(path => aliasEntryIsValid(fs, path)),
      fs.files.keys().forall(path => fileWorkspaceExists(fs, path)),
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
  pure val trace: int = 1
  pure val bytesOfFirstCall: Bytes = List(123, 10, 125, 10)
  pure val bytesOfSecondCall: Bytes = List(123, 32, 125)
  pure val initialFiles: FileSystem = {
    ...emptyFileSystem, files: Map(SavedFile("trace-1.itf.json") -> List(255, 0)),
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
    nondet count = 0.to(4).oneOf()
    val otherWorkspace = if (workspace == 1) 2 else 1
    val bytes = if (workspace == 1) bytesOfFirstCall else bytesOfSecondCall
    any {
      reserve(workspace, workspace, List("4", "2"), root),
      generate(workspace, GeneratedFiles(Map(trace -> bytes, 2 -> List(0, 255)))),
      generate(workspace, AbortedFiles(Map(trace -> bytes.slice(0, 1)))),
      createWorkspaceAlias(workspace, workspace, 3, evidencePath(root, otherWorkspace, trace)),
      stage(workspace, trace),
      writeCopy(workspace, count),
      publish(workspace),
      abandon(workspace),
      retain(workspace, trace, CopyComplete),
      retain(workspace, trace, CopyInterrupted(count)),
      cleanup(workspace, RemoveComplete),
      cleanup(workspace, RemoveInterrupted(Set(trace))),
      cleanup(workspace, RemoveInterrupted(Set(3))),
    }
  }
}
