"""Run Quint model traces against a Python driver."""

from collections.abc import Callable, Iterable, Sequence
from contextlib import AbstractContextManager, nullcontext
from dataclasses import dataclass, field
from os import PathLike
from typing import Protocol, cast, overload

from . import _native
from ._enums import Backend, DriverStage, QuintStage, WorkspaceStage
from ._native import (
    DriverError,
    EmptyTraceError,
    IncompleteGenerationError,
    InvalidTraceError,
    QuintError,
    StateMismatchError,
    WorkspaceError,
)

__all__ = [
    "Action",
    "Backend",
    "Driver",
    "DriverError",
    "DriverStage",
    "EmptyTraceError",
    "IncompleteGenerationError",
    "InvalidTraceError",
    "NamedTest",
    "QuintError",
    "QuintMap",
    "QuintSet",
    "QuintStage",
    "QuintValue",
    "Simulation",
    "StateMismatchError",
    "WorkspaceError",
    "WorkspaceStage",
    "replay",
    "run",
]

type FilePath = str | PathLike[str]
type QuintValue = (
    bool
    | int
    | str
    | list[QuintValue]
    | tuple[QuintValue, ...]
    | dict[str, QuintValue]
    | QuintSet
    | QuintMap
)


@dataclass(frozen=True, slots=True, init=False)
class QuintSet:
    """A Quint set whose elements may be compound values."""

    values: tuple[QuintValue, ...]

    def __init__(self, values: Iterable[QuintValue]) -> None:
        """Take a snapshot of the input elements."""
        object.__setattr__(self, "values", tuple(values))


@dataclass(frozen=True, slots=True, init=False)
class QuintMap:
    """A Quint map whose keys may be compound values."""

    entries: tuple[tuple[QuintValue, QuintValue], ...]

    def __init__(self, entries: Iterable[tuple[QuintValue, QuintValue]]) -> None:
        """Take a snapshot of the input entries."""
        object.__setattr__(self, "entries", tuple(entries))


@dataclass(frozen=True, slots=True)
class Action:
    """The operation name and its named arguments for this step."""

    name: str
    arguments: dict[str, QuintValue]


class Driver(Protocol):
    """Apply a model operation and report the implementation state."""

    def step(self, action: Action, /) -> None:
        """Apply the operation to this trace state."""

    def observe(self) -> QuintValue:
        """Return the state that the trace compares."""


@dataclass(frozen=True, slots=True, kw_only=True)
class _ModelConfig:
    main: str | None = None
    max_samples: int | None = None


@dataclass(frozen=True, slots=True)
class Simulation(_ModelConfig):
    """Generate traces using Quint simulation."""

    spec: FilePath
    init: str | None = field(default=None, kw_only=True)
    step: str | None = field(default=None, kw_only=True)
    n_traces: int = field(default=1, kw_only=True)
    max_steps: int | None = field(default=None, kw_only=True)


@dataclass(frozen=True, slots=True)
class NamedTest(_ModelConfig):
    """Generate traces from one named Quint test."""

    spec: FilePath
    test: str = field(kw_only=True)


def _unsigned(name: str, value: int | None) -> int | None:
    if value is None:
        return None
    if isinstance(value, bool) or not isinstance(value, int) or not 0 <= value < 2**64:
        message = f"{name} must be an integer in the range 0..2**64"
        raise ValueError(message)
    return value


type _DriverFactory = Callable[[], Driver]
type _DriverContextFactory = Callable[[], AbstractContextManager[Driver]]


def _context_factory(
    factory: _DriverFactory | None,
    context: _DriverContextFactory | None,
) -> _DriverContextFactory:
    if factory is not None and context is None:
        return lambda: nullcontext(factory())
    if context is not None and factory is None:
        return context
    message = "supply exactly one of driver_factory and driver_context"
    raise TypeError(message)


@overload
def replay(
    traces: FilePath | Sequence[FilePath],
    driver_factory: _DriverFactory,
    *,
    driver_context: None = None,
    action_path: Sequence[str] = (),
    state_path: Sequence[str] = (),
) -> None: ...


@overload
def replay(
    traces: FilePath | Sequence[FilePath],
    driver_factory: None = None,
    *,
    driver_context: _DriverContextFactory,
    action_path: Sequence[str] = (),
    state_path: Sequence[str] = (),
) -> None: ...


def replay(
    traces: FilePath | Sequence[FilePath],
    driver_factory: _DriverFactory | None = None,
    *,
    driver_context: _DriverContextFactory | None = None,
    action_path: Sequence[str] = (),
    state_path: Sequence[str] = (),
) -> None:
    """Replay each saved trace with a fresh driver and close its context."""
    paths = (
        [cast("FilePath", traces)] if isinstance(traces, (str, PathLike)) else traces
    )
    _native.replay(
        paths,
        _context_factory(driver_factory, driver_context),
        (action_path, state_path),
    )


@overload
def run(
    config: Simulation | NamedTest,
    driver_factory: _DriverFactory,
    *,
    driver_context: None = None,
    quint: FilePath,
    seed: int | None = None,
    backend: Backend | None = None,
    action_path: Sequence[str] = (),
    state_path: Sequence[str] = (),
    artifact_dir: FilePath | None = None,
) -> None: ...


@overload
def run(
    config: Simulation | NamedTest,
    driver_factory: None = None,
    *,
    driver_context: _DriverContextFactory,
    quint: FilePath,
    seed: int | None = None,
    backend: Backend | None = None,
    action_path: Sequence[str] = (),
    state_path: Sequence[str] = (),
    artifact_dir: FilePath | None = None,
) -> None: ...


def run(  # noqa: PLR0913 - The documented options are keyword-only.
    config: Simulation | NamedTest,
    driver_factory: _DriverFactory | None = None,
    *,
    driver_context: _DriverContextFactory | None = None,
    quint: FilePath,
    seed: int | None = None,
    backend: Backend | None = None,
    action_path: Sequence[str] = (),
    state_path: Sequence[str] = (),
    artifact_dir: FilePath | None = None,
) -> None:
    """Generate Quint traces and replay each with its own driver lifetime."""
    seed = _unsigned("seed", seed)
    if backend is not None and not isinstance(backend, Backend):
        message = "backend must be a Backend member"
        raise TypeError(message)
    if isinstance(config, Simulation):
        traces = _unsigned("n_traces", config.n_traces)
        if traces is None:
            message = "n_traces must be an integer"
            raise ValueError(message)
        mode = None
        options = (
            config.init,
            config.step,
            traces,
            _unsigned("max_steps", config.max_steps),
        )
    elif isinstance(config, NamedTest):
        mode = config.test
        options = None
    else:
        message = "config must be Simulation or NamedTest"
        raise TypeError(message)
    _native.run(
        (config.spec, config.main, _unsigned("max_samples", config.max_samples)),
        mode,
        options,
        _context_factory(driver_factory, driver_context),
        (quint, seed, None if backend is None else backend.value, artifact_dir),
        (action_path, state_path),
    )
