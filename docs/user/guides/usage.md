# Generate and replay Quint traces

## Install with uv

In a uv project with a `requires-python` range within `>=3.14,<3.16`, add
Quint Connect to the development dependency group.

```sh
uv add --group dev quint-connect-py
```

To start a new project in an empty directory, initialize it first.

```sh
uv init --bare --python '>=3.14,<3.16'
uv add --group dev quint-connect-py
```

Use `uv run` to run Python or your test command in the project environment.
The Python import is `quint_connect`.

## Write a driver

Implement `step(action)` to apply an operation through the public API of the code
under test. Implement `observe()` to return the state you want to compare with
the model. Read the operation name from `action.name` and its named arguments
from `action.arguments`. Handle initialization through the operation recorded
at step 0. Quint records an empty name for anonymous operations.

Provide a factory that returns a fresh driver each time Quint Connect calls it.
If a driver owns resources, supply `driver_context` as a factory that opens a
context manager yielding the driver. For example, given your test harness's
`open_environment` and `TestDriver`:

```python
from contextlib import contextmanager
from quint_connect import replay


@contextmanager
def driver_context():
    with open_environment() as environment:
        yield TestDriver(environment)


replay(["first.itf.json", "second.itf.json"], driver_context=driver_context)
```

Each context is entered after its trace is validated and exited before the
next trace starts. Supply either the driver factory or `driver_context`.
On failure, the context receives the original driver exception or a
`StateMismatchError`. A context manager's return value cannot suppress the
replay failure. A failure during exit produces `DriverError` with
`DriverStage.EXIT` if the trace passed. If replay failed first, the exit
exception is available as `driver_cleanup_error` on the original error.

## Replay a saved ITF trace

```python
from quint_connect import replay

replay("counter.itf.json", CounterDriver, state_path=("count",))
```

With this selection, `replay()` compares `count` in each trace state with the
value returned by `observe()`. Implement `CounterDriver` for the code under
test. After installing a compatible wheel, you can replay saved ITF traces
offline.

## Generate traces with Quint

```python
from quint_connect import Backend, Simulation, run

run(
    Simulation("counter.qnt", n_traces=10),
    CounterDriver,
    quint="/path/to/quint",
    seed=42,
    backend=Backend.RUST,
    state_path=("count",),
)
```

Quint Connect supports the Rust and TypeScript backends of Quint 0.34.0.
To generate traces from a named test, pass
`NamedTest("counter.qnt", test="roundTripTest")` and set `action_path` to the
field path where the model records the operation. `StateMismatchError` and
`DriverError` from generated traces expose `seed` and `artifact_path`. Pass
the saved ITF to `replay()` with the same driver and selectors. When saving a
failed trace, `run()` creates `artifact_dir` and any missing parent directories,
then writes the trace to its own subdirectory. Relative paths are resolved
against the caller's working directory. If creating the directory or saving the
trace fails, the original error carries the OS error in `artifact_error`.

Use enum members such as `Backend.RUST` for evaluator selection and
`DriverStage.APPLY`, `QuintStage.LOOKUP`, or `WorkspaceStage.RESERVE` to
inspect failure stages.

## Upgrade from 0.1

In 0.2, use `backend=Backend.RUST` in place of `backend="rust"`, and
`backend=Backend.TYPESCRIPT` for the TypeScript evaluator. For code that
branches on an exception's stage, compare it with the corresponding enum
member, such as `DriverStage.APPLY`. Use `stage.value` to log the string.

If your driver factory uses an outer `ExitStack` to close a harness, move
that ownership into a [driver context](#write-a-driver). Pass the context
factory as `driver_context` to `run()` or `replay()`. Each trace gets its own
harness and closes it before the next one opens.

```python
from quint_connect import Backend, Simulation, run

run(
    Simulation("counter.qnt", n_traces=10),
    driver_context=driver_context,
    quint="quint",
    backend=Backend.RUST,
    artifact_dir="_build/quint-connect",
    action_path=("op",),
    state_path=("count",),
)
```

On a driver failure during generated replay, read `DriverError.artifact_path`
and `DriverError.seed` to reproduce the failure. The original Python exception
is available as `__cause__`.

## Run from pytest

Call `run()` or `replay()` inside a test function. The calls work with
`pytest -n 2`. Each call to `run()` generates traces in its own working
directory, and several workers can read the same saved trace. If drivers write
to a database or files, have the factory allocate separate resources as needed.

With Hypothesis, use `@given` to pick an integer between 0 and `2**64 - 1`,
inclusive, and pass it to `run()` as the `seed`. Hypothesis shrinks the seed.

```python
from hypothesis import given, strategies as st
from quint_connect import Simulation, run


@given(seed=st.integers(min_value=0, max_value=2**64 - 1))
def test_counter_follows_model(seed: int) -> None:
    run(
        Simulation("examples/counter.qnt", max_steps=2),
        CounterDriver,
        quint="quint",
        seed=seed,
        action_path=("op",),
        state_path=("count",),
    )
```
