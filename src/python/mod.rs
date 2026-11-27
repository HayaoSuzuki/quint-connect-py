mod diagnostics;
mod error;
mod value;

use std::path::PathBuf;
use std::sync::Arc;

use pyo3::prelude::*;
use pyo3::types::PyBool;

use crate::cli::{Backend, Mode, Request, TestFilter};
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
    comparison: Arc<ComparisonCallbacks>,
}

#[derive(Default, FromPyObject)]
struct ComparisonCallbacks {
    transform_expected: Option<Py<PyAny>>,
    equals: Option<Py<PyAny>>,
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

    fn compare(&mut self, expected: Value, actual: &Value) -> PyResult<Option<Value>> {
        let ComparisonCallbacks {
            transform_expected,
            equals,
        } = self.comparison.as_ref();
        if transform_expected.is_none() && equals.is_none() {
            return Ok((&expected != actual).then_some(expected));
        }
        Python::attach(|py| {
            let expected = if let Some(transform) = transform_expected {
                let selected = self.types.write(py, &expected)?;
                let transformed = transform.bind(py).call1((selected,))?;
                self.types.read(&transformed)?
            } else {
                expected
            };
            let matched = if let Some(equals) = equals {
                let expected_value = self.types.write(py, &expected)?;
                let observed = self.types.write(py, actual)?;
                equals
                    .bind(py)
                    .call1((expected_value, observed))?
                    .cast::<PyBool>()?
                    .is_true()
            } else {
                &expected == actual
            };
            Ok((!matched).then_some(expected))
        })
    }

    fn finish(self, trace: &TraceFile, problem: Option<&TraceProblem<PyErr>>) -> PyResult<()> {
        Python::attach(|py| {
            let exit = self.exit.bind(py);
            let Some(problem) = problem else {
                exit.call1((py.None(), py.None(), py.None()))?;
                return Ok(());
            };
            let exception = match problem {
                TraceProblem::Driver { cause, .. } => cause.clone_ref(py),
                TraceProblem::Mismatch { detail, presented } => presented
                    .get_or_init(|| {
                        error::mismatch_exception(py, &self.types, trace, detail)
                            .unwrap_or_else(|error| error)
                    })
                    .clone_ref(py),
            };
            if let Err(cleanup) = exit.call1((
                exception.get_type(py),
                exception.value(py),
                exception.traceback(py),
            )) && !cleanup.value(py).is(exception.value(py))
            {
                return Err(cleanup);
            }
            Ok(())
        })
    }
}

fn factory(
    context_factory: Py<PyAny>,
    types: Arc<Types>,
    comparison: ComparisonCallbacks,
) -> impl FnMut() -> PyResult<PythonDriver> + Send {
    let comparison = Arc::new(comparison);
    move || {
        Python::attach(|py| {
            let context = context_factory.bind(py).call0()?;
            let exit = context.getattr("__exit__")?.unbind();
            let object = context.call_method0("__enter__")?.unbind();
            Ok(PythonDriver {
                object,
                exit,
                types: Arc::clone(&types),
                comparison: Arc::clone(&comparison),
            })
        })
    }
}

#[derive(FromPyObject)]
struct ReplayOptions {
    #[pyo3(item)]
    action_path: Vec<String>,
    #[pyo3(item)]
    state_path: Vec<String>,
    #[pyo3(item)]
    comparison: Option<ComparisonCallbacks>,
    #[pyo3(item)]
    log_replay: bool,
    #[pyo3(item)]
    log_steps: bool,
}

impl ReplayOptions {
    fn prepare(
        self,
        context_factory: Py<PyAny>,
        types: Arc<Types>,
    ) -> (
        Selection,
        LocalEnvironment<impl FnMut() -> PyResult<PythonDriver> + Send + use<>>,
    ) {
        let selection = Selection {
            action_path: self.action_path,
            state_path: self.comparison.as_ref().map(|_| self.state_path),
        };
        let reporter = self
            .log_replay
            .then(|| diagnostics::reporter(Arc::clone(&types), self.log_steps));
        let factory = factory(context_factory, types, self.comparison.unwrap_or_default());
        (selection, LocalEnvironment::new(factory, reporter))
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
    options: ReplayOptions,
) -> PyResult<()> {
    let types = Arc::new(Types::load(py)?);
    let (selection, mut environment) = options.prepare(context_factory, types);
    let caller = std::env::current_dir()?;
    let files = saved_files(&paths, &caller);
    let result = py.detach(move || replay_files(&files, &selection, &mut environment));
    result.map_err(|failure| error::from_replay(py, failure))
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
    PatternTest {
        #[pyo3(item)]
        pattern: String,
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
                filter: TestFilter::Name(test),
                samples: request.max_samples,
            },
            GenerationMode::PatternTest { pattern } => Mode::NamedTest {
                filter: TestFilter::Pattern(pattern),
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
    options: ReplayOptions,
) -> PyResult<()> {
    let request = Request::try_from(request)?;
    let types = Arc::new(Types::load(py)?);
    let (selection, mut environment) = options.prepare(context_factory, types);
    let result = py.detach(move || run_model(&request, &selection, &mut environment));
    result.map_err(|failure| error::from_run(py, *failure))
}

#[pymodule(name = "_native")]
fn native(module: &Bound<'_, PyModule>) -> PyResult<()> {
    module.add_function(wrap_pyfunction!(replay, module)?)?;
    module.add_function(wrap_pyfunction!(run, module)?)?;
    error::register(module)
}
