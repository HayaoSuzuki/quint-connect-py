// Observable behavior of run() and replay() in issue #1.
// Calls progress independently. Quint CLI, ITF validation, and driver results
// enter as outcomes. Values and paths have finite representatives for simulation.
module quint_connect {
  type CallId = int
  type WorkspaceId = int
  type DriverId = int
  type TraceId = int
  type Seed = int

  type Value = IntValue(int) | BoolValue(bool) | TextValue(str)

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
  }

  type Source = SavedItf | GeneratedItf(Generation)

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

  type GenerationResult = ProcessFailed(str) | ProcessSucceeded(List[TraceId])

  type Location = AtTrace(TracePosition) | AtStep(StepPosition)

  type TraceError = {
    location: Location,
    cause: str,
  }

  type ValidationResult = ValidSteps(List[TraceStep]) | EmptyStates | InvalidItf(TraceError)

  type DriverStage = Factory | Apply | Observe

  type DriverErrorDetail = {
    location: Location,
    stage: DriverStage,
    cause: str,
  }

  type Mismatch = {
    position: StepPosition,
    step: TraceStep,
    actual: Value,
  }

  // An artifact identifies the exact ITF and its call-specific directory.
  type Artifact = {
    directory: WorkspaceId,
    trace: TraceId,
  }

  type SaveResult = ArtifactSaved(Artifact) | ArtifactSaveFailed(str)

  type Artifacts = FromSavedTrace | FromGeneration({ seed: Seed, save: SaveResult })

  type EmptyInput = NoInputPaths | NoGeneratedItf | NoTraceStates(TracePosition)

  type WorkspaceStage = Reserve | Cleanup

  type Failure =
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
    | WorkspaceReserved(WorkspaceId)
    | ValidationAttempted(TracePosition)
    | TraceValidated(TracePosition)
    | FactoryCalled(TracePosition)
    | DriverCreated({ trace: TracePosition, driver: DriverId })
    | OperationCalled(StepPosition)
    | ObservationCalled(StepPosition)
    | DifferenceObserved(Mismatch)
    | SaveAttempted(TracePosition)
    | CleanupAttempted(WorkspaceId)
    | Returned(Outcome)

  type CallState = {
    phase: Phase,
    history: List[Event],
  }

  type WorkspaceOwner = WorkspaceFree | WorkspaceReservedBy(CallId)

  var calls: CallId -> CallState
  var workspaces: WorkspaceId -> WorkspaceOwner
}
