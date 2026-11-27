module quint_saved_replay_test {
  import quint_connect_documents.* from "./quint_connect"
  import quint_filesystem as fs from "./quint_filesystem"
  import quint_connect(CALL_IDS = Set(1, 2), WORKSPACE_IDS = Set(1, 2), DRIVER_IDS = Set(1, 2),
    JSON_LABELS = jsonLabels, GENERATED_INPUTS = generatedInputs, SAVED_INPUTS = savedInputs).* from "./quint_connect"

  pure val firstPosition: TracePosition = { trace: 0, traceIndex: 0 }
  pure val secondPosition: TracePosition = { trace: 1, traceIndex: 1 }

  def finishedAs(result: Outcome): bool = calls.get(1).phase == Finished(result)

  def pathWasOpened(path: fs::FilePath, position: TracePosition): bool =
    hasEvent(calls.get(1).history, event => event == SavedReadAttempted({ path: path, position: position }))

  run missingFileReportsItsPathAndStopsBeforeDriverTest =
    init
      .then(startReplayPaths(1, List(fs::SavedFile("missing.itf.json"), fs::SavedFile("good.itf.json")), itemsSelection))
      .then(readSavedPath(1, SavedReadSucceeded))
      .expect(finishedAs(failed(TraceFailed({
        location: AtSavedTrace({ path: fs::SavedFile("missing.itf.json"), position: firstPosition }),
        cause: "file not found",
      }))) and safety)
      .expect(pathWasOpened(fs::SavedFile("missing.itf.json"), firstPosition) and
        not(pathWasOpened(fs::SavedFile("good.itf.json"), secondPosition)))
      .then(createDriver(1, FactorySucceeded(1)).fail())

  run readFailurePreservesPathAndCauseTest =
    init
      .then(startReplayPaths(1, List(fs::SavedFile("good.itf.json")), itemsSelection))
      .then(readSavedPath(1, SavedReadFailed("permission denied")))
      .expect(finishedAs(failed(TraceFailed({
        location: AtSavedTrace({ path: fs::SavedFile("good.itf.json"), position: firstPosition }),
        cause: "permission denied",
      }))) and filesystem == initialFilesystem and safety)

  run malformedSecondFileIsOpenedAfterFirstDriverCompletesTest =
    init
      .then(startReplayPaths(1, List(fs::SavedFile("good.itf.json"), fs::SavedFile("bad.itf.json"), fs::SavedFile("empty.itf.json")), itemsSelection))
      .then(readSavedPath(1, SavedReadSucceeded))
      .expect(pathWasOpened(fs::SavedFile("good.itf.json"), firstPosition) and
        not(pathWasOpened(fs::SavedFile("bad.itf.json"), secondPosition)))
      .then(createDriver(1, FactorySucceeded(1)))
      .then(applyOperation(1, OperationApplied))
      .then(observeState(1, Observed(itemSet)))
      .then(readSavedPath(1, SavedReadSucceeded))
      .expect(finishedAs(failed(TraceFailed({
        location: AtSavedTrace({ path: fs::SavedFile("bad.itf.json"), position: secondPosition }),
        cause: "invalid JSON",
      }))) and safety)
      .expect(pathWasOpened(fs::SavedFile("bad.itf.json"), secondPosition) and not(pathWasOpened(fs::SavedFile("empty.itf.json"), {
        trace: 2, traceIndex: 2,
      })))

  run repeatedPathIsReadAndGetsFreshDriverEachTimeTest =
    init
      .then(startReplayPaths(1, List(fs::SavedFile("good.itf.json"), fs::SavedFile("good.itf.json")), itemsSelection))
      .then(readSavedPath(1, SavedReadSucceeded))
      .then(createDriver(1, FactorySucceeded(1)))
      .then(applyOperation(1, OperationApplied))
      .then(observeState(1, Observed(itemSet)))
      .then(readSavedPath(1, SavedReadSucceeded))
      .then(createDriver(1, FactorySucceeded(2)))
      .then(applyOperation(1, OperationApplied))
      .then(observeState(1, Observed(itemSet)))
      .expect(finishedAs(Passed) and safety)
      .expect(pathWasOpened(fs::SavedFile("good.itf.json"), firstPosition) and pathWasOpened(fs::SavedFile("good.itf.json"), secondPosition))

  run savedPathIsRetainedInMismatchAndNextFileIsNotOpenedTest =
    init
      .then(startReplayPaths(1, List(fs::SavedFile("good.itf.json"), fs::SavedFile("missing.itf.json")), itemsSelection))
      .then(readSavedPath(1, SavedReadSucceeded))
      .then(createDriver(1, FactorySucceeded(1)))
      .then(applyOperation(1, OperationApplied))
      .then(observeState(1, Observed(integerDigit(1))))
      .expect(safety and filesystem == initialFilesystem and
        not(pathWasOpened(fs::SavedFile("missing.itf.json"), secondPosition)))
      .expect(hasEvent(calls.get(1).history, event =>
        match event {
          | FailureRecognized(error) =>
            match error {
              | StatesDiffer(mismatch) =>
                mismatch.artifacts == FromSavedFile(fs::SavedFile("good.itf.json")) and
                  mismatch.detail.position == { trace: firstPosition, stepIndex: 0 }
              | _ => false
            }
          | _ => false
        }
      ))

  run emptySavedFileAndEmptyPathListHaveDifferentDiagnosticsTest =
    init
      .then(startReplayPaths(1, List(fs::SavedFile("empty.itf.json")), itemsSelection))
      .then(readSavedPath(1, SavedReadSucceeded))
      .then(startReplayPaths(2, List(), itemsSelection))
      .expect(finishedAs(failed(EmptyTrace(NoSavedTraceStates({
        path: fs::SavedFile("empty.itf.json"), position: firstPosition,
      })))) and calls.get(2).phase == Finished(failed(EmptyTrace(NoInputPaths))) and safety)

  run invalidStepDiagnosticIdentifiesTheSavedFileAndStepTest =
    init
      .then(startReplayPaths(1, List(fs::SavedFile("named.itf.json")), itemsSelection))
      .then(readSavedPath(1, SavedReadSucceeded))
      .expect(finishedAs(failed(TraceFailed({
        location: AtSavedStep({ path: fs::SavedFile("named.itf.json"), position: { trace: firstPosition, stepIndex: 0 } }),
        cause: "invalid operation",
      }))) and safety)
}
