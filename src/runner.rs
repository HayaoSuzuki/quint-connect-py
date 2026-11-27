#[cfg(feature = "python")]
mod process;

use std::ffi::OsStr;
use std::io;
use std::path::{Path, PathBuf};

use crate::cli::{self, InvalidRequest, LookupError, Plan, Request};
use crate::itf::Selection;
use crate::replay::{Driver, ReplayEnvironment, ReplayError, TraceFile, replay};

#[cfg(feature = "python")]
use self::process::RunningChild;
#[cfg(feature = "python")]
use crate::replay::LocalEnvironment;

pub type DriverErrorOf<E> = <<E as ReplayEnvironment>::Driver as Driver>::Error;

#[derive(Debug)]
pub struct RunError<E> {
    pub seed: Option<u64>,
    pub failure: Failure<E>,
    pub artifact: Option<Result<PathBuf, ArtifactError>>,
    pub cleanup: Option<Cleanup>,
}

#[derive(Debug)]
#[cfg_attr(
    not(feature = "python"),
    allow(dead_code, reason = "the Python boundary reads full diagnostics")
)]
pub enum Failure<E> {
    Request(InvalidRequest),
    #[cfg(feature = "python")]
    RandomSeed(getrandom::Error),
    #[cfg(feature = "python")]
    CurrentDirectory(io::Error),
    Lookup(LookupError),
    Reserve(io::Error),
    Spawn(io::Error),
    Exit {
        status: Exit,
        stdout: Vec<u8>,
        stderr: Vec<u8>,
    },
    ChildIo(ChildIoError),
    Listing {
        workspace: PathBuf,
        cause: io::Error,
    },
    EmptyOutput,
    Incomplete {
        requested: u64,
        produced: usize,
    },
    Replay(ReplayError<E>),
    Cleanup {
        workspace: PathBuf,
        cause: io::Error,
    },
}

#[derive(Debug)]
pub enum Cleanup {
    Failed(io::Error),
    Deferred {
        workspace: PathBuf,
        cause: io::Error,
    },
}

