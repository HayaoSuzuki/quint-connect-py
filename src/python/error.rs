use pyo3::exceptions::{PyAssertionError, PyException, PyValueError};
use pyo3::prelude::*;
use pyo3::types::PyBytes;

use crate::cli::InvalidRequest;
use crate::replay::{DriverStage, ReplayError, TraceCause, TraceFile};
use crate::runner::{ArtifactError, ChildIoStage, Cleanup, Exit, Failure, RunError};

use super::value::Types;

pyo3::create_exception!(quint_connect, InvalidTraceError, PyException);
pyo3::create_exception!(quint_connect, EmptyTraceError, PyException);
pyo3::create_exception!(quint_connect, DriverError, PyException);
pyo3::create_exception!(quint_connect, StateMismatchError, PyAssertionError);
pyo3::create_exception!(quint_connect, QuintError, PyException);
pyo3::create_exception!(quint_connect, WorkspaceError, PyException);
pyo3::create_exception!(quint_connect, IncompleteGenerationError, PyException);

pub(super) fn register(module: &Bound<'_, PyModule>) -> PyResult<()> {
    let py = module.py();
    module.add("InvalidTraceError", py.get_type::<InvalidTraceError>())?;
    module.add("EmptyTraceError", py.get_type::<EmptyTraceError>())?;
    module.add("DriverError", py.get_type::<DriverError>())?;
    module.add("StateMismatchError", py.get_type::<StateMismatchError>())?;
    module.add("QuintError", py.get_type::<QuintError>())?;
    module.add("WorkspaceError", py.get_type::<WorkspaceError>())?;
    module.add(
        "IncompleteGenerationError",
        py.get_type::<IncompleteGenerationError>(),
    )
}

fn trace_attributes(
    error: &PyErr,
    py: Python<'_>,
    trace: &TraceFile,
    step: Option<usize>,
) -> PyResult<()> {
    let value = error.value(py);
    value.setattr("trace_path", trace.display_path.as_path())?;
    value.setattr("trace_index", trace.index)?;
    value.setattr("step_index", step)
}

fn empty_trace(
    py: Python<'_>,
    message: &'static str,
    trace: Option<&TraceFile>,
) -> PyResult<PyErr> {
    let error = EmptyTraceError::new_err(message);
    if let Some(trace) = trace {
        trace_attributes(&error, py, trace, None)?;
    } else {
        let value = error.value(py);
        value.setattr("trace_path", py.None())?;
        value.setattr("trace_index", py.None())?;
        value.setattr("step_index", py.None())?;
    }
    Ok(error)
}

pub(super) fn from_replay(py: Python<'_>, types: &Types, failure: ReplayError<PyErr>) -> PyErr {
    replay_exception(py, types, failure).unwrap_or_else(|error| error)
}

fn replay_exception(py: Python<'_>, types: &Types, failure: ReplayError<PyErr>) -> PyResult<PyErr> {
    let error = match failure {
        ReplayError::NoInput => empty_trace(py, "no input trace paths", None)?,
        ReplayError::NoStates(trace) => empty_trace(py, "ITF trace has no states", Some(&trace))?,
        ReplayError::InvalidTrace { trace, step, cause } => {
            let (message, source) = match cause {
                TraceCause::Read(cause) => (cause.to_string(), Some(cause.into())),
                TraceCause::Decode(cause) => (cause.to_owned(), None),
            };
            let error =
                InvalidTraceError::new_err(format!("{}: {message}", trace.display_path.display()));
            trace_attributes(&error, py, &trace, step)?;
            error.value(py).setattr("reason", message)?;
            error.set_cause(py, source);
            error
        }
        ReplayError::Driver {
            trace,
            step,
            stage,
            cause,
        } => {
            let stage = match stage {
                DriverStage::Factory => "factory",
                DriverStage::Apply => "apply",
                DriverStage::Observe => "observe",
            };
            let error = DriverError::new_err(format!("driver {stage} failed"));
            trace_attributes(&error, py, &trace, step)?;
            error.value(py).setattr("stage", stage)?;
            error.set_cause(py, Some(*cause));
            error
        }
        ReplayError::Mismatch(mismatch) => {
            let error = StateMismatchError::new_err(format!(
                "{}: state differs at step {}",
                mismatch.trace.display_path.display(),
                mismatch.step_index
            ));
            trace_attributes(&error, py, &mismatch.trace, Some(mismatch.step_index))?;
            let value = error.value(py);
            value.setattr("action", types.action(py, &mismatch.step.action)?)?;
            value.setattr("expected", types.write(py, &mismatch.step.expected)?)?;
            value.setattr("actual", types.write(py, &mismatch.actual)?)?;
            value.setattr("seed", py.None())?;
            value.setattr("artifact_path", py.None())?;
            value.setattr("artifact_error", py.None())?;
            value.setattr("artifact_candidate", py.None())?;
            value.setattr("cleanup_error", py.None())?;
            value.setattr("cleanup_deferred", false)?;
            value.setattr("workspace", py.None())?;
            error
        }
    };
    Ok(error)
}

pub(super) fn from_run(py: Python<'_>, types: &Types, failure: RunError<PyErr>) -> PyErr {
    run_exception(py, types, failure).unwrap_or_else(|error| error)
}

fn io_exception(
    py: Python<'_>,
    error: PyErr,
    stage: &'static str,
    cause: std::io::Error,
) -> PyResult<PyErr> {
    error.value(py).setattr("stage", stage)?;
    error.set_cause(py, Some(cause.into()));
    Ok(error)
}

