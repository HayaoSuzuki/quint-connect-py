module quint_conformance_documents {
  import quint_connect_documents.* from "./quint_connect"
  import quint_filesystem as fs from "./quint_filesystem"

  // A two-step ITF trace. The add operation takes delta = 1 and omits ignored.
  pure val multistepBytes: fs::Bytes = List(
    123, 34, 118, 97, 114, 115, 34, 58, 91, 34, 110, 34, 93, 44, 34, 115, 116, 97, 116, 101,
    115, 34, 58, 91, 123, 34, 110, 34, 58, 123, 34, 35, 98, 105, 103, 105, 110, 116, 34, 58,
    34, 48, 34, 125, 44, 34, 109, 98, 116, 58, 58, 97, 99, 116, 105, 111, 110, 84, 97, 107,
    101, 110, 34, 58, 34, 105, 110, 105, 116, 34, 44, 34, 109, 98, 116, 58, 58, 110, 111, 110,
    100, 101, 116, 80, 105, 99, 107, 115, 34, 58, 123, 125, 125, 44, 123, 34, 110, 34, 58, 123,
    34, 35, 98, 105, 103, 105, 110, 116, 34, 58, 34, 49, 34, 125, 44, 34, 109, 98, 116, 58,
    58, 97, 99, 116, 105, 111, 110, 84, 97, 107, 101, 110, 34, 58, 34, 97, 100, 100, 34, 44,
    34, 109, 98, 116, 58, 58, 110, 111, 110, 100, 101, 116, 80, 105, 99, 107, 115, 34, 58, 123,
    34, 100, 101, 108, 116, 97, 34, 58, 123, 34, 116, 97, 103, 34, 58, 34, 83, 111, 109, 101,
    34, 44, 34, 118, 97, 108, 117, 101, 34, 58, 123, 34, 35, 98, 105, 103, 105, 110, 116, 34,
    58, 34, 49, 34, 125, 125, 44, 34, 105, 103, 110, 111, 114, 101, 100, 34, 58, 123, 34, 116,
    97, 103, 34, 58, 34, 78, 111, 110, 101, 34, 44, 34, 118, 97, 108, 117, 101, 34, 58, 123,
    34, 35, 116, 117, 112, 34, 58, 91, 93, 125, 125, 125, 125, 93, 125, 10,
  )
  // The push operation receives items = [{ flag: true }].
  pure val nestedMutationBytes: fs::Bytes = List(
    123, 34, 118, 97, 114, 115, 34, 58, 91, 34, 110, 34, 93, 44, 34, 115, 116, 97, 116, 101,
    115, 34, 58, 91, 123, 34, 110, 34, 58, 123, 34, 35, 98, 105, 103, 105, 110, 116, 34, 58,
    34, 48, 34, 125, 44, 34, 109, 98, 116, 58, 58, 97, 99, 116, 105, 111, 110, 84, 97, 107,
    101, 110, 34, 58, 34, 105, 110, 105, 116, 34, 44, 34, 109, 98, 116, 58, 58, 110, 111, 110,
    100, 101, 116, 80, 105, 99, 107, 115, 34, 58, 123, 125, 125, 44, 123, 34, 110, 34, 58, 123,
    34, 35, 98, 105, 103, 105, 110, 116, 34, 58, 34, 49, 34, 125, 44, 34, 109, 98, 116, 58,
    58, 97, 99, 116, 105, 111, 110, 84, 97, 107, 101, 110, 34, 58, 34, 112, 117, 115, 104, 34,
    44, 34, 109, 98, 116, 58, 58, 110, 111, 110, 100, 101, 116, 80, 105, 99, 107, 115, 34, 58,
    123, 34, 105, 116, 101, 109, 115, 34, 58, 123, 34, 116, 97, 103, 34, 58, 34, 83, 111, 109,
    101, 34, 44, 34, 118, 97, 108, 117, 101, 34, 58, 91, 123, 34, 102, 108, 97, 103, 34, 58,
    116, 114, 117, 101, 125, 93, 125, 125, 125, 93, 125, 10,
  )

  // An anonymous MBT operation takes items = { 0, -00 } and expects n = 0001.
  pure val anonymousOperationBytes: fs::Bytes = List(
    123, 34, 118, 97, 114, 115, 34, 58, 91, 34, 110, 34, 93, 44, 34, 115, 116, 97, 116, 101, 115,
    34, 58, 91, 123, 34, 110, 34, 58, 123, 34, 35, 98, 105, 103, 105, 110, 116, 34, 58, 34, 48,
    48, 48, 49, 34, 125, 44, 34, 109, 98, 116, 58, 58, 97, 99, 116, 105, 111, 110, 84, 97, 107,
    101, 110, 34, 58, 34, 34, 44, 34, 109, 98, 116, 58, 58, 110, 111, 110, 100, 101, 116, 80, 105,
    99, 107, 115, 34, 58, 123, 34, 105, 116, 101, 109, 115, 34, 58, 123, 34, 116, 97, 103, 34, 58,
    34, 83, 111, 109, 101, 34, 44, 34, 118, 97, 108, 117, 101, 34, 58, 123, 34, 35, 115, 101, 116,
    34, 58, 91, 123, 34, 35, 98, 105, 103, 105, 110, 116, 34, 58, 34, 48, 34, 125, 44, 123, 34,
    35, 98, 105, 103, 105, 110, 116, 34, 58, 34, 45, 48, 48, 34, 125, 93, 125, 125, 125, 125, 93,
    125, 10,
  )

  pure val fixtureSavedInputs: str -> fs::Bytes =
    savedInputs.put("multistep.itf.json", multistepBytes)
      .put("nested-mutation.itf.json", nestedMutationBytes)
      .put("anonymous-operation.itf.json", anonymousOperationBytes)
}

