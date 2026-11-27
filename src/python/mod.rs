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

#[derive(FromPyObject)]
struct SelectionPaths {
    #[pyo3(item)]
    action_path: Vec<String>,
    #[pyo3(item)]
    state_path: Vec<String>,
}

impl From<SelectionPaths> for Selection {
    fn from(paths: SelectionPaths) -> Self {
        Self {
            action_path: paths.action_path,
            state_path: paths.state_path,
        }
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
    let selection = Selection::from(paths_selection);
    let result = py.detach(move || replay_files(&files, &selection, &mut environment));
    result.map_err(|failure| error::from_replay(py, &types, failure))
}

#[derive(FromPyObject)]
enum GenerationMode {
    Simulation {
        #[pyo3(item)]
        init: Option<String>,
        #[pyo3(item)]
        step: Option<String>,
        #[pyo3(item)]
        n_traces: u64,
        #[pyo3(item)]
        max_steps: Option<u64>,
    },
    NamedTest {
        #[pyo3(item)]
        test: String,
    },
}

#[derive(FromPyObject)]
struct RunRequest {
    #[pyo3(item)]
    spec: PathBuf,
    #[pyo3(item)]
    quint: PathBuf,
    #[pyo3(item)]
    main: Option<String>,
    #[pyo3(item)]
    max_samples: Option<u64>,
    #[pyo3(item)]
    mode: GenerationMode,
    #[pyo3(item)]
    seed: Option<u64>,
    #[pyo3(item)]
    backend: Option<String>,
    #[pyo3(item)]
    artifact_dir: Option<PathBuf>,
}

impl TryFrom<RunRequest> for Request {
    type Error = PyErr;

    fn try_from(request: RunRequest) -> PyResult<Self> {
        let mode = match request.mode {
            GenerationMode::Simulation {
                init,
                step,
                n_traces,
                max_steps,
            } => Mode::Simulation {
                init,
                step,
                traces: n_traces,
                samples: request.max_samples,
                steps: max_steps,
            },
            GenerationMode::NamedTest { test } => Mode::NamedTest {
                name: test,
                samples: request.max_samples,
            },
        };
        let backend = request
            .backend
            .as_deref()
            .map(str::parse::<Backend>)
            .transpose()
            .map_err(|()| {
                pyo3::exceptions::PyTypeError::new_err("backend must be a Backend member")
            })?;

        Ok(Self {
            model: request.spec,
            executable: request.quint,
            main: request.main,
            backend,
            mode,
            seed: request.seed,
            artifact_dir: request.artifact_dir,
        })
    }
}

#[pyfunction]
fn run(
    py: Python<'_>,
    request: RunRequest,
    context_factory: Py<PyAny>,
    paths_selection: SelectionPaths,
) -> PyResult<()> {
    let request = Request::try_from(request)?;
    let selection = Selection::from(paths_selection);
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
