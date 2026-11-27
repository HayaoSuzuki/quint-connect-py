// Each successful operation either advances immediately or is observed and compared.
module quint_replay_comparison_test {
  type Mode = OperationsOnly | CompareState
  type Phase = Applying | Observing | Comparing | Finished
  type Outcome = Pending | Passed | Mismatch | ComparisonFailed

  var mode: Mode
  var phase: Phase
  var applied: int
  var observed: int
  var outcome: Outcome
  var observedValue: int
  var comparedExpected: int

  action init(selected: Mode): bool = all {
    mode' = selected,
    phase' = Applying,
    applied' = 0,
    observed' = 0,
    outcome' = Pending,
    observedValue' = 0,
    comparedExpected' = 0,
  }

  action applyOperation = all {
    phase == Applying,
    mode' = mode,
    phase' = if (mode == OperationsOnly) Finished else Observing,
    applied' = applied + 1,
    observed' = observed,
    outcome' = if (mode == OperationsOnly) Passed else Pending,
    observedValue' = observedValue,
    comparedExpected' = comparedExpected,
  }

  action observeState(value: int): bool = all {
    phase == Observing,
    mode' = mode,
    phase' = Comparing,
    applied' = applied,
    observed' = observed + 1,
    outcome' = outcome,
    observedValue' = value,
    comparedExpected' = comparedExpected,
  }

  // The comparison policy supplies the result after projecting the model value.
  action completeComparison(projected: int, result: Outcome): bool = all {
    phase == Comparing,
    result != Pending,
    mode' = mode,
    phase' = Finished,
    applied' = applied,
    observed' = observed,
    outcome' = result,
    observedValue' = observedValue,
    comparedExpected' = projected,
  }

  action initialize = any { init(OperationsOnly), init(CompareState) }

  action step = any {
    applyOperation,
    observeState(11),
    completeComparison(10, Passed),
    completeComparison(11, Mismatch),
    completeComparison(10, ComparisonFailed),
    all {
      phase == Finished,
      mode' = mode,
      phase' = phase,
      applied' = applied,
      observed' = observed,
      outcome' = outcome,
      observedValue' = observedValue,
      comparedExpected' = comparedExpected,
    },
  }

  val safety =
    observed <= applied and
    (mode == OperationsOnly implies observed == 0) and
    (phase == Finished implies outcome != Pending)

  run operationsOnlyNeverObservesTest = init(OperationsOnly)
    .then(applyOperation)
    .expect(phase == Finished and outcome == Passed and applied == 1 and observed == 0 and safety)

  run comparisonCanAcceptDifferentValuesTest = init(CompareState)
    .then(applyOperation)
    .then(observeState(11))
    .then(completeComparison(10, Passed))
    .expect(phase == Finished and outcome == Passed and comparedExpected != observedValue and safety)

  run comparisonCanRejectEqualValuesTest = init(CompareState)
    .then(applyOperation)
    .then(observeState(11))
    .then(completeComparison(11, Mismatch))
    .expect(phase == Finished and outcome == Mismatch and comparedExpected == observedValue and safety)

  run comparisonFailureStopsReplayTest = init(CompareState)
    .then(applyOperation)
    .then(observeState(11))
    .then(completeComparison(10, ComparisonFailed))
    .expect(phase == Finished and outcome == ComparisonFailed and safety)
}