module quint_conformance {
  import quint_cli as cli from "./quint_cli"
  import quint_filesystem as fs from "./quint_filesystem"
  import quint_itf as itf from "./quint_itf"
  import quint_values as qv from "./quint_values"
  import quint_connect_documents.* from "./quint_connect"
  import quint_conformance_documents.*
  import quint_parallel_inputs.* from "./quint_parallel"
  import quint_connect(CALL_IDS = Set(1, 2), WORKSPACE_IDS = Set(1, 2), DRIVER_IDS = Set(1, 2),
    GENERATED_INPUTS = parallelGeneratedInputs, SAVED_INPUTS = fixtureSavedInputs, SAVED_ALIASES = Map(),
    EXISTING_ARTIFACTS = Map()).* from "./quint_connect"

  type Request =
    | ReplayPaths({ paths: List[str], selection: itf::Selection })
    | RunQuint({ cli: cli::CliRequest, drawnSeed: Seed, artifactRoot: str, selection: itf::Selection })

  type Response =
    | SavedRead(ReadResult)
    | ChildStarted
    | ChildSpawnFailed(str)
    | ChildSucceeded(List[ProducedFile])
    | ChildFailed({ problem: ProcessProblem, partialOutput: List[ProducedFile] })
    | ChildIoFailed({ problem: ProcessIoProblem, exit: ExitKnowledge })
    | ChildExitWasConfirmed(List[ProducedFile])
    | DirectoryListing(ListingResult)
    | GeneratedRead(ReadResult)
    | DriverFactory(FactoryResult)
    | DriverApply(OperationResult)
    | DriverApplyWithMutation({ result: OperationResult, arguments: qv::Text -> Value })
    | DriverObserve(ObservationResult)
    | ArtifactCandidateList(List[int])
    | ArtifactReservation(StorageResult)
    | EvidenceCopyStarted
    | EvidenceCopyWritten(int)
    | EvidenceCopyFinished(StorageResult)
    | WorkspaceCleanup({ result: StorageResult, removal: fs::CleanupOutcome })
    | WorkspaceCleanupWasDeferred({ cause: str, partialOutput: List[ProducedFile] })

  type FixtureInput = Start(Request) | Respond(Response)
  type ScheduledInput = { callId: CallId, input: FixtureInput }

  var schedule: List[ScheduledInput]

  action initializeSchedule: bool = all {
    init,
    schedule' = List(),
  }

  action startCall(id: CallId, request: Request): bool = all {
    match request {
      | ReplayPaths(saved) =>
        startReplayPaths(id, saved.paths.foldl(List(), (paths, path) => paths.append(fs::SavedFile(path))),
          saved.selection)
      | RunQuint(runRequest) =>
        startRequestedRun(id, runRequest.cli, runRequest.drawnSeed, runRequest.artifactRoot, runRequest.selection)
    },
    schedule' = schedule.append({ callId: id, input: Start(request) }),
  }

  action initialize(request: Request): bool =
    initializeSchedule.then(startCall(1, request))

  pure def partialBytes(files: List[ProducedFile]): fs::TraceFiles =
    generatedBytes(regularEntries(files))

