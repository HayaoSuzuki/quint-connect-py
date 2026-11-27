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
  pure val fixtureSavedInputs: str -> fs::Bytes =
    savedInputs.put("multistep.itf.json", multistepBytes)
}

module quint_conformance {
  import quint_cli as cli from "./quint_cli"
  import quint_filesystem as fs from "./quint_filesystem"
  import quint_itf as itf from "./quint_itf"
  import quint_connect_documents.* from "./quint_connect"
  import quint_conformance_documents.*
  import quint_connect(CALL_IDS = Set(1), WORKSPACE_IDS = Set(1), DRIVER_IDS = Set(1, 2),
    GENERATED_INPUTS = generatedInputs, SAVED_INPUTS = fixtureSavedInputs, SAVED_ALIASES = Map(),
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
    | DirectoryListing(ListingResult)
    | GeneratedRead(ReadResult)
    | DriverFactory(FactoryResult)
    | DriverApply(OperationResult)
    | DriverObserve(ObservationResult)
    | ArtifactCandidateList(List[int])
    | ArtifactReservation(StorageResult)
    | EvidenceCopyStarted
    | EvidenceCopyWritten(int)
    | EvidenceCopyFinished(StorageResult)
    | WorkspaceCleanup({ result: StorageResult, removal: fs::CleanupOutcome })

  var fixture: { request: Request, responses: List[Response] }

  action initialize(request: Request): bool = all {
    init,
    fixture' = { request: request, responses: List() },
  }

  action requestRun: bool = all {
    match fixture.request {
      | ReplayPaths(request) =>
        startReplayPaths(1, request.paths.foldl(List(), (paths, path) => paths.append(fs::SavedFile(path))),
          request.selection)
      | RunQuint(request) =>
        startRequestedRun(1, request.cli, request.drawnSeed, request.artifactRoot, request.selection)
    },
    fixture' = fixture,
  }

  // Record exactly the responses supplied to the runner by each scenario.
  action respond(response: Response): bool = all {
    match response {
      | SavedRead(result) => readSavedPath(1, result)
      | ChildStarted => startProcess(1)
      | ChildSpawnFailed(cause) => failSpawn(1, cause)
      | ChildSucceeded(files) => completeProcessSuccess(1, files)
      | ChildFailed(failure) =>
        completeProcessFailure(1, failure.problem, generatedBytes(regularEntries(failure.partialOutput)))
      | DirectoryListing(result) => listGeneratedOutput(1, result)
      | GeneratedRead(result) => readGeneratedInput(1, result)
      | DriverFactory(result) => createDriver(1, result)
      | DriverApply(result) => applyOperation(1, result)
      | DriverObserve(result) => observeState(1, result)
      | ArtifactCandidateList(candidates) => planArtifactDirectories(1, candidates)
      | ArtifactReservation(result) => tryArtifactDirectory(1, result)
      | EvidenceCopyStarted => beginArtifactCopy(1)
      | EvidenceCopyWritten(count) => writeArtifactCopy(1, count)
      | EvidenceCopyFinished(result) => completeArtifactCopy(1, result)
      | WorkspaceCleanup(cleanup) => cleanWorkspaceWithRemoval(1, cleanup.result, cleanup.removal)
    },
    fixture' = { ...fixture, responses: fixture.responses.append(response) },
  }

  val completedFixture: bool = hasFinished(calls.get(1).phase) and safety

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
      .then(requestRun)
      .then(replayCounter(1))
      .then(replayCounter(2))
      .expect(completedFixture)

  run invalidSecondSavedFileTest =
    initialize(ReplayPaths({
      paths: List("good.itf.json", "bad.itf.json", "empty.itf.json"), selection: itemsSelection,
    }))
      .then(requestRun)
      .then(respond(SavedRead(ReadSucceeded)))
      .then(respond(DriverFactory(FactorySucceeded(1))))
      .then(respond(DriverApply(OperationApplied)))
      .then(respond(DriverObserve(Observed(itemSet))))
      .then(respond(SavedRead(ReadSucceeded)))
      .expect(completedFixture)

  run driverApplyFailureTest =
    initialize(ReplayPaths({ paths: List("multistep.itf.json", "missing.itf.json"), selection: counterSelection }))
      .then(requestRun)
      .then(replayCounterOpening(1))
      .then(respond(DriverApply(OperationFailed("driver rejected add"))))
      .expect(completedFixture)

  run namedGeneratedReplayTest =
    initialize(generatedRequest(namedTestConfig, namedSelection))
      .then(requestRun)
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
      .then(requestRun)
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
      .then(requestRun)
      .then(respond(ChildStarted))
      .then(respond(ChildSucceeded(List(firstFile))))
      .then(respond(DirectoryListing(ListingSucceeded)))
      .then(respond(GeneratedRead(ReadSucceeded)))
      .then(respond(DriverFactory(FactorySucceeded(1))))
      .then(respond(DriverApply(OperationApplied)))
      .then(respond(DriverObserve(Observed(integerDigit(1)))))

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
      .then(requestRun)
      .then(respond(ChildSpawnFailed("executable format error")))
      .then(respond(removedWorkspace))
      .expect(completedFixture)

  run nonzeroExitWithOutputTest =
    initialize(generatedRequest(simulationWithCount(1), itemsSelection))
      .then(requestRun)
      .then(respond(ChildStarted))
      .then(respond(ChildFailed({
        problem: NonzeroExit({ code: 3, output: capturedOutput }),
        partialOutput: List(firstFile),
      })))
      .then(respond(removedWorkspace))
      .expect(completedFixture)

  run signalExitWithOutputAndCleanupFailureTest =
    initialize(generatedRequest(simulationWithCount(1), itemsSelection))
      .then(requestRun)
      .then(respond(ChildStarted))
      .then(respond(ChildFailed({
        problem: SignalExit({ signal: 15, output: capturedOutput }),
        partialOutput: List(firstFile),
      })))
      .then(respond(WorkspaceCleanup({
        result: StorageFailed("cannot remove partial output"), removal: fs::RemoveInterrupted(Set(firstFile.trace)),
      })))
      .expect(completedFixture)
}
