// Observable behavior of run() and replay() in issue #1.
// Calls progress independently through command planning, ITF decoding, comparison,
// and filesystem effects. Process and operating-system outcomes are external inputs.
module quint_connect {
  import quint_values as qv from "./quint_values"
  import quint_itf as itf from "./quint_itf"
  import quint_cli as cli from "./quint_cli"
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

  pure def textValue(value: str): Value =
    { nodes: List(qv::TextNode(value)), root: 0 }

  type Operation = {
    name: str,
    arguments: str -> Value,
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
    | SavedPaths(List[str])
    | SavedEvidence({ root: str, workspace: WorkspaceId })
    | GeneratedItf(Generation)

  type TracePosition = {
    trace: TraceId,
    traceIndex: int,
  }

  type StepPosition = {
    trace: TracePosition,
    stepIndex: int,
  }

  type TraceBatch = {
    source: Source,
    traces: List[TraceId],
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

  // Internal generation result, with filenames ordered by completeProcessSuccess.
  type GenerationResult = ProcessFailed(str) | ProcessSucceeded(List[TraceId])

  type SavedTracePosition = { path: str, position: TracePosition }

  type Location =
    | AtTrace(TracePosition)
    | AtStep(StepPosition)
    | AtSavedTrace(SavedTracePosition)
    | AtSavedStep({ path: str, position: StepPosition })

  type SavedReadResult = SavedReadSucceeded | SavedReadFailed(str)

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

  // Retained evidence uses a distinct namespace and survives workspace cleanup.
  type ArtifactDirectory = FailureDirectory(WorkspaceId)

  type Artifact = {
    directory: ArtifactDirectory,
    trace: TraceId,
    root: str,
  }

  type SaveResult = ArtifactSaved(Artifact) | ArtifactSaveFailed(str)

  type Artifacts =
    | FromSavedTrace
    | FromSavedFile(str)
    | FromGeneration({ seed: Seed, save: SaveResult })

  type EmptyInput = NoInputPaths | NoGeneratedItf | NoTraceStates(TracePosition) | NoSavedTraceStates(SavedTracePosition)

  type WorkspaceStage = Reserve | Cleanup

  type RequestProblem =
    | RejectedSeed
    | RejectedTraceCount
    | RejectedActionPath
    | RejectedSampleLimit
    | RejectedStepLimit

  type Failure =
    | InvalidRequest(RequestProblem)
    | WorkspaceFailed({ seed: Seed, stage: WorkspaceStage, cause: str })
    | QuintFailed({ seed: Seed, cause: str })
    | EmptyTrace(EmptyInput)
    | IncompleteGeneration({ seed: Seed, requested: int, produced: int })
    | TraceFailed(TraceError)
    | DriverFailed(DriverErrorDetail)
    | StatesDiffer({ detail: Mismatch, artifacts: Artifacts })

  type CleanupNote = NoCleanupError | CleanupAlsoFailed(str)

  type Outcome = Passed | Failed({ error: Failure, cleanup: CleanupNote })

  type Phase =
    | Ready
    | AwaitingGeneration(Generation)
    | AwaitingValidation(TraceBatch)
    | AwaitingDriver(ValidatedTrace)
    | AwaitingOperation(ActiveTrace)
    | AwaitingObservation(ActiveTrace)
    | AwaitingArtifact({ generation: Generation, detail: Mismatch })
    | AwaitingCleanup({ generation: Generation, result: Outcome })
    | Finished(Outcome)

  // The history records observable calls in order, including calls that fail.
  type Event =
    | ReplayRequested(List[TraceId])
    | ReplayFilesRequested(List[str])
    | SavedReadAttempted(SavedTracePosition)
    | CommandPrepared({ request: cli::CliRequest, drawnSeed: Seed, command: cli::QuintCommand })
    | WorkspaceReserved(Generation)
    | GenerationCompleted({ generation: Generation, result: GenerationResult })
    | ValidationAttempted(TracePosition)
    | TraceValidated({ position: TracePosition, steps: List[TraceStep] })
    | FactoryCalled(TracePosition)
    | DriverCreated({ trace: TracePosition, driver: DriverId })
    | OperationCalled({ context: DriverStep, operation: Operation })
    | ObservationCalled({ context: DriverStep, expected: Value })
    | ObservationMatched({ position: StepPosition, actual: Value })
    | DifferenceObserved(Mismatch)
    | SaveAttempted({ position: TracePosition, result: StorageResult })
    | CleanupAttempted({ workspace: WorkspaceId, result: StorageResult })
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
  const JSON_LABELS: itf::TextLabels
  const GENERATED_INPUTS: Set[fs::Bytes]
  const SAVED_INPUTS: str -> fs::Bytes

  pure val initialFilesystem: fs::FileSystem = {
    ...fs::emptyFileSystem,
    files: SAVED_INPUTS.keys().fold(Map(), (acc, path) => acc.put(fs::SavedFile(path), SAVED_INPUTS.get(path))),
  }

  var calls: CallId -> CallState
  var filesystem: fs::FileSystem

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
      { ...recorded, phase: AwaitingValidation({ source: source, traces: traces, traceIndex: 0 }) }
  }

  pure def finish(s: CallState, source: Source, result: Outcome): CallState =
    match source {
      | SavedItf => returned(s, result)
      | SavedPaths(_) => returned(s, result)
      | SavedEvidence(_) => returned(s, result)
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

  pure def onGeneration(s: CallState, g: Generation, result: GenerationResult): CallState = {
    val recorded = recordEvent(s, s.phase, GenerationCompleted({ generation: g, result: result }))
    val source = GeneratedItf(g)
    match result {
      | ProcessFailed(cause) => stop(recorded, source, QuintFailed({ seed: g.seed, cause: cause }))
      | ProcessSucceeded(traces) =>
        if (traces.length() == 0)
          stop(recorded, source, EmptyTrace(NoGeneratedItf))
        else
          match g.expectation {
            | SimulationCount(requested) =>
              if (hasEnoughTraces(g.expectation, traces.length()))
                { ...recorded, phase: AwaitingValidation({ source: source, traces: traces, traceIndex: 0 }) }
              else
                stop(recorded, source, IncompleteGeneration({
                  seed: g.seed, requested: requested, produced: traces.length(),
                }))
            | NamedTestOutput =>
              { ...recorded, phase: AwaitingValidation({ source: source, traces: traces, traceIndex: 0 }) }
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

  pure def onOperation(s: CallState, active: ActiveTrace, result: OperationResult): CallState = {
    val context = driverStep(active)
    val recorded = recordEvent(s, s.phase, OperationCalled({ context: context, operation: currentStep(active).operation }))
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
      | SavedEvidence(_) => stop(recorded, source, StatesDiffer({ detail: detail, artifacts: FromSavedTrace }))
      | GeneratedItf(g) => { ...recorded, phase: AwaitingArtifact({ generation: g, detail: detail }) }
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

  pure def onArtifact(s: CallState, g: Generation, detail: Mismatch, result: StorageResult): CallState = {
    val recorded = recordEvent(s, s.phase, SaveAttempted({ position: detail.position.trace, result: result }))
    val save = match result {
      | StorageSucceeded => ArtifactSaved({ directory: FailureDirectory(g.workspace), trace: detail.position.trace.trace, root: g.artifactRoot })
      | StorageFailed(cause) => ArtifactSaveFailed(cause)
    }
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
  }

  action changeCallWithFiles(id: CallId, updated: CallState, snapshot: fs::FileSystem): bool = all {
    calls' = calls.set(id, updated),
    filesystem' = snapshot,
  }

  action changeCall(id: CallId, updated: CallState): bool =
    changeCallWithFiles(id, updated, filesystem)

  // Branches of an action-valued match must declare the same updates.
  // The false guard keeps a phase mismatch from producing a transition.
  action inapplicable: bool = all {
    false,
    calls' = calls,
    filesystem' = filesystem,
  }

  action startReplayWithSelection(id: CallId, traces: List[TraceId], selection: itf::Selection): bool = all {
    calls.get(id).phase == Ready,
    changeCall(id, onReplay({ ...calls.get(id), selection: selection }, SavedItf, traces)),
  }

  action startReplay(id: CallId, traces: List[TraceId]): bool =
    startReplayWithSelection(id, traces, defaultSelection)

  action startReplayPaths(id: CallId, paths: List[str], selection: itf::Selection): bool = all {
    calls.get(id).phase == Ready,
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
      recordEvent(requestState, AwaitingGeneration(g), WorkspaceReserved(g)),
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

  action startRequestedRun(
    id: CallId, request: cli::CliRequest, drawnSeed: Seed, artifactRoot: str, selection: itf::Selection
  ): bool =
    match cli::quintCommand(request, drawnSeed) {
      | InvalidSeed => rejectRunRequest(id, RejectedSeed)
      | InvalidTraceCount => rejectRunRequest(id, RejectedTraceCount)
      | InvalidSampleLimit => rejectRunRequest(id, RejectedSampleLimit)
      | InvalidStepLimit => rejectRunRequest(id, RejectedStepLimit)
      | CommandReady(command) =>
        if (hasActionSource(request.config, selection)) {
          val requestState = { ...calls.get(id), selection: selection }
          reserveRun(id, {
            expectation: commandExpectation(request.config),
            seed: command.seed,
            workspace: command.workspace,
            artifactRoot: artifactRoot,
          }, recordEvent(requestState, Ready, CommandPrepared({ request: request, drawnSeed: drawnSeed, command: command })))
        } else rejectRunRequest(id, RejectedActionPath)
    }

  action failReservation(id: CallId, seed: Seed, cause: str): bool = all {
    calls.get(id).phase == Ready,
    changeCall(id, stop(calls.get(id), SavedItf, WorkspaceFailed({ seed: seed, stage: Reserve, cause: cause }))),
  }

  pure def traceSet(traces: List[TraceId]): Set[TraceId] =
    traces.foldl(Set(), (distinct, trace) => distinct.union(Set(trace)))

  pure def generationFilesAgree(result: GenerationResult, output: fs::GenerationFiles): bool =
    match result {
      | ProcessFailed(_) =>
        match output {
          | AbortedFiles(_) => true
          | _ => false
        }
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
          changeCallWithFiles(
            id, onGeneration(calls.get(id), g, result), fs::recordTraceFiles(filesystem, g.workspace, output)
          ),
        }
      | _ => inapplicable
    }

  action completeProcessFailure(id: CallId, cause: str, partialOutput: fs::TraceFiles): bool =
    completeGenerationWithFiles(id, ProcessFailed(cause), fs::AbortedFiles(partialOutput))

  // One complete listing carries both each file's basename and its bytes.
  type ProducedFile = { name: List[str], trace: TraceId, bytes: fs::Bytes }

  pure def generatedNames(entries: List[ProducedFile]): List[cli::GeneratedFile] =
    entries.foldl(List(), (acc, entry) => acc.append({ name: entry.name, trace: entry.trace }))

  pure def generatedBytes(entries: List[ProducedFile]): fs::TraceFiles =
    entries.foldl(Map(), (acc, entry) => acc.put(entry.trace, entry.bytes))

  pure def distinctProducedFiles(entries: List[ProducedFile]): bool =
    entries.indices().map(i => entries.nth(i).name).size() == entries.length() and
      entries.indices().map(i => entries.nth(i).trace).size() == entries.length()

  action completeProcessSuccess(id: CallId, entries: List[ProducedFile]): bool = all {
    distinctProducedFiles(entries),
    completeGenerationWithFiles(
      id,
      ProcessSucceeded(cli::orderedGeneratedTraces(generatedNames(entries))),
      fs::GeneratedFiles(generatedBytes(entries))
    ),
  }

  // Existing lifecycle scenarios give ordered trace IDs and omit byte contents.
  action completeGeneration(id: CallId, result: GenerationResult): bool =
    match result {
      | ProcessFailed(cause) => completeProcessFailure(id, cause, Map())
      | ProcessSucceeded(paths) =>
        completeGenerationWithFiles(id, result, fs::GeneratedFiles(traceSet(paths).mapBy(_ => List())))
    }

  def traceIsReadable(batch: TraceBatch): bool =
    match batch.source {
      | SavedItf => true
      | SavedPaths(_) => false
      | SavedEvidence(saved) =>
        filesystem.files.keys().contains(fs::evidencePath(saved.root, saved.workspace, tracePosition(batch).trace))
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
    match itf::parseItfBytes(bytes, JSON_LABELS) {
      | ByteInputParsed(document) => fromDecodedTrace(itf::decodeItf(document, selection))
      | ByteInputInvalidUtf8 => InvalidItf({ location: InvalidFile, cause: "invalid UTF-8" })
      | ByteInputInvalidJson => InvalidItf({ location: InvalidFile, cause: "invalid JSON" })
      | ByteInputUnlabeledText => InvalidItf({ location: InvalidFile, cause: "unlabeled JSON text in model input" })
    }

  action validateBytes(id: CallId, bytes: fs::Bytes): bool =
    validateTrace(id, validationForBytes(bytes, calls.get(id).selection))

  pure def validateSavedFile(snapshot: fs::FileSystem, path: str, result: SavedReadResult, selection: itf::Selection): ValidationResult = {
    val location = fs::SavedFile(path)
    if (not(snapshot.files.keys().contains(location)))
      InvalidItf({ location: InvalidFile, cause: "file not found" })
    else
      match result {
        | SavedReadFailed(cause) => InvalidItf({ location: InvalidFile, cause: cause })
        | SavedReadSucceeded => validationForBytes(snapshot.files.get(location), selection)
      }
  }

  action readSavedPath(id: CallId, result: SavedReadResult): bool =
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
          | SavedEvidence(_) => false
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
    validateBytes(id, bytes),
  }

  action replayEvidence(
    id: CallId, artifactRoot: str, workspace: WorkspaceId, trace: TraceId, selection: itf::Selection
  ): bool = all {
    calls.get(id).phase == Ready,
    filesystem.files.keys().contains(fs::evidencePath(artifactRoot, workspace, trace)),
    changeCall(id, onReplay(
      { ...calls.get(id), selection: selection }, SavedEvidence({ root: artifactRoot, workspace: workspace }), List(trace)
    )),
  }

  def evidenceInputMatches(id: CallId, bytes: fs::Bytes): bool =
    match calls.get(id).phase {
      | AwaitingValidation(batch) =>
        match batch.source {
          | SavedEvidence(saved) => {
            val path = fs::evidencePath(saved.root, saved.workspace, tracePosition(batch).trace)
            if (filesystem.files.keys().contains(path)) filesystem.files.get(path) == bytes
            else false
          }
          | _ => false
        }
      | _ => false
    }

  action validateEvidenceDocument(id: CallId, bytes: fs::Bytes): bool = all {
    evidenceInputMatches(id, bytes),
    validateBytes(id, bytes),
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

  action applyOperation(id: CallId, result: OperationResult): bool =
    match calls.get(id).phase {
      | AwaitingOperation(active) => changeCall(id, onOperation(calls.get(id), active, result))
      | _ => inapplicable
    }

  action observeState(id: CallId, result: ObservationResult): bool =
    match calls.get(id).phase {
      | AwaitingObservation(active) => changeCall(id, onObservation(calls.get(id), active, result))
      | _ => inapplicable
    }

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
        all {
          copyAgrees(result, copy),
          fs::canRetainTraceFile(filesystem, workspace, trace, copy),
          changeCallWithFiles(
            id,
            onArtifact(calls.get(id), ctx.generation, ctx.detail, result),
            fs::retainTraceFile(filesystem, workspace, trace, copy)
          ),
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

  pure val openingStep: TraceStep =
    { operation: { name: "init", arguments: Map() }, expected: integerDigit(0) }

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
    if (hasPrior(history, index, event =>
      match event {
        | ReplayFilesRequested(_) => true
        | _ => false
      }
    ))
      previousIs(history, index, event =>
        match event {
          | SavedReadAttempted(file) => file.position == position
          | _ => false
        }
      )
    else traceIsNext(history, index, position)

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

  pure def observationFollowsOperation(history: List[Event], index: int, ctx: DriverStep): bool =
    previousIs(history, index, event =>
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
          if (index >= 2)
            match history.nth(index - 2) {
              | OperationCalled(operation) =>
                operation.context.position == detail.position and operation.operation == detail.step.operation
              | _ => false
            }
          else
            false
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
      | SaveAttempted(_) => true
      | CleanupAttempted(_) => true
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

  pure def savedRequiredTrace(
    g: Generation, position: TracePosition, save: SaveResult, storage: StorageResult
  ): bool =
    match storage {
      | StorageSucceeded =>
        save == ArtifactSaved({ directory: FailureDirectory(g.workspace), trace: position.trace, root: g.artifactRoot })
      | StorageFailed(cause) => save == ArtifactSaveFailed(cause)
    }

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
                        savedRequiredTrace(completed.generation, attempt.position, detail.save, attempt.result)
                    | _ => false
                  }
                )
            | _ => false
          }
        )
    }

  pure def matchingDiagnostics(history: List[Event], index: int): bool =
    match history.nth(index) {
      | SaveAttempted(attempt) =>
        previousIs(history, index, event =>
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
    if (reservations.size() == 1 and cleanups.size() == 1) {
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
                    commandExpectation(plan.request.config) == g.expectation
                | _ => true
              }
            )
          | GenerationCompleted(completed) =>
            hasPrior(history, index, event => event == WorkspaceReserved(completed.generation))
          | CleanupAttempted(cleaned) => ownsWorkspace(history, cleaned.workspace)
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
            val savedPath = fs::evidencePath(storage.root, workspace, trace)
            if (attempt.result == StorageSucceeded)
              storage.evidence == fs::PublishedEvidence(trace) and filesystem.files.keys().contains(savedPath)
            else
              storage.evidence == fs::AbandonedEvidence(trace) and not(filesystem.files.keys().contains(savedPath))
          }
          | _ => true
        }
      )
    }

  val persistedEvidence: bool =
    filesystem.workspaces.keys().forall(workspace =>
      evidenceFollowsSave(calls.get(filesystem.workspaces.get(workspace).owner).history, workspace)
    )

  val safety: bool = and {
    replayInOrder,
    firstFailureStopsReplay,
    mismatchKeepsEvidence,
    consistentResult,
    isolatedResources,
    fs::fileSystemSafety(filesystem, initialFilesystem),
    persistedEvidence,
  }

  pure val incrementStep: TraceStep =
    { operation: { name: "increment", arguments: Map("amount" -> integerDigit(1)) }, expected: integerDigit(1) }

  pure def hasFinished(phase: Phase): bool =
    match phase {
      | Finished(_) => true
      | _ => false
    }

  val pendingCalls: Set[CallId] =
    CALL_IDS.filter(id => not(hasFinished(calls.get(id).phase)))

  pure def simulatorRequest(workspace: WorkspaceId, config: cli::QuintConfig): cli::CliRequest = {
    executable: "/bin/quint", model: "/models/sample.qnt", workspace: workspace,
    main: cli::CliDefault, backend: cli::CliDefault, seed: cli::CliSpecified(sampleSeed), config: config,
  }

  pure def simulationWithCount(count: int): cli::QuintConfig =
    cli::Simulation({
      init: cli::CliDefault, step: cli::CliDefault, nTraces: cli::CliSpecified(count),
      maxSamples: cli::CliDefault, maxSteps: cli::CliDefault,
    })

  action validateSampledSavedTrace(id: CallId, result: ValidationResult): bool =
    match calls.get(id).phase {
      | AwaitingValidation(batch) => all { batch.source == SavedItf, validateTrace(id, result) }
      | _ => inapplicable
    }

  action readGeneratedInput(id: CallId): bool =
    match calls.get(id).phase {
      | AwaitingValidation(batch) =>
        match batch.source {
          | GeneratedItf(g) => {
            val trace = tracePosition(batch).trace
            if (fs::canReadGeneratedFile(filesystem, g.workspace, trace))
              validateGeneratedDocument(id, filesystem.files.get(fs::workingPath(g.workspace, trace)))
            else inapplicable
          }
          | _ => inapplicable
        }
      | _ => inapplicable
    }

  pure val itemSet: Value = {
    root: 2,
    nodes: List(qv::BooleanNode(true), qv::IntegerNode({ negative: false, digits: List(1) }), qv::SetNode(List(0, 1))),
  }

  action step: bool = all {
    pendingCalls.size() > 0,
    {
      nondet id = pendingCalls.oneOf()
      nondet workspace = WORKSPACE_IDS.oneOf()
      nondet driver = DRIVER_IDS.oneOf()
      nondet observed = Set(integerDigit(0), integerDigit(1), booleanValue(true), textValue("fixture"), itemSet).oneOf()
      nondet producedBytes = GENERATED_INPUTS.union(Set(List(123))).oneOf()
      any {
        startReplay(id, List()),
        startReplay(id, List(0, 1)),
        startReplay(id, List(0, 0)),
        startReplayPaths(id, List("good.itf.json"), { ...defaultSelection, statePath: List("items") }),
        startReplayPaths(id, List("good.itf.json", "bad.itf.json"), { ...defaultSelection, statePath: List("items") }),
        startReplayPaths(id, List("good.itf.json", "missing.itf.json"), { ...defaultSelection, statePath: List("items") }),
        readSavedPath(id, SavedReadSucceeded),
        readSavedPath(id, SavedReadFailed("permission denied")),
        startRequestedRun(id, simulatorRequest(workspace, simulationWithCount(1)),
          sampleSeed, defaultArtifactRoot, { ...defaultSelection, statePath: List("items") }),
        startRequestedRun(id, simulatorRequest(workspace, simulationWithCount(2)),
          sampleSeed, defaultArtifactRoot, { ...defaultSelection, statePath: List("items") }),
        startRequestedRun(id, simulatorRequest(workspace, cli::NamedTestMode({ name: List(97), maxSamples: cli::CliDefault })),
          sampleSeed, defaultArtifactRoot, { actionPath: List("dispatch"), statePath: List("items") }),
        failReservation(id, sampleSeed, "temporary directory unavailable"),
        completeProcessSuccess(id, List()),
        completeProcessSuccess(id,
          List({ name: cli::generatedFilename(List("2")), trace: 0, bytes: producedBytes })
        ),
        completeProcessSuccess(id,
          List({ name: cli::generatedFilename(List("1", "0")), trace: 1, bytes: producedBytes },
            { name: cli::generatedFilename(List("2")), trace: 0, bytes: producedBytes })
        ),
        completeProcessFailure(id, "Quint failed", Map(0 -> List(123))),
        readGeneratedInput(id),
        validateSampledSavedTrace(id, ValidSteps(List(openingStep))),
        validateSampledSavedTrace(id, ValidSteps(List(openingStep, incrementStep))),
        validateSampledSavedTrace(id, EmptyStates),
        validateSampledSavedTrace(id, InvalidItf({ location: InvalidStep(1), cause: "invalid later operation" })),
        createDriver(id, FactorySucceeded(driver)),
        createDriver(id, FactoryFailed("factory failed")),
        applyOperation(id, OperationApplied),
        applyOperation(id, OperationFailed("operation failed")),
        observeState(id, Observed(observed)),
        observeState(id, ObservationFailed("observation failed")),
        saveArtifact(id, StorageSucceeded),
        saveArtifact(id, StorageFailed("artifact destination unavailable")),
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
      itf::RawText({ spelling: "items", codePoints: List(105, 116, 101, 109, 115) }),
      itf::RawArray(List(0)),
      itf::RawText({ spelling: "1", codePoints: List(49) }),
      itf::RawObject(List(("#bigint", 2))),
      itf::RawBoolean(true),
      itf::RawArray(List(3, 4)),
      itf::RawObject(List(("#set", 5))),
      itf::RawText({ spelling: "init", codePoints: List(105, 110, 105, 116) }),
      itf::RawObject(List()),
      itf::RawObject(List(("items", 6), ("mbt::actionTaken", 7), ("mbt::nondetPicks", 8))),
      itf::RawArray(List(9)),
      itf::RawObject(List(("vars", 1), ("states", 10))),
    ),
  }

  pure val itemsSelection: itf::Selection = { actionPath: List(), statePath: List("items") }

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

  pure val generatedInputs: Set[fs::Bytes] = Set(originalBytes, otherBytes, namedBytes)

  pure val jsonLabels: itf::TextLabels = Map(
    List(118, 97, 114, 115) -> "vars",
    List(115, 116, 97, 116, 101, 115) -> "states",
    List(105, 116, 101, 109, 115) -> "items",
    List(35, 115, 101, 116) -> "#set",
    List(35, 98, 105, 103, 105, 110, 116) -> "#bigint",
    List(49) -> "1",
    List(109, 98, 116, 58, 58, 97, 99, 116, 105, 111, 110, 84, 97, 107, 101, 110) -> "mbt::actionTaken",
    List(109, 98, 116, 58, 58, 110, 111, 110, 100, 101, 116, 80, 105, 99, 107, 115) -> "mbt::nondetPicks",
    List(105, 110, 105, 116) -> "init",
    List(100, 105, 115, 112, 97, 116, 99, 104) -> "dispatch",
    List(116, 97, 103) -> "tag",
    List(118, 97, 108, 117, 101) -> "value",
    List(35, 116, 117, 112) -> "#tup",
  )
}

module quint_connect_sample {
  import quint_connect_documents.*
  import quint_connect(CALL_IDS = Set(1, 2), WORKSPACE_IDS = Set(1, 2), DRIVER_IDS = Set(1, 2, 3, 4), JSON_LABELS = jsonLabels, GENERATED_INPUTS = generatedInputs, SAVED_INPUTS = savedInputs).*

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