  action respondTo(id: CallId, response: Response): bool = all {
    match response {
      | SavedRead(result) => readSavedPath(id, result)
      | ChildStarted => startProcess(id)
      | ChildSpawnFailed(cause) => failSpawn(id, cause)
      | ChildSucceeded(files) => completeProcessSuccess(id, files)
      | ChildFailed(failure) =>
        completeProcessFailure(id, failure.problem, partialBytes(failure.partialOutput))
      | ChildIoFailed(failure) => failProcessIo(id, failure.problem, failure.exit)
      | ChildExitWasConfirmed(files) => confirmChildExit(id, fs::regularWorkspaceContents(partialBytes(files)))
      | DirectoryListing(result) => listGeneratedOutput(id, result)
      | GeneratedRead(result) => readGeneratedInput(id, result)
      | DriverFactory(result) => createDriver(id, result)
      | DriverApply(result) => applyOperation(id, result)
      | DriverApplyWithMutation(apply) => applyOperationWithMutation(id, apply.result, apply.arguments)
      | DriverObserve(result) => observeState(id, result)
      | ArtifactCandidateList(candidates) => planArtifactDirectories(id, candidates)
      | ArtifactReservation(result) => tryArtifactDirectory(id, result)
      | EvidenceCopyStarted => beginArtifactCopy(id)
      | EvidenceCopyWritten(count) => writeArtifactCopy(id, count)
      | EvidenceCopyFinished(result) => completeArtifactCopy(id, result)
      | WorkspaceCleanup(cleanup) => cleanWorkspaceWithRemoval(id, cleanup.result, cleanup.removal)
      | WorkspaceCleanupWasDeferred(cleanup) =>
        deferCleanup(id, cleanup.cause, fs::regularWorkspaceContents(partialBytes(cleanup.partialOutput)))
    },
    schedule' = schedule.append({ callId: id, input: Respond(response) }),
  }

  action respond(response: Response): bool = respondTo(1, response)

  val completedFixture: bool = and {
    schedule.length() > 0,
    schedule.foldl(Set(), (ids, step) => ids.union(Set(step.callId)))
      .forall(id => hasFinished(calls.get(id).phase)),
    safety,
  }

  pure val counterSelection: itf::Selection = { actionPath: List(), statePath: List(List(110)) }
  pure val namedSelection: itf::Selection = {
    ...itemsSelection, actionPath: List(List(100, 105, 115, 112, 97, 116, 99, 104)),
  }

  pure def generatedRequest(config: cli::QuintConfig, selection: itf::Selection): Request =
    RunQuint({
      cli: simulatorRequest(1, config), drawnSeed: sampleSeed, artifactRoot: defaultArtifactRoot, selection: selection,
    })

  pure val namedTestConfig: cli::QuintConfig =
    cli::NamedTestMode({ name: List(97, 46, 98), maxSamples: cli::CliDefault })

  pure val firstFile: ProducedFile =
    { name: cli::generatedFilename(List("2")), trace: 2, bytes: originalBytes }

  pure val secondFile: ProducedFile =
    { name: cli::generatedFilename(List("1", "0")), trace: 41, bytes: otherBytes }

  pure val thirdFile: ProducedFile =
    { name: cli::generatedFilename(List("1", "1")), trace: 11, bytes: originalBytes }

  pure val namedFile: ProducedFile =
    { name: cli::generatedFilename(List("0")), trace: 0, bytes: namedBytes }

  pure val removedWorkspace: Response =
    WorkspaceCleanup({ result: StorageSucceeded, removal: fs::RemoveComplete })

  action replayCounterOpening(driver: DriverId): bool =
    respond(SavedRead(ReadSucceeded))
      .then(respond(DriverFactory(FactorySucceeded(driver))))
      .then(respond(DriverApply(OperationApplied)))
      .then(respond(DriverObserve(Observed(integerDigit(0)))))

  action replayCounter(driver: DriverId): bool =
    replayCounterOpening(driver)
      .then(respond(DriverApply(OperationApplied)))
      .then(respond(DriverObserve(Observed(integerDigit(1)))))

  run repeatedMultistepReplayTest =
    initialize(ReplayPaths({ paths: List("multistep.itf.json", "multistep.itf.json"), selection: counterSelection }))
      .then(replayCounter(1))
      .then(replayCounter(2))
      .expect(completedFixture)

