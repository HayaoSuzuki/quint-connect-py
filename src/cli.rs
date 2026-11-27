use std::ffi::{OsStr, OsString};
use std::io;
use std::path::{Path, PathBuf};
use std::str::FromStr;

use crate::itf::Selection;

pub const LIMIT: u64 = (1 << 53) - 1;

#[derive(Clone, Copy)]
pub enum Backend {
    Rust,
    TypeScript,
}

impl Backend {
    const fn argument(self) -> &'static str {
        match self {
            Self::Rust => "rust",
            Self::TypeScript => "typescript",
        }
    }
}

impl FromStr for Backend {
    type Err = ();

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        match value {
            "rust" => Ok(Self::Rust),
            "typescript" => Ok(Self::TypeScript),
            _ => Err(()),
        }
    }
}

pub enum Mode {
    Simulation {
        init: Option<String>,
        step: Option<String>,
        traces: u64,
        samples: Option<u64>,
        steps: Option<u64>,
    },
    NamedTest {
        name: String,
        samples: Option<u64>,
    },
}

pub struct Request {
    pub model: PathBuf,
    pub executable: PathBuf,
    pub main: Option<String>,
    pub backend: Option<Backend>,
    pub mode: Mode,
    pub seed: Option<u64>,
    pub artifact_dir: Option<PathBuf>,
}

#[derive(Debug, PartialEq, Eq)]
pub enum InvalidRequest {
    TraceCount,
    SampleLimit,
    StepLimit,
    ActionPath,
}

#[derive(Debug)]
pub struct Plan {
    pub executable: PathBuf,
    pub arguments: Vec<OsString>,
    pub trace_count: Option<u64>,
    pub seed: u64,
}

/// Validate the request and render each option as one OS argument.
pub fn plan(
    request: &Request,
    selection: &Selection,
    caller: &Path,
    drawn_seed: u64,
) -> Result<Plan, InvalidRequest> {
    let seed = request.seed.unwrap_or(drawn_seed);
    let model = caller.join(&request.model).into_os_string();
    let executable = if bare(&request.executable) {
        request.executable.clone()
    } else {
        caller.join(&request.executable)
    };
    let mut common = vec![
        OsString::from("--out-itf=trace_{seq}.itf.json"),
        format!("--seed={seed}").into(),
    ];
    optional_argument(&mut common, "--main", request.main.as_deref());
    optional_argument(
        &mut common,
        "--backend",
        request.backend.map(Backend::argument),
    );

    let (arguments, trace_count) = match &request.mode {
        Mode::Simulation {
            init,
            step,
            traces,
            samples,
            steps,
        } => {
            let samples = samples.unwrap_or(*traces);
            if !(1..=LIMIT).contains(traces) {
                return Err(InvalidRequest::TraceCount);
            }
            if !(*traces..=LIMIT).contains(&samples) {
                return Err(InvalidRequest::SampleLimit);
            }
            if steps.is_some_and(|value| value > LIMIT) {
                return Err(InvalidRequest::StepLimit);
            }
            let mut arguments = vec!["run".into(), model, "--mbt".into()];
            arguments.extend(common);
            arguments.push(format!("--n-traces={traces}").into());
            arguments.push(format!("--max-samples={samples}").into());
            optional_argument(&mut arguments, "--init", init.as_deref());
            optional_argument(&mut arguments, "--step", step.as_deref());
            optional_argument(&mut arguments, "--max-steps", *steps);
            (arguments, Some(*traces))
        }
        Mode::NamedTest { name, samples } => {
            if samples.is_some_and(|value| !(1..=LIMIT).contains(&value)) {
                return Err(InvalidRequest::SampleLimit);
            }
            if selection.action_path.is_empty() {
                return Err(InvalidRequest::ActionPath);
            }
            let mut arguments = vec!["test".into(), model];
            arguments.extend(common);
            arguments.push(format!("--match={}", exact_pattern(name)).into());
            optional_argument(&mut arguments, "--max-samples", *samples);
            (arguments, None)
        }
    };
    Ok(Plan {
        executable,
        arguments,
        trace_count,
        seed,
    })
}

fn optional_argument(
    arguments: &mut Vec<OsString>,
    flag: &str,
    value: Option<impl std::fmt::Display>,
) {
    if let Some(value) = value {
        arguments.push(format!("{flag}={value}").into());
    }
}

fn exact_pattern(name: &str) -> String {
    let mut pattern = String::from("^");
    for character in name.chars() {
        if "^$\\.*+?()[]{}|".contains(character) {
            pattern.push('\\');
        }
        pattern.push(character);
    }
    pattern.push('$');
    pattern
}

fn bare(path: &Path) -> bool {
    path.file_name() == Some(path.as_os_str())
}

#[derive(Debug)]
#[cfg_attr(
    not(feature = "python"),
    allow(
        dead_code,
        reason = "the Python boundary reports the path and native cause"
    )
)]
pub struct LookupError {
    pub path: PathBuf,
    pub cause: io::Error,
}

pub fn resolve_executable(
    program: &Path,
    caller: &Path,
    paths: Option<&OsStr>,
) -> Result<PathBuf, LookupError> {
    if !bare(program) {
        return Ok(caller.join(program));
    }
    let mut rejected = None;
    for directory in paths.into_iter().flat_map(std::env::split_paths) {
        let location = caller.join(directory).join(program);
        for candidate in candidates(location) {
            match executable_file(&candidate) {
                Ok(()) => return Ok(candidate),
                Err(cause) if cause.kind() == io::ErrorKind::NotFound => {}
                Err(cause) => {
                    rejected.get_or_insert(LookupError {
                        path: candidate,
                        cause,
                    });
                }
            }
        }
    }
    Err(rejected.unwrap_or_else(|| LookupError {
        path: program.to_owned(),
        cause: io::Error::new(io::ErrorKind::NotFound, "command not found"),
    }))
}

