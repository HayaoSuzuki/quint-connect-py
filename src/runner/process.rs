use std::io::{self, Read};
use std::path::Path;
use std::process::{Child, Command, ExitStatus, Stdio};
use std::thread::{self, JoinHandle};

use crate::cli::Plan;

use super::{ChildIoError, ChildIoStage, ChildOutput, Exit};

pub struct RunningChild {
    child: Child,
    stdout: Option<JoinHandle<io::Result<Vec<u8>>>>,
    stderr: Option<JoinHandle<io::Result<Vec<u8>>>>,
    reader_start_error: Option<io::Error>,
}

impl RunningChild {
    pub(super) fn spawn(plan: &Plan, workspace: &Path) -> io::Result<Self> {
        let mut child = Command::new(&plan.executable)
            .args(&plan.arguments)
            .current_dir(workspace)
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()?;
        let stdout = child
            .stdout
            .take()
            .ok_or_else(|| io::Error::other("missing stdout pipe"))
            .and_then(drain);
        let stderr = child
            .stderr
            .take()
            .ok_or_else(|| io::Error::other("missing stderr pipe"))
            .and_then(drain);
        let (stdout, stdout_error) = split(stdout);
        let (stderr, stderr_error) = split(stderr);
        Ok(Self {
            child,
            stdout,
            stderr,
            reader_start_error: stdout_error.or(stderr_error),
        })
    }

    pub(super) fn collect(&mut self) -> Result<ChildOutput, ChildIoError> {
        let status = self.child.wait().map_err(|cause| ChildIoError {
            stage: ChildIoStage::WaitForExit,
            cause,
            exit_confirmed: false,
        })?;
        let stdout = join(self.stdout.take());
        let stderr = join(self.stderr.take());
        let failed = |cause| ChildIoError {
            stage: ChildIoStage::CollectOutput,
            cause,
            exit_confirmed: true,
        };
        if let Some(error) = self.reader_start_error.take() {
            return Err(failed(error));
        }
        Ok(ChildOutput {
            status: exit(status),
            stdout: stdout.map_err(failed)?,
            stderr: stderr.map_err(failed)?,
        })
    }

    pub(super) fn confirm_exit(&mut self) -> io::Result<()> {
        self.child
            .try_wait()?
            .map(|_| ())
            .ok_or_else(|| io::Error::other("Quint exit remains unconfirmed"))
    }
}

fn split<T>(result: io::Result<T>) -> (Option<T>, Option<io::Error>) {
    match result {
        Ok(value) => (Some(value), None),
        Err(error) => (None, Some(error)),
    }
}

fn drain(mut pipe: impl Read + Send + 'static) -> io::Result<JoinHandle<io::Result<Vec<u8>>>> {
    thread::Builder::new().spawn(move || {
        let mut bytes = Vec::new();
        pipe.read_to_end(&mut bytes)?;
        Ok(bytes)
    })
}

fn join(reader: Option<JoinHandle<io::Result<Vec<u8>>>>) -> io::Result<Vec<u8>> {
    let Some(reader) = reader else {
        return Ok(Vec::new());
    };
    reader
        .join()
        .map_err(|_| io::Error::other("process output reader failed"))?
}

fn exit(status: ExitStatus) -> Exit {
    if status.success() {
        return Exit::Success;
    }
    if let Some(code) = status.code() {
        return Exit::Code(code);
    }
    #[cfg(unix)]
    {
        use std::os::unix::process::ExitStatusExt;
        if let Some(signal) = status.signal() {
            return Exit::Signal(signal);
        }
    }
    Exit::Unknown
}
