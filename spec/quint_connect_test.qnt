module quint_connect_test {
  import quint_cli as cli from "./quint_cli"
  import quint_filesystem as fs from "./quint_filesystem"
  import quint_itf as itf from "./quint_itf"
  import quint_values as qv from "./quint_values"
  import quint_connect_documents.* from "./quint_connect"
  import quint_connect(CALL_IDS = Set(1, 2), WORKSPACE_IDS = Set(1, 2), DRIVER_IDS = Set(1, 2, 3, 4), GENERATED_INPUTS = generatedInputs, SAVED_INPUTS = Map(), SAVED_ALIASES = Map()).* from "./quint_connect"

  pure val simulation: Generation =
    { expectation: SimulationCount(1), seed: sampleSeed, workspace: 1, artifactRoot: defaultArtifactRoot }

  pure val namedGeneration: Generation =
    { expectation: NamedTestOutput, seed: sampleSeed, workspace: 2, artifactRoot: defaultArtifactRoot }

  pure val firstTrace: TracePosition = { trace: 7, traceIndex: 0 }
  pure val firstPosition: StepPosition = { trace: firstTrace, stepIndex: 0 }
  pure val secondPosition: StepPosition = { trace: firstTrace, stepIndex: 1 }

  pure val firstMismatch: Mismatch =
    { position: firstPosition, step: openingStep, actual: integerDigit(1) }

  pure val typedMismatch: Mismatch =
    { position: secondPosition, step: incrementStep, actual: booleanValue(true) }

  def finishedAs(id: CallId, outcome: Outcome): bool =
    calls.get(id).phase == Finished(outcome)

  action makeFirstStep(id: CallId, driver: DriverId): bool =
    validateTrace(id, ValidSteps(List(openingStep)))
      .then(createDriver(id, FactorySucceeded(driver)))
      .then(applyOperation(id, OperationApplied))

  run repeatedSavedPathGetsNewDriverTest =
    init
      .then(startReplay(1, List(7, 7)))
      .then(makeFirstStep(1, 1))
      .then(observeState(1, Observed(integerDigit(0))))
      .then(validateTrace(1, ValidSteps(List(openingStep))))
      .expect(not(factoryResultAllowed(FactorySucceeded(1))))
      .then(createDriver(1, FactorySucceeded(2)))
      .then(applyOperation(1, OperationApplied))
      .then(observeState(1, Observed(integerDigit(0))))
      .expect(finishedAs(1, Passed) and safety)
      .expect(hasEvent(calls.get(1).history, event =>
        event == DriverCreated({ trace: { trace: 7, traceIndex: 1 }, driver: 2 })
      ))

  run secondTraceUsesItsOwnOperationAndExpectedValueTest =
    init
      .then(startReplay(1, List(7, 8)))
      .then(makeFirstStep(1, 1))
      .then(observeState(1, Observed(integerDigit(0))))
      .then(validateTrace(1, ValidSteps(List(incrementStep))))
      .then(createDriver(1, FactorySucceeded(2)))
      .then(applyOperation(1, OperationApplied))
      .then(observeState(1, Observed(integerDigit(1))))
      .expect(finishedAs(1, Passed) and safety)
      .expect(hasEvent(calls.get(1).history, event =>
        event == OperationCalled({
          context: { position: { trace: { trace: 8, traceIndex: 1 }, stepIndex: 0 }, driver: 2 },
          operation: incrementStep.operation,
        })
      ))

  run invalidLaterStepBlocksFactoryTest =
    init
      .then(startReplay(1, List(7, 8)))
      .then(validateTrace(1, InvalidItf({ location: InvalidStep(1), cause: "invalid action" })))
      .expect(finishedAs(1, failed(TraceFailed({ location: AtStep(secondPosition), cause: "invalid action" }))))
      .expect(calls.get(1).history == List(
        ReplayRequested(List(7, 8)),
        ValidationAttempted(firstTrace),
        FailureRecognized(TraceFailed({ location: AtStep(secondPosition), cause: "invalid action" })),
        Returned(failed(TraceFailed({ location: AtStep(secondPosition), cause: "invalid action" })))
      ) and safety)

  run invalidNextTraceCannotReturnSuccessTest =
    init
      .then(startReplay(1, List(7, 8)))
      .then(makeFirstStep(1, 1))
      .then(observeState(1, Observed(integerDigit(0))))
      .then(validateTrace(1, InvalidItf({ location: InvalidFile, cause: "invalid next ITF" })))
      .expect(finishedAs(1, failed(TraceFailed({
        location: AtTrace({ trace: 8, traceIndex: 1 }), cause: "invalid next ITF",
      }))) and safety)

  run emptyInputAndEmptyStatesAreDistinctTest =
    init
      .then(startReplay(1, List()))
      .then(startReplay(2, List(7)))
      .then(validateTrace(2, EmptyStates))
      .expect(finishedAs(1, failed(EmptyTrace(NoInputPaths))) and
        finishedAs(2, failed(EmptyTrace(NoTraceStates(firstTrace)))) and safety)
      .then(step.fail())

  run generationErrorsBlockReplayTest =
    init
      .then(startRun(1, simulation))
      .then(startRun(2, { ...namedGeneration, expectation: SimulationCount(2) }))
      .then(completeGeneration(1, ProcessFailed("Quint exited unsuccessfully")))
      .then(completeGeneration(2, ProcessSucceeded(List(7))))
      .then(cleanWorkspace(2, StorageSucceeded))
      .then(cleanWorkspace(1, StorageSucceeded))
      .expect(finishedAs(1, failed(QuintFailed({ seed: sampleSeed, cause: "Quint exited unsuccessfully" }))) and
        finishedAs(2, failed(IncompleteGeneration({ seed: sampleSeed, requested: 2, produced: 1 }))) and safety)

  run reservationAndNoGeneratedTracesTest =
    init
      .then(failReservation(1, sampleSeed, "cannot reserve"))
      .then(startRun(2, namedGeneration))
      .then(completeGeneration(2, ProcessSucceeded(List())))
      .then(cleanWorkspace(2, StorageSucceeded))
      .expect(finishedAs(1, failed(WorkspaceFailed({ seed: sampleSeed, stage: Reserve, cause: "cannot reserve" }))) and
        finishedAs(2, failed(EmptyTrace(NoGeneratedItf))) and safety)

  run initialOperationAndObservationFailuresTest =
    init
      .then(startReplay(1, List(7, 8)))
      .then(startReplay(2, List(7, 8)))
      .then(validateTrace(1, ValidSteps(List(openingStep, incrementStep))))
      .then(createDriver(1, FactorySucceeded(1)))
      .then(applyOperation(1, OperationFailed("apply failed")))
      .then(makeFirstStep(2, 2))
      .then(observeState(2, ObservationFailed("observe failed")))
      .expect(finishedAs(1, failed(DriverFailed({
          location: AtStep(firstPosition), stage: Apply, cause: "apply failed",
        }))) and finishedAs(2, failed(DriverFailed({
          location: AtStep(firstPosition), stage: Observe, cause: "observe failed",
        }))) and safety)

  run factoryFailurePreventsOperationsTest =
    init
      .then(startReplay(1, List(7, 8)))
      .then(validateTrace(1, ValidSteps(List(openingStep))))
      .then(createDriver(1, FactoryFailed("factory failed")))
      .expect(finishedAs(1, failed(DriverFailed({
        location: AtTrace(firstTrace), stage: Factory, cause: "factory failed",
      }))) and safety)

  run generatedAndSavedMismatchAgreeTest =
    init
      .then(startRun(1, simulation))
      .then(completeGeneration(1, ProcessSucceeded(List(7, 8))))
      .then(validateTrace(1, ValidSteps(List(openingStep, incrementStep))))
      .then(createDriver(1, FactorySucceeded(1)))
      .then(applyOperation(1, OperationApplied))
      .then(observeState(1, Observed(integerDigit(0))))
      .then(applyOperation(1, OperationApplied))
      .then(observeState(1, Observed(booleanValue(true))))
      .then(saveArtifact(1, StorageSucceeded))
      .then(cleanWorkspace(1, StorageFailed("cleanup failed")))
      .then(startReplay(2, List(7)))
      .then(validateTrace(2, ValidSteps(List(openingStep, incrementStep))))
      .then(createDriver(2, FactorySucceeded(2)))
      .then(applyOperation(2, OperationApplied))
      .then(observeState(2, Observed(integerDigit(0))))
      .then(applyOperation(2, OperationApplied))
      .then(observeState(2, Observed(booleanValue(true))))
      .expect(finishedAs(1, Failed({
        error: StatesDiffer({
          detail: typedMismatch,
          artifacts: FromGeneration({ seed: sampleSeed, save: ArtifactSaved(fs::evidencePath(defaultArtifactRoot, 1, 7)) }),
        }),
        cleanup: CleanupAlsoFailed("cleanup failed"),
      })) and finishedAs(2, failed(StatesDiffer({
        detail: typedMismatch, artifacts: FromSavedTrace,
      }))) and safety)
      .expect(not(hasEvent(calls.get(2).history, event =>
        match event {
          | SaveAttempted(_) => true
          | _ => false
        }
      )))

  run interleavedRunsKeepSeparateArtifactsTest =
    init
      .then(startRun(1, simulation))
      .then(startRun(2, namedGeneration))
      .then(completeGeneration(2, ProcessSucceeded(List(7))))
      .then(completeGeneration(1, ProcessSucceeded(List(7))))
      .then(makeFirstStep(2, 2))
      .then(makeFirstStep(1, 1))
      .then(observeState(2, Observed(integerDigit(1))))
      .then(observeState(1, Observed(integerDigit(1))))
      .then(saveArtifact(1, StorageSucceeded))
      .then(saveArtifact(2, StorageSucceeded))
      .then(cleanWorkspace(1, StorageSucceeded))
      .then(cleanWorkspace(2, StorageSucceeded))
      .expect(finishedAs(1, failed(StatesDiffer({
        detail: firstMismatch,
        artifacts: FromGeneration({ seed: sampleSeed, save: ArtifactSaved(fs::evidencePath(defaultArtifactRoot, 1, 7)) }),
      }))) and finishedAs(2, failed(StatesDiffer({
        detail: firstMismatch,
        artifacts: FromGeneration({ seed: sampleSeed, save: ArtifactSaved(fs::evidencePath(defaultArtifactRoot, 2, 7)) }),
      }))) and safety)
      .then(step.fail())

  run saveFailureRetainsMismatchTest =
    init
      .then(startRun(1, simulation))
      .then(completeGeneration(1, ProcessSucceeded(List(7))))
      .then(makeFirstStep(1, 1))
      .then(observeState(1, Observed(integerDigit(1))))
      .then(saveArtifact(1, StorageFailed("cannot save")))
      .then(cleanWorkspace(1, StorageSucceeded))
      .expect(finishedAs(1, failed(StatesDiffer({
        detail: firstMismatch,
        artifacts: FromGeneration({ seed: sampleSeed, save: ArtifactSaveFailed("cannot save") }),
      }))) and safety)

  run cleanupOnlyBecomesPrimaryAfterPassingTest =
    init
      .then(startRun(1, simulation))
      .then(startRun(2, namedGeneration))
      .then(completeGeneration(1, ProcessSucceeded(List(7))))
      .then(completeGeneration(2, ProcessSucceeded(List(7))))
      .then(makeFirstStep(1, 1))
      .then(makeFirstStep(2, 2))
      .then(observeState(1, Observed(integerDigit(0))))
      .then(observeState(2, Observed(integerDigit(0))))
      .then(cleanWorkspace(1, StorageFailed("cleanup failed")))
      .then(cleanWorkspace(2, StorageSucceeded))
      .expect(finishedAs(1, failed(WorkspaceFailed({ seed: sampleSeed, stage: Cleanup, cause: "cleanup failed" }))) and
        finishedAs(2, Passed) and safety)

  // Keep a negative transition check last. A disabled action sets no next state.
  run reservedWorkspaceCannotBeReusedTest =
    init
      .then(startRun(1, simulation))
      .then(startRun(2, { ...namedGeneration, workspace: 1 }).fail())

  run cannotObserveBeforeApplyingOperationTest =
    init
      .then(startReplay(1, List(7)))
      .then(validateTrace(1, ValidSteps(List(openingStep))))
      .then(createDriver(1, FactorySucceeded(1)))
      .then(observeState(1, Observed(integerDigit(0))).fail())

  run cannotApplyAfterFirstMismatchTest =
    init
      .then(startReplay(1, List(7, 8)))
      .then(validateTrace(1, ValidSteps(List(openingStep, incrementStep))))
      .then(createDriver(1, FactorySucceeded(1)))
      .then(applyOperation(1, OperationApplied))
      .then(observeState(1, Observed(integerDigit(1))))
      .expect(finishedAs(1, failed(StatesDiffer({
        detail: firstMismatch, artifacts: FromSavedTrace,
      }))) and safety)
      .then(applyOperation(1, OperationApplied).fail())


  pure val sampleRequest: cli::CliRequest = {
    callerDirectory: "/models",
    executable: cli::ExecutablePath(cli::AbsolutePath("/bin/quint")),
    model: cli::RelativePath("counter.qnt"),
    workspace: 1,
    main: cli::CliDefault,
    backend: cli::CliDefault,
    seed: cli::CliSpecified(cli::maxSeed),
    config: cli::Simulation({
      init: cli::CliDefault, step: cli::CliDefault, nTraces: cli::CliSpecified(2),
      maxSamples: cli::CliDefault, maxSteps: cli::CliDefault,
    }),
  }

  run callerRelativePathsSurviveIsolatedWorkspaceReservationTest = {
    val request = {
      ...sampleRequest,
      callerDirectory: "/checkout",
      executable: cli::ExecutablePath(cli::RelativePath("tools/quint")),
      model: cli::RelativePath("spec/counter.qnt"),
    }
    init
      .then(startRequestedRun(1, request, sampleSeed, defaultArtifactRoot, itemsSelection))
      .expect(filesystem.workspaces.get(1).owner == 1 and hasEvent(calls.get(1).history, event =>
        match event {
          | CommandPrepared(plan) =>
            plan.command.workspace == 1 and
            plan.command.executable == cli::DirectExecutable(cli::AnchoredPath({
              directory: "/checkout", path: "tools/quint",
            })) and
            plan.command.argv.nth(1) == cli::ModelArgument(cli::AnchoredPath({
              directory: "/checkout", path: "spec/counter.qnt",
            }))
          | _ => false
        }) and safety)
  }

  pure val reverseDirectoryListing: List[ProducedFile] = List(
    { name: cli::generatedFilename(List("1", "0")), trace: 10, bytes: otherBytes },
    { name: cli::generatedFilename(List("2")), trace: 2, bytes: originalBytes },
  )

  pure val compoundStep: TraceStep = {
    operation: { name: initName, arguments: Map() },
    expected: { nodes: itf::valueNodes(compoundDocument), root: 6 },
  }

  pure val reversedItems: Value = {
    nodes: List(qv::BooleanNode(true), qv::IntegerNode({ negative: false, digits: List(1) }),
      qv::SetNode(List(0, 1))),
    root: 2,
  }

  pure val missingBoolean: Value = {
    nodes: List(qv::IntegerNode({ negative: false, digits: List(1) }), qv::SetNode(List(0))),
    root: 1,
  }

  pure val compoundMismatch: Mismatch = {
    position: { trace: { trace: 2, traceIndex: 0 }, stepIndex: 0 },
    step: compoundStep,
    actual: missingBoolean,
  }

  run compoundEqualityDeterminesReplaySuccessTest =
    init
      .then(startReplayWithSelection(1, List(2), itemsSelection))
      .then(validateDocument(1, compoundDocument))
      .then(createDriver(1, FactorySucceeded(1)))
      .then(applyOperation(1, OperationApplied))
      .then(observeState(1, Observed(reversedItems)))
      .expect(finishedAs(1, Passed) and safety)

  run sortedGenerationAndSavedBytesReproduceMismatchTest = {
    val saved = fs::evidencePath("evidence", 1, 2)
    val savedMismatch = { ...compoundMismatch, position: { trace: { trace: 0, traceIndex: 0 }, stepIndex: 0 } }
    init
      .then(startRequestedRun(1, sampleRequest, sampleSeed, "evidence", itemsSelection))
      .then(completeProcessSuccess(1, reverseDirectoryListing))
      .then(listGeneratedOutput(1, ListingSucceeded))
      .then(validateGeneratedDocument(1, originalBytes))
      .then(createDriver(1, FactorySucceeded(1)))
      .then(applyOperation(1, OperationApplied))
      .then(observeState(1, Observed(missingBoolean)))
      .then(saveArtifactWithCopy(1, StorageSucceeded, fs::CopyComplete))
      .then(cleanWorkspaceWithRemoval(1, StorageSucceeded, fs::RemoveComplete))
      .expect(finishedAs(1, failed(StatesDiffer({
        detail: compoundMismatch,
        artifacts: FromGeneration({ seed: cli::maxSeed, save: ArtifactSaved(saved) }),
      }))) and safety)
      .expect(filesystem.files.keys() == Set(saved))
      .expect(filesystem.files.get(saved) == originalBytes)
      .then(startReplayPaths(2, List(saved), itemsSelection))
      .then(readSavedPath(2, ReadSucceeded))
      .then(createDriver(2, FactorySucceeded(2)))
      .then(applyOperation(2, OperationApplied))
      .then(observeState(2, Observed(missingBoolean)))
      .expect(finishedAs(2, failed(StatesDiffer({ detail: savedMismatch, artifacts: FromSavedFile(saved) }))) and safety)
  }

  run wrongGeneratedBytesCannotBePassedToDecoderTest =
    init
      .then(startRequestedRun(1, sampleRequest, sampleSeed, "evidence", itemsSelection))
      .then(completeProcessSuccess(1, reverseDirectoryListing))
      .then(listGeneratedOutput(1, ListingSucceeded))
      .then(validateGeneratedDocument(1, otherBytes).fail())

  run seedRejectionDoesNotReserveOrExecuteTest =
    init
      .then(startRequestedRun(1, { ...sampleRequest, seed: cli::CliSpecified(List("0", "1")) },
        sampleSeed, "evidence", itemsSelection))
      .expect(finishedAs(1, failed(InvalidRequest(RejectedSeed))) and filesystem.workspaces.keys().size() == 0 and safety)
      .then(completeProcessSuccess(1, reverseDirectoryListing).fail())

  run failedProcessOutputIsUnreadableAndRemovedTest =
    init
      .then(startRequestedRun(1, sampleRequest, sampleSeed, "evidence", itemsSelection))
      .then(completeProcessFailure(1, "nonzero exit", Map(2 -> originalBytes)))
      .expect(filesystem.files.get(fs::workingPath(1, 2)) == originalBytes)
      .expect(not(fs::canReadGeneratedFile(filesystem, 1, 2)))
      .then(cleanWorkspace(1, StorageSucceeded))
      .expect(finishedAs(1, failed(QuintFailed({ seed: cli::maxSeed, cause: "nonzero exit" }))) and
        filesystem.files.keys().size() == 0 and safety)

  run namedTestRequiresAndUsesItsExplicitOperationPathTest =
    init
      .then(startRequestedRun(1, { ...sampleRequest,
        config: cli::NamedTestMode({ name: List(97), maxSamples: cli::CliDefault }),
      }, sampleSeed, "evidence", itemsSelection))
      .expect(finishedAs(1, failed(InvalidRequest(RejectedActionPath))) and filesystem.workspaces.keys().size() == 0)
      .then(startRequestedRun(2, { ...sampleRequest,
        config: cli::NamedTestMode({ name: List(97), maxSamples: cli::CliDefault }),
      }, sampleSeed, "evidence", { actionPath: List(List(100, 105, 115, 112, 97, 116, 99, 104)), statePath: List(List(105, 116, 101, 109, 115)) }))
      .then(completeProcessSuccess(2, List({ name: cli::generatedFilename(List("0")), trace: 0, bytes: namedBytes })))
      .then(listGeneratedOutput(2, ListingSucceeded))
      .then(validateGeneratedDocument(2, namedBytes))
      .then(createDriver(2, FactorySucceeded(2)))
      .then(applyOperation(2, OperationApplied))
      .then(observeState(2, Observed(reversedItems)))
      .then(cleanWorkspace(2, StorageSucceeded))
      .expect(finishedAs(2, Passed) and safety)

  run invalidJsonReadStopsBeforeCreatingDriverTest =
    init
      .then(startRequestedRun(1, { ...sampleRequest, config: simulationWithCount(1) },
        sampleSeed, "evidence", itemsSelection))
      .then(completeProcessSuccess(1, List({ name: cli::generatedFilename(List("0")), trace: 0, bytes: List(123) })))
      .then(listGeneratedOutput(1, ListingSucceeded))
      .then(validateGeneratedDocument(1, List(123)))
      .then(cleanWorkspace(1, StorageSucceeded))
      .expect(finishedAs(1, failed(TraceFailed({
        location: AtTrace({ trace: 0, traceIndex: 0 }), cause: "invalid JSON",
      }))) and safety)
      .then(createDriver(1, FactorySucceeded(1)).fail())

  run invalidCliLimitsAreRejectedBeforeReservationTest =
    init
      .then(startRequestedRun(1, { ...sampleRequest,
        config: cli::Simulation({
          init: cli::CliDefault, step: cli::CliDefault, nTraces: cli::CliSpecified(2),
          maxSamples: cli::CliSpecified(1), maxSteps: cli::CliDefault,
        }),
      }, sampleSeed, "evidence", itemsSelection))
      .then(startRequestedRun(2, { ...sampleRequest,
        config: cli::Simulation({
          init: cli::CliDefault, step: cli::CliDefault, nTraces: cli::CliDefault,
          maxSamples: cli::CliDefault, maxSteps: cli::CliSpecified(-1),
        }),
      }, sampleSeed, "evidence", itemsSelection))
      .expect(finishedAs(1, failed(InvalidRequest(RejectedSampleLimit))) and
        finishedAs(2, failed(InvalidRequest(RejectedStepLimit))) and filesystem == initialFilesystem and safety)
}
