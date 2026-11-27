module quint_driver_lifecycle {
  type Phase = AwaitingEnter | Replaying | AwaitingExit | Finished
  type Result = Passed | EnterFailed | DriverFailed | StatesDiffer | ExitFailed

  var lifecycle: {
    phase: Phase,
    entered: int,
    exited: int,
    primary: Result,
    result: Result,
    exitFailed: bool,
  }

  action init = lifecycle' = {
    phase: AwaitingEnter, entered: 0, exited: 0, primary: Passed, result: Passed, exitFailed: false,
  }

  action enter(succeeded: bool): bool = all {
    lifecycle.phase == AwaitingEnter,
    lifecycle' = if (succeeded)
      { ...lifecycle, phase: Replaying, entered: lifecycle.entered + 1 }
    else
      { ...lifecycle, phase: Finished, primary: EnterFailed, result: EnterFailed },
  }

  action replay(result: Result): bool = all {
    lifecycle.phase == Replaying,
    Set(Passed, DriverFailed, StatesDiffer).contains(result),
    lifecycle' = { ...lifecycle, phase: AwaitingExit, primary: result },
  }

  action exit(failed: bool): bool = {
    val result = if (lifecycle.primary == Passed and failed) ExitFailed else lifecycle.primary
    all {
      lifecycle.phase == AwaitingExit,
      lifecycle' = {
        ...lifecycle,
        phase: if (result == Passed and lifecycle.entered < 2) AwaitingEnter else Finished,
        exited: lifecycle.exited + 1,
        result: result,
        exitFailed: failed,
      },
    }
  }

  action step = any {
    enter(true),
    enter(false),
    replay(Passed),
    replay(DriverFailed),
    replay(StatesDiffer),
    exit(false),
    exit(true),
    all { lifecycle.phase == Finished, lifecycle' = lifecycle },
  }

  val balanced = all {
    lifecycle.entered >= 0 and lifecycle.entered <= 2,
    lifecycle.exited >= 0,
    if (Set(Replaying, AwaitingExit).contains(lifecycle.phase))
      lifecycle.entered == lifecycle.exited + 1
    else
      lifecycle.entered == lifecycle.exited,
  }

  val preservesPrimary =
    lifecycle.phase == Finished implies
      lifecycle.result ==
        (if (lifecycle.primary == Passed and lifecycle.exitFailed) ExitFailed else lifecycle.primary)

  val safety = balanced and preservesPrimary
}
