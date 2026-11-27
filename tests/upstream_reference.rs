use quint_connect::{Config, Driver, Result, State, Step, quint_run, quint_test, switch};

#[derive(Default)]
struct Counter {
    count: i64,
}

impl State<Counter> for i64 {
    fn from_driver(driver: &Counter) -> Result<Self> {
        Ok(driver.count)
    }
}
impl Driver for Counter {
    type State = i64;

    fn config() -> Config {
        Config {
            state: &["count"],
            nondet: &["op"],
        }
    }

    fn step(&mut self, step: &Step) -> Result {
        switch!(step {
            Reset => self.count = 0,
            Add(delta: i64) => self.count += delta,
        })
    }
}

#[quint_run(
    spec = "examples/counter.qnt",
    max_steps = 2,
    max_samples = 1,
    seed = "0x2a"
)]
#[ignore = "requires Quint 0.34.0 on PATH"]
fn official_simulation_replays_the_counter() -> impl Driver {
    Counter::default()
}

#[quint_test(
    spec = "examples/counter.qnt",
    test = "roundTripTest",
    max_samples = 1,
    seed = "0x2a"
)]
#[ignore = "requires Quint 0.34.0 on PATH"]
fn official_named_test_replays_the_counter() -> impl Driver {
    Counter::default()
}
