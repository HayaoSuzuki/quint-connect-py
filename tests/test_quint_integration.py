import os
from pathlib import Path
from shutil import which
from typing import Literal

import pytest
from quint_connect import (
    Action,
    NamedTest,
    QuintError,
    QuintMap,
    QuintValue,
    Simulation,
    StateMismatchError,
    replay,
    run,
)

MODEL = Path(__file__).resolve().parents[1] / "examples" / "counter.qnt"
Backend = Literal["rust", "typescript"]


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


@pytest.mark.parametrize("backend", ["rust", "typescript"])
def test_counter_matches_simulation(backend: Backend) -> None:
    config = Simulation(MODEL, max_steps=2)

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


@pytest.mark.parametrize("backend", ["rust", "typescript"])
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


def test_generated_mismatch_can_be_replayed(tmp_path: Path) -> None:
    config = Simulation(MODEL, max_steps=2)
    shared = os.environ.get("QUINT_TEST_SHARED_ARTIFACT_DIR")
    artifact_dir = tmp_path if shared is None else Path(shared)

    class BrokenCounter:
        def step(self, _action: Action, /) -> None:
            pass

        def observe(self) -> int:
            return 0

    with pytest.raises(StateMismatchError) as generated:
        run(
            config,
            BrokenCounter,
            quint=quint_executable(),
            seed=42,
            artifact_dir=artifact_dir,
            action_path=("op",),
            state_path=("count",),
        )

    artifact = generated.value.artifact_path
    assert artifact is not None
    assert artifact.is_file()
    assert not generated.value.trace_path.exists()
    assert generated.value.seed == 42
    with pytest.raises(StateMismatchError) as saved:
        replay(artifact, BrokenCounter, action_path=("op",), state_path=("count",))
    assert (saved.value.step_index, saved.value.action, saved.value.expected) == (
        generated.value.step_index,
        generated.value.action,
        generated.value.expected,
    )


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


@pytest.mark.parametrize("backend", ["rust", "typescript"])
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

    assert caught.value.stage == "lookup"
    assert caught.value.executable == Path("quint")
    assert caught.value.stdout == caught.value.stderr == b""
    assert caught.value.exit_code is None
    assert caught.value.signal is None