#[allow(
    clippy::too_many_lines,
    reason = "one exhaustive match keeps failure-to-exception mapping together"
)]
fn primary_error(py: Python<'_>, types: &Types, failure: Failure<PyErr>) -> PyResult<PyErr> {
    let error = match failure {
        Failure::Request(request) => {
            return Ok(PyValueError::new_err(match request {
                InvalidRequest::TraceCount => "n_traces must be in 1..=2**53-1",
                InvalidRequest::SampleLimit => {
                    "max_samples outside the allowed range for this mode"
                }
                InvalidRequest::StepLimit => "max_steps must be in 0..=2**53-1",
                InvalidRequest::ActionPath => "named tests require action_path",
            }));
        }
        Failure::RandomSeed(cause) => {
            WorkspaceError::new_err(format!("could not draw a seed: {cause}"))
        }
        Failure::CurrentDirectory(cause) => io_exception(
            py,
            WorkspaceError::new_err("could not read caller directory"),
            "caller_directory",
            cause,
        )?,
        Failure::Lookup(lookup) => {
            let error = QuintError::new_err(format!(
                "could not select Quint executable: {}",
                lookup.path.display()
            ));
            error
                .value(py)
                .setattr("executable", lookup.path.as_path())?;
            io_exception(py, error, "lookup", lookup.cause)?
        }
        Failure::Reserve(cause) => io_exception(
            py,
            WorkspaceError::new_err("could not reserve workspace"),
            "reserve",
            cause,
        )?,
        Failure::Spawn(cause) => io_exception(
            py,
            QuintError::new_err("could not spawn Quint"),
            "spawn",
            cause,
        )?,
        Failure::Exit {
            status,
            stdout,
            stderr,
        } => {
            let error = QuintError::new_err("Quint exited unsuccessfully");
            let value = error.value(py);
            let (code, signal) = match status {
                Exit::Code(code) => (Some(code), None),
                Exit::Signal(signal) => (None, Some(signal)),
                _ => (None, None),
            };
            value.setattr("stage", "exit")?;
            value.setattr("exit_code", code)?;
            value.setattr("signal", signal)?;
            value.setattr("stdout", PyBytes::new(py, &stdout))?;
            value.setattr("stderr", PyBytes::new(py, &stderr))?;
            error
        }
        Failure::ChildIo(problem) => {
            let stage = match problem.stage {
                ChildIoStage::WaitForExit => "wait_for_exit",
                ChildIoStage::CollectOutput => "collect_output",
            };
            io_exception(
                py,
                QuintError::new_err(format!("Quint {stage} failed")),
                stage,
                problem.cause,
            )?
        }
        Failure::Listing { workspace, cause } => {
            let error = WorkspaceError::new_err("could not list workspace");
            error.value(py).setattr("workspace", workspace.as_path())?;
            io_exception(py, error, "listing", cause)?
        }
        Failure::EmptyOutput => empty_trace(py, "Quint generated no ITF traces", None)?,
        Failure::Incomplete {
            requested,
            produced,
        } => {
            let error = IncompleteGenerationError::new_err(format!(
                "Quint generated {produced} of {requested} traces"
            ));
            error.value(py).setattr("requested", requested)?;
            error.value(py).setattr("produced", produced)?;
            error
        }
        Failure::Replay(failure) => replay_exception(py, types, failure)?,
        Failure::Cleanup { workspace, cause } => {
            let error = WorkspaceError::new_err("could not remove workspace");
            error.value(py).setattr("workspace", workspace.as_path())?;
            io_exception(py, error, "cleanup", cause)?
        }
    };
    Ok(error)
}

fn run_exception(py: Python<'_>, types: &Types, result: RunError<PyErr>) -> PyResult<PyErr> {
    let error = primary_error(py, types, result.failure)?;
    let value = error.value(py);
    value.setattr("seed", result.seed)?;
    value.setattr("cleanup_error", py.None())?;
    value.setattr("cleanup_deferred", false)?;
    if !value.hasattr("workspace")? {
        value.setattr("workspace", py.None())?;
    }
    if error.is_instance_of::<QuintError>(py) {
        if !value.hasattr("executable")? {
            value.setattr("executable", py.None())?;
        }
        if !value.hasattr("stdout")? {
            value.setattr("stdout", PyBytes::new(py, b""))?;
            value.setattr("stderr", PyBytes::new(py, b""))?;
            value.setattr("exit_code", py.None())?;
            value.setattr("signal", py.None())?;
        }
    }
    if let Some(artifact) = result.artifact {
        match artifact {
            Ok(path) => value.setattr("artifact_path", path.as_path())?,
            Err(problem) => {
                let cause = match problem {
                    ArtifactError::Prepare(cause) | ArtifactError::Save(cause) => cause,
                    ArtifactError::Reserve { directory, cause } => {
                        value.setattr("artifact_candidate", directory.as_path())?;
                        cause
                    }
                };
                value.setattr("artifact_error", PyErr::from(cause).into_value(py))?;
            }
        }
    }
    if let Some(cleanup) = result.cleanup {
        match cleanup {
            Cleanup::Failed(cause) => {
                value.setattr("cleanup_error", PyErr::from(cause).into_value(py))?;
            }
            Cleanup::Deferred { workspace, cause } => {
                value.setattr("workspace", workspace.as_path())?;
                value.setattr("cleanup_deferred", true)?;
                value.setattr("cleanup_error", PyErr::from(cause).into_value(py))?;
            }
        }
    }
    Ok(error)
}
