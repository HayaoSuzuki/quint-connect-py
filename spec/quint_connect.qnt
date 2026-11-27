// Observable behavior of run() and replay() in issue #1.
// Calls progress independently through command planning, ITF decoding, comparison,
// and filesystem effects. Process and operating-system outcomes are external inputs.
module quint_connect {
  import quint_values as qv from "./quint_values"
  import quint_itf as itf from "./quint_itf"
  import quint_cli as cli from "./quint_cli"
  import quint_path_search as path from "./quint_path_search"
  import quint_filesystem as fs from "./quint_filesystem"

  type CallId = int
  type WorkspaceId = int
  type DriverId = int
  type TraceId = int
  type Seed = List[str]

  pure val sampleSeed: Seed = List("4", "2")
  pure val defaultArtifactRoot: str = "default artifacts"
  pure val defaultSelection: itf::Selection = { actionPath: List(), statePath: List() }

  type Value = { nodes: List[qv::ValueNode], root: int }

  pure def integerDigit(digit: int): Value =
    { nodes: List(qv::IntegerNode({ negative: false, digits: List(digit) })), root: 0 }

  pure def booleanValue(value: bool): Value =
    { nodes: List(qv::BooleanNode(value)), root: 0 }

  pure def textValue(value: qv::Text): Value =
    { nodes: List(qv::TextNode(value)), root: 0 }

  type OperationArguments = qv::Text -> Value
  type Operation = {
    name: qv::Text,
    arguments: OperationArguments,
  }

  type TraceStep = {
    operation: Operation,
    expected: Value,
  }

  type OutputExpectation = SimulationCount(int) | NamedTestOutput

  type Generation = {
    expectation: OutputExpectation,
    seed: Seed,
    workspace: WorkspaceId,
    artifactRoot: str,
  }

  type Source =
    | SavedItf
    | SavedPaths(List[fs::FilePath])
    | GeneratedItf(Generation)

  type TracePosition = {
    trace: TraceId,
    traceIndex: int,
  }

  type StepPosition = {
    trace: TracePosition,
    stepIndex: int,
  }

  type TraceBasenames = TraceId -> List[str]

  type TraceBatch = {
    source: Source,
    traces: List[TraceId],
    basenames: TraceBasenames,
    traceIndex: int,
  }

  type ValidatedTrace = {
    batch: TraceBatch,
    steps: List[TraceStep],
  }

  type ActiveTrace = {
    validated: ValidatedTrace,
    driver: DriverId,
    stepIndex: int,
  }

  type ProcessOutput = { stdout: fs::Bytes, stderr: fs::Bytes }
  type ProcessIoStage = WaitForExit | CollectOutput
  type ProcessIoProblem = { stage: ProcessIoStage, cause: str }
  type ExitKnowledge = ExitConfirmed(fs::TraceFiles) | ExitUnconfirmed
  type ProcessProblem =
    | SpawnFailure(str)
    | NonzeroExit({ code: int, output: ProcessOutput })
    | SignalExit({ signal: int, output: ProcessOutput })
    | ProcessIoFailure(ProcessIoProblem)

  // Successful process output is listed before replay.
  type GenerationResult = ProcessFailed(ProcessProblem) | OutputUnavailable(str) | ProcessSucceeded(List[TraceId])

  pure val noProcessOutput: ProcessOutput = { stdout: List(), stderr: List() }

  pure def validProcessOutput(output: ProcessOutput): bool =
    fs::validBytes(output.stdout) and fs::validBytes(output.stderr)

  pure def isExitProblem(problem: ProcessProblem): bool =
    match problem {
      | SpawnFailure(_) => false
      | ProcessIoFailure(_) => false
      | NonzeroExit(exit) => exit.code != 0 and validProcessOutput(exit.output)
      | SignalExit(exit) => exit.signal > 0 and validProcessOutput(exit.output)
    }

  type ListingResult = ListingSucceeded | ListingFailed(str)

  type SavedTracePosition = { path: fs::FilePath, position: TracePosition }
  type GeneratedTracePosition = { path: fs::FilePath, basename: List[str], position: TracePosition }

  type Location =
    | AtTrace(TracePosition)
    | AtStep(StepPosition)
    | AtGeneratedTrace(GeneratedTracePosition)
    | AtSavedTrace(SavedTracePosition)
    | AtSavedStep({ path: fs::FilePath, position: StepPosition })

  type ReadResult = ReadSucceeded | ReadFailed(str)

  type TraceError = {
    location: Location,
    cause: str,
  }

  type ParseLocation = InvalidFile | InvalidStep(int)

  type ValidationResult =
    | ValidSteps(List[TraceStep])
    | EmptyStates
    | InvalidItf({ location: ParseLocation, cause: str })

  pure def fromDecodedStep(decoded: itf::DecodedStep): TraceStep =
    { operation: { name: decoded.name, arguments: decoded.arguments }, expected: decoded.expected }

  pure def itfProblem(problem: itf::StepProblem): str =
    match problem {
      | StateNotRecord => "ITF state must be a record"
      | MissingDeclaredVariable => "ITF state omits a declared variable"
      | InvalidOperation => "invalid operation"
      | InvalidArgument => "invalid operation argument"
      | InvalidExpectedValue => "invalid expected value"
    }

  pure def fromDecodedTrace(result: itf::DecodeResult): ValidationResult =
    match result {
      | DecodedTrace(steps) =>
        ValidSteps(steps.foldl(List(), (acc, decoded) => acc.append(fromDecodedStep(decoded))))
      | NoStates => EmptyStates
      | InvalidTrace(error) =>
        match error {
          | InvalidJsonTree => InvalidItf({ location: InvalidFile, cause: "invalid JSON tree" })
          | InvalidEnvelope => InvalidItf({ location: InvalidFile, cause: "invalid ITF envelope" })
          | AtState(detail) =>
            InvalidItf({ location: InvalidStep(detail.index), cause: itfProblem(detail.problem) })
        }
    }

  type DriverStage = Factory | Apply | Observe

  type DriverErrorDetail = {
    location: Location,
    stage: DriverStage,
    cause: str,
  }

  type FactoryResult = FactorySucceeded(DriverId) | FactoryFailed(str)
  type OperationResult = OperationApplied | OperationFailed(str)
  type DriverArgumentUpdate = ArgumentsUnchanged | ArgumentsReplaced(OperationArguments)
  type ObservationResult = Observed(Value) | ObservationFailed(str)
  type StorageResult = StorageSucceeded | StorageFailed(str)

  type DriverStep = {
    position: StepPosition,
    driver: DriverId,
  }

  type Mismatch = {
    position: StepPosition,
    step: TraceStep,
    actual: Value,
  }

  type ArtifactDirectoryProblem = { root: str, directory: int, cause: str }
  type SaveResult = ArtifactSaved(fs::FilePath) | ArtifactDirectoryFailed(ArtifactDirectoryProblem) | ArtifactSaveFailed(str)
  type ArtifactPreparation = ArtifactUnplanned | ArtifactCandidates(List[int]) | ArtifactReadyToCopy
  type DirectoryAttempt = DirectoryReserved | DirectoryCollision | DirectoryRejected(str)

  type Artifacts =
    | FromSavedTrace
    | FromSavedFile(fs::FilePath)
    | FromGeneration({ seed: Seed, save: SaveResult })

  type EmptyInput = NoInputPaths | NoGeneratedItf | NoTraceStates(TracePosition) | NoSavedTraceStates(SavedTracePosition)

  type WorkspaceStage = Reserve | Cleanup

  type RequestProblem =
    | RejectedSeed
    | RejectedTraceCount
    | RejectedActionPath
    | RejectedSampleLimit
    | RejectedStepLimit

  type PathEnvironment = { directories: List[cli::InputPath], observations: path::Candidate -> path::Observation }
  type PathLookup = { callerDirectory: str, name: str, environment: PathEnvironment, result: path::SearchResult }
  type ExecutionTarget = ExplicitExecutable(cli::ResolvedPath) | ExecutableOnPath(path::Candidate)

  type Failure =
    | InvalidRequest(RequestProblem)
    | WorkspaceFailed({ seed: Seed, stage: WorkspaceStage, cause: str })
    | QuintFailed({ seed: Seed, problem: ProcessProblem })
    | ExecutableLookupFailed({ seed: Seed, problem: path::Resolution })
    | OutputListingFailed({ seed: Seed, workspace: WorkspaceId, cause: str })
    | EmptyTrace(EmptyInput)
    | IncompleteGeneration({ seed: Seed, requested: int, produced: int })
    | TraceFailed(TraceError)
    | DriverFailed(DriverErrorDetail)
    | StatesDiffer({ detail: Mismatch, artifacts: Artifacts })

  type CleanupNote = NoCleanupError | CleanupAlsoFailed(str) | CleanupDeferred({ workspace: WorkspaceId, cause: str })

  type Outcome = Passed | Failed({ error: Failure, cleanup: CleanupNote })

  type Phase =
    | Ready
    | AwaitingSpawn(Generation)
    | AwaitingGeneration(Generation)
    | AwaitingExitConfirmation({ generation: Generation, problem: ProcessIoProblem })
    | AwaitingListing({ generation: Generation, entries: List[cli::GeneratedEntry] })
    | AwaitingValidation(TraceBatch)
    | AwaitingDriver(ValidatedTrace)
    | AwaitingOperation(ActiveTrace)
    | AwaitingObservation(ActiveTrace)
    | AwaitingArtifact({ generation: Generation, detail: Mismatch, preparation: ArtifactPreparation })
    | AwaitingCleanup({ generation: Generation, result: Outcome })
    | Finished(Outcome)

  // The history records observable calls in order, including calls that fail.
  type Event =
    | ReplayRequested(List[TraceId])
    | ReplayFilesRequested(List[fs::FilePath])
    | SavedReadAttempted(SavedTracePosition)
    | GeneratedReadAttempted(GeneratedTracePosition)
    | PathSearchCompleted(PathLookup)
    | CommandPrepared({
        request: cli::CliRequest, drawnSeed: Seed, command: cli::QuintCommand, target: ExecutionTarget,
      })
    | WorkspaceReserved(Generation)
    | ProcessStarted(Generation)
    | ProcessExitedSuccessfully(Generation)
    | ProcessIoFailed({ generation: Generation, problem: ProcessIoProblem, exit: ExitKnowledge })
    | ChildExitConfirmed(Generation)
    | GenerationCompleted({ generation: Generation, result: GenerationResult, basenames: TraceBasenames })
    | ValidationAttempted(TracePosition)
    | TraceValidated({ position: TracePosition, steps: List[TraceStep] })
    | FactoryCalled(TracePosition)
    | DriverCreated({ trace: TracePosition, driver: DriverId })
    | OperationCalled({ context: DriverStep, operation: Operation })
    | DriverArgumentsChanged({ context: DriverStep, arguments: OperationArguments })
    | ObservationCalled({ context: DriverStep, expected: Value })
    | ObservationMatched({ position: StepPosition, actual: Value })
    | DifferenceObserved(Mismatch)
    | ArtifactDirectoryTried({ root: str, directory: int, result: DirectoryAttempt })
    | SaveAttempted({ position: TracePosition, result: SaveResult })
    | CleanupAttempted({ workspace: WorkspaceId, result: StorageResult })
    | WorkspaceCleanupDeferred({ workspace: WorkspaceId, cause: str })
    | FailureRecognized(Failure)
    | Returned(Outcome)

  type CallState = {
    phase: Phase,
    history: List[Event],
    selection: itf::Selection,
  }

  const CALL_IDS: Set[CallId]
  const WORKSPACE_IDS: Set[WorkspaceId]
  const DRIVER_IDS: Set[DriverId]
  const GENERATED_INPUTS: Set[fs::Bytes]
  const SAVED_INPUTS: str -> fs::Bytes
  const SAVED_ALIASES: str -> fs::FilePath
  const EXISTING_ARTIFACTS: fs::ArtifactDirectory -> fs::TraceFiles

