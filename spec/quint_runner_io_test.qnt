module quint_runner_io_test {
  import quint_cli as cli from "./quint_cli"
  import quint_filesystem as fs from "./quint_filesystem"
  import quint_itf as itf from "./quint_itf"
  import quint_connect_documents.* from "./quint_connect"
  import quint_connect(CALL_IDS = Set(1, 2, 3), WORKSPACE_IDS = Set(1, 2), DRIVER_IDS = Set(1, 2),
    GENERATED_INPUTS = generatedInputs, SAVED_INPUTS = Map(), SAVED_ALIASES = Map(), EXISTING_ARTIFACTS = Map()).* from "./quint_connect"

  pure val firstTrace: TracePosition = { trace: 2, traceIndex: 0 }
  pure val secondTrace: TracePosition = { trace: 41, traceIndex: 1 }
  pure val thirdTrace: TracePosition = { trace: 11, traceIndex: 2 }
  pure val replayTrace: TracePosition = { trace: 0, traceIndex: 0 }
  pure val evidence = fs::evidencePath(defaultArtifactRoot, 1, 2)

  pure val firstOutput: ProducedFile =
    { name: cli::generatedFilename(List("2")), trace: 2, bytes: originalBytes }

  pure val secondOutput: ProducedFile =
    { name: cli::generatedFilename(List("1", "0")), trace: 41, bytes: originalBytes }

  pure val thirdOutput: ProducedFile =
    { name: cli::generatedFilename(List("1", "1")), trace: 11, bytes: originalBytes }

  pure val detail: Mismatch = {
    position: { trace: firstTrace, stepIndex: 0 },
    step: {
      operation: { name: initName, arguments: Map() },
      expected: { nodes: itf::valueNodes(compoundDocument), root: 6 },
    },
    actual: integerDigit(1),
  }

  pure def generation(count: int): Generation =
    { expectation: SimulationCount(count), seed: sampleSeed, workspace: 1, artifactRoot: defaultArtifactRoot }

  pure def mismatchOutcome(save: SaveResult): Outcome =
    failed(StatesDiffer({ detail: detail, artifacts: FromGeneration({ seed: sampleSeed, save: save }) }))

  def runHasEvent(predicate: (Event) => bool): bool = hasEvent(calls.get(1).history, predicate)

  def generatedFileWasOpened(position: TracePosition): bool =
    runHasEvent(event =>
      match event {
        | GeneratedReadAttempted(file) => file.position == position
        | _ => false
      }
    )

  action startGeneratedRun(count: int): bool =
    startRequestedRun(1, simulatorRequest(1, simulationWithCount(count)), sampleSeed, defaultArtifactRoot, itemsSelection)

  action runToMismatch: bool =
    startGeneratedRun(1)
      .then(startProcess(1))
      .then(completeProcessSuccess(1, List(firstOutput)))
      .then(listGeneratedOutput(1, ListingSucceeded))
      .then(readGeneratedInput(1, ReadSucceeded))
      .then(createDriver(1, FactorySucceeded(1)))
      .then(applyOperation(1, OperationApplied))
      .then(observeState(1, Observed(integerDigit(1))))

  run nonRegularEntriesDoNotCountAndCleanupPreservesAliasTargetTest = {
    val aliasPath = fs::workingPath(2, 41)
    val error = IncompleteGeneration({ seed: sampleSeed, requested: 2, produced: 1 })
    val entries: List[ProducedEntry] = List(
      { name: cli::generatedFilename(List("1", "0")), trace: 41, contents: AliasEntry(evidence) },
      { name: cli::generatedFilename(List("1", "1")), trace: 11, contents: DirectoryEntry },
      { name: cli::generatedFilename(List("1", "2")), trace: 12, contents: OtherEntry },
      { name: firstOutput.name, trace: firstOutput.trace, contents: RegularContents(List()) },
    )
    init
      .then(runToMismatch)
      .then(saveArtifact(1, StorageSucceeded))
      .then(cleanWorkspace(1, StorageSucceeded))
      .then(startRequestedRun(2, simulatorRequest(2, simulationWithCount(2)), sampleSeed, defaultArtifactRoot, itemsSelection))
      .then(startProcess(2))
      .then(completeProcessWithEntries(2, entries))
      .expect(fs::resolveFilePath(filesystem, aliasPath) == fs::ResolvedFile(evidence) and
        fs::workingNonFiles(filesystem, 2) == Map(11 -> fs::WorkspaceDirectory, 12 -> fs::WorkspaceSpecial) and safety)
      .then(listGeneratedOutput(2, ListingSucceeded))
      .then(cleanWorkspace(2, StorageSucceeded))
      .expect(calls.get(2).phase == Finished(failed(error)) and
        fs::workingEntries(filesystem, 2).size() == 0 and
        not(filesystem.aliases.keys().contains(aliasPath)) and filesystem.files.get(evidence) == originalBytes and safety)
  }

  run interruptedCleanupRetainsOnlyTheReportedDirectoryTest = {
    val error = IncompleteGeneration({ seed: sampleSeed, requested: 2, produced: 1 })
    val entries: List[ProducedEntry] = List(
      { name: firstOutput.name, trace: firstOutput.trace, contents: RegularContents(originalBytes) },
      { name: thirdOutput.name, trace: thirdOutput.trace, contents: DirectoryEntry },
      { name: cli::generatedFilename(List("1", "2")), trace: 12, contents: OtherEntry },
    )
    init
      .then(startGeneratedRun(2))
      .then(startProcess(1))
      .then(completeProcessWithEntries(1, entries))
      .then(listGeneratedOutput(1, ListingSucceeded))
      .then(cleanWorkspaceWithRemoval(1, StorageFailed("cleanup interrupted"), fs::RemoveInterrupted(Set(11))))
      .expect(calls.get(1).phase == Finished(Failed({ error: error, cleanup: CleanupAlsoFailed("cleanup interrupted") })) and
        fs::workingEntries(filesystem, 1) == Set(11) and
        fs::workingNonFiles(filesystem, 1) == Map(11 -> fs::WorkspaceDirectory) and safety)
  }

  run listingFailurePreventsReplayAndRemainsPrimaryAfterCleanupFailureTest = {
    val error = OutputListingFailed({ seed: sampleSeed, workspace: 1, cause: "directory listing failed" })
    init
      .then(startGeneratedRun(2))
      .then(startProcess(1))
      .then(completeProcessSuccess(1, List(secondOutput, firstOutput)))
      .expect(calls.get(1).phase == AwaitingListing({
        generation: generation(2), entries: generatedNames(List(secondOutput, firstOutput)),
      }) and runHasEvent(event => event == ProcessExitedSuccessfully(generation(2))) and
        fs::workingFiles(filesystem, 1) == Set(2, 41) and safety)
      .then(listGeneratedOutput(1, ListingFailed("directory listing failed")))
      .expect(calls.get(1).phase == AwaitingCleanup({ generation: generation(2), result: failed(error) }) and
        not(generatedFileWasOpened(firstTrace)) and not(runHasEvent(isValidationAttempt)) and safety)
      .then(cleanWorkspaceWithRemoval(1, StorageFailed("cleanup interrupted"), fs::RemoveInterrupted(Set(41))))
      .expect(calls.get(1).phase == Finished(Failed({ error: error, cleanup: CleanupAlsoFailed("cleanup interrupted") })) and
        not(generatedFileWasOpened(secondTrace)) and fs::workingFiles(filesystem, 1) == Set(41) and safety)
  }

  run readFailureOnSecondGeneratedFileStopsBeforeThirdFileTest = {
    val error = TraceFailed({
      location: AtGeneratedTrace({ path: fs::workingPath(1, 41), basename: secondOutput.name, position: secondTrace }),
      cause: "permission denied",
    })
    init
      .then(startGeneratedRun(3))
      .then(startProcess(1))
      .then(completeProcessSuccess(1, List(thirdOutput, secondOutput, firstOutput)))
      .then(listGeneratedOutput(1, ListingSucceeded))
      .then(readGeneratedInput(1, ReadSucceeded))
      .expect(generatedFileWasOpened(firstTrace) and not(generatedFileWasOpened(secondTrace)))
      .then(createDriver(1, FactorySucceeded(1)))
      .then(applyOperation(1, OperationApplied))
      .then(observeState(1, Observed(itemSet)))
      .then(readGeneratedInput(1, ReadFailed("permission denied")))
      .expect(calls.get(1).phase == AwaitingCleanup({ generation: generation(3), result: failed(error) }) and
        runHasEvent(event => event == ObservationMatched({
          position: { trace: firstTrace, stepIndex: 0 }, actual: itemSet,
        })) and generatedFileWasOpened(secondTrace) and not(generatedFileWasOpened(thirdTrace)) and
        not(runHasEvent(event => event == ValidationAttempted(secondTrace) or event == FactoryCalled(secondTrace))) and safety)
      .then(cleanWorkspace(1, StorageSucceeded))
      .expect(calls.get(1).phase == Finished(failed(error)) and
        fs::workingFiles(filesystem, 1) == Set() and safety)
  }

  run stagedPrefixIsPrivateUntilFullCopyIsPublishedTest =
    init
      .then(runToMismatch)
      .then(planArtifactDirectories(1, List(1)))
      .then(tryArtifactDirectory(1, StorageSucceeded))
      .then(beginArtifactCopy(1))
      .then(writeArtifactCopy(1, 5))
      .expect(filesystem.workspaces.get(1).evidence == fs::StagedEvidence({
        trace: 2, bytes: originalBytes.slice(0, 5),
      }) and not(filesystem.files.keys().contains(evidence)) and safety)
      .then(startReplayPaths(2, List(evidence), itemsSelection))
      .then(readSavedPath(2, ReadSucceeded))
      .expect(calls.get(2).phase == Finished(failed(TraceFailed({
        location: AtSavedTrace({ path: evidence, position: replayTrace }), cause: "file not found",
      }))) and safety)
      .then(writeArtifactCopy(1, originalBytes.length()))
      .expect(not(filesystem.files.keys().contains(evidence)) and safety)
      .then(startReplayPaths(3, List(evidence), itemsSelection))
      .then(completeArtifactCopy(1, StorageSucceeded))
      .expect(calls.get(1).phase == AwaitingCleanup({
        generation: generation(1), result: mismatchOutcome(ArtifactSaved(evidence)),
      }) and filesystem.files.get(evidence) == originalBytes and
        fs::workingFiles(filesystem, 1) == Set(2) and safety)
      .then(readSavedPath(3, ReadSucceeded))
      .then(cleanWorkspace(1, StorageSucceeded))
      .expect(calls.get(1).phase == Finished(mismatchOutcome(ArtifactSaved(evidence))) and
        filesystem.files.keys() == Set(evidence) and safety)
      .then(createDriver(3, FactorySucceeded(2)))
      .then(applyOperation(3, OperationApplied))
      .then(observeState(3, Observed(itemSet)))
      .expect(calls.get(3).phase == Finished(Passed) and safety)

  run incompleteCopyCannotBePublishedTest =
    init
      .then(runToMismatch)
      .then(planArtifactDirectories(1, List(1)))
      .then(tryArtifactDirectory(1, StorageSucceeded))
      .then(beginArtifactCopy(1))
      .then(writeArtifactCopy(1, 5))
      .then(completeArtifactCopy(1, StorageSucceeded).fail())

  run publicationFailureAfterFullWritePreservesMismatchTest =
    init
      .then(runToMismatch)
      .then(planArtifactDirectories(1, List(1)))
      .then(tryArtifactDirectory(1, StorageSucceeded))
      .then(beginArtifactCopy(1))
      .then(writeArtifactCopy(1, originalBytes.length()))
      .expect(filesystem.workspaces.get(1).evidence == fs::StagedEvidence({
        trace: 2, bytes: originalBytes,
      }) and not(filesystem.files.keys().contains(evidence)) and safety)
      .then(completeArtifactCopy(1, StorageFailed("publication failed")))
      .expect(filesystem.workspaces.get(1).evidence == fs::AbandonedEvidence(2) and
        not(filesystem.files.keys().contains(evidence)) and safety)
      .then(cleanWorkspace(1, StorageSucceeded))
      .expect(calls.get(1).phase == Finished(mismatchOutcome(ArtifactSaveFailed("publication failed"))) and
        filesystem.files.keys() == Set() and safety)
}