  run invalidSecondSavedFileTest =
    initialize(ReplayPaths({
      paths: List("good.itf.json", "bad.itf.json", "empty.itf.json"), selection: itemsSelection,
    }))
      .then(respond(SavedRead(ReadSucceeded)))
      .then(respond(DriverFactory(FactorySucceeded(1))))
      .then(respond(DriverApply(OperationApplied)))
      .then(respond(DriverObserve(Observed(itemSet))))
      .then(respond(SavedRead(ReadSucceeded)))
      .expect(completedFixture)

  run driverApplyFailureTest =
    initialize(ReplayPaths({ paths: List("multistep.itf.json", "missing.itf.json"), selection: counterSelection }))
      .then(replayCounterOpening(1))
      .then(respond(DriverApply(OperationFailed("driver rejected add"))))
      .expect(completedFixture)

  pure val itemsArgument: qv::Text = List(105, 116, 101, 109, 115) // items

  pure def itemsWithFlag(flag: bool): Value = {
    nodes: List(
      qv::BooleanNode(flag),
      qv::RecordNode(Map(List(102, 108, 97, 103) -> 0)), // flag
      qv::ListNode(List(1)),
    ),
    root: 2,
  }

  val mismatchHasOriginalArguments: bool =
    hasEvent(calls.get(1).history, event =>
      match event {
        | DifferenceObserved(mismatch) =>
          qv::equalValues(mismatch.step.operation.arguments.get(itemsArgument), itemsWithFlag(true))
        | _ => false
      })

  run nestedArgumentMutationMismatchTest =
    initialize(ReplayPaths({ paths: List("nested-mutation.itf.json"), selection: counterSelection }))
      .then(replayCounterOpening(1))
      .then(respond(DriverApplyWithMutation({
        result: OperationApplied, arguments: Map(itemsArgument -> itemsWithFlag(false)),
      })))
      .then(respond(DriverObserve(Observed(integerDigit(0)))))
      .expect(completedFixture and mismatchHasOriginalArguments)

  pure val observedDuplicateSet: Value = {
    nodes: List(
      qv::IntegerNode({ negative: false, digits: List(0) }),
      qv::IntegerNode({ negative: true, digits: List(0, 0) }),
      qv::SetNode(List(0, 1)),
    ),
    root: 2,
  }

  val anonymousMismatchHasNormalizedValues: bool =
    hasEvent(calls.get(1).history, event =>
      match event {
        | DifferenceObserved(mismatch) => {
          val argument = mismatch.step.operation.arguments.get(itemsArgument)
          mismatch.step.operation.name == List() and
            (match argument.nodes.nth(argument.root) {
              | SetNode(children) => children.length() == 1 and argument.nodes.nth(children.head()) ==
                  qv::IntegerNode({ negative: false, digits: List(0) })
              | _ => false
            }) and
            mismatch.step.expected.nodes.nth(mismatch.step.expected.root) == qv::IntegerNode({ negative: false, digits: List(1) }) and
            mismatch.actual == {
              ...observedDuplicateSet, nodes: List(
                qv::IntegerNode({ negative: false, digits: List(0) }),
                qv::IntegerNode({ negative: false, digits: List(0) }),
                qv::SetNode(List(0)),
              ),
            }
        }
        | _ => false
      })

  run anonymousOperationNormalizesMismatchValuesTest =
    initialize(ReplayPaths({ paths: List("anonymous-operation.itf.json"), selection: counterSelection }))
      .then(respond(SavedRead(ReadSucceeded)))
      .then(respond(DriverFactory(FactorySucceeded(1))))
      .then(respond(DriverApply(OperationApplied)))
      .then(respond(DriverObserve(Observed(observedDuplicateSet))))
      .expect(completedFixture and anonymousMismatchHasNormalizedValues)

  run namedGeneratedReplayTest =
    initialize(generatedRequest(namedTestConfig, namedSelection))
      .then(respond(ChildStarted))
      .then(respond(ChildSucceeded(List(namedFile))))
      .then(respond(DirectoryListing(ListingSucceeded)))
      .then(respond(GeneratedRead(ReadSucceeded)))
      .then(respond(DriverFactory(FactorySucceeded(1))))
      .then(respond(DriverApply(OperationApplied)))
      .then(respond(DriverObserve(Observed(itemSet))))
      .then(respond(removedWorkspace))
      .expect(completedFixture)

