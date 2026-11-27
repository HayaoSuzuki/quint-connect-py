"""Finite options and diagnostic stages exposed by the Python API."""

from enum import Enum


class Backend(Enum):
    """An evaluator for executing Quint models."""

    RUST = "rust"
    TYPESCRIPT = "typescript"


class DriverStage(Enum):
    """The driver callback that failed while replaying a trace."""

    FACTORY = "factory"
    APPLY = "apply"
    OBSERVE = "observe"
    EXIT = "exit"


class QuintStage(Enum):
    """The process operation that failed while running Quint."""

    LOOKUP = "lookup"
    SPAWN = "spawn"
    WAIT_FOR_EXIT = "wait_for_exit"
    COLLECT_OUTPUT = "collect_output"
    EXIT = "exit"


class WorkspaceStage(Enum):
    """The workspace operation that failed while generating traces."""

    RANDOM_SEED = "random_seed"
    CALLER_DIRECTORY = "caller_directory"
    RESERVE = "reserve"
    LISTING = "listing"
    CLEANUP = "cleanup"
