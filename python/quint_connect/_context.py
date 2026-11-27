"""Adapt a Python with statement to the native driver's enter and exit calls."""

from collections.abc import Callable, Generator
from contextlib import AbstractContextManager
from types import TracebackType
from typing import cast


def _using[T](
    factory: Callable[[], AbstractContextManager[T]],
) -> Generator[T, None, StopIteration | None]:
    # Return failures so a StopIteration from the user's context retains its identity.
    try:
        with factory() as driver:
            yield driver
    except StopIteration as failure:
        return failure
    return None


class WithContext[T]:
    """Suspend the user's with statement while the native runner uses the driver."""

    def __init__(self, factory: Callable[[], AbstractContextManager[T]]) -> None:
        """Defer calling the factory until enter."""
        self._scope = _using(factory)

    def __enter__(self) -> T:
        """Open the context and obtain its driver."""
        try:
            return next(self._scope)
        except StopIteration as finished:
            # Only a StopIteration from the factory or enter can terminate here.
            failure = cast("StopIteration", finished.value)
        raise failure

    def __exit__(
        self,
        _exc_type: type[BaseException] | None,
        error: BaseException | None,
        _traceback: TracebackType | None,
        /,
    ) -> None:
        """Resume the with statement and propagate any exit failure."""
        failure: StopIteration | None = None
        try:
            if error is None:
                next(self._scope)
            else:
                self._scope.throw(error)
        except StopIteration as finished:
            failure = cast("StopIteration | None", finished.value)
        if failure is not None:
            raise failure