  run secondGeneratedReadFailureTest =
    initialize(generatedRequest(simulationWithCount(3), itemsSelection))
      .then(respond(ChildStarted))
      .then(respond(ChildSucceeded(List(thirdFile, secondFile, firstFile))))
      .then(respond(DirectoryListing(ListingSucceeded)))
      .then(respond(GeneratedRead(ReadSucceeded)))
      .then(respond(DriverFactory(FactorySucceeded(1))))
      .then(respond(DriverApply(OperationApplied)))
      .then(respond(DriverObserve(Observed(itemSet))))
      .then(respond(GeneratedRead(ReadFailed("permission denied"))))
      .then(respond(WorkspaceCleanup({
        result: StorageFailed("cleanup interrupted"), removal: fs::RemoveInterrupted(Set(41)),
      })))
      .expect(completedFixture)

  action reachGeneratedMismatch: bool =
    initialize(generatedRequest(simulationWithCount(1), itemsSelection))
      .then(respond(ChildStarted))
      .then(respond(ChildSucceeded(List(firstFile))))
      .then(respond(DirectoryListing(ListingSucceeded)))
      .then(respond(GeneratedRead(ReadSucceeded)))
      .then(respond(DriverFactory(FactorySucceeded(1))))
      .then(respond(DriverApply(OperationApplied)))
      .then(respond(DriverObserve(Observed(integerDigit(1)))))

  run generatedDriverFailureSavedTest =
    initialize(generatedRequest(simulationWithCount(1), itemsSelection))
      .then(respond(ChildStarted))
      .then(respond(ChildSucceeded(List(firstFile))))
      .then(respond(DirectoryListing(ListingSucceeded)))
      .then(respond(GeneratedRead(ReadSucceeded)))
      .then(respond(DriverFactory(FactorySucceeded(1))))
      .then(respond(DriverApply(OperationFailed("driver failed"))))
      .then(respond(ArtifactCandidateList(List(7))))
      .then(respond(ArtifactReservation(StorageSucceeded)))
      .then(respond(EvidenceCopyStarted))
      .then(respond(EvidenceCopyWritten(originalBytes.length())))
      .then(respond(EvidenceCopyFinished(StorageSucceeded)))
      .then(respond(removedWorkspace))
      .expect(completedFixture)

  run generatedMismatchSavedTest =
    reachGeneratedMismatch
      .then(respond(ArtifactCandidateList(List(7))))
      .then(respond(ArtifactReservation(StorageSucceeded)))
      .then(respond(EvidenceCopyStarted))
      .then(respond(EvidenceCopyWritten(5)))
      .then(respond(EvidenceCopyWritten(originalBytes.length())))
      .then(respond(EvidenceCopyFinished(StorageSucceeded)))
      .then(respond(removedWorkspace))
      .expect(completedFixture)

  run artifactDirectoryFailureTest =
    reachGeneratedMismatch
      .then(respond(ArtifactCandidateList(List(7))))
      .then(respond(ArtifactReservation(StorageFailed("artifact directory unavailable"))))
      .then(respond(removedWorkspace))
      .expect(completedFixture)

  pure val capturedOutput: ProcessOutput = {
    stdout: List(255, 0), stderr: List(101, 114, 114, 10),
  }

  run spawnFailureTest =
    initialize(generatedRequest(simulationWithCount(1), itemsSelection))
      .then(respond(ChildSpawnFailed("executable format error")))
      .then(respond(removedWorkspace))
      .expect(completedFixture)

  run nonzeroExitWithOutputTest =
    initialize(generatedRequest(simulationWithCount(1), itemsSelection))
      .then(respond(ChildStarted))
      .then(respond(ChildFailed({
        problem: NonzeroExit({ code: 3, output: capturedOutput }),
        partialOutput: List(firstFile),
      })))
      .then(respond(removedWorkspace))
      .expect(completedFixture)

  run signalExitWithOutputAndCleanupFailureTest =
    initialize(generatedRequest(simulationWithCount(1), itemsSelection))
      .then(respond(ChildStarted))
      .then(respond(ChildFailed({
        problem: SignalExit({ signal: 15, output: capturedOutput }),
        partialOutput: List(firstFile),
      })))
      .then(respond(WorkspaceCleanup({
        result: StorageFailed("cannot remove partial output"), removal: fs::RemoveInterrupted(Set(firstFile.trace)),
      })))
      .expect(completedFixture)

  pure val partialFile: ProducedFile = { ...firstFile, bytes: List(123, 34) }

