module quint_filesystem_test {
  import quint_filesystem.* from "./quint_filesystem"
  import quint_filesystem_sample.* from "./quint_filesystem"

  pure val firstTrace: FilePath = workingPath(1, trace)
  pure val secondTrace: FilePath = workingPath(2, trace)
  pure val firstArtifact: FilePath = evidencePath(root, 1, trace)
  pure val secondArtifact: FilePath = evidencePath(root, 2, trace)
  pure val callerFile: FilePath = SavedFile("trace-1.itf.json")
  pure val firstAlias: FilePath = workingPath(1, 3)
  pure val secondAlias: FilePath = workingPath(1, 4)
  pure val otherOwnerAlias: FilePath = workingPath(2, 3)

  action reserveAndGenerate(workspace: int, bytes: Bytes): bool =
    reserve(workspace, workspace, List("4", "2"), root)
      .then(generate(workspace, GeneratedFiles(Map(trace -> bytes, 2 -> List(0, 255)))))

  run callsWithSameSeedRootAndTraceNumbersRetainTheirOwnBytesTest =
    init
      .then(reserve(1, 1, List("4", "2"), root))
      .then(reserve(2, 2, List("4", "2"), root))
      .then(generate(2, GeneratedFiles(Map(trace -> bytesOfSecondCall, 2 -> List(24)))))
      .then(generate(1, GeneratedFiles(Map(trace -> bytesOfFirstCall, 2 -> List(42)))))
      .then(stage(1, trace))
      .then(writeCopy(1, 2))
      .then(retain(2, trace, CopyComplete))
      .expect(not(filesystem.files.keys().contains(firstArtifact)) and
        filesystem.files.get(secondArtifact) == bytesOfSecondCall and safety)
      .then(cleanup(2, RemoveComplete))
      .expect(filesystem.files.get(firstTrace) == bytesOfFirstCall and
        not(filesystem.files.keys().contains(secondTrace)) and safety)
      .then(writeCopy(1, bytesOfFirstCall.length()))
      .then(publish(1))
      .then(cleanup(1, RemoveComplete))
      .expect(filesystem.files == initialFiles.files
        .put(firstArtifact, bytesOfFirstCall)
        .put(secondArtifact, bytesOfSecondCall) and safety)

  run onlyTheOwnerCanRecordRegularOrEmptyProcessOutputTest = {
    val regular = regularWorkspaceContents(Map(trace -> bytesOfFirstCall))
    val empty = regularWorkspaceContents(Map())
    init
      .then(reserve(1, 1, List("4", "2"), root))
      .expect(canRecordWorkspaceContents(filesystem, 1, 1, GeneratedFiles(regular.regular), regular) and
        not(canRecordWorkspaceContents(filesystem, 1, 2, GeneratedFiles(regular.regular), regular)) and
        not(canRecordWorkspaceContents(filesystem, 1, 2, AbortedFiles(Map()), empty)) and
        not(canRecordWorkspaceContents(filesystem, 2, 2, AbortedFiles(Map()), empty)) and safety)
  }

  run partiallyWrittenEvidenceIsNeverPublishedTest =
    init
      .then(reserveAndGenerate(1, bytesOfFirstCall))
      .then(stage(1, trace))
      .then(writeCopy(1, 2))
      .expect(filesystem.workspaces.get(1).evidence == StagedEvidence({ trace: trace, bytes: List(123, 10) }))
      .expect(not(filesystem.files.keys().contains(firstArtifact)) and
        not(canPublishEvidence(filesystem, 1)) and
        not(canCleanupFiles(filesystem, 1, RemoveComplete)) and safety)
      .then(abandon(1))
      .expect(filesystem.workspaces.get(1).evidence == AbandonedEvidence(trace) and
        filesystem.files.get(firstTrace) == bytesOfFirstCall and
        not(filesystem.files.keys().contains(firstArtifact)) and safety)
      .then(cleanup(1, RemoveComplete))
      .expect(filesystem.files == initialFiles.files and safety)

