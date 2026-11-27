module quint_progress_test {
  import quint_filesystem as fs from "./quint_filesystem"
  import quint_connect_documents.* from "./quint_connect"
  import quint_connect(CALL_IDS = Set(1, 2), WORKSPACE_IDS = Set(1), DRIVER_IDS = Set(1, 2),
    GENERATED_INPUTS = generatedInputs, SAVED_INPUTS = Map(), SAVED_ALIASES = Map()).* from "./quint_connect"

  run nextTraceCanBeLongerAndBothCallsStillConcludeTest =
    init
      .then(startReplay(1, List(0, 1)))
      .then(validateTrace(1, ValidSteps(List(openingStep))))
      .then(createDriver(1, FactorySucceeded(1)))
      .then(applyOperation(1, OperationApplied))
      .then(observeState(1, Observed(integerDigit(0))))
      .expect(processingProgress)
      .then(startReplay(2, List(0)))
      .then(validateTrace(2, ValidSteps(List(openingStep))))
      .then(validateTrace(1, ValidSteps(List(openingStep, incrementStep))))
      .expect(processingProgress and pendingCalls == Set(1, 2))
      .then(createDriver(1, FactorySucceeded(2)))
      .then(applyOperation(1, OperationApplied))
      .then(observeState(1, Observed(integerDigit(0))))
      .then(applyOperation(1, OperationApplied))
      .then(observeState(1, Observed(integerDigit(1))))
      .expect(processingProgress and calls.get(1).phase == Finished(Passed) and pendingCalls == Set(2))
      .then(createDriver(2, FactoryFailed("driver factory failed")))
      .expect(safety and totalWork(calls, filesystem) == noWork)

  run sampledSchedulerAdvancesAbstractGenerationWithoutBasenamesTest = {
    val generation = { expectation: SimulationCount(1), seed: sampleSeed, workspace: 1, artifactRoot: defaultArtifactRoot }
    init
      .then(startReplay(2, List()))
      .then(startRun(1, generation))
      .then(completeGeneration(1, ProcessSucceeded(List(2))))
      .expect(processingProgress)
      .then(step)
      .expect(processingProgress and hasEvent(calls.get(1).history, isValidationAttempt))
  }

  run emptyArtifactCopyCanAdvanceFromStagingToCleanupTest = {
    val generation = { expectation: SimulationCount(1), seed: sampleSeed, workspace: 1, artifactRoot: defaultArtifactRoot }
    val artifact = fs::evidencePath(defaultArtifactRoot, 1, 2)
    init
      .then(startRun(1, generation))
      .then(completeGeneration(1, ProcessSucceeded(List(2))))
      .then(validateTrace(1, ValidSteps(List(openingStep))))
      .then(createDriver(1, FactorySucceeded(1)))
      .then(applyOperation(1, OperationApplied))
      .then(observeState(1, Observed(integerDigit(1))))
      .then(beginArtifactCopy(1))
      .expect(processingProgress and hasNextResponse(1))
      .then(completeArtifactCopy(1, StorageSucceeded))
      .expect(processingProgress and filesystem.files.get(artifact) == List())
      .then(cleanWorkspace(1, StorageSucceeded))
      .then(startReplay(2, List()))
      .expect(safety and totalWork(calls, filesystem) == noWork)
  }
}