  run outputCollectionFailureAfterExitConfirmationTest =
    initialize(generatedRequest(simulationWithCount(1), itemsSelection))
      .then(respond(ChildStarted))
      .then(respond(ChildIoFailed({
        problem: { stage: CollectOutput, cause: "output pipe failed" }, exit: ExitUnconfirmed,
      })))
      .then(respond(ChildExitWasConfirmed(List(partialFile))))
      .expect(all {
        filesystem.files.get(fs::workingPath(1, partialFile.trace)) == partialFile.bytes,
        not(fs::canReadGeneratedFile(filesystem, 1, partialFile.trace)),
        safety,
      })
      .then(respond(removedWorkspace))
      .expect(all {
        completedFixture,
        filesystem.workspaces.get(1).status == fs::WorkspaceRemoved,
        not(filesystem.files.keys().contains(fs::workingPath(1, partialFile.trace))),
      })

  run waitFailureWithDeferredCleanupTest =
    initialize(generatedRequest(simulationWithCount(1), itemsSelection))
      .then(respond(ChildStarted))
      .then(respond(ChildIoFailed({
        problem: { stage: WaitForExit, cause: "wait failed" }, exit: ExitUnconfirmed,
      })))
      .then(respond(WorkspaceCleanupWasDeferred({
        cause: "reap could not be confirmed", partialOutput: List(partialFile),
      })))
      .expect(all {
        completedFixture,
        filesystem.workspaces.get(1).status == fs::WorkspaceActive,
        filesystem.files.get(fs::workingPath(1, partialFile.trace)) == partialFile.bytes,
      })

  pure val sharedArtifactRoot = "shared artifacts"

  pure def parallelRequest(id: CallId): Request = RunQuint({
    cli: simulatorRequest(id, simulationWithCount(1)), drawnSeed: sampleSeed,
    artifactRoot: sharedArtifactRoot, selection: itemsSelection,
  })

  action observeParallelMismatch(id: CallId): bool =
    respondTo(id, DirectoryListing(ListingSucceeded))
      .then(respondTo(id, GeneratedRead(ReadSucceeded)))
      .then(respondTo(id, DriverFactory(FactorySucceeded(id))))
      .then(respondTo(id, DriverApply(OperationApplied)))
      .then(respondTo(id, DriverObserve(Observed(integerDigit(id)))))

  run overlappingArtifactReservationTest =
    initializeSchedule
      .then(startCall(1, parallelRequest(1)))
      .then(startCall(2, parallelRequest(2)))
      .then(respondTo(1, ChildStarted))
      .then(respondTo(2, ChildStarted))
      .then(respondTo(2, ChildSucceeded(List({ ...firstFile, bytes: parallelBytes.get(2) }))))
      .then(respondTo(1, ChildSucceeded(List({ ...firstFile, bytes: parallelBytes.get(1) }))))
      .then(observeParallelMismatch(1))
      .then(observeParallelMismatch(2))
      .then(respondTo(1, ArtifactCandidateList(List(7))))
      .then(respondTo(2, ArtifactCandidateList(List(7, 8))))
      .then(respondTo(1, ArtifactReservation(StorageSucceeded)))
      .then(respondTo(1, EvidenceCopyStarted))
      .then(respondTo(1, EvidenceCopyWritten(5)))
      .then(respondTo(2, ArtifactReservation(StorageSucceeded)))
      .then(respondTo(2, ArtifactReservation(StorageSucceeded)))
      .then(respondTo(2, EvidenceCopyStarted))
      .then(respondTo(2, EvidenceCopyWritten(5)))
      .then(respondTo(1, EvidenceCopyWritten(parallelBytes.get(1).length())))
      .then(respondTo(1, EvidenceCopyFinished(StorageSucceeded)))
      .then(respondTo(1, removedWorkspace))
      .expect(all {
        not(filesystem.files.keys().contains(fs::workingPath(1, firstFile.trace))),
        filesystem.files.get(fs::workingPath(2, firstFile.trace)) == parallelBytes.get(2),
        filesystem.files.get(fs::evidencePath(sharedArtifactRoot, 7, firstFile.trace)) == parallelBytes.get(1),
        safety,
      })
      .then(respondTo(2, EvidenceCopyWritten(parallelBytes.get(2).length())))
      .then(respondTo(2, EvidenceCopyFinished(StorageSucceeded)))
      .then(respondTo(2, removedWorkspace))
      .expect(all {
        completedFixture,
        filesystem.files.get(fs::evidencePath(sharedArtifactRoot, 7, firstFile.trace)) == parallelBytes.get(1),
        filesystem.files.get(fs::evidencePath(sharedArtifactRoot, 8, firstFile.trace)) == parallelBytes.get(2),
        not(filesystem.files.keys().contains(fs::workingPath(2, firstFile.trace))),
      })
}
