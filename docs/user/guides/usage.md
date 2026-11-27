# Generate and replay Quint traces

## Install with uv

Create a virtual environment with CPython 3.14 or 3.15 and install the package.

```sh
uv venv --python 3.14
uv pip install quint-connect-py
```

Import `quint_connect` in that environment. In an existing uv project whose
supported Python versions are within the package's range, use
`uv add --dev quint-connect-py` to add it as a test dependency.

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

The first release targets the Rust and TypeScript backends of Quint 0.34.0.
To generate traces from a named test, pass
`NamedTest("counter.qnt", test="roundTripTest")` and set `action_path` to the
field path where the model records the operation. `StateMismatchError` and
`DriverError` from generated traces expose `seed` and `artifact_path`. Pass
the saved ITF to `replay()` with the same driver and selectors. When
specifying `artifact_dir`, create the parent directory before calling
`run()`. If saving fails, inspect `artifact_error`.

Use enum members such as `Backend.RUST` for evaluator selection and
`DriverStage.APPLY`, `QuintStage.LOOKUP`, or `WorkspaceStage.RESERVE` to
inspect failure stages.

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
