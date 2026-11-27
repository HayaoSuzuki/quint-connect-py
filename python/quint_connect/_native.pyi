from collections.abc import Callable, Sequence
from os import PathLike
from pathlib import Path
from typing import Literal

from . import Action, Driver, QuintValue

type _Path = str | PathLike[str]
type _Selection = tuple[Sequence[str], Sequence[str]]

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
    stage: Literal["factory", "apply", "observe"]

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

class QuintError(Exception):
    seed: int | None
    stage: str
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
    stage: str
    cleanup_error: OSError | None
    cleanup_deferred: bool
    workspace: Path | None

class IncompleteGenerationError(Exception):
    seed: int
    requested: int
    produced: int

def replay(
    paths: Sequence[_Path],
    driver_factory: Callable[[], Driver],
    selection: _Selection,
    /,
) -> None: ...
def run(
    common: tuple[_Path, str | None, int | None],
    named_test: str | None,
    simulation: tuple[str | None, str | None, int, int | None] | None,
    driver_factory: Callable[[], Driver],
    execution: tuple[_Path, int | None, str | None, _Path | None],
    selection: _Selection,
    /,
) -> None: ...