#[cfg(not(windows))]
const fn candidates(path: PathBuf) -> [PathBuf; 1] {
    [path]
}

#[cfg(windows)]
fn candidates(path: PathBuf) -> Vec<PathBuf> {
    if path.extension().is_some() {
        return vec![path];
    }
    let extensions = std::env::var("PATHEXT").unwrap_or_else(|_| ".COM;.EXE;.BAT;.CMD".into());
    extensions
        .split(';')
        .map(|extension| path.with_extension(extension.trim_start_matches('.')))
        .collect()
}

fn executable_file(path: &Path) -> io::Result<()> {
    if !std::fs::metadata(path)?.is_file() {
        return Err(io::Error::new(
            io::ErrorKind::PermissionDenied,
            "not a regular executable file",
        ));
    }
    #[cfg(unix)]
    {
        use std::os::unix::ffi::OsStrExt;
        let path = std::ffi::CString::new(path.as_os_str().as_bytes())?;
        // access reads a NUL-terminated path and does not keep the pointer.
        if unsafe { libc::access(path.as_ptr(), libc::X_OK) } != 0 {
            return Err(io::Error::last_os_error());
        }
    }
    Ok(())
}

pub fn output_sequence(name: &OsStr) -> Option<&str> {
    let digits = name
        .to_str()?
        .strip_prefix("trace_")?
        .strip_suffix(".itf.json")?;
    (!digits.is_empty()
        && (digits.len() == 1 || !digits.starts_with('0'))
        && digits.bytes().all(|digit| digit.is_ascii_digit()))
    .then_some(digits)
}

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;
    use rstest::rstest;

    fn simulation(traces: u64, samples: Option<u64>, steps: Option<u64>) -> Request {
        Request {
            model: "examples/counter.qnt".into(),
            executable: "./quint".into(),
            main: None,
            backend: None,
            seed: Some(u64::MAX),
            artifact_dir: None,
            mode: Mode::Simulation {
                init: None,
                step: None,
                traces,
                samples,
                steps,
            },
        }
    }

    #[rstest]
    #[case::zero_traces(0, None, None, InvalidRequest::TraceCount)]
    #[case::too_many_traces(LIMIT + 1, None, None, InvalidRequest::TraceCount)]
    #[case::unsatisfiable_sample_limit(2, Some(1), None, InvalidRequest::SampleLimit)]
    #[case::oversized_sample_limit(1, Some(LIMIT + 1), None, InvalidRequest::SampleLimit)]
    #[case::oversized_step_limit(1, None, Some(LIMIT + 1), InvalidRequest::StepLimit)]
    fn rejects_invalid_limits(
        #[case] traces: u64,
        #[case] samples: Option<u64>,
        #[case] steps: Option<u64>,
        #[case] expected: InvalidRequest,
    ) {
        let request = simulation(traces, samples, steps);

        let result = plan(&request, &Selection::default(), Path::new("/caller"), 2);

        assert_eq!(result.unwrap_err(), expected);
    }

    #[test]
    fn simulation_uses_exact_unsigned_seed_and_zero_step_limit() {
        let request = simulation(2, None, Some(0));

        let prepared = plan(&request, &Selection::default(), Path::new("/caller"), 2).unwrap();

        assert_eq!(
            prepared.arguments,
            [
                "run",
                "/caller/examples/counter.qnt",
                "--mbt",
                "--out-itf=trace_{seq}.itf.json",
                "--seed=18446744073709551615",
                "--n-traces=2",
                "--max-samples=2",
                "--max-steps=0",
            ]
        );
        assert_eq!(prepared.executable, Path::new("/caller/./quint"));
        assert_eq!(prepared.trace_count, Some(2));
        assert_eq!(prepared.seed, u64::MAX);
    }

    #[test]
    fn named_test_escapes_regexp_metacharacters_inside_one_argument() {
        let mut request = simulation(1, None, None);
        request.mode = Mode::NamedTest {
            name: "a+b[ü]".into(),
            samples: Some(5),
        };
        request.main = Some("m a=in".into());
        let selection = Selection {
            action_path: vec!["op".into()],
            ..Selection::default()
        };

        let prepared = plan(&request, &selection, Path::new("/caller"), 0).unwrap();

        assert_eq!(
            prepared.arguments,
            [
                "test",
                "/caller/examples/counter.qnt",
                "--out-itf=trace_{seq}.itf.json",
                "--seed=18446744073709551615",
                "--main=m a=in",
                r"--match=^a\+b\[ü\]$",
                "--max-samples=5",
            ]
        );
    }

    #[cfg(unix)]
    #[test]
    fn path_search_anchors_empty_and_relative_entries_in_caller_directory() {
        use std::os::unix::fs::PermissionsExt;
        let directory = tempfile::tempdir().unwrap();
        let root = directory.path();
        std::fs::write(root.join("quint"), "").unwrap();
        std::fs::create_dir(root.join("bin")).unwrap();
        let expected = root.join("bin/quint");
        std::fs::write(&expected, "").unwrap();
        std::fs::set_permissions(&expected, std::fs::Permissions::from_mode(0o700)).unwrap();

        let resolved =
            resolve_executable(Path::new("quint"), root, Some(OsStr::new(":bin"))).unwrap();

        assert_eq!(resolved, expected);
    }

    proptest! {
        #[test]
        fn canonical_output_numbers_round_trip(index in any::<u128>()) {
            let digits = index.to_string();
            let basename = format!("trace_{digits}.itf.json");

            let sequence = output_sequence(OsStr::new(&basename));

            prop_assert_eq!(sequence, Some(digits.as_str()));
        }
    }
}
