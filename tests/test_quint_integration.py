import os
from collections.abc import Generator
from contextlib import contextmanager
from pathlib import Path
from shutil import which
from typing import override

import pytest
from quint_connect import (
    Action,
    Backend,
    DriverError,
    DriverStage,
    NamedTest,
    NamedTests,
    QuintError,
    QuintMap,
    QuintStage,
    QuintValue,
    Simulation,
    StateComparison,
    StateMismatchError,
    replay,
    run,
)

MODEL = Path(__file__).resolve().parents[1] / "examples" / "counter.qnt"


class Counter:
    def __init__(self) -> None:
        self.count = 0

    def step(self, action: Action, /) -> None:
        if action.name == "Reset":
            self.count = 0
        else:
            assert action.name == "Add"
            delta = action.arguments["delta"]
            assert type(delta) is int
            self.count += delta

    def observe(self) -> int:
        return self.count


def quint_executable() -> str:
    path = which("quint")
    if path is None:
        pytest.skip("requires Quint 0.34.0 on PATH")
    return path


@pytest.mark.parametrize("backend", [Backend.RUST, Backend.TYPESCRIPT])
def test_counter_matches_simulation(backend: Backend, tmp_path: Path) -> None:
    config = Simulation(MODEL, max_steps=2)
    artifact_dir = tmp_path / "output" / "artifacts"

    result = run(
        config,
        Counter,
        quint=quint_executable(),
        seed=42,
        backend=backend,
        artifact_dir=artifact_dir,
        action_path=("op",),
        state_path=("count",),
    )

    assert result is None
    assert not artifact_dir.exists()


@pytest.mark.parametrize("backend", [Backend.RUST, Backend.TYPESCRIPT])
def test_counter_matches_named_test(backend: Backend) -> None:
    config = NamedTest(MODEL, test="roundTripTest", max_samples=1)

    result = run(
        config,
        Counter,
        quint=quint_executable(),
        seed=42,
        backend=backend,
        action_path=("op",),
        state_path=("count",),
    )

    assert result is None


@pytest.mark.parametrize("backend", [Backend.RUST, Backend.TYPESCRIPT])
def test_named_tests_selects_multiple_traces(tmp_path: Path, backend: Backend) -> None:
    model = tmp_path / "selection.qnt"
    model.write_text(
        """module selection {
  var op: { tag: str, value: () }
  action init = op' = { tag: "Reset", value: () }
  run alphaTest = init.expect(op.tag == "Reset")
  run betaTest = init.expect(op.tag == "Reset")
  run unrelatedTest = init.expect(false)
}""",
        encoding="utf-8",
    )
    events: list[str] = []

    class RecordingDriver:
        def step(self, action: Action, /) -> None:
            events.append(action.name)

    run(
        NamedTests(model, pattern="^(alpha|beta)Test$", max_samples=1),
        RecordingDriver,
        quint=quint_executable(),
        backend=backend,
        comparison=None,
        action_path=("op",),
        seed=42,
    )

    assert events == ["Reset", "Reset"]


@pytest.mark.parametrize(
    "stage",
    [DriverStage.FACTORY, DriverStage.APPLY, DriverStage.OBSERVE, DriverStage.COMPARE],
)
def test_generated_driver_failure_saves_a_replayable_trace(
    tmp_path: Path, stage: DriverStage
) -> None:
    failure = RuntimeError(stage.value)
    artifact_dir = tmp_path / "output" / "artifacts"

    class FailingDriver(Counter):
        @override
        def step(self, action: Action, /) -> None:
            if stage is DriverStage.APPLY:
                raise failure
            super().step(action)

        @override
        def observe(self) -> int:
            if stage is DriverStage.OBSERVE:
                raise failure
            return super().observe()

    def factory() -> FailingDriver:
        if stage is DriverStage.FACTORY:
            raise failure
        return FailingDriver()

    def equals(expected: QuintValue, actual: QuintValue) -> bool:
        if stage is DriverStage.COMPARE:
            raise failure
        return expected == actual

    comparison = StateComparison(equals=equals)

    with pytest.raises(DriverError) as caught:
        run(
            Simulation(MODEL, max_steps=2),
            factory,
            quint=quint_executable(),
            seed=42,
            artifact_dir=artifact_dir,
            comparison=comparison,
            action_path=("op",),
            state_path=("count",),
        )

    error = caught.value
    assert error.seed == 42
    assert error.stage is stage
    assert error.__cause__ is failure
    assert error.artifact_error is None
    assert error.artifact_path is not None
    assert error.artifact_path.is_file()
    assert not error.trace_path.exists()
    with pytest.raises(DriverError) as saved:
        replay(
            error.artifact_path,
            factory,
            action_path=("op",),
            state_path=("count",),
            comparison=comparison,
        )
    assert saved.value.stage is stage
    assert saved.value.step_index == error.step_index


def test_generated_context_exit_failure_saves_the_trace(tmp_path: Path) -> None:
    failure = RuntimeError("context exit failed")

    @contextmanager
    def driver_context() -> Generator[Counter]:
        yield Counter()
        raise failure

    with pytest.raises(DriverError) as caught:
        run(
            Simulation(MODEL, max_steps=2),
            driver_context=driver_context,
            quint=quint_executable(),
            seed=42,
            artifact_dir=tmp_path,
            action_path=("op",),
            state_path=("count",),
        )

    error = caught.value
    assert error.stage is DriverStage.EXIT
    assert error.__cause__ is failure
    assert error.artifact_path is not None
    assert error.artifact_path.is_file()


