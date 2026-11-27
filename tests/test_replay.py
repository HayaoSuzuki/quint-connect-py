import json
import logging
import tempfile
from collections.abc import Generator
from contextlib import contextmanager, suppress
from pathlib import Path
from typing import override

import pytest
from hypothesis import given
from hypothesis import strategies as st
from quint_connect import (
    Action,
    DriverError,
    DriverStage,
    EmptyTraceError,
    InvalidTraceError,
    QuintValue,
    StateComparison,
    StateMismatchError,
    replay,
)


def write_trace(path: Path, states: list[dict[str, object]]) -> Path:
    path.write_text(json.dumps({"vars": ["state"], "states": states}), encoding="utf-8")
    return path


def state(value: object, picks: dict[str, object] | None = None) -> dict[str, object]:
    return {
        "state": value,
        "mbt::actionTaken": "init",
        "mbt::nondetPicks": {} if picks is None else picks,
    }


class ConstantDriver:
    def __init__(self, value: QuintValue) -> None:
        self.value = value

    def step(self, _action: Action, /) -> None:
        pass

    def observe(self) -> QuintValue:
        return self.value


def test_replay_without_observation(tmp_path: Path) -> None:
    path = write_trace(tmp_path / "trace.itf.json", [state({"#unserializable": "Int"})])
    calls: list[str] = []

    class ActionDriver:
        def step(self, action: Action, /) -> None:
            calls.append(action.name)

    replay(path, ActionDriver, comparison=None)

    assert calls == ["init"]


def test_operation_only_still_validates_operations_before_creation(
    tmp_path: Path,
) -> None:
    path = write_trace(tmp_path / "trace.itf.json", [state(True), {"state": True}])

    def factory() -> ConstantDriver:
        pytest.fail("invalid operations must be rejected before creating a driver")

    with pytest.raises(InvalidTraceError) as caught:
        replay(path, factory, comparison=None)

    assert caught.value.step_index == 1


def test_replay_transforms_expected_state(tmp_path: Path) -> None:
    path = write_trace(tmp_path / "trace.itf.json", [state("MODEL")])

    def lower(value: QuintValue) -> str:
        assert isinstance(value, str)
        return value.lower()

    replay(
        path,
        lambda: ConstantDriver("model"),
        state_path=("state",),
        comparison=StateComparison(transform_expected=lower),
    )


def test_replay_uses_custom_equality(tmp_path: Path) -> None:
    path = write_trace(tmp_path / "trace.itf.json", [state({"#bigint": "10"})])

    def near(expected: QuintValue, actual: QuintValue) -> bool:
        assert type(expected) is int
        assert type(actual) is int
        return abs(expected - actual) <= 1

    replay(
        path,
        lambda: ConstantDriver(11),
        state_path=("state",),
        comparison=StateComparison(equals=near),
    )


def test_mismatch_reports_the_values_used_by_the_comparator(tmp_path: Path) -> None:
    path = write_trace(tmp_path / "trace.itf.json", [state("MODEL")])
    comparison = StateComparison(
        transform_expected=lambda _value: "model",
        equals=lambda _expected, _actual: False,
    )

    with pytest.raises(StateMismatchError) as caught:
        replay(
            path,
            lambda: ConstantDriver("model"),
            state_path=("state",),
            comparison=comparison,
        )

    assert caught.value.expected == "model"
    assert caught.value.actual == "model"
    assert caught.value.diff == ""


def test_replay_preserves_comparison_exception(tmp_path: Path) -> None:
    path = write_trace(tmp_path / "trace.itf.json", [state(True)])
    failure = RuntimeError("comparison failed")

    def compare(_expected: QuintValue, _actual: QuintValue) -> bool:
        raise failure

    with pytest.raises(DriverError) as caught:
        replay(
            path,
            lambda: ConstantDriver(True),
            state_path=("state",),
            comparison=StateComparison(equals=compare),
        )

    assert caught.value.stage is DriverStage.COMPARE
    assert caught.value.step_index == 0
    assert caught.value.__cause__ is failure


def test_state_mismatch_displays_a_diff(tmp_path: Path) -> None:
    path = write_trace(tmp_path / "trace.itf.json", [state({"answer": True})])

    with pytest.raises(StateMismatchError) as caught:
        replay(path, lambda: ConstantDriver({"answer": False}), state_path=("state",))

    assert "-{'answer': True}" in caught.value.diff
    assert "+{'answer': False}" in caught.value.diff
    assert caught.value.diff in str(caught.value)


def test_replay_logs_trace_step_and_observation(
    tmp_path: Path, caplog: pytest.LogCaptureFixture
) -> None:
    path = write_trace(tmp_path / "trace.itf.json", [state(True)])

    with caplog.at_level(logging.DEBUG, logger="quint_connect"):
        replay(path, lambda: ConstantDriver(True), state_path=("state",))

    assert any("trace 0" in message for message in caplog.messages)
    assert any("step 0" in message and "init" in message for message in caplog.messages)
    assert any("observed True" in message for message in caplog.messages)


@given(st.integers(min_value=-(2**512), max_value=2**512))
def test_python_integer_round_trips(number: int) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        path = write_trace(
            Path(tmp) / "trace.itf.json", [state({"#bigint": str(number)})]
        )

        result = replay(path, lambda: ConstantDriver(number), state_path=("state",))

    assert result is None


def test_invalid_tail_is_reported_before_factory(tmp_path: Path) -> None:
    path = write_trace(tmp_path / "trace.itf.json", [state(True), {"state": True}])
    calls = []

    def factory() -> ConstantDriver:
        calls.append("factory")
        return ConstantDriver(True)

    with pytest.raises(InvalidTraceError) as caught:
        replay(path, factory, state_path=("state",))

    assert caught.value.trace_path == path
    assert caught.value.step_index == 1
    assert calls == []


