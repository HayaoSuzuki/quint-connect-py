module quint_process_io_test {
  import quint_filesystem as fs from "./quint_filesystem"
  import quint_connect_documents.* from "./quint_connect"
  import quint_connect(CALL_IDS = Set(1), WORKSPACE_IDS = Set(7), DRIVER_IDS = Set(1),
    GENERATED_INPUTS = generatedInputs, SAVED_INPUTS = Map(), SAVED_ALIASES = Map(), EXISTING_ARTIFACTS = Map()).* from "./quint_connect"

  pure val generation: Generation = {
    expectation: SimulationCount(1), seed: sampleSeed, workspace: 7, artifactRoot: defaultArtifactRoot,
  }

  pure val outputProblem: ProcessIoProblem = { stage: CollectOutput, cause: "output pipe failed" }
  pure val waitProblem: ProcessIoProblem = { stage: WaitForExit, cause: "wait failed" }
  pure val outputError: Failure = QuintFailed({ seed: sampleSeed, problem: ProcessIoFailure(outputProblem) })
  pure val waitError: Failure = QuintFailed({ seed: sampleSeed, problem: ProcessIoFailure(waitProblem) })
  pure val partialOutput: fs::TraceFiles = Map(2 -> originalBytes)
  pure val partialContents: fs::WorkspaceContents = {
    regular: partialOutput,
    aliases: Map(3 -> fs::SavedFile("external.itf.json")),
    nonFiles: Map(4 -> fs::WorkspaceDirectory, 5 -> fs::WorkspaceSpecial),
  }

  def reachedReplayOrSave: bool =
    hasEvent(calls.get(1).history, event =>
      match event {
        | ProcessExitedSuccessfully(_) => true
        | GeneratedReadAttempted(_) => true
        | ValidationAttempted(_) => true
        | FactoryCalled(_) => true
        | SaveAttempted(_) => true
        | _ => false
      }
    )

  def attemptedCleanup: bool =
    hasEvent(calls.get(1).history, event =>
      match event {
        | CleanupAttempted(_) => true
        | _ => false
      }
    )

  val awaitingExitConfirmation: bool =
    match calls.get(1).phase {
      | AwaitingExitConfirmation(_) => true
      | _ => false
    }

  val hasUnreadablePartialOutput: bool = and {
    filesystem.workspaces.get(7).output == fs::AbortedFiles(partialOutput),
    fs::workingFiles(filesystem, 7) == Set(2),
    fs::workingEntries(filesystem, 7) == Set(2, 3, 4, 5),
    filesystem.files.get(fs::workingPath(7, 2)) == originalBytes,
    not(fs::canReadGeneratedFile(filesystem, 7, 2)),
  }

  action startChild: bool = startRun(1, generation).then(startProcess(1))

  action failWaitWithoutExitConfirmation: bool =
    failProcessIo(1, waitProblem, ExitUnconfirmed)

  run outputCollectionFailureWithConfirmedExitCleansPartialOutputTest =
    init
      .then(startChild)
      .then(failProcessIo(1, outputProblem, ExitConfirmed(partialContents)))
      .expect(calls.get(1).phase == AwaitingCleanup({ generation: generation, result: failed(outputError) }) and
        hasUnreadablePartialOutput and not(reachedReplayOrSave) and safety)
      .then(cleanWorkspace(1, StorageSucceeded))
      .expect(calls.get(1).phase == Finished(failed(outputError)) and attemptedCleanup and
        fs::workingEntries(filesystem, 7) == Set() and not(reachedReplayOrSave) and safety)

  run waitFailureRemainsPrimaryAfterExitConfirmationAndCleanupFailureTest =
    init
      .then(startChild)
      .then(failWaitWithoutExitConfirmation)
      .expect(awaitingExitConfirmation and not(attemptedCleanup) and
        filesystem.workspaces.get(7).status == fs::WorkspaceActive and safety)
      .then(confirmChildExit(1, partialContents))
      .expect(calls.get(1).phase == AwaitingCleanup({ generation: generation, result: failed(waitError) }) and
        hasUnreadablePartialOutput and not(attemptedCleanup) and safety)
      .then(cleanWorkspaceWithRemoval(1, StorageFailed("cleanup interrupted"), fs::RemoveInterrupted(Set(2, 5))))
      .expect(calls.get(1).phase == Finished(Failed({
        error: waitError, cleanup: CleanupAlsoFailed("cleanup interrupted"),
      })) and attemptedCleanup and fs::workingEntries(filesystem, 7) == Set(2, 5) and not(reachedReplayOrSave) and safety)

  run deferredCleanupRetainsActiveWorkspaceAndPartialOutputTest =
    init
      .then(startChild)
      .then(failWaitWithoutExitConfirmation)
      .then(deferCleanup(1, "reap could not be confirmed", partialContents))
      .expect(calls.get(1).phase == Finished(Failed({
        error: waitError, cleanup: CleanupDeferred({ workspace: 7, cause: "reap could not be confirmed" }),
      })) and filesystem.workspaces.get(7).status == fs::WorkspaceActive and
        filesystem.workspaces.get(7).evidence == fs::NoEvidence and
        filesystem.artifactDirectories.keys() == Set() and
        hasUnreadablePartialOutput and not(attemptedCleanup) and not(reachedReplayOrSave) and safety)

  run nonzeroExitLeavesAllEntryKindsForCleanupTest = {
    val problem = NonzeroExit({ code: 2, output: noProcessOutput })
    val error = QuintFailed({ seed: sampleSeed, problem: problem })
    init
      .then(startChild)
      .then(completeProcessFailureWithContents(1, problem, partialContents))
      .expect(calls.get(1).phase == AwaitingCleanup({ generation: generation, result: failed(error) }) and
        hasUnreadablePartialOutput and not(reachedReplayOrSave) and safety)
      .then(cleanWorkspace(1, StorageSucceeded))
      .expect(calls.get(1).phase == Finished(failed(error)) and
        fs::workingEntries(filesystem, 7).size() == 0 and safety)
  }

  run cleanupIsDisabledUntilChildExitIsConfirmedTest =
    init
      .then(startChild)
      .then(failWaitWithoutExitConfirmation)
      .then(cleanWorkspace(1, StorageSucceeded).fail())

  run waitFailureRequiresStartedChildTest =
    init
      .then(startRun(1, generation))
      .then(failWaitWithoutExitConfirmation.fail())

  run cleanupInvariantRequiresExitEvidenceAfterSpawnTest = {
    val generation = { expectation: SimulationCount(1), seed: sampleSeed, workspace: 7, artifactRoot: defaultArtifactRoot }
    val reserved = List(WorkspaceReserved(generation))
    val running = reserved.append(ProcessStarted(generation))
    val stopped = running.append(ProcessExitedSuccessfully(generation))
    assert(and {
      cleanupHasExitEvidence(reserved, reserved.length(), 7),
      not(cleanupHasExitEvidence(running, running.length(), 7)),
      cleanupHasExitEvidence(stopped, stopped.length(), 7),
    })
  }
}