  pure val initialFilesystem: fs::FileSystem = {
    val saved = SAVED_INPUTS.keys().fold(Map(), (acc, path) => acc.put(fs::SavedFile(path), SAVED_INPUTS.get(path)))
    val existing = EXISTING_ARTIFACTS.keys().fold(saved, (files, directory) => {
      val traces = EXISTING_ARTIFACTS.get(directory)
      traces.keys().fold(files, (acc, trace) =>
        acc.put(fs::evidencePath(directory.root, directory.directory, trace), traces.get(trace)))
    })
    {
      ...fs::emptyFileSystem,
      files: existing,
      aliases: SAVED_ALIASES.keys().fold(Map(), (acc, path) => acc.put(fs::SavedFile(path), SAVED_ALIASES.get(path))),
      artifactDirectories: EXISTING_ARTIFACTS.keys().mapBy(_ => fs::ExistingArtifactDirectory),
    }
  }

  var calls: CallId -> CallState
  var filesystem: fs::FileSystem
  var lastStepReducedWork: bool

  pure def recordEvent(s: CallState, phase: Phase, event: Event): CallState =
    { ...s, phase: phase, history: s.history.append(event) }

  pure def failed(error: Failure): Outcome =
    Failed({ error: error, cleanup: NoCleanupError })

  pure def returned(s: CallState, result: Outcome): CallState =
    recordEvent(s, Finished(result), Returned(result))

  pure def onReplay(s: CallState, source: Source, traces: List[TraceId]): CallState = {
    val request = match source {
      | SavedPaths(paths) => ReplayFilesRequested(paths)
      | _ => ReplayRequested(traces)
    }
    val recorded = recordEvent(s, s.phase, request)
    if (traces.length() == 0)
      stop(recorded, source, EmptyTrace(NoInputPaths))
    else
      { ...recorded, phase: AwaitingValidation({ source: source, traces: traces, basenames: Map(), traceIndex: 0 }) }
  }

  pure def finish(s: CallState, source: Source, result: Outcome): CallState =
    match source {
      | SavedItf => returned(s, result)
      | SavedPaths(_) => returned(s, result)
      | GeneratedItf(generation) =>
        { ...s, phase: AwaitingCleanup({ generation: generation, result: result }) }
    }

  pure def stop(s: CallState, source: Source, error: Failure): CallState =
    finish(recordEvent(s, s.phase, FailureRecognized(error)), source, failed(error))

  pure def validExpectation(expectation: OutputExpectation): bool =
    match expectation {
      | SimulationCount(requested) => requested > 0
      | NamedTestOutput => true
    }

  pure def hasEnoughTraces(expectation: OutputExpectation, produced: int): bool =
    match expectation {
      | SimulationCount(requested) => produced >= requested
      | NamedTestOutput => produced > 0
    }

  pure def onGeneration(s: CallState, g: Generation, result: GenerationResult, basenames: TraceBasenames): CallState = {
    val recorded = recordEvent(s, s.phase, GenerationCompleted({ generation: g, result: result, basenames: basenames }))
    val source = GeneratedItf(g)
    match result {
      | ProcessFailed(problem) => stop(recorded, source, QuintFailed({ seed: g.seed, problem: problem }))
      | OutputUnavailable(cause) => stop(recorded, source, OutputListingFailed({
          seed: g.seed, workspace: g.workspace, cause: cause,
        }))
      | ProcessSucceeded(traces) =>
        if (traces.length() == 0)
          stop(recorded, source, EmptyTrace(NoGeneratedItf))
        else
          match g.expectation {
            | SimulationCount(requested) =>
              if (hasEnoughTraces(g.expectation, traces.length()))
                { ...recorded, phase: AwaitingValidation({ source: source, traces: traces, basenames: basenames, traceIndex: 0 }) }
              else
                stop(recorded, source, IncompleteGeneration({
                  seed: g.seed, requested: requested, produced: traces.length(),
                }))
            | NamedTestOutput =>
              { ...recorded, phase: AwaitingValidation({ source: source, traces: traces, basenames: basenames, traceIndex: 0 }) }
          }
    }
  }

  pure def tracePosition(batch: TraceBatch): TracePosition =
    { trace: batch.traces.nth(batch.traceIndex), traceIndex: batch.traceIndex }

  pure def errorLocation(batch: TraceBatch, location: ParseLocation): Location = {
    val position = tracePosition(batch)
    match batch.source {
      | SavedPaths(paths) => {
        val path = paths.nth(batch.traceIndex)
        match location {
          | InvalidFile => AtSavedTrace({ path: path, position: position })
          | InvalidStep(index) =>
            AtSavedStep({ path: path, position: { trace: position, stepIndex: index } })
        }
      }
      | _ =>
        match location {
          | InvalidFile => AtTrace(position)
          | InvalidStep(index) => AtStep({ trace: position, stepIndex: index })
        }
    }
  }

  pure def emptyTraceInput(batch: TraceBatch): EmptyInput =
    match batch.source {
      | SavedPaths(paths) => NoSavedTraceStates({ path: paths.nth(batch.traceIndex), position: tracePosition(batch) })
      | _ => NoTraceStates(tracePosition(batch))
    }

  pure def onValidation(s: CallState, batch: TraceBatch, result: ValidationResult): CallState = {
    val position = tracePosition(batch)
    val recorded = recordEvent(s, s.phase, ValidationAttempted(position))
    match result {
      | ValidSteps(steps) => recordEvent(
          recorded,
          AwaitingDriver({ batch: batch, steps: steps }),
          TraceValidated({ position: position, steps: steps })
        )
      | EmptyStates => stop(recorded, batch.source, EmptyTrace(emptyTraceInput(batch)))
      | InvalidItf(error) =>
        stop(recorded, batch.source, TraceFailed({
          location: errorLocation(batch, error.location), cause: error.cause,
        }))
    }
  }

  pure def validValidation(result: ValidationResult): bool =
    match result {
      | ValidSteps(steps) => steps.length() > 0
      | _ => true
    }

  pure def onFactory(s: CallState, validated: ValidatedTrace, result: FactoryResult): CallState = {
    val position = tracePosition(validated.batch)
    val recorded = recordEvent(s, s.phase, FactoryCalled(position))
    match result {
      | FactorySucceeded(driver) => recordEvent(
          recorded,
          AwaitingOperation({ validated: validated, driver: driver, stepIndex: 0 }),
          DriverCreated({ trace: position, driver: driver })
        )
      | FactoryFailed(cause) =>
        stop(recorded, validated.batch.source, DriverFailed({
          location: errorLocation(validated.batch, InvalidFile), stage: Factory, cause: cause,
        }))
    }
  }

  pure def currentStep(active: ActiveTrace): TraceStep =
    active.validated.steps.nth(active.stepIndex)

  pure def driverStep(active: ActiveTrace): DriverStep =
    { position: { trace: tracePosition(active.validated.batch), stepIndex: active.stepIndex }, driver: active.driver }

  pure def onOperation(
    s: CallState, active: ActiveTrace, result: OperationResult, update: DriverArgumentUpdate
  ): CallState = {
    val context = driverStep(active)
    val called = recordEvent(s, s.phase, OperationCalled({ context: context, operation: currentStep(active).operation }))
    // Only the copy handed to the callback can change. The validated step
    // remains the source of the arguments recorded in mismatch diagnostics.
    val recorded = match update {
      | ArgumentsUnchanged => called
      | ArgumentsReplaced(arguments) =>
        recordEvent(called, s.phase, DriverArgumentsChanged({ context: context, arguments: arguments }))
    }
    match result {
      | OperationApplied => { ...recorded, phase: AwaitingObservation(active) }
      | OperationFailed(cause) =>
        stop(recorded, active.validated.batch.source, DriverFailed({
          location: errorLocation(active.validated.batch, InvalidStep(active.stepIndex)), stage: Apply, cause: cause,
        }))
    }
  }

  pure def afterMatch(s: CallState, active: ActiveTrace): CallState = {
    val batch = active.validated.batch
    val followingStep = active.stepIndex + 1
    val followingTrace = batch.traceIndex + 1
    if (followingStep < active.validated.steps.length())
      { ...s, phase: AwaitingOperation({ ...active, stepIndex: followingStep }) }
    else if (followingTrace < batch.traces.length())
      { ...s, phase: AwaitingValidation({ ...batch, traceIndex: followingTrace }) }
    else
      finish(s, batch.source, Passed)
  }

  pure def onMismatch(s: CallState, source: Source, detail: Mismatch): CallState = {
    val recorded = recordEvent(s, s.phase, DifferenceObserved(detail))
    match source {
      | SavedItf => stop(recorded, source, StatesDiffer({ detail: detail, artifacts: FromSavedTrace }))
      | SavedPaths(paths) => stop(recorded, source, StatesDiffer({
          detail: detail, artifacts: FromSavedFile(paths.nth(detail.position.trace.traceIndex)),
        }))
      | GeneratedItf(g) => { ...recorded, phase: AwaitingArtifact({ generation: g, detail: detail, preparation: ArtifactUnplanned }) }
    }
  }

  pure def onObservation(s: CallState, active: ActiveTrace, result: ObservationResult): CallState = {
    val context = driverStep(active)
    val stepData = currentStep(active)
    val source = active.validated.batch.source
    val recorded = recordEvent(s, s.phase, ObservationCalled({ context: context, expected: stepData.expected }))
    match result {
      | Observed(actual) =>
        if (not(qv::isUsable(actual)))
          stop(recorded, source, DriverFailed({
            location: errorLocation(active.validated.batch, InvalidStep(active.stepIndex)), stage: Observe, cause: "invalid driver observation",
          }))
        else if (qv::equalValues(stepData.expected, actual))
          afterMatch(recordEvent(recorded, recorded.phase, ObservationMatched({ position: context.position, actual: actual })), active)
        else
          onMismatch(recorded, source, { position: context.position, step: stepData, actual: actual })
      | ObservationFailed(cause) =>
        stop(recorded, source, DriverFailed({
          location: errorLocation(active.validated.batch, InvalidStep(active.stepIndex)), stage: Observe, cause: cause,
        }))
    }
  }

  pure def onArtifact(s: CallState, g: Generation, detail: Mismatch, save: SaveResult): CallState = {
    val recorded = recordEvent(s, s.phase, SaveAttempted({ position: detail.position.trace, result: save }))
    stop(recorded, GeneratedItf(g), StatesDiffer({
      detail: detail,
      artifacts: FromGeneration({ seed: g.seed, save: save }),
    }))
  }

  pure def onCleanup(s: CallState, g: Generation, primary: Outcome, result: StorageResult): CallState = {
    val recorded = recordEvent(s, s.phase, CleanupAttempted({ workspace: g.workspace, result: result }))
    match result {
      | StorageSucceeded => returned(recorded, primary)
      | StorageFailed(cause) =>
        match primary {
          | Passed => stop(recorded, SavedItf, WorkspaceFailed({ seed: g.seed, stage: Cleanup, cause: cause }))
          | Failed(failure) => returned(recorded, Failed({ ...failure, cleanup: CleanupAlsoFailed(cause) }))
        }
    }
  }

  action init: bool = all {
    calls' = CALL_IDS.mapBy(_ => { phase: Ready, history: List(), selection: defaultSelection }),
    filesystem' = initialFilesystem,
    lastStepReducedWork' = true,
  }

  action changeCallWithFiles(id: CallId, updated: CallState, snapshot: fs::FileSystem): bool = {
    val nextCalls = calls.set(id, updated)
    all {
      calls' = nextCalls,
      filesystem' = snapshot,
      lastStepReducedWork' = workLess(totalWork(nextCalls, snapshot), totalWork(calls, filesystem)),
    }
  }

  action changeCall(id: CallId, updated: CallState): bool =
    changeCallWithFiles(id, updated, filesystem)

  // Branches of an action-valued match must declare the same updates.
  // The false guard keeps a phase mismatch from producing a transition.
  action inapplicable: bool = all {
    false,
    calls' = calls,
    filesystem' = filesystem,
    lastStepReducedWork' = lastStepReducedWork,
  }