def test_driver_mutation_does_not_change_mismatch_arguments(tmp_path: Path) -> None:
    path = write_trace(
        tmp_path / "trace.itf.json", [state(True, {"items": [{"flag": True}]})]
    )

    class MutatingDriver(ConstantDriver):
        @override
        def step(self, action: Action, /) -> None:
            items = action.arguments["items"]
            assert isinstance(items, list)
            first = items[0]
            assert isinstance(first, dict)
            first["flag"] = False

    with pytest.raises(StateMismatchError) as caught:
        replay(path, lambda: MutatingDriver(False), state_path=("state",))

    assert caught.value.action.arguments == {"items": [{"flag": True}]}
    assert caught.value.expected is True
    assert caught.value.actual is False


@pytest.mark.parametrize(
    "stage", [DriverStage.FACTORY, DriverStage.APPLY, DriverStage.OBSERVE]
)
def test_driver_failure_keeps_original_exception(
    tmp_path: Path, stage: DriverStage
) -> None:
    path = write_trace(tmp_path / "trace.itf.json", [state(True)])
    original = RuntimeError(stage.value)

    class FailingDriver(ConstantDriver):
        @override
        def step(self, _action: Action, /) -> None:
            if stage is DriverStage.APPLY:
                raise original

        @override
        def observe(self) -> QuintValue:
            if stage is DriverStage.OBSERVE:
                raise original
            return True

    def factory() -> ConstantDriver:
        if stage is DriverStage.FACTORY:
            raise original
        return FailingDriver(True)

    with pytest.raises(DriverError) as caught:
        replay(path, factory, state_path=("state",))

    assert caught.value.stage is stage
    assert caught.value.__cause__ is original
    assert caught.value.seed is None
    assert caught.value.artifact_path is None


def test_context_exits_before_the_next_trace(tmp_path: Path) -> None:
    path = write_trace(tmp_path / "trace.itf.json", [state(True)])
    events: list[str] = []

    @contextmanager
    def driver_context() -> Generator[ConstantDriver]:
        events.append("enter")
        try:
            yield ConstantDriver(True)
        finally:
            events.append("exit")

    replay([path, path], driver_context=driver_context, state_path=("state",))

    assert events == ["enter", "exit", "enter", "exit"]


def test_context_receives_driver_failure(tmp_path: Path) -> None:
    path = write_trace(tmp_path / "trace.itf.json", [state(True)])
    failure = RuntimeError("driver failed")
    received: list[RuntimeError] = []

    class FailingDriver(ConstantDriver):
        @override
        def step(self, _action: Action, /) -> None:
            raise failure

    @contextmanager
    def driver_context() -> Generator[ConstantDriver]:
        try:
            yield FailingDriver(True)
        except RuntimeError as error:
            received.append(error)
            raise

    with pytest.raises(DriverError) as caught:
        replay(path, driver_context=driver_context, state_path=("state",))

    assert received == [failure]
    assert caught.value.__cause__ is failure


def test_context_exit_cannot_suppress_a_mismatch(tmp_path: Path) -> None:
    path = write_trace(tmp_path / "trace.itf.json", [state(True)])

    @contextmanager
    def driver_context() -> Generator[ConstantDriver]:
        with suppress(StateMismatchError):
            yield ConstantDriver(False)

    with pytest.raises(StateMismatchError) as caught:
        replay(path, driver_context=driver_context, state_path=("state",))

    assert caught.value.actual is False


def test_context_exit_failure_preserves_the_mismatch(tmp_path: Path) -> None:
    path = write_trace(tmp_path / "trace.itf.json", [state(True)])
    failure = RuntimeError("context exit failed")

    @contextmanager
    def driver_context() -> Generator[ConstantDriver]:
        try:
            yield ConstantDriver(False)
        finally:
            raise failure

    with pytest.raises(StateMismatchError) as caught:
        replay(path, driver_context=driver_context, state_path=("state",))

    assert caught.value.actual is False
    assert caught.value.driver_cleanup_error is failure


def test_context_exit_failure_is_reported_after_a_passing_trace(
    tmp_path: Path,
) -> None:
    path = write_trace(tmp_path / "trace.itf.json", [state(True)])
    failure = RuntimeError("context exit failed")

    @contextmanager
    def driver_context() -> Generator[ConstantDriver]:
        yield ConstantDriver(True)
        raise failure

    with pytest.raises(DriverError) as caught:
        replay(path, driver_context=driver_context, state_path=("state",))

    assert caught.value.stage is DriverStage.EXIT
    assert caught.value.step_index is None
    assert caught.value.__cause__ is failure


def test_deep_selected_value_survives_decode_conversion_and_comparison(
    tmp_path: Path,
) -> None:
    depth = 12_000
    arrays = "[" * depth + "true" + "]" * depth
    trace = tmp_path / "deep.itf.json"
    trace.write_text(
        '{"vars":["state"],"states":[{"state":'
        + arrays
        + ',"mbt::actionTaken":"init","mbt::nondetPicks":{"argument":'
        + arrays
        + "}}]}",
        encoding="utf-8",
    )

    class DeepDriver:
        def __init__(self) -> None:
            self.observed: QuintValue = False

        def step(self, action: Action, /) -> None:
            self.observed = action.arguments["argument"]

        def observe(self) -> QuintValue:
            return self.observed

    result = replay(trace, DeepDriver, state_path=("state",))

    assert result is None


def test_empty_path_list_has_nullable_trace_attributes() -> None:
    paths: list[Path] = []

    with pytest.raises(EmptyTraceError) as caught:
        replay(paths, lambda: ConstantDriver(True))

    assert caught.value.trace_path is None
    assert caught.value.trace_index is None
    assert caught.value.step_index is None
