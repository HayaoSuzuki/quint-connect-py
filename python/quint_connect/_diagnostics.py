"""Format replay diagnostics using the application's logging configuration."""

import logging
from difflib import unified_diff
from pprint import pformat

_LOGGER = logging.getLogger("quint_connect")


def logging_enabled() -> bool:
    """Check whether replay should report events to Python."""
    return _LOGGER.isEnabledFor(logging.INFO)


def detail_logging_enabled() -> bool:
    """Check whether replay should convert per-step diagnostics."""
    return _LOGGER.isEnabledFor(logging.DEBUG)


def trace_started(trace_index: int, path: object) -> None:
    """Report which ITF file is about to be read."""
    _LOGGER.info("trace %d: %s", trace_index, path)


def step_started(trace_index: int, step_index: int, action: object) -> None:
    """Report the action and arguments before calling the driver."""
    _LOGGER.debug("trace %d step %d: %r", trace_index, step_index, action)


def expected_state(trace_index: int, step_index: int, value: object) -> None:
    """Report the model state selected from the ITF."""
    _LOGGER.debug("trace %d step %d: expected %r", trace_index, step_index, value)


def observed_state(trace_index: int, step_index: int, value: object) -> None:
    """Report the implementation's observed state."""
    _LOGGER.debug("trace %d step %d: observed %r", trace_index, step_index, value)


def state_diff(expected: object, actual: object) -> str:
    """Render differences between the values attached to a mismatch."""
    return "\n".join(
        unified_diff(
            pformat(expected).splitlines(),
            pformat(actual).splitlines(),
            fromfile="expected",
            tofile="actual",
            lineterm="",
        )
    )