  action startReplayWithSelection(id: CallId, traces: List[TraceId], selection: itf::Selection): bool = all {
    calls.get(id).phase == Ready,
    changeCall(id, onReplay({ ...calls.get(id), selection: selection }, SavedItf, traces)),
  }

  action startReplay(id: CallId, traces: List[TraceId]): bool =
    startReplayWithSelection(id, traces, defaultSelection)

  // Replay accepts caller files and published artifact paths, including paths that do not yet exist.
  action startReplayPaths(id: CallId, paths: List[fs::FilePath], selection: itf::Selection): bool = all {
    calls.get(id).phase == Ready,
    paths.indices().forall(i =>
      match paths.nth(i) {
        | WorkingFile(_) => false
        | _ => true
      }
    ),
    changeCall(id, onReplay(
      { ...calls.get(id), selection: selection }, SavedPaths(paths), range(0, paths.length())
    )),
  }

  action reserveRun(id: CallId, g: Generation, requestState: CallState): bool = all {
    calls.get(id).phase == Ready,
    cli::validSeed(g.seed),
    validExpectation(g.expectation),
    WORKSPACE_IDS.contains(g.workspace),
    fs::canReserveFiles(filesystem, g.workspace, id),
    changeCallWithFiles(
      id,
      recordEvent(requestState, AwaitingSpawn(g), WorkspaceReserved(g)),
      fs::reserveFiles(filesystem, g.workspace, id, g.seed, g.artifactRoot)
    ),
  }

  action startRun(id: CallId, g: Generation): bool =
    reserveRun(id, g, calls.get(id))

  pure def commandExpectation(config: cli::QuintConfig): OutputExpectation =
    match config {
      | Simulation(options) => SimulationCount(cli::optionOr(options.nTraces, 1))
      | NamedTestMode(_) => NamedTestOutput
    }

  action rejectRunRequest(id: CallId, problem: RequestProblem): bool = all {
    calls.get(id).phase == Ready,
    changeCall(id, stop(calls.get(id), SavedItf, InvalidRequest(problem))),
  }

  pure def hasActionSource(config: cli::QuintConfig, selection: itf::Selection): bool =
    match config {
      | Simulation(_) => true
      | NamedTestMode(_) => selection.actionPath.length() > 0
    }

  action reservePlannedRun(
    id: CallId, request: cli::CliRequest, drawnSeed: Seed, command: cli::QuintCommand,
    artifactRoot: str, state: CallState, target: ExecutionTarget
  ): bool =
    reserveRun(id, {
      expectation: commandExpectation(request.config), seed: command.seed,
      workspace: command.workspace, artifactRoot: artifactRoot,
    }, recordEvent(state, Ready, CommandPrepared({
      request: request, drawnSeed: drawnSeed, command: command, target: target,
    })))

  action startRequestedRunWithPath(
    id: CallId, request: cli::CliRequest, drawnSeed: Seed, artifactRoot: str, selection: itf::Selection,
    environment: PathEnvironment
  ): bool =
    match cli::quintCommand(request, drawnSeed) {
      | InvalidSeed => rejectRunRequest(id, RejectedSeed)
      | InvalidTraceCount => rejectRunRequest(id, RejectedTraceCount)
      | InvalidSampleLimit => rejectRunRequest(id, RejectedSampleLimit)
      | InvalidStepLimit => rejectRunRequest(id, RejectedStepLimit)
      | CommandReady(command) =>
        if (hasActionSource(request.config, selection)) {
          val state = { ...calls.get(id), selection: selection }
          match command.executable {
            | DirectExecutable(executable) => reservePlannedRun(
                id, request, drawnSeed, command, artifactRoot, state, ExplicitExecutable(executable))
            | SearchCallerPath(search) => {
              val result = path::searchPath(search.directory, search.name, environment.directories, environment.observations)
              val resolved = recordEvent(state, Ready, PathSearchCompleted({
                callerDirectory: search.directory, name: search.name, environment: environment, result: result,
              }))
              match result.resolution {
                | Found(candidate) => reservePlannedRun(
                    id, request, drawnSeed, command, artifactRoot, resolved, ExecutableOnPath(candidate))
                | _ => all {
                    calls.get(id).phase == Ready,
                    changeCall(id, stop(resolved, SavedItf, ExecutableLookupFailed({
                      seed: command.seed, problem: result.resolution,
                    }))),
                  }
              }
            }
          }
        } else rejectRunRequest(id, RejectedActionPath)
    }

  action startRequestedRun(
    id: CallId, request: cli::CliRequest, drawnSeed: Seed, artifactRoot: str, selection: itf::Selection
  ): bool =
    startRequestedRunWithPath(id, request, drawnSeed, artifactRoot, selection, { directories: List(), observations: Map() })

  action failReservation(id: CallId, seed: Seed, cause: str): bool = all {
    calls.get(id).phase == Ready,
    changeCall(id, stop(calls.get(id), SavedItf, WorkspaceFailed({ seed: seed, stage: Reserve, cause: cause }))),
  }

  action startProcess(id: CallId): bool =
    match calls.get(id).phase {
      | AwaitingSpawn(g) =>
        changeCall(id, recordEvent(calls.get(id), AwaitingGeneration(g), ProcessStarted(g)))
      | _ => inapplicable
    }

  action failSpawn(id: CallId, cause: str): bool =
    match calls.get(id).phase {
      | AwaitingSpawn(g) => {
        val output = fs::AbortedFiles(Map())
        all {
          fs::canRecordTraceFiles(filesystem, g.workspace, output),
          changeCallWithFiles(id, onGeneration(calls.get(id), g, ProcessFailed(SpawnFailure(cause)), Map()),
            fs::recordTraceFiles(filesystem, g.workspace, output)),
        }
      }
      | _ => inapplicable
    }

  pure def processIoError(g: Generation, problem: ProcessIoProblem): Failure =
    QuintFailed({ seed: g.seed, problem: ProcessIoFailure(problem) })

  action recordAbortedWorkspace(id: CallId, g: Generation, state: CallState, partial: fs::TraceFiles): bool = {
    val output = fs::AbortedFiles(partial)
    all {
      fs::canRecordTraceFiles(filesystem, g.workspace, output),
      changeCallWithFiles(id, state, fs::recordTraceFiles(filesystem, g.workspace, output)),
    }
  }

  action failProcessIo(id: CallId, problem: ProcessIoProblem, exit: ExitKnowledge): bool =
    match calls.get(id).phase {
      | AwaitingGeneration(g) => {
        val current = calls.get(id)
        val observed = recordEvent(current, current.phase, ProcessIoFailed({
          generation: g, problem: problem, exit: exit,
        }))
        val error = processIoError(g, problem)
        match exit {
          | ExitConfirmed(partial) =>
            recordAbortedWorkspace(id, g, stop(observed, GeneratedItf(g), error), partial)
          | ExitUnconfirmed =>
            changeCall(id, recordEvent(observed, AwaitingExitConfirmation({
              generation: g, problem: problem,
            }), FailureRecognized(error)))
        }
      }
      | _ => inapplicable
    }

  action confirmChildExit(id: CallId, partial: fs::TraceFiles): bool =
    match calls.get(id).phase {
      | AwaitingExitConfirmation(ctx) => {
        val current = calls.get(id)
        val confirmed = recordEvent(current, current.phase, ChildExitConfirmed(ctx.generation))
        val result = failed(processIoError(ctx.generation, ctx.problem))
        recordAbortedWorkspace(id, ctx.generation, finish(confirmed, GeneratedItf(ctx.generation), result), partial)
      }
      | _ => inapplicable
    }

  action deferCleanup(id: CallId, cause: str, observedPartial: fs::TraceFiles): bool =
    match calls.get(id).phase {
      | AwaitingExitConfirmation(ctx) => {
        val current = calls.get(id)
        val pending = recordEvent(current, current.phase, WorkspaceCleanupDeferred({
          workspace: ctx.generation.workspace, cause: cause,
        }))
        val result = Failed({ error: processIoError(ctx.generation, ctx.problem), cleanup: CleanupDeferred({ workspace: ctx.generation.workspace, cause: cause }) })
        recordAbortedWorkspace(id, ctx.generation, returned(pending, result), observedPartial)
      }
      | _ => inapplicable
    }

  pure def traceSet(traces: List[TraceId]): Set[TraceId] =
    traces.foldl(Set(), (distinct, trace) => distinct.union(Set(trace)))

  pure def generationFilesAgree(result: GenerationResult, output: fs::GenerationFiles): bool =
    match result {
      | ProcessFailed(problem) =>
        match output {
          | AbortedFiles(_) => isExitProblem(problem)
          | _ => false
        }
      | OutputUnavailable(_) => false
      | ProcessSucceeded(paths) =>
        match output {
          | GeneratedFiles(written) =>
            traceSet(paths).size() == paths.length() and traceSet(paths).subseteq(written.keys())
          | _ => false
        }
    }

  action completeGenerationWithFiles(id: CallId, result: GenerationResult, output: fs::GenerationFiles): bool =
    match calls.get(id).phase {
      | AwaitingGeneration(g) =>
        all {
          generationFilesAgree(result, output),
          fs::canRecordTraceFiles(filesystem, g.workspace, output),
          {
            val current = calls.get(id)
            val exited = match result {
              | ProcessSucceeded(_) => recordEvent(current, current.phase, ProcessExitedSuccessfully(g))
              | _ => current
            }
            changeCallWithFiles(id, onGeneration(exited, g, result, Map()), fs::recordTraceFiles(filesystem, g.workspace, output))
          },
        }
      | _ => inapplicable
    }

  action completeProcessFailure(id: CallId, problem: ProcessProblem, partialOutput: fs::TraceFiles): bool =
    completeGenerationWithFiles(id, ProcessFailed(problem), fs::AbortedFiles(partialOutput))

  // Non-regular entries appear in the listing but do not supply ITF bytes.
  type EntryContents = RegularContents(fs::Bytes) | DirectoryEntry | AliasEntry(fs::FilePath) | OtherEntry
  type ProducedEntry = { name: List[str], trace: TraceId, contents: EntryContents }
  type ProducedFile = { name: List[str], trace: TraceId, bytes: fs::Bytes }

  pure def regularEntries(files: List[ProducedFile]): List[ProducedEntry] =
    files.foldl(List(), (entries, file) => entries.append({
      name: file.name, trace: file.trace, contents: RegularContents(file.bytes),
    }))

  pure def directoryEntries(entries: List[ProducedEntry]): List[cli::GeneratedEntry] =
    entries.foldl(List(), (acc, entry) => {
      val kind = match entry.contents {
        | RegularContents(_) => cli::RegularFile
        | DirectoryEntry => cli::Directory
        | AliasEntry(_) => cli::Symlink
        | OtherEntry => cli::Other
      }
      acc.append({ name: entry.name, trace: entry.trace, kind: kind })
    })

  pure def generatedNames(files: List[ProducedFile]): List[cli::GeneratedEntry] =
    directoryEntries(regularEntries(files))

  pure def generatedBytes(entries: List[ProducedEntry]): fs::TraceFiles =
    entries.foldl(Map(), (acc, entry) =>
      match entry.contents {
        | RegularContents(bytes) => acc.put(entry.trace, bytes)
        | _ => acc
      }
    )

  pure def generatedAliases(entries: List[ProducedEntry]): TraceId -> fs::FilePath =
    entries.foldl(Map(), (acc, entry) =>
      match entry.contents {
        | AliasEntry(target) => acc.put(entry.trace, target)
        | _ => acc
      }
    )

  pure def distinctProducedEntries(entries: List[ProducedEntry]): bool =
    entries.indices().map(i => entries.nth(i).name).size() == entries.length() and
      entries.indices().map(i => entries.nth(i).trace).size() == entries.length()