  run failedPublicationKeepsCompleteStagingPrivateTest =
    init
      .then(reserveAndGenerate(1, bytesOfFirstCall))
      .then(stage(1, trace))
      .then(writeCopy(1, bytesOfFirstCall.length()))
      .expect(canPublishEvidence(filesystem, 1) and
        not(filesystem.files.keys().contains(firstArtifact)) and safety)
      .then(abandon(1))
      .then(cleanup(1, RemoveComplete))
      .expect(filesystem.files == initialFiles.files and safety)

  run failedGenerationOutputCannotBeReplayedOrRetainedTest =
    init
      .then(reserve(1, 1, List("4", "2"), root))
      .then(generate(1, AbortedFiles(Map(trace -> List(123)))))
      .expect(filesystem.files.get(firstTrace) == List(123) and
        not(canReadGeneratedFile(filesystem, 1, trace)) and
        not(canRetainTraceFile(filesystem, 1, trace, CopyComplete)) and safety)
      .then(cleanup(1, RemoveComplete))
      .expect(filesystem.files == initialFiles.files and safety)

  run interruptedCleanupPreservesRetainedAndUnrelatedFilesTest =
    init
      .then(reserveAndGenerate(1, bytesOfFirstCall))
      .then(reserveAndGenerate(2, bytesOfSecondCall))
      .then(retain(1, trace, CopyComplete))
      .then(retain(2, trace, CopyComplete))
      .then(cleanup(1, RemoveInterrupted(Set(2))))
      .expect(filesystem.workspaces.get(1).status == WorkspacePartiallyRemoved and
        filesystem.files == initialFiles.files
          .put(workingPath(1, 2), List(0, 255))
          .put(secondTrace, bytesOfSecondCall)
          .put(workingPath(2, 2), List(0, 255))
          .put(firstArtifact, bytesOfFirstCall)
          .put(secondArtifact, bytesOfSecondCall) and safety)
      .then(cleanup(2, RemoveComplete))
      .expect(filesystem.files == initialFiles.files
        .put(workingPath(1, 2), List(0, 255))
        .put(firstArtifact, bytesOfFirstCall)
        .put(secondArtifact, bytesOfSecondCall) and safety)

  run workspaceIdentityCannotBeReassignedTest =
    init
      .then(reserveAndGenerate(1, bytesOfFirstCall))
      .expect(not(canReserveFiles(filesystem, 1, 2)) and
        not(canReserveFiles(filesystem, 2, 1)) and safety)
      .then(cleanup(1, RemoveComplete))
      .then(reserve(2, 2, List("4", "2"), root))
      .expect(not(canReserveFiles(filesystem, 1, 3)) and safety)

  run emptyGenerationHasNoReadableWorkFileTest =
    init
      .then(reserve(1, 1, List("4", "2"), root))
      .then(generate(1, GeneratedFiles(Map())))
      .expect(not(canReadGeneratedFile(filesystem, 1, trace)) and safety)
      .then(cleanup(1, RemoveComplete))
      .expect(filesystem.files == initialFiles.files and safety)

  run savedAliasesResolveChainsTest = {
    val alias = SavedFile("alias.itf.json")
    val chainedAlias = SavedFile("chain.itf.json")
    val snapshot = {
      ...initialFiles,
      aliases: Map(chainedAlias -> alias, alias -> callerFile),
    }
    all {
      resolveFilePath(snapshot, callerFile) == ResolvedFile(callerFile),
      resolveFilePath(snapshot, chainedAlias) == ResolvedFile(callerFile),
      readFileBytes(snapshot, chainedAlias) == FileBytes(List(255, 0)),
    }
  }