def test_generated_mismatch_can_be_replayed(tmp_path: Path) -> None:
    config = Simulation(MODEL, max_steps=2)
    shared = os.environ.get("QUINT_TEST_SHARED_ARTIFACT_DIR")
    artifact_dir = tmp_path / "output" / "artifacts" if shared is None else Path(shared)

    class BrokenCounter:
        def step(self, _action: Action, /) -> None:
            pass

        def observe(self) -> int:
            return 0

    received: list[StateMismatchError] = []

    @contextmanager
    def driver_context() -> Generator[BrokenCounter]:
        try:
            yield BrokenCounter()
        except StateMismatchError as error:
            received.append(error)
            raise

    with pytest.raises(StateMismatchError) as generated:
        run(
            config,
            driver_context=driver_context,
            quint=quint_executable(),
            seed=42,
            artifact_dir=artifact_dir,
            action_path=("op",),
            state_path=("count",),
        )

    assert generated.value is received[0]
    artifact = generated.value.artifact_path
    assert generated.value.artifact_error is None
    assert artifact is not None
    assert artifact.is_file()
    assert artifact.is_relative_to(artifact_dir)
    assert not generated.value.trace_path.exists()
    assert generated.value.seed == 42
    with pytest.raises(StateMismatchError) as saved:
        replay(artifact, BrokenCounter, action_path=("op",), state_path=("count",))
    assert (saved.value.step_index, saved.value.action, saved.value.expected) == (
        generated.value.step_index,
        generated.value.action,
        generated.value.expected,
    )


@pytest.mark.parametrize("error_type", [StateMismatchError, DriverError])
def test_artifact_root_failure_keeps_the_replay_error(
    tmp_path: Path, error_type: type[StateMismatchError | DriverError]
) -> None:
    occupied = tmp_path / "output"
    occupied.write_text("existing file", encoding="utf-8")
    failure = RuntimeError("driver failed")

    class FailingCounter(Counter):
        @override
        def observe(self) -> int:
            if error_type is DriverError:
                raise failure
            return -1

    with pytest.raises(error_type) as caught:
        run(
            Simulation(MODEL, max_steps=2),
            FailingCounter,
            quint=quint_executable(),
            seed=42,
            artifact_dir=occupied / "artifacts",
            action_path=("op",),
            state_path=("count",),
        )

    error = caught.value
    assert error.seed == 42
    assert error.artifact_path is None
    assert error.artifact_candidate is None
    assert isinstance(error.artifact_error, OSError)
    assert not error.trace_path.exists()
    assert occupied.read_text(encoding="utf-8") == "existing file"
    if isinstance(error, DriverError):
        assert error.__cause__ is failure


class TicTacToe:
    def __init__(self) -> None:
        self.board: dict[tuple[int, int], str] = {}
        self.turn = "X"

    def step(self, action: Action, /) -> None:
        if action.name == "init":
            self.board.clear()
            self.turn = "X"
            return
        if action.name == "stuttered":
            return

        assert action.name in ("MoveX", "MoveO")
        player = action.name[-1]
        assert player == self.turn
        position = action.arguments.get(
            "coordinate", action.arguments.get("corner", (2, 2))
        )
        assert isinstance(position, tuple)
        assert len(position) == 2
        row, column = position
        assert type(row) is int
        assert type(column) is int
        assert (row, column) not in self.board
        self.board[row, column] = player
        self.turn = "O" if player == "X" else "X"

    def observe(self) -> QuintValue:
        def cell(row: int, column: int) -> QuintValue:
            player = self.board.get((row, column))
            if player is None:
                return {"tag": "Empty", "value": ()}
            return {"tag": "Occupied", "value": {"tag": player, "value": ()}}

        board = QuintMap(
            (row, QuintMap((column, cell(row, column)) for column in range(1, 4)))
            for row in range(1, 4)
        )
        return {"board": board, "nextTurn": {"tag": self.turn, "value": ()}}


@pytest.mark.parametrize("backend", [Backend.RUST, Backend.TYPESCRIPT])
def test_pinned_upstream_tictactoe(backend: Backend) -> None:
    model = Path(__file__).with_name("fixtures") / "tictactoe.qnt"
    config = Simulation(model, max_steps=12)

    result = run(config, TicTacToe, quint=quint_executable(), seed=42, backend=backend)

    assert result is None


@pytest.mark.skipif(os.name != "posix", reason="uses the POSIX TMPDIR setting")
def test_default_artifact_parent_stays_in_caller_directory(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    quint = quint_executable()
    caller = tmp_path / "caller"
    moved = tmp_path / "driver"
    first_temp = caller / "tmp"
    first_temp.mkdir(parents=True)
    (moved / "tmp").mkdir(parents=True)
    monkeypatch.chdir(caller)
    monkeypatch.setenv("TMPDIR", "tmp")
    config = Simulation(MODEL, max_steps=0)

    class DirectoryChangingDriver:
        def step(self, _action: Action, /) -> None:
            monkeypatch.chdir(moved)

        def observe(self) -> int:
            return 1

    with pytest.raises(StateMismatchError) as caught:
        run(
            config,
            DirectoryChangingDriver,
            quint=quint,
            seed=42,
            action_path=("op",),
            state_path=("count",),
        )

    artifact = caught.value.artifact_path
    assert artifact is not None
    assert artifact.parent.parent == first_temp
    assert artifact.is_file()


def test_lookup_error_has_stable_process_attributes(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("PATH", str(tmp_path))
    config = Simulation(MODEL, max_steps=0)

    with pytest.raises(QuintError) as caught:
        run(config, Counter, quint="quint", seed=42)

    assert caught.value.stage is QuintStage.LOOKUP
    assert caught.value.executable == Path("quint")
    assert caught.value.stdout == caught.value.stderr == b""
    assert caught.value.exit_code is None
    assert caught.value.signal is None