  action completeProcessWithEntries(id: CallId, entries: List[ProducedEntry]): bool =
    match calls.get(id).phase {
      | AwaitingGeneration(g) => {
        val output = fs::GeneratedFiles(generatedBytes(entries))
        val aliases = generatedAliases(entries)
        all {
          distinctProducedEntries(entries),
          fs::canRecordTraceFiles(filesystem, g.workspace, output),
          aliases.keys().forall(trace => fs::canCreateWorkingAlias(filesystem, g.workspace, id, trace)),
          changeCallWithFiles(id, recordEvent(calls.get(id),
            AwaitingListing({ generation: g, entries: directoryEntries(entries) }), ProcessExitedSuccessfully(g)),
            aliases.keys().fold(fs::recordTraceFiles(filesystem, g.workspace, output), (snapshot, trace) =>
              fs::createWorkingAlias(snapshot, g.workspace, trace, aliases.get(trace)))),
        }
      }
      | _ => inapplicable
    }

  action completeProcessSuccess(id: CallId, files: List[ProducedFile]): bool =
    completeProcessWithEntries(id, regularEntries(files))

  action listGeneratedOutput(id: CallId, result: ListingResult): bool =
    match calls.get(id).phase {
      | AwaitingListing(listing) => {
        val output = match result {
          | ListingSucceeded => {
              result: ProcessSucceeded(cli::orderedGeneratedEntries(listing.entries)),
              basenames: listing.entries.foldl(Map(), (names, entry) => names.put(entry.trace, entry.name)),
            }
          | ListingFailed(cause) => { result: OutputUnavailable(cause), basenames: Map() }
        }
        changeCall(id, onGeneration(calls.get(id), listing.generation, output.result, output.basenames))
      }
      | _ => inapplicable
    }

  // Existing lifecycle scenarios give ordered trace IDs and omit byte contents.
  action completeGeneration(id: CallId, result: GenerationResult): bool =
    match result {
      | ProcessFailed(problem) => completeProcessFailure(id, problem, Map())
      | ProcessSucceeded(paths) =>
        completeGenerationWithFiles(id, result, fs::GeneratedFiles(traceSet(paths).mapBy(_ => List())))
      | OutputUnavailable(_) => inapplicable
    }

  def traceIsReadable(batch: TraceBatch): bool =
    match batch.source {
      | SavedItf => true
      | SavedPaths(_) => false
      | GeneratedItf(g) => fs::canReadGeneratedFile(filesystem, g.workspace, tracePosition(batch).trace)
    }

  action validateTrace(id: CallId, result: ValidationResult): bool = all {
    validValidation(result),
    match calls.get(id).phase {
      | AwaitingValidation(batch) =>
        all {
          traceIsReadable(batch),
          changeCall(id, onValidation(calls.get(id), batch, result)),
        }
      | _ => inapplicable
    },
  }

  action validateDocument(id: CallId, document: itf::ItfDocument): bool =
    validateTrace(id, fromDecodedTrace(itf::decodeItf(document, calls.get(id).selection)))

  pure def validationForBytes(bytes: fs::Bytes, selection: itf::Selection): ValidationResult =
    match itf::parseItfBytes(bytes) {
      | ByteInputParsed(document) => fromDecodedTrace(itf::decodeItf(document, selection))
      | ByteInputInvalidUtf8 => InvalidItf({ location: InvalidFile, cause: "invalid UTF-8" })
      | ByteInputInvalidJson => InvalidItf({ location: InvalidFile, cause: "invalid JSON" })
    }

  pure def validateSavedFile(snapshot: fs::FileSystem, path: fs::FilePath, result: ReadResult, selection: itf::Selection): ValidationResult = {
    match fs::readFileBytes(snapshot, path) {
      | FileUnavailable(problem) => InvalidItf({
          location: InvalidFile,
          cause: if (problem == fs::AliasCycle) "alias cycle" else "file not found",
        })
      | FileBytes(bytes) =>
        match result {
          | ReadFailed(cause) => InvalidItf({ location: InvalidFile, cause: cause })
          | ReadSucceeded => validationForBytes(bytes, selection)
        }
    }
  }

  action readSavedPath(id: CallId, result: ReadResult): bool =
    match calls.get(id).phase {
      | AwaitingValidation(batch) =>
        match batch.source {
          | SavedPaths(paths) => {
            val current = calls.get(id)
            val path = paths.nth(batch.traceIndex)
            val recorded = recordEvent(current, current.phase, SavedReadAttempted({
              path: path, position: tracePosition(batch),
            }))
            changeCall(id, onValidation(recorded, batch, validateSavedFile(filesystem, path, result, current.selection)))
          }
          | _ => inapplicable
        }
      | _ => inapplicable
    }

  def workingInputMatches(id: CallId, bytes: fs::Bytes): bool =
    match calls.get(id).phase {
      | AwaitingValidation(batch) =>
        match batch.source {
          | SavedItf => false
          | SavedPaths(_) => false
          | GeneratedItf(g) => {
            val trace = tracePosition(batch).trace
            val path = fs::workingPath(g.workspace, trace)
            if (fs::canReadGeneratedFile(filesystem, g.workspace, trace))
              filesystem.files.get(path) == bytes
            else false
          }
        }
      | _ => false
    }

  action validateGeneratedDocument(id: CallId, bytes: fs::Bytes): bool = all {
    workingInputMatches(id, bytes),
    readGeneratedInput(id, ReadSucceeded),
  }

  def factoryResultAllowed(result: FactoryResult): bool =
    match result {
      | FactorySucceeded(driver) =>
        DRIVER_IDS.contains(driver) and
          not(CALL_IDS.exists(id => hasEvent(calls.get(id).history, event =>
            match event {
              | DriverCreated(created) => created.driver == driver
              | _ => false
            }
          )))
      | FactoryFailed(_) => true
    }

  action createDriver(id: CallId, result: FactoryResult): bool = all {
    factoryResultAllowed(result),
    match calls.get(id).phase {
      | AwaitingDriver(validated) => changeCall(id, onFactory(calls.get(id), validated, result))
      | _ => inapplicable
    },
  }

  action applyOperationWithUpdate(id: CallId, result: OperationResult, update: DriverArgumentUpdate): bool =
    match calls.get(id).phase {
      | AwaitingOperation(active) => changeCall(id, onOperation(calls.get(id), active, result, update))
      | _ => inapplicable
    }

  action applyOperation(id: CallId, result: OperationResult): bool =
    applyOperationWithUpdate(id, result, ArgumentsUnchanged)

  action applyOperationWithMutation(id: CallId, result: OperationResult, argumentsAfter: OperationArguments): bool =
    applyOperationWithUpdate(id, result, ArgumentsReplaced(argumentsAfter))

  action observeState(id: CallId, result: ObservationResult): bool =
    match calls.get(id).phase {
      | AwaitingObservation(active) => changeCall(id, onObservation(calls.get(id), active, result))
      | _ => inapplicable
    }

  action planArtifactDirectories(id: CallId, candidates: List[int]): bool =
    match calls.get(id).phase {
      | AwaitingArtifact(ctx) => all {
          ctx.preparation == ArtifactUnplanned,
          candidates.length() > 0,
          candidates.indices().forall(i => candidates.nth(i) >= 0),
          changeCall(id, { ...calls.get(id), phase: AwaitingArtifact({
            ...ctx, preparation: ArtifactCandidates(candidates),
          }) }),
        }
      | _ => inapplicable
    }

  action tryArtifactDirectory(id: CallId, result: StorageResult): bool =
    match calls.get(id).phase {
      | AwaitingArtifact(ctx) =>
        match ctx.preparation {
          | ArtifactCandidates(candidates) => {
            val directory = candidates.head()
            val root = ctx.generation.artifactRoot
            val workspace = ctx.generation.workspace
            val current = calls.get(id)
            if (not(fs::artifactDirectoryAvailable(filesystem, root, directory))) {
              val remaining = candidates.tail()
              val recorded = recordEvent(current, current.phase, ArtifactDirectoryTried({
                root: root, directory: directory, result: DirectoryCollision,
              }))
              if (remaining.length() > 0)
                changeCall(id, { ...recorded, phase: AwaitingArtifact({
                  ...ctx, preparation: ArtifactCandidates(remaining),
                }) })
              else
                changeCall(id, onArtifact(recorded, ctx.generation, ctx.detail, ArtifactDirectoryFailed({
                  root: root, directory: directory, cause: "artifact directory already exists",
                })))
            } else
              match result {
                | StorageSucceeded => all {
                    fs::canReserveArtifactDirectory(filesystem, workspace, directory),
                    changeCallWithFiles(id, recordEvent(current, AwaitingArtifact({
                      ...ctx, preparation: ArtifactReadyToCopy,
                    }), ArtifactDirectoryTried({
                      root: root, directory: directory, result: DirectoryReserved,
                    })), fs::reserveArtifactDirectory(filesystem, workspace, directory)),
                  }
                | StorageFailed(cause) => {
                  val recorded = recordEvent(current, current.phase, ArtifactDirectoryTried({
                    root: root, directory: directory, result: DirectoryRejected(cause),
                  }))
                  changeCall(id, onArtifact(recorded, ctx.generation, ctx.detail,
                    ArtifactDirectoryFailed({ root: root, directory: directory, cause: cause })))
                }
              }
          }
          | _ => inapplicable
        }
      | _ => inapplicable
    }

  action beginArtifactCopy(id: CallId): bool =
    match calls.get(id).phase {
      | AwaitingArtifact(ctx) => {
        val workspace = ctx.generation.workspace
        val trace = ctx.detail.position.trace.trace
        all {
          ctx.preparation == ArtifactReadyToCopy,
          fs::canStageReservedEvidence(filesystem, workspace, trace),
          changeCallWithFiles(id, calls.get(id), fs::stageReservedEvidence(filesystem, workspace, trace)),
        }
      }
      | _ => inapplicable
    }

  action writeArtifactCopy(id: CallId, count: int): bool =
    match calls.get(id).phase {
      | AwaitingArtifact(ctx) => {
        val workspace = ctx.generation.workspace
        match filesystem.workspaces.get(workspace).evidence {
          | StagedEvidence(staged) => all {
              count > staged.bytes.length(),
              fs::canWriteEvidence(filesystem, workspace, count),
              changeCallWithFiles(id, calls.get(id), fs::writeEvidence(filesystem, workspace, count)),
            }
          | _ => inapplicable
        }
      }
      | _ => inapplicable
    }

  action completeArtifactCopy(id: CallId, result: StorageResult): bool =
    match calls.get(id).phase {
      | AwaitingArtifact(ctx) => {
        val workspace = ctx.generation.workspace
        match result {
          | StorageSucceeded =>
            match filesystem.workspaces.get(workspace).artifactDirectory {
              | ArtifactDirectoryReserved(directory) => {
                val saved = fs::evidencePath(ctx.generation.artifactRoot, directory, ctx.detail.position.trace.trace)
                all {
                  fs::canPublishEvidence(filesystem, workspace),
                  changeCallWithFiles(id, onArtifact(calls.get(id), ctx.generation, ctx.detail, ArtifactSaved(saved)),
                    fs::publishEvidence(filesystem, workspace)),
                }
              }
              | NoArtifactDirectory => inapplicable
            }
          | StorageFailed(cause) => all {
              fs::canAbandonEvidence(filesystem, workspace),
              changeCallWithFiles(id, onArtifact(calls.get(id), ctx.generation, ctx.detail, ArtifactSaveFailed(cause)),
                fs::abandonEvidence(filesystem, workspace)),
            }
        }
      }
      | _ => inapplicable
    }

  // Lifecycle tests can collapse the same filesystem transitions into one action.
  pure def copyAgrees(result: StorageResult, copy: fs::CopyOutcome): bool =
    match copy {
      | CopyComplete => result == StorageSucceeded
      | CopyInterrupted(_) => result != StorageSucceeded
    }

  action saveArtifactWithCopy(id: CallId, result: StorageResult, copy: fs::CopyOutcome): bool =
    match calls.get(id).phase {
      | AwaitingArtifact(ctx) => {
        val workspace = ctx.generation.workspace
        val trace = ctx.detail.position.trace.trace
        val save = match result {
          | StorageSucceeded => ArtifactSaved(fs::evidencePath(ctx.generation.artifactRoot, workspace, trace))
          | StorageFailed(cause) => ArtifactSaveFailed(cause)
        }
        all {
          ctx.preparation == ArtifactUnplanned,
          copyAgrees(result, copy),
          fs::canRetainTraceFile(filesystem, workspace, trace, copy),
          changeCallWithFiles(id, onArtifact(calls.get(id), ctx.generation, ctx.detail, save),
            fs::retainTraceFile(filesystem, workspace, trace, copy)),
        }
      }
      | _ => inapplicable
    }

