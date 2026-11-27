module quint_driver_lifecycle_test {
  import quint_driver_lifecycle.* from "./quint_driver_lifecycle"

  run exitsBeforeEnteringNextTraceTest =
    init.then(enter(true)).then(replay(Passed)).then(exit(false))
      .expect(lifecycle.phase == AwaitingEnter and lifecycle.exited == 1 and safety)
      .then(enter(true)).then(replay(Passed)).then(exit(false))
      .expect(lifecycle.phase == Finished and lifecycle.exited == 2 and safety)

  run failedEntryDoesNotExitTest =
    init.then(enter(false))
      .expect(lifecycle.result == EnterFailed and lifecycle.exited == 0 and safety)

  run mismatchRemainsPrimaryAfterExitFailureTest =
    init.then(enter(true)).then(replay(StatesDiffer)).then(exit(true))
      .expect(lifecycle.result == StatesDiffer and lifecycle.exitFailed and safety)

  run successfulTraceReportsExitFailureTest =
    init.then(enter(true)).then(replay(Passed)).then(exit(true))
      .expect(lifecycle.result == ExitFailed and safety)
}
