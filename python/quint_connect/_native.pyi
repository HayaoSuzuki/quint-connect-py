from collections.abc import Sequence
from os import PathLike
from pathlib import Path

from . import Action, QuintValue, _DriverContextFactory, _RunRequest, _SelectionPaths
from ._enums import DriverStage, QuintStage, WorkspaceStage

type _Path = str | PathLike[str]

class InvalidTraceError(Exception):
    trace_path: Path
    trace_index: int
    step_index: int | None
    reason: str

class EmptyTraceError(Exception):
    trace_path: Path | None
    trace_index: int | None
    step_index: int | None

class DriverError(Exception):
    trace_path: Path
    trace_index: int
    step_index: int | None
    stage: DriverStage
    seed: int | None
    artifact_path: Path | None
    artifact_error: OSError | None
    artifact_candidate: Path | None
    cleanup_error: OSError | None
    cleanup_deferred: bool
    workspace: Path | None
    driver_cleanup_error: BaseException | None

class StateMismatchError(AssertionError):
    trace_path: Path
    trace_index: int
    step_index: int
    action: Action
    expected: QuintValue
    actual: QuintValue
    seed: int | None
    artifact_path: Path | None
    artifact_error: OSError | None
    artifact_candidate: Path | None
    cleanup_error: OSError | None
    cleanup_deferred: bool
    workspace: Path | None
    driver_cleanup_error: BaseException | None

class QuintError(Exception):
    seed: int | None
    stage: QuintStage
    exit_code: int | None
    signal: int | None
    stdout: bytes
    stderr: bytes
    executable: Path | None
    cleanup_error: OSError | None
    cleanup_deferred: bool
    workspace: Path | None

class WorkspaceError(Exception):
    seed: int | None
    stage: WorkspaceStage
    cleanup_error: OSError | None
    cleanup_deferred: bool
    workspace: Path | None

class IncompleteGenerationError(Exception):
    seed: int
    requested: int
    produced: int

def replay(
    paths: Sequence[_Path],
    context_factory: _DriverContextFactory,
    selection: _SelectionPaths,
    /,
) -> None: ...
def run(
    request: _RunRequest,
    context_factory: _DriverContextFactory,
    selection: _SelectionPaths,
    /,
) -> None: ...