  action saveArtifact(id: CallId, result: StorageResult): bool =
    saveArtifactWithCopy(id, result, if (result == StorageSucceeded) fs::CopyComplete else fs::CopyInterrupted(0))

  action cleanWorkspaceWithRemoval(id: CallId, result: StorageResult, removal: fs::CleanupOutcome): bool =
    match calls.get(id).phase {
      | AwaitingCleanup(ctx) => {
        val workspace = ctx.generation.workspace
        all {
          (result == StorageSucceeded) == (removal == fs::RemoveComplete),
          fs::canCleanupFiles(filesystem, workspace, removal),
          changeCallWithFiles(
            id,
            onCleanup(calls.get(id), ctx.generation, ctx.result, result),
            fs::cleanupFiles(filesystem, workspace, removal)
          ),
        }
      }
      | _ => inapplicable
    }

  action cleanWorkspace(id: CallId, result: StorageResult): bool =
    cleanWorkspaceWithRemoval(
      id, result, if (result == StorageSucceeded) fs::RemoveComplete else fs::RemoveInterrupted(Set())
    )

  pure val initName: qv::Text = List(105, 110, 105, 116) // init

  pure val openingStep: TraceStep =
    { operation: { name: initName, arguments: Map() }, expected: integerDigit(0) }

  pure def hasEvent(history: List[Event], predicate: (Event) => bool): bool =
    history.indices().exists(index => predicate(history.nth(index)))

  def anyCallHas(predicate: (Event) => bool): bool =
    CALL_IDS.exists(id => hasEvent(calls.get(id).history, predicate))

  pure def isValidationAttempt(event: Event): bool =
    match event {
      | ValidationAttempted(_) => true
      | _ => false
    }

  pure def isMatch(event: Event): bool =
    match event {
      | ObservationMatched(_) => true
      | _ => false
    }

  pure def isFailure(event: Event): bool =
    match event {
      | FailureRecognized(_) => true
      | _ => false
    }

  pure def hasPrior(history: List[Event], index: int, predicate: (Event) => bool): bool =
    history.indices().exists(i => i < index and predicate(history.nth(i)))

  pure def previousIs(history: List[Event], index: int, predicate: (Event) => bool): bool =
    if (index > 0) predicate(history.nth(index - 1)) else false

  pure def replayInputs(history: List[Event]): List[TraceId] =
    history.foldl(List(), (traces, event) =>
      match event {
        | ReplayRequested(paths) => paths
        | ReplayFilesRequested(paths) => range(0, paths.length())
        | GenerationCompleted(completed) =>
          match completed.result {
            | ProcessFailed(_) => List()
            | OutputUnavailable(_) => List()
            | ProcessSucceeded(paths) =>
              if (hasEnoughTraces(completed.generation.expectation, paths.length())) paths else List()
          }
        | _ => traces
      }
    )

  pure def traceIsNext(history: List[Event], index: int, position: TracePosition): bool = {
    val paths = replayInputs(history.slice(0, index))
    val priorTraces = history.indices().filter(i => i < index and isValidationAttempt(history.nth(i)))
    val followsCompleteTrace = previousIs(history, index, event =>
      match event {
        | ObservationMatched(matched) =>
          matched.position.trace.traceIndex == position.traceIndex - 1 and
            hasPrior(history, index, prior =>
              match prior {
                | TraceValidated(accepted) =>
                  accepted.position == matched.position.trace and
                    accepted.steps.length() == matched.position.stepIndex + 1
                | _ => false
              }
            )
        | _ => false
      }
    )
    if (position.traceIndex >= 0 and position.traceIndex < paths.length())
      paths.nth(position.traceIndex) == position.trace and
        position.traceIndex == priorTraces.size() and
        (position.traceIndex == 0 or followsCompleteTrace)
    else
      false
  }

  pure def requestedSavedPath(history: List[Event], index: int, file: SavedTracePosition): bool =
    hasPrior(history, index, event =>
      match event {
        | ReplayFilesRequested(paths) =>
          if (paths.indices().contains(file.position.traceIndex))
            paths.nth(file.position.traceIndex) == file.path
          else false
        | _ => false
      }
    )

  pure def validationFollowsInput(history: List[Event], index: int, position: TracePosition): bool =
    previousIs(history, index, event =>
      match event {
        | SavedReadAttempted(file) => file.position == position
        | GeneratedReadAttempted(file) => file.position == position
        | _ => false
      }
    ) or (not(hasPrior(history, index, event =>
      match event {
        | ReplayFilesRequested(_) => true
        | _ => false
      }
    )) and traceIsNext(history, index, position))

  pure def driverOwnsStep(history: List[Event], index: int, ctx: DriverStep): bool =
    hasPrior(history, index, event => event == DriverCreated({ trace: ctx.position.trace, driver: ctx.driver }))

  pure def matchesValidatedStep(
    history: List[Event], index: int, position: StepPosition, predicate: (TraceStep) => bool
  ): bool =
    hasPrior(history, index, event =>
      match event {
        | TraceValidated(validated) =>
          if (validated.position == position.trace and validated.steps.indices().contains(position.stepIndex))
            predicate(validated.steps.nth(position.stepIndex))
          else
            false
        | _ => false
      }
    )

  pure def stepIsNext(history: List[Event], index: int, ctx: DriverStep): bool =
    driverOwnsStep(history, index, ctx) and
    if (ctx.position.stepIndex == 0)
      previousIs(history, index, event => event == DriverCreated({ trace: ctx.position.trace, driver: ctx.driver }))
    else
      previousIs(history, index, event =>
        match event {
          | ObservationMatched(matched) =>
            matched.position == { ...ctx.position, stepIndex: ctx.position.stepIndex - 1 }
          | _ => false
        }
      )

  pure def appliedOperationBefore(history: List[Event], index: int, predicate: (Event) => bool): bool =
    if (index > 0)
      match history.nth(index - 1) {
        | DriverArgumentsChanged(_) => previousIs(history, index - 1, predicate)
        | _ => predicate(history.nth(index - 1))
      }
    else false

  pure def observationFollowsOperation(history: List[Event], index: int, ctx: DriverStep): bool =
    appliedOperationBefore(history, index, event =>
      match event {
        | OperationCalled(operation) => operation.context == ctx
        | _ => false
      }
    )

  pure def matchingObservation(history: List[Event], index: int, position: StepPosition, value: Value): bool =
    previousIs(history, index, event =>
      match event {
        | ObservationCalled(observation) =>
          observation.context.position == position and qv::equalValues(observation.expected, value)
        | _ => false
      }
    )

  pure def replayEventInOrder(history: List[Event], index: int): bool =
    match history.nth(index) {
      | SavedReadAttempted(file) =>
        requestedSavedPath(history, index, file) and traceIsNext(history, index, file.position)
      | GeneratedReadAttempted(file) =>
        traceIsNext(history, index, file.position) and hasPrior(history, index, event =>
          match event {
            | GenerationCompleted(completed) =>
              if (completed.basenames.keys().contains(file.position.trace))
                file.path == fs::workingPath(completed.generation.workspace, file.position.trace) and
                  file.basename == completed.basenames.get(file.position.trace)
              else false
            | _ => false
          }
        )
      | ValidationAttempted(position) => validationFollowsInput(history, index, position)
      | TraceValidated(validated) =>
        validated.steps.length() > 0 and
          previousIs(history, index, event => event == ValidationAttempted(validated.position))
      | FactoryCalled(position) =>
        previousIs(history, index, event =>
          match event {
            | TraceValidated(validated) => validated.position == position
            | _ => false
          }
        )
      | DriverCreated(created) =>
        previousIs(history, index, event => event == FactoryCalled(created.trace))
      | OperationCalled(operation) =>
        stepIsNext(history, index, operation.context) and
          matchesValidatedStep(history, index, operation.context.position, entry =>
            entry.operation == operation.operation
          )
      | DriverArgumentsChanged(change) =>
        previousIs(history, index, event =>
          match event {
            | OperationCalled(operation) => operation.context == change.context
            | _ => false
          }
        )
      | ObservationCalled(observation) =>
        observationFollowsOperation(history, index, observation.context) and
          matchesValidatedStep(history, index, observation.context.position, entry =>
            entry.expected == observation.expected
          )
      | ObservationMatched(matched) =>
        matchingObservation(history, index, matched.position, matched.actual)
      | DifferenceObserved(detail) =>
        not(qv::equalValues(detail.step.expected, detail.actual)) and
          matchingObservation(history, index, detail.position, detail.step.expected) and
          appliedOperationBefore(history, index - 1, event =>
            match event {
              | OperationCalled(operation) =>
                operation.context.position == detail.position and operation.operation == detail.step.operation
              | _ => false
            }
          )
      | _ => true
    }

  val replayInOrder: bool =
    CALL_IDS.forall(id => {
      val history = calls.get(id).history
      history.indices().forall(index => replayEventInOrder(history, index))
    })

  pure def stopped(event: Event): bool =
    match event {
      | DifferenceObserved(_) => true
      | FailureRecognized(_) => true
      | Returned(_) => true
      | _ => false
    }

  pure def allowedAfterFailure(event: Event): bool =
    match event {
      | ArtifactDirectoryTried(_) => true
      | SaveAttempted(_) => true
      | CleanupAttempted(_) => true
      | ChildExitConfirmed(_) => true
      | WorkspaceCleanupDeferred(_) => true
      | FailureRecognized(_) => true
      | Returned(_) => true
      | _ => false
    }

  pure def afterStopOnlyFinishes(s: CallState): bool =
    s.history.indices().forall(index =>
      not(hasPrior(s.history, index, stopped)) or allowedAfterFailure(s.history.nth(index))
    )

  val firstFailureStopsReplay: bool =
    CALL_IDS.forall(id => afterStopOnlyFinishes(calls.get(id)))

  pure def ownsWorkspace(history: List[Event], workspace: WorkspaceId): bool =
    hasEvent(history, event =>
      match event {
        | WorkspaceReserved(g) => g.workspace == workspace
        | _ => false
      }
    )

  pure def artifactMatchesMismatch(history: List[Event], index: int, mismatch: Mismatch, artifact: Artifacts): bool =
    match artifact {
      | FromSavedTrace =>
        hasPrior(history, index, event =>
          match event {
            | ReplayRequested(_) => true
            | _ => false
          }
        )
      | FromSavedFile(path) =>
        requestedSavedPath(history, index, { path: path, position: mismatch.position.trace }) and
          hasPrior(history, index, event => event == SavedReadAttempted({ path: path, position: mismatch.position.trace }))
      | FromGeneration(detail) =>
        previousIs(history, index, event =>
          match event {
            | SaveAttempted(attempt) =>
              attempt.position == mismatch.position.trace and
                hasPrior(history, index, prior =>
                  match prior {
                    | GenerationCompleted(completed) =>
                      completed.generation.seed == detail.seed and
                        detail.save == attempt.result
                    | _ => false
                  }
                )
            | _ => false
          }
        )
    }

  pure def matchingDiagnostics(history: List[Event], index: int): bool =
    match history.nth(index) {
      | ArtifactDirectoryTried(_) =>
        hasPrior(history, index, event =>
          match event {
            | DifferenceObserved(_) => true
            | _ => false
          }
        )
      | SaveAttempted(attempt) =>
        hasPrior(history, index, event =>
          match event {
            | DifferenceObserved(detail) => detail.position.trace == attempt.position
            | _ => false
          }
        ) and hasPrior(history, index, prior =>
          match prior {
            | GenerationCompleted(_) => true
            | _ => false
          }
        )
      | FailureRecognized(error) =>
        match error {
          | StatesDiffer(mismatch) =>
            hasPrior(history, index, event => event == DifferenceObserved(mismatch.detail)) and
            artifactMatchesMismatch(history, index, mismatch.detail, mismatch.artifacts)
          | _ => true
        }
      | _ => true
    }

