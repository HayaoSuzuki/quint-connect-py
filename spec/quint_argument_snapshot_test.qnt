module quint_argument_snapshot_test {
  import quint_values as qv from "./quint_values"
  import quint_connect_documents.* from "./quint_connect"
  import quint_connect(CALL_IDS = Set(1), WORKSPACE_IDS = Set(1), DRIVER_IDS = Set(1),
    GENERATED_INPUTS = generatedInputs, SAVED_INPUTS = Map(), SAVED_ALIASES = Map(),
    EXISTING_ARTIFACTS = Map()).* from "./quint_connect"

  pure val trace: TracePosition = { trace: 7, traceIndex: 0 }
  pure val openingContext: DriverStep = { position: { trace: trace, stepIndex: 0 }, driver: 1 }
  pure val pushContext: DriverStep = { position: { trace: trace, stepIndex: 1 }, driver: 1 }
  pure val itemsArgument: qv::Text = List(105, 116, 101, 109, 115) // items

  pure def itemsWithFlag(flag: bool): Value = {
    nodes: List(
      qv::BooleanNode(flag),
      qv::RecordNode(Map(List(102, 108, 97, 103) -> 0)), // flag
      qv::ListNode(List(1)),
    ),
    root: 2,
  }

  pure val pushStep: TraceStep = {
    operation: {
      name: List(112, 117, 115, 104), // push
      arguments: Map(itemsArgument -> itemsWithFlag(true)),
    },
    expected: integerDigit(1),
  }

  pure val argumentsAfter: qv::Text -> Value =
    Map(itemsArgument -> itemsWithFlag(false))

  pure val steps: List[TraceStep] = List(openingStep, pushStep, incrementStep)

  action startWithMatchedOpeningStep: bool =
    init
      .then(startReplay(1, List(7, 8)))
      .then(validateTrace(1, ValidSteps(steps)))
      .then(createDriver(1, FactorySucceeded(1)))
      .then(applyOperation(1, OperationApplied))
      .then(observeState(1, Observed(openingStep.expected)))

  pure val historyThroughMutation: List[Event] = List(
    ReplayRequested(List(7, 8)),
    ValidationAttempted(trace),
    TraceValidated({ position: trace, steps: steps }),
    FactoryCalled(trace),
    DriverCreated({ trace: trace, driver: 1 }),
    OperationCalled({ context: openingContext, operation: openingStep.operation }),
    ObservationCalled({ context: openingContext, expected: openingStep.expected }),
    ObservationMatched({ position: openingContext.position, actual: openingStep.expected }),
    OperationCalled({ context: pushContext, operation: pushStep.operation }),
    DriverArgumentsChanged({ context: pushContext, arguments: argumentsAfter }),
  )

  run mismatchAfterNestedArgumentMutationRetainsOriginalStepTest = {
    val actual = integerDigit(0)
    val mismatch: Mismatch = { position: pushContext.position, step: pushStep, actual: actual }
    val error = StatesDiffer({ detail: mismatch, artifacts: FromSavedTrace })
    startWithMatchedOpeningStep
      .then(applyOperationWithMutation(1, OperationApplied, argumentsAfter))
      .then(observeState(1, Observed(actual)))
      .expect(all {
        calls.get(1).phase == Finished(failed(error)),
        calls.get(1).history == historyThroughMutation.concat(List(
          ObservationCalled({ context: pushContext, expected: pushStep.expected }),
          DifferenceObserved(mismatch),
          FailureRecognized(error),
          Returned(failed(error)),
        )),
        safety,
      })
  }

  run applyFailureAfterNestedArgumentMutationStopsReplayTest = {
    val cause = "push failed after changing an item"
    val error = DriverFailed({ location: AtStep(pushContext.position), stage: Apply, cause: cause })
    startWithMatchedOpeningStep
      .then(applyOperationWithMutation(1, OperationFailed(cause), argumentsAfter))
      .expect(all {
        calls.get(1).phase == Finished(failed(error)),
        calls.get(1).history == historyThroughMutation.concat(List(
          FailureRecognized(error),
          Returned(failed(error)),
        )),
        safety,
      })
      .then(any {
        observeState(1, Observed(pushStep.expected)),
        applyOperation(1, OperationApplied),
      }.fail())
  }
}