  run danglingAndCyclicAliasesHaveDistinctReadFailuresTest = {
    val dangling = SavedFile("dangling.itf.json")
    val missing = SavedFile("missing.itf.json")
    val loopA = SavedFile("loop-a.itf.json")
    val loopB = SavedFile("loop-b.itf.json")
    val self = SavedFile("self.itf.json")
    val snapshot = {
      ...initialFiles,
      aliases: Map(dangling -> missing, loopA -> loopB, loopB -> loopA, self -> self),
    }
    all {
      readFileBytes(snapshot, missing) == FileUnavailable(MissingFile),
      readFileBytes(snapshot, dangling) == FileUnavailable(MissingFile),
      readFileBytes(snapshot, loopA) == FileUnavailable(AliasCycle),
      readFileBytes(snapshot, self) == FileUnavailable(AliasCycle),
    }
  }

  run workspaceAliasRequiresAnUnusedNameInTheOwnersWorkspaceTest =
    init
      .then(reserve(1, 1, List("4", "2"), root))
      .expect(not(canCreateWorkingAlias(filesystem, 1, 2, 3)))
      .then(createWorkspaceAlias(1, 1, 3, callerFile))
      .expect(not(canCreateWorkingAlias(filesystem, 1, 1, 3)) and
        not(canRecordTraceFiles(filesystem, 1, GeneratedFiles(Map(3 -> bytesOfFirstCall)))))
      .then(generate(1, GeneratedFiles(Map(trace -> bytesOfFirstCall))))
      .expect(not(canCreateWorkingAlias(filesystem, 1, 1, trace)) and
        not(canReadGeneratedFile(filesystem, 1, 3)) and safety)

  run completeCleanupUnlinksAliasesAndPreservesTheirTargetsTest =
    init
      .then(reserveAndGenerate(1, bytesOfFirstCall))
      .then(reserveAndGenerate(2, bytesOfSecondCall))
      .then(retain(2, trace, CopyComplete))
      .then(createWorkspaceAlias(2, 2, 3, callerFile))
      .then(createWorkspaceAlias(1, 1, 3, secondArtifact))
      .then(createWorkspaceAlias(1, 1, 4, otherOwnerAlias))
      .expect(readFileBytes(filesystem, firstAlias) == FileBytes(bytesOfSecondCall) and
        readFileBytes(filesystem, secondAlias) == FileBytes(List(255, 0)) and safety)
      .then(cleanup(1, RemoveComplete))
      .expect(filesystem.aliases == Map(otherOwnerAlias -> callerFile) and
        readFileBytes(filesystem, firstAlias) == FileUnavailable(MissingFile) and
        readFileBytes(filesystem, secondAlias) == FileUnavailable(MissingFile) and
        readFileBytes(filesystem, secondArtifact) == FileBytes(bytesOfSecondCall) and
        readFileBytes(filesystem, otherOwnerAlias) == FileBytes(List(255, 0)) and safety)

  run interruptedCleanupKeepsOnlyNamedWorkspaceEntriesTest =
    init
      .then(reserveAndGenerate(1, bytesOfFirstCall))
      .then(reserveAndGenerate(2, bytesOfSecondCall))
      .then(retain(2, trace, CopyComplete))
      .then(createWorkspaceAlias(1, 1, 3, secondArtifact))
      .then(createWorkspaceAlias(1, 1, 4, callerFile))
      .then(cleanup(1, RemoveInterrupted(Set(2, 3))))
      .expect(filesystem.workspaces.get(1).status == WorkspacePartiallyRemoved and
        workingEntries(filesystem, 1) == Set(2, 3) and
        readFileBytes(filesystem, firstAlias) == FileBytes(bytesOfSecondCall) and
        readFileBytes(filesystem, secondAlias) == FileUnavailable(MissingFile) and
        readFileBytes(filesystem, callerFile) == FileBytes(List(255, 0)) and safety)