  val mismatchKeepsEvidence: bool =
    CALL_IDS.forall(id => {
      val history = calls.get(id).history
      history.indices().forall(index => matchingDiagnostics(history, index))
    })

  pure def resultMatchesHistory(history: List[Event], result: Outcome): bool =
    match result {
      | Passed => {
        val validations = history.indices().filter(index => isValidationAttempt(history.nth(index)))
        val matches = history.indices().filter(index => isMatch(history.nth(index)))
        val accepted = history.indices().filter(index =>
          match history.nth(index) {
            | TraceValidated(_) => true
            | _ => false
          }
        )
        val totalSteps = history.foldl(0, (sum, event) =>
          match event {
            | TraceValidated(validated) => sum + validated.steps.length()
            | _ => sum
          }
        )
        validations.size() == replayInputs(history).length() and
          accepted.size() == validations.size() and
          matches.size() == totalSteps and totalSteps > 0 and not(hasEvent(history, isFailure))
      }
      | Failed(failure) => {
        val failures = history.indices().filter(i => isFailure(history.nth(i)))
        val matchesFirstFailure = failures.size() == 1 and
          hasEvent(history, event => event == FailureRecognized(failure.error))
        val preservedMismatch = match failure.error {
          | StatesDiffer(_) => true
          | _ => not(hasEvent(history, event =>
              match event {
                | DifferenceObserved(_) => true
                | _ => false
              }
            ))
        }
        matchesFirstFailure and preservedMismatch
      }
    }

  pure def hasNoCleanupNote(result: Outcome): bool =
    match result {
      | Passed => true
      | Failed(failure) => failure.cleanup == NoCleanupError
    }

  pure def cleanupSupportsOutcome(
    alreadyFailed: bool, generation: Generation, storage: StorageResult, result: Outcome
  ): bool =
    match storage {
      | StorageSucceeded => hasNoCleanupNote(result)
      | StorageFailed(cause) =>
        match result {
          | Passed => false
          | Failed(failure) =>
            if (alreadyFailed)
              failure.cleanup == CleanupAlsoFailed(cause)
            else
              failure.cleanup == NoCleanupError and
                failure.error == WorkspaceFailed({ seed: generation.seed, stage: Cleanup, cause: cause })
        }
    }

  pure def cleanupHasExitEvidence(history: List[Event], index: int, workspace: WorkspaceId): bool = {
    val started = hasPrior(history, index, event =>
      match event {
        | ProcessStarted(g) => g.workspace == workspace
        | _ => false
      }
    )
    not(started) or hasPrior(history, index, event =>
      match event {
        | ProcessExitedSuccessfully(g) => g.workspace == workspace
        | ChildExitConfirmed(g) => g.workspace == workspace
        | GenerationCompleted(completion) =>
          completion.generation.workspace == workspace and
            (match completion.result {
              | ProcessFailed(problem) => isExitProblem(problem)
              | _ => false
            })
        | ProcessIoFailed(failure) =>
          failure.generation.workspace == workspace and failure.exit != ExitUnconfirmed
        | _ => false
      }
    )
  }

  pure def childExitUnconfirmed(history: List[Event], index: int, workspace: WorkspaceId): bool =
    hasPrior(history, index, event =>
      match event {
        | ProcessIoFailed(failure) => failure.generation.workspace == workspace and failure.exit == ExitUnconfirmed
        | _ => false
      }
    ) and not(hasPrior(history, index, event =>
      match event {
        | ChildExitConfirmed(g) => g.workspace == workspace
        | _ => false
      }
    ))

  pure def resultMatchesCleanup(history: List[Event], result: Outcome): bool = {
    val reservations = history.indices().filter(index =>
      match history.nth(index) {
        | WorkspaceReserved(_) => true
        | _ => false
      }
    )
    val cleanups = history.indices().filter(index =>
      match history.nth(index) {
        | CleanupAttempted(_) => true
        | _ => false
      }
    )
    val deferred = history.indices().filter(index =>
      match history.nth(index) {
        | WorkspaceCleanupDeferred(_) => true
        | _ => false
      }
    )
    if (deferred.size() == 1) {
      val notedAt = deferred.getOnlyElement()
      reservations.size() == 1 and cleanups.size() == 0 and notedAt == history.length() - 2 and
        (match history.nth(notedAt) {
          | WorkspaceCleanupDeferred(note) =>
            match result {
              | Failed(failure) => failure.cleanup == CleanupDeferred(note) and
                childExitUnconfirmed(history, notedAt, note.workspace)
              | _ => false
            }
          | _ => false
        })
    } else if (deferred.size() != 0) false
    else if (reservations.size() == 1 and cleanups.size() == 1) {
      val reservedAt = reservations.getOnlyElement()
      val cleanedAt = cleanups.getOnlyElement()
      val alreadyFailed = hasPrior(history, cleanedAt, isFailure)
      match history.nth(reservedAt) {
        | WorkspaceReserved(generation) =>
          match history.nth(cleanedAt) {
            | CleanupAttempted(cleaned) =>
              reservedAt < cleanedAt and cleaned.workspace == generation.workspace and
                cleanupSupportsOutcome(alreadyFailed, generation, cleaned.result, result)
            | _ => false
          }
        | _ => false
      }
    } else
      reservations.size() == 0 and cleanups.size() == 0 and hasNoCleanupNote(result)
  }

  pure def ownsReturnedResult(s: CallState): bool = {
    val firstReturns = s.history.indices().filter(index =>
      match s.history.nth(index) {
        | Returned(_) => true
        | _ => false
      }
    )
    match s.phase {
      | Finished(result) =>
        firstReturns == Set(s.history.length() - 1) and
          s.history.nth(s.history.length() - 1) == Returned(result) and
          resultMatchesHistory(s.history, result) and
          resultMatchesCleanup(s.history, result)
      | _ => firstReturns.size() == 0
    }
  }

  val consistentResult: bool =
    CALL_IDS.forall(id => ownsReturnedResult(calls.get(id)))

  pure def allocatedDriver(event: Event, driver: DriverId): bool =
    match event {
      | DriverCreated(created) => created.driver == driver
      | _ => false
    }

  pure def executableMatchesPlan(
    history: List[Event], index: int, command: cli::QuintCommand, target: ExecutionTarget
  ): bool =
    match command.executable {
      | DirectExecutable(executable) => target == ExplicitExecutable(executable)
      | SearchCallerPath(search) =>
        previousIs(history, index, event =>
          match event {
            | PathSearchCompleted(lookup) =>
              search.directory == lookup.callerDirectory and search.name == lookup.name and
                (match lookup.result.resolution {
                  | Found(candidate) => target == ExecutableOnPath(candidate)
                  | _ => false
                })
            | _ => false
          }
        )
    }

  val isolatedResources: bool = and {
    WORKSPACE_IDS.forall(workspace => {
      val owners = CALL_IDS.filter(id => ownsWorkspace(calls.get(id).history, workspace))
      if (fs::workspaceAvailable(filesystem, workspace))
        owners.size() == 0
      else
        owners == Set(filesystem.workspaces.get(workspace).owner)
    }),
    DRIVER_IDS.forall(driver =>
      CALL_IDS.fold(0, (sum, id) => {
        val history = calls.get(id).history
        sum + history.indices().filter(index => allocatedDriver(history.nth(index), driver)).size()
      }) <= 1
    ),
    CALL_IDS.forall(id => {
      val history = calls.get(id).history
      history.indices().forall(index =>
        match history.nth(index) {
          | WorkspaceReserved(g) =>
            history.indices().forall(i =>
              match history.nth(i) {
                | CommandPrepared(plan) =>
                  i < index and plan.command.workspace == g.workspace and plan.command.seed == g.seed and
                    cli::quintCommand(plan.request, plan.drawnSeed) == cli::CommandReady(plan.command) and
                    commandExpectation(plan.request.config) == g.expectation and
                    executableMatchesPlan(history, i, plan.command, plan.target)
                | _ => true
              }
            )
          | PathSearchCompleted(lookup) =>
            lookup.result == path::searchPath(lookup.callerDirectory, lookup.name,
              lookup.environment.directories, lookup.environment.observations)
          | ProcessStarted(g) =>
            previousIs(history, index, event => event == WorkspaceReserved(g))
          | ProcessExitedSuccessfully(g) =>
            hasPrior(history, index, event => event == ProcessStarted(g))
          | GenerationCompleted(completed) =>
            hasPrior(history, index, event => event == WorkspaceReserved(completed.generation)) and
              (match completed.result {
                | ProcessFailed(problem) =>
                  not(hasPrior(history, index, event => event == ProcessExitedSuccessfully(completed.generation))) and
                    (match problem {
                      | SpawnFailure(_) =>
                        previousIs(history, index, event => event == WorkspaceReserved(completed.generation))
                      | _ => isExitProblem(problem) and
                        previousIs(history, index, event => event == ProcessStarted(completed.generation))
                    })
                | _ => previousIs(history, index, event =>
                    event == ProcessExitedSuccessfully(completed.generation))
              })
          | ProcessIoFailed(failure) =>
            previousIs(history, index, event => event == ProcessStarted(failure.generation)) and
              (if (history.indices().contains(index + 1))
                history.nth(index + 1) == FailureRecognized(processIoError(failure.generation, failure.problem))
              else false)
          | ChildExitConfirmed(g) => childExitUnconfirmed(history, index, g.workspace)
          | CleanupAttempted(cleaned) =>
            ownsWorkspace(history, cleaned.workspace) and
              cleanupHasExitEvidence(history, index, cleaned.workspace) and
              not(childExitUnconfirmed(history, index, cleaned.workspace))
          | WorkspaceCleanupDeferred(note) =>
            if (ownsWorkspace(history, note.workspace))
              childExitUnconfirmed(history, index, note.workspace) and
                filesystem.workspaces.get(note.workspace).status == fs::WorkspaceActive
            else false
          | _ => true
        }
      )
    }),
  }

  def evidenceFollowsSave(history: List[Event], workspace: WorkspaceId): bool =
    if (fs::workspaceAvailable(filesystem, workspace)) false
    else {
      val storage = filesystem.workspaces.get(workspace)
      history.indices().forall(index =>
        match history.nth(index) {
          | SaveAttempted(attempt) => {
            val trace = attempt.position.trace
            match attempt.result {
              | ArtifactSaved(path) =>
                match storage.artifactDirectory {
                  | ArtifactDirectoryReserved(directory) =>
                    storage.evidence == fs::PublishedEvidence(trace) and
                      path == fs::evidencePath(storage.root, directory, trace) and filesystem.files.keys().contains(path)
                  | NoArtifactDirectory => false
                }
              | ArtifactDirectoryFailed(_) =>
                storage.evidence == fs::NoEvidence and storage.artifactDirectory == fs::NoArtifactDirectory
              | ArtifactSaveFailed(_) =>
                storage.evidence == fs::AbandonedEvidence(trace) and storage.artifactDirectory == fs::NoArtifactDirectory
            }
          }
          | _ => true
        }
      )
    }

  def stagedEvidenceMatchesCall(workspace: WorkspaceId): bool = {
    val storage = filesystem.workspaces.get(workspace)
    match storage.evidence {
      | StagedEvidence(staged) =>
        match calls.get(storage.owner).phase {
          | AwaitingArtifact(ctx) =>
            ctx.generation.workspace == workspace and ctx.detail.position.trace.trace == staged.trace
          | _ => false
        }
      | _ => true
    }
  }

  val persistedEvidence: bool =
    filesystem.workspaces.keys().forall(workspace =>
      stagedEvidenceMatchesCall(workspace) and
        evidenceFollowsSave(calls.get(filesystem.workspaces.get(workspace).owner).history, workspace)
    )

  pure val noWork: List[int] = List(0, 0, 0, 0, 0)

  pure def pendingTraces(batch: TraceBatch): int = batch.traces.length() - batch.traceIndex