#[derive(Debug)]
pub enum ArtifactError {
    Prepare(io::Error),
    Reserve {
        directory: PathBuf,
        cause: io::Error,
    },
    Save(io::Error),
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Exit {
    Success,
    Code(i32),
    Signal(i32),
    #[cfg(feature = "python")]
    Unknown,
}

pub struct ChildOutput {
    pub status: Exit,
    pub stdout: Vec<u8>,
    pub stderr: Vec<u8>,
}

#[derive(Clone, Copy, Debug)]
pub enum ChildIoStage {
    WaitForExit,
    CollectOutput,
}

#[derive(Debug)]
pub struct ChildIoError {
    pub stage: ChildIoStage,
    pub cause: io::Error,
    pub exit_confirmed: bool,
}

#[allow(
    dead_code,
    reason = "structured events are intended for conformance tests"
)]
pub enum RunEvent<'a> {
    Prepared(&'a Plan),
    Reserved(&'a Path),
    ProcessStarted,
    ProcessExitedSuccessfully,
    ProcessIoFailed(&'a ChildIoError),
    ExitConfirmed,
    CleanupDeferred(&'a io::Error),
    Listed(&'a [TraceFile]),
    ArtifactTried(&'a Path, &'a io::Result<()>),
    ArtifactSaved(&'a TraceFile, &'a Result<PathBuf, ArtifactError>),
    CleanupAttempted(&'a io::Result<()>),
}

/// Process and filesystem effects used by the runner. The runner owns their ordering.
pub trait RunEnvironment: ReplayEnvironment {
    type Child;

    fn reserve(&mut self) -> io::Result<PathBuf>;
    fn spawn(&mut self, plan: &Plan, workspace: &Path) -> io::Result<Self::Child>;
    fn wait(&mut self, child: &mut Self::Child) -> Result<ChildOutput, ChildIoError>;
    fn confirm_exit(&mut self, child: &mut Self::Child) -> io::Result<()>;
    fn list(&mut self, workspace: &Path) -> io::Result<Vec<PathBuf>>;
    fn artifact_candidates(&mut self, root: &Path) -> io::Result<Vec<PathBuf>>;
    fn reserve_artifact(&mut self, directory: &Path) -> io::Result<()>;
    fn publish(&mut self, directory: &Path, name: &OsStr, bytes: &[u8]) -> io::Result<PathBuf>;
    fn cleanup(&mut self, workspace: &Path) -> io::Result<()>;
    fn run_event(&mut self, _: RunEvent<'_>) {}
}

impl<E> RunError<E> {
    fn new(seed: Option<u64>, failure: Failure<E>) -> Box<Self> {
        Box::new(Self {
            seed,
            failure,
            artifact: None,
            cleanup: None,
        })
    }
}

#[cfg(feature = "python")]
pub fn run<E: RunEnvironment>(
    request: &Request,
    selection: &Selection,
    environment: &mut E,
) -> Result<(), Box<RunError<DriverErrorOf<E>>>> {
    let caller = std::env::current_dir()
        .map_err(|cause| RunError::new(None, Failure::CurrentDirectory(cause)))?;
    let drawn_seed = match request.seed {
        Some(seed) => seed,
        None => {
            getrandom::u64().map_err(|cause| RunError::new(None, Failure::RandomSeed(cause)))?
        }
    };
    run_from(
        request,
        selection,
        &caller,
        std::env::var_os("PATH").as_deref(),
        drawn_seed,
        environment,
    )
}

pub fn run_from<E: RunEnvironment>(
    request: &Request,
    selection: &Selection,
    caller: &Path,
    paths: Option<&OsStr>,
    drawn_seed: u64,
    environment: &mut E,
) -> Result<(), Box<RunError<DriverErrorOf<E>>>> {
    let mut plan = cli::plan(request, selection, caller, drawn_seed)
        .map_err(|error| RunError::new(None, Failure::Request(error)))?;
    let seed = Some(plan.seed);
    plan.executable = cli::resolve_executable(&plan.executable, caller, paths)
        .map_err(|error| RunError::new(seed, Failure::Lookup(error)))?;
    environment.run_event(RunEvent::Prepared(&plan));
    let root = request.artifact_dir.as_ref().map_or_else(
        || caller.join(std::env::temp_dir()),
        |path| caller.join(path),
    );
    let workspace = environment
        .reserve()
        .map_err(|error| RunError::new(seed, Failure::Reserve(error)))?;
    environment.run_event(RunEvent::Reserved(&workspace));

    let mut result = run_in(&plan, &workspace, selection, environment);
    if let Err(error) = &mut result {
        if matches!(error.cleanup, Some(Cleanup::Deferred { .. })) {
            return result;
        }
        if let Failure::Replay(ReplayError::Mismatch(mismatch)) = &error.failure {
            let saved = save_evidence(environment, &root, &mismatch.trace, &mismatch.bytes);
            environment.run_event(RunEvent::ArtifactSaved(&mismatch.trace, &saved));
            error.artifact = Some(saved);
        }
    }
    let cleanup = environment.cleanup(&workspace);
    environment.run_event(RunEvent::CleanupAttempted(&cleanup));
    if let Err(cause) = cleanup {
        match &mut result {
            Ok(()) => return Err(RunError::new(seed, Failure::Cleanup { workspace, cause })),
            Err(error) => error.cleanup = Some(Cleanup::Failed(cause)),
        }
    }
    result
}

fn run_in<E: RunEnvironment>(
    plan: &Plan,
    workspace: &Path,
    selection: &Selection,
    environment: &mut E,
) -> Result<(), Box<RunError<DriverErrorOf<E>>>> {
    let failure = |kind| RunError::new(Some(plan.seed), kind);
    let mut child = environment
        .spawn(plan, workspace)
        .map_err(|cause| failure(Failure::Spawn(cause)))?;
    environment.run_event(RunEvent::ProcessStarted);
    let output = match environment.wait(&mut child) {
        Ok(output) => output,
        Err(problem) => {
            environment.run_event(RunEvent::ProcessIoFailed(&problem));
            let confirmed = problem.exit_confirmed;
            let mut error = failure(Failure::ChildIo(problem));
            if !confirmed {
                match environment.confirm_exit(&mut child) {
                    Ok(()) => environment.run_event(RunEvent::ExitConfirmed),
                    Err(cause) => {
                        environment.run_event(RunEvent::CleanupDeferred(&cause));
                        error.cleanup = Some(Cleanup::Deferred {
                            workspace: workspace.to_owned(),
                            cause,
                        });
                    }
                }
            }
            return Err(error);
        }
    };
    if output.status != Exit::Success {
        return Err(failure(Failure::Exit {
            status: output.status,
            stdout: output.stdout,
            stderr: output.stderr,
        }));
    }
    environment.run_event(RunEvent::ProcessExitedSuccessfully);
    let files = environment.list(workspace).map_err(|cause| {
        failure(Failure::Listing {
            workspace: workspace.to_owned(),
            cause,
        })
    })?;
    let mut sequenced: Vec<_> = files
        .into_iter()
        .filter_map(|path| {
            let sequence = path.file_name().and_then(cli::output_sequence)?.to_owned();
            Some((sequence, path))
        })
        .collect();
    sequenced.sort_unstable_by(|(a, _), (b, _)| a.len().cmp(&b.len()).then_with(|| a.cmp(b)));
    let traces = sequenced
        .into_iter()
        .enumerate()
        .map(|(index, (_, path))| TraceFile {
            display_path: path.clone(),
            path,
            index,
        })
        .collect::<Vec<_>>();
    environment.run_event(RunEvent::Listed(&traces));
    if traces.is_empty() {
        return Err(failure(Failure::EmptyOutput));
    }
    if let Some(requested) = plan.trace_count
        && (traces.len() as u64) < requested
    {
        return Err(failure(Failure::Incomplete {
            requested,
            produced: traces.len(),
        }));
    }
    replay(&traces, selection, environment).map_err(|error| failure(Failure::Replay(error)))
}

fn save_evidence<E: RunEnvironment>(
    environment: &mut E,
    root: &Path,
    trace: &TraceFile,
    bytes: &[u8],
) -> Result<PathBuf, ArtifactError> {
    let name = trace.path.file_name().ok_or_else(|| {
        ArtifactError::Save(io::Error::new(
            io::ErrorKind::InvalidInput,
            "trace path has no name",
        ))
    })?;
    let candidates = environment
        .artifact_candidates(root)
        .map_err(ArtifactError::Prepare)?;
    let mut collision = None;
    for directory in candidates {
        let reservation = environment.reserve_artifact(&directory);
        environment.run_event(RunEvent::ArtifactTried(&directory, &reservation));
        match reservation {
            Ok(()) => {
                return environment
                    .publish(&directory, name, bytes)
                    .map_err(ArtifactError::Save);
            }
            Err(cause) if cause.kind() == io::ErrorKind::AlreadyExists => {
                collision = Some(ArtifactError::Reserve { directory, cause });
            }
            Err(cause) => return Err(ArtifactError::Reserve { directory, cause }),
        }
    }
    Err(collision
        .unwrap_or_else(|| ArtifactError::Prepare(io::Error::other("no artifact candidates"))))
}

#[cfg(feature = "python")]
impl<D: Driver, F: FnMut() -> Result<D, D::Error>> RunEnvironment for LocalEnvironment<F> {
    type Child = RunningChild;

    fn reserve(&mut self) -> io::Result<PathBuf> {
        Ok(tempfile::Builder::new()
            .prefix("quint-work-")
            .tempdir()?
            .keep())
    }

    fn spawn(&mut self, plan: &Plan, workspace: &Path) -> io::Result<RunningChild> {
        RunningChild::spawn(plan, workspace)
    }

    fn wait(&mut self, child: &mut RunningChild) -> Result<ChildOutput, ChildIoError> {
        child.collect()
    }

    fn confirm_exit(&mut self, child: &mut RunningChild) -> io::Result<()> {
        child.confirm_exit()
    }

    fn list(&mut self, workspace: &Path) -> io::Result<Vec<PathBuf>> {
        let mut files = Vec::new();
        for entry in std::fs::read_dir(workspace)? {
            let entry = entry?;
            if entry.file_type()?.is_file() {
                files.push(entry.path());
            }
        }
        Ok(files)
    }

    fn artifact_candidates(&mut self, root: &Path) -> io::Result<Vec<PathBuf>> {
        let nonce = getrandom::u64().map_err(io::Error::other)?;
        Ok((0..16)
            .map(|index| root.join(format!("quint-artifact-{nonce:016x}-{index}")))
            .collect())
    }

    fn reserve_artifact(&mut self, directory: &Path) -> io::Result<()> {
        std::fs::create_dir(directory)
    }

    fn publish(&mut self, directory: &Path, name: &OsStr, bytes: &[u8]) -> io::Result<PathBuf> {
        use std::io::Write;
        let result = (|| {
            let mut staged = tempfile::NamedTempFile::new_in(directory)?;
            staged.write_all(bytes)?;
            staged.flush()?;
            let destination = directory.join(name);
            staged.persist(&destination).map_err(|error| error.error)?;
            Ok(destination)
        })();
        if result.is_err() {
            let _ = std::fs::remove_dir(directory);
        }
        result
    }

    fn cleanup(&mut self, workspace: &Path) -> io::Result<()> {
        std::fs::remove_dir_all(workspace)
    }
}
