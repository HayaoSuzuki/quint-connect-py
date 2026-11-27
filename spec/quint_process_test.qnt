module quint_process_test {
  import quint_filesystem as fs from "./quint_filesystem"
  import quint_connect_documents.* from "./quint_connect"
  import quint_connect(CALL_IDS = Set(1), WORKSPACE_IDS = Set(7), DRIVER_IDS = Set(1),
    GENERATED_INPUTS = generatedInputs, SAVED_INPUTS = Map(), SAVED_ALIASES = Map()).* from "./quint_connect"

  pure val generation: Generation = {
    expectation: SimulationCount(1), seed: sampleSeed, workspace: 7, artifactRoot: defaultArtifactRoot,
  }

  pure val output: ProcessOutput = { stdout: List(255, 0), stderr: List(101, 114, 114, 10) }
  pure val nonzero = NonzeroExit({ code: 3, output: output })
  pure val signaled = SignalExit({ signal: 15, output: output })

  def hasProcessStart: bool = hasEvent(calls.get(1).history, event => event == ProcessStarted(generation))

  def reachedReplay: bool = hasEvent(calls.get(1).history, event =>
    match event {
      | GeneratedReadAttempted(_) => true
      | FactoryCalled(_) => true
      | _ => false
    }
  )

  run spawnFailureCleansReservedWorkspaceWithoutStartingChildTest = {
    val failure = failed(QuintFailed({ seed: sampleSeed, problem: SpawnFailure("not executable") }))
    init
      .then(startRun(1, generation))
      .then(failSpawn(1, "not executable"))
      .expect(calls.get(1).phase == AwaitingCleanup({ generation: generation, result: failure }) and
        not(hasProcessStart) and fs::workingEntries(filesystem, 7).size() == 0 and safety)
      .then(cleanWorkspace(1, StorageSucceeded))
      .expect(calls.get(1).phase == Finished(failure) and not(reachedReplay) and safety)
  }

  run nonzeroExitKeepsOutputAndMasksPartialTracesTest =
    init
      .then(startRun(1, generation))
      .then(startProcess(1))
      .then(completeProcessFailure(1, nonzero, Map(2 -> originalBytes)))
      .expect(hasProcessStart and not(reachedReplay) and safety)
      .then(cleanWorkspace(1, StorageSucceeded))
      .expect(calls.get(1).phase == Finished(failed(QuintFailed({ seed: sampleSeed, problem: nonzero }))) and
        fs::workingEntries(filesystem, 7).size() == 0 and safety)

  run signalRemainsPrimaryWhenCleanupAlsoFailsTest =
    init
      .then(startRun(1, generation))
      .then(startProcess(1))
      .then(completeProcessFailure(1, signaled, Map(2 -> originalBytes)))
      .then(cleanWorkspaceWithRemoval(1, StorageFailed("cannot remove"), fs::RemoveInterrupted(Set(2))))
      .expect(calls.get(1).phase == Finished(Failed({
        error: QuintFailed({ seed: sampleSeed, problem: signaled }), cleanup: CleanupAlsoFailed("cannot remove"),
      })) and hasProcessStart and not(reachedReplay) and safety)

  run childCannotExitBeforeItStartsTest =
    init
      .then(startRun(1, generation))
      .then(completeProcessFailure(1, nonzero, Map()).fail())

  run successfulExitCodeCannotBeReportedAsFailureTest =
    init
      .then(startRun(1, generation))
      .then(startProcess(1))
      .then(completeProcessFailure(1, NonzeroExit({ code: 0, output: output }), Map()).fail())
}
