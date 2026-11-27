import json
import tempfile
from pathlib import Path
from typing import override

import pytest
from hypothesis import given
from hypothesis import strategies as st
from quint_connect import (
    Action,
    DriverError,
    EmptyTraceError,
    InvalidTraceError,
    QuintValue,
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


@pytest.mark.parametrize("stage", ["factory", "apply", "observe"])
def test_driver_failure_keeps_original_exception(tmp_path: Path, stage: str) -> None:
    path = write_trace(tmp_path / "trace.itf.json", [state(True)])
    original = RuntimeError(stage)

    class FailingDriver(ConstantDriver):
        @override
        def step(self, _action: Action, /) -> None:
            if stage == "apply":
                raise original

        @override
        def observe(self) -> QuintValue:
            if stage == "observe":
                raise original
            return True

    def factory() -> ConstantDriver:
        if stage == "factory":
            raise original
        return FailingDriver(True)

    with pytest.raises(DriverError) as caught:
        replay(path, factory, state_path=("state",))

    assert caught.value.stage == stage
    assert caught.value.__cause__ is original


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