  run workspaceNonFilesOccupyTheSameSlotsAsFilesAndAliasesTest =
    init
      .expect(not(canCreateWorkingNonFile(filesystem, 1, 1, 5)))
      .then(reserve(1, 1, List("4", "2"), root))
      .expect(not(canCreateWorkingNonFile(filesystem, 1, 2, 5)) and
        not(canCreateWorkingNonFile(filesystem, 1, 1, -1)))
      .then(createWorkspaceNonFile(1, 1, 5, WorkspaceDirectory))
      .expect(not(canCreateWorkingNonFile(filesystem, 1, 1, 5)) and
        not(canCreateWorkingAlias(filesystem, 1, 1, 5)) and
        not(canRecordTraceFiles(filesystem, 1, GeneratedFiles(Map(5 -> bytesOfFirstCall)))))
      .then(createWorkspaceAlias(1, 1, 6, callerFile))
      .then(generate(1, GeneratedFiles(Map(trace -> bytesOfFirstCall))))
      .expect(not(canCreateWorkingNonFile(filesystem, 1, 1, trace)) and
        not(canCreateWorkingNonFile(filesystem, 1, 1, 6)) and
        not(canReadGeneratedFile(filesystem, 1, 5)) and
        workingEntries(filesystem, 1) == Set(trace, 5, 6) and safety)

  run interruptedCleanupRetainsOnlySpecifiedOwnedEntriesTest =
    init
      .then(reserveAndGenerate(1, bytesOfFirstCall))
      .then(reserveAndGenerate(2, bytesOfSecondCall))
      .then(createWorkspaceNonFile(1, 1, 5, WorkspaceDirectory))
      .then(createWorkspaceNonFile(1, 1, 6, WorkspaceSpecial))
      .then(createWorkspaceNonFile(2, 2, 5, WorkspaceSpecial))
      .then(createWorkspaceNonFile(2, 2, 7, WorkspaceDirectory))
      .then(createWorkspaceAlias(1, 1, 3, otherOwnerAlias))
      .then(createWorkspaceAlias(2, 2, 3, callerFile))
      .expect(not(canCleanupFiles(filesystem, 1, RemoveInterrupted(Set(7)))) and safety)
      .then(cleanup(2, RemoveInterrupted(Set(3, 5, 7))))
      .expect(workingEntries(filesystem, 2) == Set(3, 5, 7) and
        workingEntries(filesystem, 1) == Set(trace, 2, 3, 5, 6) and safety)
      .then(cleanup(1, RemoveInterrupted(Set(5))))
      .expect(workingEntries(filesystem, 1) == Set(5) and
        filesystem.nonFiles == Map(
          workingPath(1, 5) -> WorkspaceDirectory,
          workingPath(2, 5) -> WorkspaceSpecial,
          workingPath(2, 7) -> WorkspaceDirectory,
        ) and
        filesystem.aliases == Map(otherOwnerAlias -> callerFile) and
        filesystem.files == initialFiles.files and safety)

  run completeCleanupRemovesOnlyOwnedNonFilesTest =
    init
      .then(reserveAndGenerate(1, bytesOfFirstCall))
      .then(reserveAndGenerate(2, bytesOfSecondCall))
      .then(createWorkspaceNonFile(1, 1, 5, WorkspaceDirectory))
      .then(createWorkspaceNonFile(1, 1, 6, WorkspaceSpecial))
      .then(createWorkspaceNonFile(2, 2, 5, WorkspaceSpecial))
      .then(createWorkspaceAlias(2, 2, 3, callerFile))
      .then(cleanup(2, RemoveInterrupted(Set(3, 5))))
      .then(cleanup(1, RemoveComplete))
      .expect(workingEntries(filesystem, 1) == Set() and
        filesystem.nonFiles == Map(workingPath(2, 5) -> WorkspaceSpecial) and
        filesystem.aliases == Map(otherOwnerAlias -> callerFile) and
        not(canCreateWorkingNonFile(filesystem, 1, 1, 5)) and
        not(canCreateWorkingNonFile(filesystem, 2, 2, 6)) and safety)