  pure def activeWork(active: ActiveTrace, beforeObservation: int): List[int] =
    List(4, pendingTraces(active.validated.batch), 1,
      active.validated.steps.length() - active.stepIndex, beforeObservation)

  // In lexicographic order an outer phase can introduce a finite amount of
  // work at a lower position, such as the number of steps in a new trace.
  pure def callWork(state: CallState, snapshot: fs::FileSystem): List[int] =
    match state.phase {
      | Ready => List(8, 0, 0, 0, 0)
      | AwaitingSpawn(_) => List(7, 0, 0, 0, 0)
      | AwaitingGeneration(_) => List(6, 1, 0, 0, 0)
      | AwaitingExitConfirmation(_) => List(6, 0, 0, 0, 0)
      | AwaitingListing(_) => List(5, 0, 0, 0, 0)
      | AwaitingValidation(batch) => List(4, pendingTraces(batch), 3, 0, 0)
      | AwaitingDriver(validated) => List(4, pendingTraces(validated.batch), 2, 0, 0)
      | AwaitingOperation(active) => activeWork(active, 1)
      | AwaitingObservation(active) => activeWork(active, 0)
      | AwaitingArtifact(ctx) => {
        val workspace = ctx.generation.workspace
        match snapshot.workspaces.get(workspace).evidence {
          | StagedEvidence(staged) => {
            val bytes = snapshot.files.get(fs::workingPath(workspace, staged.trace))
            List(3, 0, bytes.length() - staged.bytes.length(), 0, 0)
          }
          | _ =>
            match ctx.preparation {
              | ArtifactUnplanned => List(3, 3, 0, 0, 0)
              | ArtifactCandidates(candidates) => List(3, 2, candidates.length(), 0, 0)
              | ArtifactReadyToCopy => List(3, 1, 0, 0, 0)
            }
        }
      }
      | AwaitingCleanup(_) => List(2, 0, 0, 0, 0)
      | Finished(_) => noWork
    }

  pure def totalWork(states: CallId -> CallState, snapshot: fs::FileSystem): List[int] =
    states.keys().fold(noWork, (total, id) => {
      val rank = callWork(states.get(id), snapshot)
      range(0, total.length()).foldl(List(), (sum, i) => sum.append(total.nth(i) + rank.nth(i)))
    })

  pure def workLess(left: List[int], right: List[int]): bool =
    range(0, left.length()).foldl(0, (order, i) =>
      if (order == 0) left.nth(i) - right.nth(i) else order
    ) < 0

  // For each unfinished phase, this checks the guard of a response that can
  // advance it. Driver callbacks may fail even when every driver ID is in use.
  def hasNextResponse(id: CallId): bool =
    match calls.get(id).phase {
      | Ready => true // The caller can submit a replay.
      | AwaitingSpawn(_) => true
      | AwaitingGeneration(g) =>
        fs::canRecordTraceFiles(filesystem, g.workspace, fs::AbortedFiles(Map()))
      | AwaitingExitConfirmation(ctx) =>
        fs::canRecordTraceFiles(filesystem, ctx.generation.workspace, fs::AbortedFiles(Map()))
      | AwaitingListing(_) => true // The listing may succeed or fail.
      | AwaitingValidation(batch) =>
        match batch.source {
          | SavedPaths(_) => true // A requested path can be read or report an error.
          | _ => traceIsReadable(batch)
        }
      | AwaitingDriver(_) => true
      | AwaitingOperation(_) => true
      | AwaitingObservation(_) => true
      | AwaitingArtifact(ctx) =>
        match ctx.preparation {
          | ArtifactUnplanned => true
          | ArtifactCandidates(candidates) => candidates.length() > 0
          | ArtifactReadyToCopy =>
            fs::canStageReservedEvidence(filesystem, ctx.generation.workspace, ctx.detail.position.trace.trace) or
              fs::canAbandonEvidence(filesystem, ctx.generation.workspace)
        }
      | AwaitingCleanup(ctx) =>
        fs::canCleanupFiles(filesystem, ctx.generation.workspace, fs::RemoveComplete)
      | Finished(_) => false
    }

  val processingProgress: bool = and {
    lastStepReducedWork,
    pendingCalls.forall(hasNextResponse),
    CALL_IDS.forall(id => {
      val rank = callWork(calls.get(id), filesystem)
      rank.indices().forall(i => rank.nth(i) >= 0)
    }),
    (totalWork(calls, filesystem) == noWork) == (pendingCalls.size() == 0),
  }

  val safety: bool = and {
    replayInOrder,
    firstFailureStopsReplay,
    mismatchKeepsEvidence,
    consistentResult,
    isolatedResources,
    fs::fileSystemSafety(filesystem, initialFilesystem),
    persistedEvidence,
    processingProgress,
  }

  pure val incrementStep: TraceStep =
    { operation: {
        name: List(105, 110, 99, 114, 101, 109, 101, 110, 116), // increment
        arguments: Map(List(97, 109, 111, 117, 110, 116) -> integerDigit(1)), // amount
      }, expected: integerDigit(1) }

  pure def hasFinished(phase: Phase): bool =
    match phase {
      | Finished(_) => true
      | _ => false
    }

  val pendingCalls: Set[CallId] =
    CALL_IDS.filter(id => not(hasFinished(calls.get(id).phase)))

  pure def simulatorRequest(workspace: WorkspaceId, config: cli::QuintConfig): cli::CliRequest = {
    callerDirectory: "/models",
    executable: cli::ExecutablePath(cli::AbsolutePath("/bin/quint")),
    model: cli::RelativePath("sample.qnt"),
    workspace: workspace,
    main: cli::CliDefault, backend: cli::CliDefault, seed: cli::CliSpecified(sampleSeed), config: config,
  }

  pure def simulationWithCount(count: int): cli::QuintConfig =
    cli::Simulation({
      init: cli::CliDefault, step: cli::CliDefault, nTraces: cli::CliSpecified(count),
      maxSamples: cli::CliDefault, maxSteps: cli::CliDefault,
    })

  action validateSampledAbstractTrace(id: CallId, result: ValidationResult): bool =
    match calls.get(id).phase {
      | AwaitingValidation(batch) =>
        match batch.source {
          | SavedItf => validateTrace(id, result)
          | GeneratedItf(_) =>
            all { batch.basenames.keys().size() == 0, validateTrace(id, result) }
          | SavedPaths(_) => inapplicable
        }
      | _ => inapplicable
    }

  action readGeneratedInput(id: CallId, result: ReadResult): bool =
    match calls.get(id).phase {
      | AwaitingValidation(batch) =>
        match batch.source {
          | GeneratedItf(g) => {
            val position = tracePosition(batch)
            val path = fs::workingPath(g.workspace, position.trace)
            if (batch.basenames.keys().contains(position.trace)) {
              val file = { path: path, basename: batch.basenames.get(position.trace), position: position }
              val current = calls.get(id)
              val recorded = recordEvent(current, current.phase, GeneratedReadAttempted(file))
              all {
                fs::canReadGeneratedFile(filesystem, g.workspace, position.trace),
                match result {
                  | ReadSucceeded => changeCall(id, onValidation(recorded, batch,
                      validationForBytes(filesystem.files.get(path), current.selection)))
                  | ReadFailed(cause) => changeCall(id, stop(recorded, batch.source, TraceFailed({
                      location: AtGeneratedTrace(file), cause: cause,
                    })))
                },
              }
            } else inapplicable
          }
          | _ => inapplicable
        }
      | _ => inapplicable
    }

  pure val itemSet: Value = {
    root: 2,
    nodes: List(qv::BooleanNode(true), qv::IntegerNode({ negative: false, digits: List(1) }), qv::SetNode(List(0, 1))),
  }

  action startSampledEvidenceReplay(id: CallId, workspace: WorkspaceId, selection: itf::Selection): bool =
    if (fs::workspaceAvailable(filesystem, workspace)) inapplicable
    else {
      val storage = filesystem.workspaces.get(workspace)
      match storage.artifactDirectory {
        | NoArtifactDirectory => inapplicable
        | ArtifactDirectoryReserved(directory) =>
          match storage.evidence {
            | StagedEvidence(staged) =>
              startReplayPaths(id, List(fs::evidencePath(storage.root, directory, staged.trace)), selection)
            | PublishedEvidence(trace) =>
              startReplayPaths(id, List(fs::evidencePath(storage.root, directory, trace)), selection)
            | _ => inapplicable
          }
      }
    }

  action copySampledBytes(id: CallId): bool =
    match calls.get(id).phase {
      | AwaitingArtifact(ctx) => {
        val path = fs::workingPath(ctx.generation.workspace, ctx.detail.position.trace.trace)
        nondet count = Set(1, filesystem.files.get(path).length()).oneOf()
        writeArtifactCopy(id, count)
      }
      | _ => inapplicable
    }

  action step: bool = all {
    pendingCalls.size() > 0,
    {
      nondet id = pendingCalls.oneOf()
      // A missing ID cannot pass allocation guards. The fallback still lets
      // this call advance through replay and error responses.
      nondet workspace = (if (WORKSPACE_IDS.size() == 0) Set(0) else WORKSPACE_IDS).oneOf()
      nondet driver = (if (DRIVER_IDS.size() == 0) Set(0) else DRIVER_IDS).oneOf()
      nondet observed = Set(integerDigit(0), integerDigit(1), booleanValue(true), textValue(List(102, 105, 120, 116, 117, 114, 101)), itemSet).oneOf()
      nondet producedBytes = GENERATED_INPUTS.union(Set(List(123))).oneOf()
      any {
        startReplay(id, List()),
        startReplay(id, List(0, 1)),
        startReplay(id, List(0, 0)),
        startReplayPaths(id, List(fs::SavedFile("good.itf.json")), { ...defaultSelection, statePath: List(List(105, 116, 101, 109, 115)) }),
        startReplayPaths(id, List(fs::SavedFile("good.itf.json"), fs::SavedFile("bad.itf.json")),
          { ...defaultSelection, statePath: List(List(105, 116, 101, 109, 115)) }),
        startReplayPaths(id, List(fs::SavedFile("good.itf.json"), fs::SavedFile("missing.itf.json")),
          { ...defaultSelection, statePath: List(List(105, 116, 101, 109, 115)) }),
        startSampledEvidenceReplay(id, workspace, { ...defaultSelection, statePath: List(List(105, 116, 101, 109, 115)) }),
        startReplayPaths(id, List(fs::SavedFile("alias.itf.json")),
          { ...defaultSelection, statePath: List(List(105, 116, 101, 109, 115)) }),
        readSavedPath(id, ReadSucceeded),
        readSavedPath(id, ReadFailed("permission denied")),
        startRequestedRun(id, simulatorRequest(workspace, simulationWithCount(1)),
          sampleSeed, defaultArtifactRoot, { ...defaultSelection, statePath: List(List(105, 116, 101, 109, 115)) }),
        startRequestedRun(id, simulatorRequest(workspace, simulationWithCount(2)),
          sampleSeed, defaultArtifactRoot, { ...defaultSelection, statePath: List(List(105, 116, 101, 109, 115)) }),
        startRequestedRun(id, simulatorRequest(workspace, cli::NamedTestMode({ name: List(97), maxSamples: cli::CliDefault })),
          sampleSeed, defaultArtifactRoot, { actionPath: List(List(100, 105, 115, 112, 97, 116, 99, 104)), statePath: List(List(105, 116, 101, 109, 115)) }),
        failReservation(id, sampleSeed, "temporary directory unavailable"),
        startProcess(id),
        failSpawn(id, "could not start Quint"),
        completeProcessSuccess(id, List()),
        completeProcessSuccess(id,
          List({ name: cli::generatedFilename(List("2")), trace: 0, bytes: producedBytes })
        ),
        completeProcessSuccess(id,
          List({ name: cli::generatedFilename(List("1", "0")), trace: 1, bytes: producedBytes },
            { name: cli::generatedFilename(List("2")), trace: 0, bytes: producedBytes })
        ),
        completeProcessWithEntries(id, List(
          { name: cli::generatedFilename(List("1")), trace: 1, contents: AliasEntry(fs::SavedFile("good.itf.json")) },
          { name: cli::generatedFilename(List("2")), trace: 0, contents: RegularContents(producedBytes) },
        )),
        completeProcessFailure(id, NonzeroExit({ code: 1, output: noProcessOutput }), Map(0 -> List(123))),
        completeProcessFailure(id, SignalExit({ signal: 15, output: noProcessOutput }), Map(0 -> List(123))),
        failProcessIo(id, { stage: WaitForExit, cause: "wait failed" }, ExitUnconfirmed),
        failProcessIo(id, { stage: CollectOutput, cause: "output read failed" }, ExitConfirmed(Map(0 -> List(123)))),
        confirmChildExit(id, Map(0 -> List(123))),
        deferCleanup(id, "exit remains unconfirmed", Map(0 -> List(123))),
        listGeneratedOutput(id, ListingSucceeded),
        listGeneratedOutput(id, ListingFailed("output listing failed")),
        readGeneratedInput(id, ReadSucceeded),
        readGeneratedInput(id, ReadFailed("output file unreadable")),
        validateSampledAbstractTrace(id, ValidSteps(List(openingStep))),
        validateSampledAbstractTrace(id, ValidSteps(List(openingStep, incrementStep))),
        validateSampledAbstractTrace(id, EmptyStates),
        validateSampledAbstractTrace(id, InvalidItf({ location: InvalidStep(1), cause: "invalid later operation" })),
        createDriver(id, FactorySucceeded(driver)),
        createDriver(id, FactoryFailed("factory failed")),
        applyOperation(id, OperationApplied),
        applyOperation(id, OperationFailed("operation failed")),
        applyOperationWithMutation(id, OperationApplied, Map(List(97, 109, 111, 117, 110, 116) -> integerDigit(2))),
        observeState(id, Observed(observed)),
        observeState(id, ObservationFailed("observation failed")),
        planArtifactDirectories(id, List(42, 100 + id)),
        tryArtifactDirectory(id, StorageSucceeded),
        tryArtifactDirectory(id, StorageFailed("artifact directory unavailable")),
        beginArtifactCopy(id),
        copySampledBytes(id),
        completeArtifactCopy(id, StorageSucceeded),
        completeArtifactCopy(id, StorageFailed("artifact destination unavailable")),
        cleanWorkspace(id, StorageSucceeded),
        cleanWorkspace(id, StorageFailed("temporary directory cleanup failed")),
      }
    },
  }
}

