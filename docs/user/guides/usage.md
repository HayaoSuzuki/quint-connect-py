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
from quint_connect import Simulation, run

run(
    Simulation("counter.qnt", n_traces=10),
    CounterDriver,
    quint="/path/to/quint",
    seed=42,
    state_path=("count",),
)
```

The first release targets the Rust and TypeScript backends of Quint 0.34.0.
To generate traces from a named test, pass
`NamedTest("counter.qnt", test="roundTripTest")` and set `action_path` to the
field path where the model records the operation. If a generated trace reveals
a state mismatch, use the exception's `seed` and `artifact_path` to identify
the run and pass the saved trace to `replay()`.

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