  run artifactReservationIsExclusiveUntilAbandonedTest =
    init
      .then(reserveAndGenerate(1, bytesOfFirstCall))
      .then(reserveAndGenerate(2, bytesOfSecondCall))
      .expect(not(canStageReservedEvidence(filesystem, 1, trace)))
      .then(reserveArtifact(1, 9))
      .expect(not(canReserveArtifactDirectory(filesystem, 2, 9)) and
        not(canReserveArtifactDirectory(filesystem, 1, 10)) and
        not(canStageReservedEvidence(filesystem, 2, 2)) and
        reserveArtifactDirectory(filesystem, 2, 9) == filesystem and safety)
      .then(stageReserved(1, trace))
      .then(writeCopy(1, 2))
      .expect(not(canReserveArtifactDirectory(filesystem, 2, 9)) and
        readFileBytes(filesystem, evidencePath(root, 9, trace)) == FileUnavailable(MissingFile) and safety)
      .then(abandon(1))
      .then(reserveArtifact(2, 9))
      .then(stageReserved(2, trace))
      .then(writeCopy(2, bytesOfSecondCall.length()))
      .then(publish(2))
      .then(cleanup(2, RemoveComplete))
      .expect(readFileBytes(filesystem, evidencePath(root, 9, trace)) == FileBytes(bytesOfSecondCall) and
        readFileBytes(filesystem, secondArtifact) == FileUnavailable(MissingFile) and safety)

  run publishedArtifactDirectoryRejectsCollisionAfterCleanupTest =
    init
      .then(reserveAndGenerate(1, bytesOfFirstCall))
      .then(reserveArtifact(1, 9))
      .then(stageReserved(1, trace))
      .then(writeCopy(1, bytesOfFirstCall.length()))
      .then(publish(1))
      .then(cleanup(1, RemoveComplete))
      .then(reserveAndGenerate(2, bytesOfSecondCall))
      .expect(not(canReserveArtifactDirectory(filesystem, 2, 9)) and
        reserveArtifactDirectory(filesystem, 2, 9) == filesystem and safety)
      .then(cleanup(2, RemoveComplete))
      .expect(filesystem.files == initialFiles.files.put(evidencePath(root, 9, trace), bytesOfFirstCall) and safety)

  run artifactDirectoryCandidatesAreScopedByRootTest =
    init
      .then(reserveAndGenerate(1, bytesOfFirstCall))
      .then(reserve(2, 2, List("4", "2"), "/alternate"))
      .then(generate(2, GeneratedFiles(Map(trace -> bytesOfSecondCall))))
      .then(reserveArtifact(1, 9))
      .then(reserveArtifact(2, 9))
      .then(stageReserved(1, trace))
      .then(stageReserved(2, trace))
      .then(writeCopy(1, bytesOfFirstCall.length()))
      .then(writeCopy(2, bytesOfSecondCall.length()))
      .then(publish(1))
      .then(publish(2))
      .then(cleanup(1, RemoveComplete))
      .then(cleanup(2, RemoveComplete))
      .expect(filesystem.files == initialFiles.files
        .put(evidencePath(root, 9, trace), bytesOfFirstCall)
        .put(evidencePath("/alternate", 9, trace), bytesOfSecondCall) and safety)

  run cleanupReleasesAnUnusedArtifactReservationTest =
    init
      .then(reserveAndGenerate(1, bytesOfFirstCall))
      .then(reserveArtifact(1, 9))
      .then(cleanup(1, RemoveComplete))
      .then(reserveAndGenerate(2, bytesOfSecondCall))
      .then(reserveArtifact(2, 9))
      .expect(filesystem.files == initialFiles.files
        .put(secondTrace, bytesOfSecondCall)
        .put(workingPath(2, 2), List(0, 255)) and safety)

  run preexistingDirectoriesRejectReservationRegardlessOfContentsTest =
    init
      .then(reserveAndGenerate(1, bytesOfFirstCall))
      .expect(not(canReserveArtifactDirectory(filesystem, 1, occupiedDirectory)) and
        not(canReserveArtifactDirectory(filesystem, 1, emptyOccupiedDirectory)) and
        reserveArtifactDirectory(filesystem, 1, occupiedDirectory) == filesystem and
        reserveArtifactDirectory(filesystem, 1, emptyOccupiedDirectory) == filesystem and safety)
      .then(cleanup(1, RemoveComplete))
      .expect(filesystem.files == initialFiles.files and
        filesystem.artifactDirectories == initialFiles.artifactDirectories and safety)
}
