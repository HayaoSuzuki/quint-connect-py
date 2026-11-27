use std::io;
use std::path::{Path, PathBuf};

use crate::itf::{Action, ItfError, Selection, TraceStep, decode_trace};
use crate::value::Value;

pub trait Driver {
    type Error;

    fn apply(&mut self, action: &Action) -> Result<(), Self::Error>;
    fn observe(&mut self) -> Result<Value, Self::Error>;
    fn finish(
        &mut self,
        _trace: &TraceFile,
        _problem: Option<&TraceProblem<Self::Error>>,
    ) -> Result<(), Self::Error> {
        Ok(())
    }
}

#[derive(Clone, Debug)]
pub struct TraceFile {
    pub path: PathBuf,
    pub display_path: PathBuf,
    pub index: usize,
}

pub fn saved_files(paths: &[PathBuf], caller: &Path) -> Vec<TraceFile> {
    paths
        .iter()
        .enumerate()
        .map(|(index, path)| TraceFile {
            path: caller.join(path),
            display_path: path.clone(),
            index,
        })
        .collect()
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum DriverStage {
    Factory,
    Apply,
    Observe,
    Exit,
}

#[derive(Debug)]
pub struct Mismatch {
    pub step_index: usize,
    pub step: TraceStep,
    pub actual: Value,
}

#[derive(Debug)]
pub enum TraceProblem<E> {
    Driver {
        step: Option<usize>,
        stage: DriverStage,
        cause: Box<E>,
    },
    Mismatch(Mismatch),
}

impl<E> TraceProblem<E> {
    fn driver(step: Option<usize>, stage: DriverStage, cause: E) -> Self {
        Self::Driver {
            step,
            stage,
            cause: Box::new(cause),
        }
    }
}

#[derive(Debug)]
pub struct FailedTrace<E> {
    pub trace: TraceFile,
    // Retain the exact bytes that were decoded and replayed.
    pub bytes: Vec<u8>,
    pub problem: TraceProblem<E>,
    pub driver_cleanup: Option<Box<E>>,
}

#[derive(Debug)]
pub enum TraceCause {
    Read(io::Error),
    Decode(&'static str),
}

#[derive(Debug)]
pub enum ReplayError<E> {
    NoInput,
    NoStates(TraceFile),
    InvalidTrace {
        trace: TraceFile,
        step: Option<usize>,
        cause: TraceCause,
    },
    FailedTrace(Box<FailedTrace<E>>),
}

#[cfg_attr(
    not(test),
    allow(dead_code, reason = "the model adapter consumes events in tests")
)]
pub enum ReplayEvent<'a> {
    Read(&'a TraceFile),
    Factory(&'a TraceFile),
    DriverCreated(&'a TraceFile),
    Apply(&'a TraceFile, usize, &'a Action),
    Observe(&'a TraceFile, usize, &'a Value),
}

pub trait ReplayEnvironment {
    type Driver: Driver;

    fn read(&mut self, trace: &TraceFile) -> io::Result<Vec<u8>>;
    fn create_driver(&mut self) -> Result<Self::Driver, <Self::Driver as Driver>::Error>;
    fn event(&mut self, _: ReplayEvent<'_>) {}
}

pub struct LocalEnvironment<F>(pub F);

impl<D: Driver, F: FnMut() -> Result<D, D::Error>> ReplayEnvironment for LocalEnvironment<F> {
    type Driver = D;

    fn read(&mut self, trace: &TraceFile) -> io::Result<Vec<u8>> {
        std::fs::read(&trace.path)
    }

    fn create_driver(&mut self) -> Result<D, D::Error> {
        (self.0)()
    }
}

type DriverErrorOf<E> = <<E as ReplayEnvironment>::Driver as Driver>::Error;

/// Reads and validates each trace, then closes its driver before advancing.
pub fn replay<E: ReplayEnvironment>(
    files: &[TraceFile],
    selection: &Selection,
    environment: &mut E,
) -> Result<(), ReplayError<DriverErrorOf<E>>> {
    if files.is_empty() {
        return Err(ReplayError::NoInput);
    }
    for trace in files {
        environment.event(ReplayEvent::Read(trace));
        let bytes = environment
            .read(trace)
            .map_err(|cause| ReplayError::InvalidTrace {
                trace: trace.clone(),
                step: None,
                cause: TraceCause::Read(cause),
            })?;
        let steps = decode_trace(&bytes, selection).map_err(|error| match error {
            ItfError::Empty => ReplayError::NoStates(trace.clone()),
            ItfError::Invalid { step, cause } => ReplayError::InvalidTrace {
                trace: trace.clone(),
                step,
                cause: TraceCause::Decode(cause),
            },
        })?;
        replay_trace(trace, steps, bytes, environment)?;
    }
    Ok(())
}

fn replay_trace<E: ReplayEnvironment>(
    trace: &TraceFile,
    steps: Vec<TraceStep>,
    bytes: Vec<u8>,
    environment: &mut E,
) -> Result<(), ReplayError<DriverErrorOf<E>>> {
    environment.event(ReplayEvent::Factory(trace));
    let (problem, driver_cleanup) = match environment.create_driver() {
        Ok(mut driver) => {
            environment.event(ReplayEvent::DriverCreated(trace));
            let result = replay_steps(trace, steps, environment, &mut driver);
            let cleanup = driver.finish(trace, result.as_ref().err());

            match (result, cleanup) {
                (Ok(()), Ok(())) => return Ok(()),
                (Ok(()), Err(cause)) => {
                    (TraceProblem::driver(None, DriverStage::Exit, cause), None)
                }
                (Err(problem), cleanup) => (problem, cleanup.err().map(Box::new)),
            }
        }
        Err(cause) => (
            TraceProblem::driver(None, DriverStage::Factory, cause),
            None,
        ),
    };
    Err(ReplayError::FailedTrace(Box::new(FailedTrace {
        trace: trace.clone(),
        bytes,
        problem,
        driver_cleanup,
    })))
}

fn replay_steps<E: ReplayEnvironment>(
    trace: &TraceFile,
    steps: Vec<TraceStep>,
    environment: &mut E,
    driver: &mut E::Driver,
) -> Result<(), TraceProblem<DriverErrorOf<E>>> {
    for (index, step) in steps.into_iter().enumerate() {
        environment.event(ReplayEvent::Apply(trace, index, &step.action));
        driver
            .apply(&step.action)
            .map_err(|cause| TraceProblem::driver(Some(index), DriverStage::Apply, cause))?;
        environment.event(ReplayEvent::Observe(trace, index, &step.expected));
        let actual = driver
            .observe()
            .map_err(|cause| TraceProblem::driver(Some(index), DriverStage::Observe, cause))?;
        if step.expected != actual {
            return Err(TraceProblem::Mismatch(Mismatch {
                step_index: index,
                step,
                actual,
            }));
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::convert::Infallible;

    const INITIAL_STATE: &str = r#"{"n":true,"mbt::actionTaken":"init","mbt::nondetPicks":{}}"#;

    struct TrueDriver;

    impl Driver for TrueDriver {
        type Error = Infallible;

        fn apply(&mut self, _: &Action) -> Result<(), Self::Error> {
            Ok(())
        }
        fn observe(&mut self) -> Result<Value, Self::Error> {
            Ok(Value::Bool(true))
        }
    }

    #[test]
    fn malformed_later_step_prevents_factory_creation() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("trace.itf.json");
        std::fs::write(
            &path,
            format!(r#"{{"vars":["n"],"states":[{INITIAL_STATE},{{"n":true}}]}}"#),
        )
        .unwrap();
        let files = saved_files(&[path], directory.path());
        let mut factories = 0;
        let mut environment = LocalEnvironment(|| {
            factories += 1;
            Ok(TrueDriver)
        });

        let error = replay(&files, &Selection::default(), &mut environment).unwrap_err();

        assert!(matches!(
            error,
            ReplayError::InvalidTrace {
                step: Some(1),
                cause: TraceCause::Decode("invalid operation"),
                ..
            }
        ));
        assert_eq!(factories, 0);
    }

    #[test]
    fn repeated_path_gets_a_fresh_driver_each_time() {
        let directory = tempfile::tempdir().unwrap();
        std::fs::write(
            directory.path().join("trace.itf.json"),
            format!(r#"{{"vars":["n"],"states":[{INITIAL_STATE}]}}"#),
        )
        .unwrap();
        let paths = [
            PathBuf::from("trace.itf.json"),
            PathBuf::from("trace.itf.json"),
        ];
        let files = saved_files(&paths, directory.path());
        let selection = Selection {
            state_path: vec!["n".into()],
            ..Selection::default()
        };
        let mut factories = 0;
        let mut environment = LocalEnvironment(|| {
            factories += 1;
            Ok(TrueDriver)
        });

        let result = replay(&files, &selection, &mut environment);

        assert!(result.is_ok(), "{result:?}");
        assert_eq!(factories, 2);
    }
}
