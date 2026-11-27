module quint_filesystem_test {
  import quint_filesystem.* from "./quint_filesystem"
  import quint_filesystem_sample.* from "./quint_filesystem"

  pure val firstTrace: FilePath = workingPath(1, trace)
  pure val secondTrace: FilePath = workingPath(2, trace)
  pure val firstArtifact: FilePath = evidencePath(root, 1, trace)
  pure val secondArtifact: FilePath = evidencePath(root, 2, trace)

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
}
