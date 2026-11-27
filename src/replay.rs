use std::io;
use std::path::{Path, PathBuf};

use crate::itf::{Action, ItfError, Selection, TraceStep, decode_trace};
use crate::value::Value;

pub trait Driver {
    type Error;

    fn apply(&mut self, action: &Action) -> Result<(), Self::Error>;
    fn observe(&mut self) -> Result<Value, Self::Error>;
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
}

#[derive(Debug)]
pub struct Mismatch {
    pub trace: TraceFile,
    pub step_index: usize,
    pub step: TraceStep,
    pub actual: Value,
    // The bytes that were decoded and replayed, retained for evidence.
    pub bytes: Vec<u8>,
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
    Driver {
        trace: TraceFile,
        step: Option<usize>,
        stage: DriverStage,
        cause: Box<E>,
    },
    Mismatch(Box<Mismatch>),
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

/// Reads and validates one trace at a time and retains the bytes of the first mismatch.
pub fn replay<E: ReplayEnvironment>(
    files: &[TraceFile],
    selection: &Selection,
    environment: &mut E,
) -> Result<(), ReplayError<<E::Driver as Driver>::Error>> {
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
        let driver_error = |step, stage, cause| ReplayError::Driver {
            trace: trace.clone(),
            step,
            stage,
            cause: Box::new(cause),
        };
        environment.event(ReplayEvent::Factory(trace));
        let mut driver = environment
            .create_driver()
            .map_err(|cause| driver_error(None, DriverStage::Factory, cause))?;
        environment.event(ReplayEvent::DriverCreated(trace));
        for (index, step) in steps.into_iter().enumerate() {
            environment.event(ReplayEvent::Apply(trace, index, &step.action));
            driver
                .apply(&step.action)
                .map_err(|cause| driver_error(Some(index), DriverStage::Apply, cause))?;
            environment.event(ReplayEvent::Observe(trace, index, &step.expected));
            let actual = driver
                .observe()
                .map_err(|cause| driver_error(Some(index), DriverStage::Observe, cause))?;
            if step.expected != actual {
                return Err(ReplayError::Mismatch(Box::new(Mismatch {
                    trace: trace.clone(),
                    step_index: index,
                    step,
                    actual,
                    bytes,
                })));
            }
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