module quint_connect_documents {
  import quint_itf as itf from "./quint_itf"
  import quint_filesystem as fs from "./quint_filesystem"

  // UTF-8 bytes of the ITF document below, including its final newline.
  pure val originalBytes: fs::Bytes = List(
    123, 34, 118, 97, 114, 115, 34, 58, 91, 34, 105, 116, 101, 109, 115, 34,
    93, 44, 34, 115, 116, 97, 116, 101, 115, 34, 58, 91, 123, 34, 105, 116,
    101, 109, 115, 34, 58, 123, 34, 35, 115, 101, 116, 34, 58, 91, 123, 34,
    35, 98, 105, 103, 105, 110, 116, 34, 58, 34, 49, 34, 125, 44, 116, 114,
    117, 101, 93, 125, 44, 34, 109, 98, 116, 58, 58, 97, 99, 116, 105, 111,
    110, 84, 97, 107, 101, 110, 34, 58, 34, 105, 110, 105, 116, 34, 44, 34,
    109, 98, 116, 58, 58, 110, 111, 110, 100, 101, 116, 80, 105, 99, 107, 115,
    34, 58, 123, 125, 125, 93, 125, 10,
  )
  pure val otherBytes: fs::Bytes = List(123, 34, 118, 97, 114, 115, 34, 58, 91, 93, 44, 34, 115, 116, 97, 116, 101, 115, 34, 58, 91, 93, 125)

  pure val compoundDocument: itf::ItfDocument = {
    root: 11,
    nodes: List(
      itf::RawText(List(105, 116, 101, 109, 115)),
      itf::RawArray(List(0)),
      itf::RawText(List(49)),
      itf::RawObject(List((itf::bigintKey, 2))),
      itf::RawBoolean(true),
      itf::RawArray(List(3, 4)),
      itf::RawObject(List((itf::setKey, 5))),
      itf::RawText(List(105, 110, 105, 116)),
      itf::RawObject(List()),
      itf::RawObject(List((List(105, 116, 101, 109, 115), 6), (itf::mbtAction, 7), (itf::mbtPicks, 8))),
      itf::RawArray(List(9)),
      itf::RawObject(List((itf::varsKey, 1), (itf::statesKey, 10))),
    ),
  }

  pure val itemsSelection: itf::Selection = { actionPath: List(), statePath: List(List(105, 116, 101, 109, 115)) }

  pure val namedBytes: fs::Bytes = List(
    123, 34, 118, 97, 114, 115, 34, 58, 91, 34, 105, 116, 101, 109, 115, 34,
    44, 34, 100, 105, 115, 112, 97, 116, 99, 104, 34, 93, 44, 34, 115, 116,
    97, 116, 101, 115, 34, 58, 91, 123, 34, 105, 116, 101, 109, 115, 34, 58,
    123, 34, 35, 115, 101, 116, 34, 58, 91, 123, 34, 35, 98, 105, 103, 105,
    110, 116, 34, 58, 34, 49, 34, 125, 44, 116, 114, 117, 101, 93, 125, 44,
    34, 100, 105, 115, 112, 97, 116, 99, 104, 34, 58, 123, 34, 116, 97, 103,
    34, 58, 34, 105, 110, 105, 116, 34, 44, 34, 118, 97, 108, 117, 101, 34,
    58, 123, 34, 35, 116, 117, 112, 34, 58, 91, 93, 125, 125, 125, 93, 125,
    10,
  )

  pure val savedInputs: str -> fs::Bytes = Map(
    "good.itf.json" -> originalBytes,
    "bad.itf.json" -> List(123),
    "empty.itf.json" -> otherBytes,
    "named.itf.json" -> namedBytes,
  )

  pure val savedAliases: str -> fs::FilePath = Map(
    "alias.itf.json" -> fs::SavedFile("good.itf.json"),
    "dangling.itf.json" -> fs::SavedFile("missing.itf.json"),
    "cycle.itf.json" -> fs::SavedFile("cycle-hop.itf.json"),
    "cycle-hop.itf.json" -> fs::SavedFile("cycle.itf.json"),
  )

  pure val generatedInputs: Set[fs::Bytes] = Set(originalBytes, otherBytes, namedBytes)

}

module quint_connect_sample {
  import quint_connect_documents.*
  import quint_connect(CALL_IDS = Set(1, 2), WORKSPACE_IDS = Set(1, 2), DRIVER_IDS = Set(1, 2, 3, 4), GENERATED_INPUTS = generatedInputs, SAVED_INPUTS = savedInputs, SAVED_ALIASES = savedAliases, EXISTING_ARTIFACTS = Map()).*

  observation replayStarted = anyCallHas(event =>
    match event {
      | ReplayRequested(paths) => paths.length() > 0
      | ReplayFilesRequested(paths) => paths.length() > 0
      | _ => false
    }
  )

  observation workspaceReserved = anyCallHas(event =>
    match event {
      | WorkspaceReserved(_) => true
      | _ => false
    }
  )

  observation reservationFailed = anyCallHas(event =>
    match event {
      | FailureRecognized(error) =>
        match error {
          | WorkspaceFailed(failure) => failure.stage == Reserve
          | _ => false
        }
      | _ => false
    }
  )

  observation listingFailureObserved = anyCallHas(event =>
    match event {
      | FailureRecognized(error) =>
        match error {
          | OutputListingFailed(_) => true
          | _ => false
        }
      | _ => false
    }
  )

  observation generatedReadFailed = anyCallHas(event =>
    match event {
      | FailureRecognized(error) =>
        match error {
          | TraceFailed(failure) =>
            match failure.location {
              | AtGeneratedTrace(_) => true
              | _ => false
            }
          | _ => false
        }
      | _ => false
    }
  )

  def processFailureObserved(matches: (ProcessProblem) => bool): bool =
    anyCallHas(event =>
      match event {
        | FailureRecognized(error) =>
          match error {
            | QuintFailed(failure) => matches(failure.problem)
            | _ => false
          }
        | _ => false
      }
    )

  observation spawnFailed = processFailureObserved(problem =>
    match problem {
      | SpawnFailure(_) => true
      | _ => false
    }
  )

  observation processExitedNonzero = processFailureObserved(problem =>
    match problem {
      | NonzeroExit(_) => true
      | _ => false
    }
  )

  observation processWasSignaled = processFailureObserved(problem =>
    match problem {
      | SignalExit(_) => true
      | _ => false
    }
  )

  observation processIoFailed = anyCallHas(event =>
    match event {
      | ProcessIoFailed(_) => true
      | _ => false
    }
  )

  observation workspaceCleanupDeferred = anyCallHas(event =>
    match event {
      | WorkspaceCleanupDeferred(_) => true
      | _ => false
    }
  )

  observation generationCompleted = anyCallHas(event =>
    match event {
      | GenerationCompleted(_) => true
      | _ => false
    }
  )

  observation traceValidated = anyCallHas(event =>
    match event {
      | TraceValidated(_) => true
      | _ => false
    }
  )

  observation driverCreated = anyCallHas(event =>
    match event {
      | DriverCreated(_) => true
      | _ => false
    }
  )

  observation driverArgumentsChanged = anyCallHas(event =>
    match event {
      | DriverArgumentsChanged(_) => true
      | _ => false
    }
  )

  observation operationCalled = anyCallHas(event =>
    match event {
      | OperationCalled(_) => true
      | _ => false
    }
  )

  observation stateObserved = anyCallHas(event =>
    match event {
      | ObservationCalled(_) => true
      | _ => false
    }
  )

  observation mismatchObserved = anyCallHas(event =>
    match event {
      | DifferenceObserved(_) => true
      | _ => false
    }
  )

  observation artifactDirectoryReserved = anyCallHas(event =>
    match event {
      | ArtifactDirectoryTried(attempt) => attempt.result == DirectoryReserved
      | _ => false
    }
  )

  observation artifactDirectoryCollision = anyCallHas(event =>
    match event {
      | ArtifactDirectoryTried(attempt) => attempt.result == DirectoryCollision
      | _ => false
    }
  )

  observation artifactCopyStaged =
    filesystem.workspaces.keys().exists(workspace =>
      match filesystem.workspaces.get(workspace).evidence {
        | StagedEvidence(_) => true
        | _ => false
      }
    )

  observation artifactCopyWritten =
    filesystem.workspaces.keys().exists(workspace =>
      match filesystem.workspaces.get(workspace).evidence {
        | StagedEvidence(staged) => staged.bytes.length() > 0
        | _ => false
      }
    )

  observation artifactSaveAttempted = anyCallHas(event =>
    match event {
      | SaveAttempted(_) => true
      | _ => false
    }
  )

  observation artifactSaved = anyCallHas(event =>
    match event {
      | FailureRecognized(error) =>
        match error {
          | StatesDiffer(failure) =>
            match failure.artifacts {
              | FromGeneration(g) =>
                match g.save {
                  | ArtifactSaved(_) => true
                  | _ => false
                }
              | _ => false
            }
          | _ => false
        }
      | _ => false
    }
  )

  observation workspaceCleaned = anyCallHas(event =>
    match event {
      | CleanupAttempted(_) => true
      | _ => false
    }
  )

  observation callPassed = anyCallHas(event =>
    match event {
      | Returned(result) => result == Passed
      | _ => false
    }
  )

  observation parallelWorkspaces =
    pendingCalls.size() == 2 and
      pendingCalls.forall(id => hasEvent(calls.get(id).history, event =>
        match event {
          | WorkspaceReserved(_) => true
          | _ => false
        }
      ))

  observation bothCallsFinished = pendingCalls.size() == 0
}
