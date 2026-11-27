mod error;
mod value;

use std::path::PathBuf;
use std::sync::Arc;

use pyo3::prelude::*;

use crate::cli::{Backend, Mode, Request};
use crate::itf::{Action, Selection};
use crate::replay::{
    Driver, LocalEnvironment, TraceFile, TraceProblem, replay as replay_files, saved_files,
};
use crate::runner::run as run_model;
use crate::value::Value;

use self::value::Types;

struct PythonDriver {
    object: Py<PyAny>,
    exit: Py<PyAny>,
    types: Arc<Types>,
}

impl Driver for PythonDriver {
    type Error = PyErr;

    fn apply(&mut self, action: &Action) -> PyResult<()> {
        Python::attach(|py| {
            let action = self.types.action(py, action)?;
            self.object.bind(py).call_method1("step", (action,))?;
            Ok(())
        })
    }

    fn observe(&mut self) -> PyResult<Value> {
        Python::attach(|py| {
            let observed = self.object.bind(py).call_method0("observe")?;
            self.types.read(&observed)
        })
    }

    fn finish(self, trace: &TraceFile, problem: Option<&TraceProblem<PyErr>>) -> PyResult<()> {
        Python::attach(|py| {
            let exit = self.exit.bind(py);
            match problem {
                None => exit.call1((py.None(), py.None(), py.None()))?,
                Some(problem) => {
                    let exception = match problem {
                        TraceProblem::Driver { cause, .. } => cause.clone_ref(py),
                        TraceProblem::Mismatch(mismatch) => {
                            error::mismatch_exception(py, &self.types, trace, mismatch)
                                .unwrap_or_else(|error| error)
                        }
                    };
                    exit.call1((
                        exception.get_type(py),
                        exception.value(py),
                        exception.traceback(py),
                    ))?
                }
            };
            Ok(())
        })
    }
}

fn factory(
    context_factory: Py<PyAny>,
    types: Arc<Types>,
) -> impl FnMut() -> PyResult<PythonDriver> + Send {
    move || {
        Python::attach(|py| {
            let context = context_factory.bind(py).call0()?;
            let exit = context.getattr("__exit__")?.unbind();
            let object = context.call_method0("__enter__")?.unbind();
            Ok(PythonDriver {
                object,
                exit,
                types: Arc::clone(&types),
            })
        })
    }
}

type SelectionPaths = (Vec<String>, Vec<String>);

fn selection((action_path, state_path): SelectionPaths) -> Selection {
    Selection {
        action_path,
        state_path,
    }
}

#[allow(
    clippy::needless_pass_by_value,
    reason = "PyO3 extracts the owned path sequence"
)]
#[pyfunction]
fn replay(
    py: Python<'_>,
    paths: Vec<PathBuf>,
    context_factory: Py<PyAny>,
    paths_selection: SelectionPaths,
) -> PyResult<()> {
    let types = Arc::new(Types::load(py)?);
    let mut environment = LocalEnvironment(factory(context_factory, Arc::clone(&types)));
    let caller = std::env::current_dir()?;
    let files = saved_files(&paths, &caller);
    let selection = selection(paths_selection);
    let result = py.detach(move || replay_files(&files, &selection, &mut environment));
    result.map_err(|failure| error::from_replay(py, &types, failure))
}

type Common = (PathBuf, Option<String>, Option<u64>);
type Simulation = (Option<String>, Option<String>, u64, Option<u64>);
type Execution = (PathBuf, Option<u64>, Option<String>, Option<PathBuf>);

#[pyfunction]
fn run(
    py: Python<'_>,
    common: Common,
    named_test: Option<String>,
    simulation: Option<Simulation>,
    context_factory: Py<PyAny>,
    execution: Execution,
    paths_selection: SelectionPaths,
) -> PyResult<()> {
    let (model, main, samples) = common;
    let (executable, seed, backend, artifact_dir) = execution;
    let mode = match (named_test, simulation) {
        (Some(name), None) => Mode::NamedTest { name, samples },
        (None, Some((init, step, traces, steps))) => Mode::Simulation {
            init,
            step,
            traces,
            samples,
            steps,
        },
        _ => {
            return Err(pyo3::exceptions::PyValueError::new_err(
                "expected one Quint generation mode",
            ));
        }
    };
    let backend = backend
        .as_deref()
        .map(str::parse::<Backend>)
        .transpose()
        .map_err(|()| pyo3::exceptions::PyTypeError::new_err("backend must be a Backend member"))?;
    let request = Request {
        model,
        executable,
        main,
        backend,
        mode,
        seed,
        artifact_dir,
    };
    let selection = selection(paths_selection);
    let types = Arc::new(Types::load(py)?);
    let mut environment = LocalEnvironment(factory(context_factory, Arc::clone(&types)));
    let result = py.detach(move || run_model(&request, &selection, &mut environment));
    result.map_err(|failure| error::from_run(py, &types, *failure))
}

#[pymodule(name = "_native")]
fn native(module: &Bound<'_, PyModule>) -> PyResult<()> {
    module.add_function(wrap_pyfunction!(replay, module)?)?;
    module.add_function(wrap_pyfunction!(run, module)?)?;
    error::register(module)
}
