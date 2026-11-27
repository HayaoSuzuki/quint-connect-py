use std::ffi::OsStr;
use std::sync::{Arc, Mutex, mpsc};
use std::time::Duration;

use super::*;
use crate::cli::{Backend, Mode, Plan, Request};
use crate::runner::{
    ArtifactError, ChildIoError, ChildIoStage, ChildOutput, Cleanup, Exit, Failure, RunEnvironment,
    RunError, RunEvent, run_from,
};

const TIMEOUT: Duration = Duration::from_secs(5);

enum Pending {
    Respond(Vec<String>),
    Finished(Json),
}

pub(super) struct Link {
    next: mpsc::Sender<Pending>,
    response: mpsc::Receiver<Json>,
}

impl Link {
    pub(super) fn receive(&self, tags: &[&str]) -> Json {
        self.next
            .send(Pending::Respond(
                tags.iter().map(|tag| (*tag).to_owned()).collect(),
            ))
            .unwrap();
        self.response
            .recv_timeout(TIMEOUT)
            .expect("fixture did not respond")
    }
}

struct Worker {
    response: mpsc::Sender<Json>,
    next: mpsc::Receiver<Pending>,
    pending: Pending,
    thread: std::thread::JoinHandle<()>,
}

impl Worker {
    fn respond(&mut self, response: &Json) {
        let Pending::Respond(tags) = &self.pending else {
            panic!("fixture continued after return");
        };
        let tag = response["tag"].as_str().unwrap();
        assert!(
            tags.iter().any(|expected| expected == tag),
            "requested {tags:?}, scheduled {tag}"
        );
        self.response.send(response.clone()).unwrap();
        self.pending = self
            .next
            .recv_timeout(TIMEOUT)
            .expect("no effect or result followed the response");
    }

    fn finish(self) -> Json {
        self.thread.join().unwrap();
        let Pending::Finished(report) = self.pending else {
            panic!("fixture ended with a blocked effect");
        };
        report
    }
}

type SharedArtifacts = Arc<Mutex<BTreeMap<PathBuf, Option<Json>>>>;

struct GeneratedRun {
    driver: SavedReplay,
    workspace: u64,
    root: String,
    request: Json,
    drawn_seed: Json,
    generation: Json,
    output: BTreeMap<PathBuf, Produced>,
    ids: BTreeMap<PathBuf, u64>,
    artifacts: SharedArtifacts,
}

struct Produced {
    trace: u64,
    bytes: Vec<u8>,
}

impl GeneratedRun {
    fn response(&self, tags: &[&str]) -> Json {
        self.driver.script.borrow_mut().receive(tags)
    }
    fn record(&self, tag: &str, value: Json) {
        self.driver.script.borrow_mut().event(tag, value);
    }
    fn workspace_path(&self) -> PathBuf {
        PathBuf::from(format!("/workspace/{}", self.workspace))
    }

    fn produced(&mut self, files: &Json) {
        for file in files.as_array().unwrap() {
            let name = file["name"].as_str().unwrap();
            let path = self.workspace_path().join(name);
            let trace = file["trace"].as_u64().unwrap();
            let bytes = serde_json::from_value(file["bytes"].clone()).unwrap();
            self.ids.insert(path.clone(), trace);
            assert!(
                self.output
                    .insert(path, Produced { trace, bytes })
                    .is_none()
            );
        }
    }

    fn position(&self, trace: &TraceFile) -> Json {
        json!({"trace": self.ids[&trace.path], "traceIndex": trace.index})
    }

    fn trace_details(&self, trace: &TraceFile) -> Json {
        json!({
            "basename": trace.path.file_name().unwrap().to_str().unwrap(),
            "path": self.working_path(self.ids[&trace.path]),
            "position": self.position(trace),
        })
    }

    fn working_path(&self, trace: u64) -> Json {
        tagged(
            "WorkingFile",
            json!({"trace": trace, "workspace": self.workspace}),
        )
    }

    fn generation_event(&self, result: &Json, basenames: &[Json]) {
        self.record(
            "GenerationCompleted",
            json!({
                "result": result, "basenames": {"#map": basenames}, "generation": self.generation,
            }),
        );
    }

    fn step_position(&self, trace: &TraceFile, index: usize) -> Json {
        json!({"trace": self.position(trace), "stepIndex": index})
    }

    fn evidence_path(&self, trace: u64, directory: &Path) -> Json {
        tagged(
            "EvidenceFile",
            json!({"trace": trace, "root": self.root, "directory": directory_id(directory)}),
        )
    }

    fn save_result(&self, trace: &TraceFile, result: &Result<PathBuf, ArtifactError>) -> Json {
        match result {
            Ok(path) => tagged(
                "ArtifactSaved",
                self.evidence_path(self.ids[&trace.path], path.parent().unwrap()),
            ),
            Err(ArtifactError::Reserve { directory, cause }) => tagged(
                "ArtifactDirectoryFailed",
                json!({"root": self.root, "directory": directory_id(directory), "cause": cause.to_string()}),
            ),
            Err(ArtifactError::Save(cause) | ArtifactError::Prepare(cause)) => {
                tagged("ArtifactSaveFailed", json!(cause.to_string()))
            }
        }
    }
}

fn directory_id(directory: &Path) -> u64 {
    directory
        .file_name()
        .unwrap()
        .to_str()
        .unwrap()
        .parse()
        .unwrap()
}

impl ReplayEnvironment for GeneratedRun {
    type Driver = ScriptedDriver;

    fn read(&mut self, trace: &TraceFile) -> io::Result<Vec<u8>> {
        let response = self.response(&["GeneratedRead"]);
        let access = &response["value"];
        match access["tag"].as_str() {
            Some("ReadSucceeded") => Ok(self.output[&trace.path].bytes.clone()),
            Some("ReadFailed") => Err(cause(&access["value"])),
            _ => panic!("invalid read result {access}"),
        }
    }

    fn create_driver(&mut self) -> Result<ScriptedDriver, String> {
        self.driver.create_driver()
    }

    fn event(&mut self, event: ReplayEvent<'_>) {
        let mut script = self.driver.script.borrow_mut();
        match event {
            ReplayEvent::Read(trace) => {
                script.event("GeneratedReadAttempted", self.trace_details(trace));
            }
            ReplayEvent::Factory(trace) => script.event("FactoryCalled", self.position(trace)),
            ReplayEvent::DriverCreated(trace) => {
                let driver = script.driver;
                script.event(
                    "DriverCreated",
                    json!({"trace": self.position(trace), "driver": driver}),
                );
            }
            ReplayEvent::Apply(trace, step, action) => {
                let context =
                    json!({"driver": script.driver, "position": self.step_position(trace, step)});
                script.context = context.clone();
                script.event(
                    "OperationCalled",
                    json!({"context": context, "operation": action_json(action)}),
                );
            }
            ReplayEvent::Observe(trace, step, expected) => {
                let context =
                    json!({"driver": script.driver, "position": self.step_position(trace, step)});
                script.event(
                    "ObservationCalled",
                    json!({"context": context, "expected": value_json(expected)}),
                );
            }
        }
    }
}

fn cause(value: &Json) -> io::Error {
    io::Error::other(value.as_str().unwrap().to_owned())
}

fn storage(value: &Json) -> io::Result<()> {
    match value["tag"].as_str() {
        Some("StorageSucceeded") => Ok(()),
        Some("StorageFailed") => Err(cause(&value["value"])),
        _ => panic!("invalid storage result {value}"),
    }
}

fn storage_json(result: &io::Result<()>) -> Json {
    result.as_ref().map_or_else(
        |e| tagged("StorageFailed", json!(e.to_string())),
        |()| unit("StorageSucceeded"),
    )
}

fn exit_problem(exit: Exit, stdout: &[u8], stderr: &[u8]) -> Json {
    let output = json!({"stdout": stdout, "stderr": stderr});
    match exit {
        Exit::Code(code) => tagged("NonzeroExit", json!({"code": code, "output": output})),
        Exit::Signal(signal) => tagged("SignalExit", json!({"signal": signal, "output": output})),
        Exit::Success => panic!("expected exit failure"),
        #[cfg(feature = "python")]
        Exit::Unknown => panic!("expected exit code or signal"),
    }
}

fn io_problem(problem: &ChildIoError) -> Json {
    let stage = match problem.stage {
        ChildIoStage::WaitForExit => "WaitForExit",
        ChildIoStage::CollectOutput => "CollectOutput",
    };
    json!({"stage": unit(stage), "cause": problem.cause.to_string()})
}

impl RunEnvironment for GeneratedRun {
    type Child = ();

    fn reserve(&mut self) -> io::Result<PathBuf> {
        Ok(self.workspace_path())
    }

    fn spawn(&mut self, _: &Plan, _: &Path) -> io::Result<()> {
        let response = self.response(&["ChildStarted", "ChildSpawnFailed"]);
        if response["tag"] == "ChildStarted" {
            return Ok(());
        }
        let error = cause(&response["value"]);
        self.generation_event(
            &tagged(
                "ProcessFailed",
                tagged("SpawnFailure", json!(error.to_string())),
            ),
            &[],
        );
        Err(error)
    }

    fn wait(&mut self, (): &mut ()) -> Result<ChildOutput, ChildIoError> {
        let response = self.response(&["ChildSucceeded", "ChildFailed", "ChildIoFailed"]);
        let value = &response["value"];
        match response["tag"].as_str() {
            Some("ChildSucceeded") => {
                self.produced(value);
                Ok(ChildOutput {
                    status: Exit::Success,
                    stdout: Vec::new(),
                    stderr: Vec::new(),
                })
            }
            Some("ChildFailed") => {
                self.produced(&value["partialOutput"]);
                let problem = &value["problem"]["value"];
                let status = match value["problem"]["tag"].as_str() {
                    Some("NonzeroExit") => {
                        Exit::Code(i32::try_from(problem["code"].as_i64().unwrap()).unwrap())
                    }
                    Some("SignalExit") => {
                        Exit::Signal(i32::try_from(problem["signal"].as_i64().unwrap()).unwrap())
                    }
                    _ => panic!("invalid process status"),
                };
                let stdout: Vec<u8> =
                    serde_json::from_value(problem["output"]["stdout"].clone()).unwrap();
                let stderr: Vec<u8> =
                    serde_json::from_value(problem["output"]["stderr"].clone()).unwrap();
                self.generation_event(
                    &tagged("ProcessFailed", exit_problem(status, &stdout, &stderr)),
                    &[],
                );
                Ok(ChildOutput {
                    status,
                    stdout,
                    stderr,
                })
            }
            Some("ChildIoFailed") => {
                assert_eq!(value["exit"]["tag"], "ExitUnconfirmed");
                let stage = match value["problem"]["stage"]["tag"].as_str() {
                    Some("WaitForExit") => ChildIoStage::WaitForExit,
                    Some("CollectOutput") => ChildIoStage::CollectOutput,
                    _ => panic!("invalid child I/O stage"),
                };
                Err(ChildIoError {
                    stage,
                    cause: cause(&value["problem"]["cause"]),
                    exit_confirmed: false,
                })
            }
            _ => panic!("invalid process response"),
        }
    }

    fn confirm_exit(&mut self, (): &mut ()) -> io::Result<()> {
        let response = self.response(&["ChildExitWasConfirmed", "WorkspaceCleanupWasDeferred"]);
        if response["tag"] == "ChildExitWasConfirmed" {
            self.produced(&response["value"]);
            Ok(())
        } else {
            self.produced(&response["value"]["partialOutput"]);
            Err(cause(&response["value"]["cause"]))
        }
    }

    fn list(&mut self, _: &Path) -> io::Result<Vec<PathBuf>> {
        let response = self.response(&["DirectoryListing"]);
        if response["value"]["tag"] == "ListingSucceeded" {
            Ok(self.output.keys().cloned().collect())
        } else {
            let cause = cause(&response["value"]["value"]);
            self.generation_event(&tagged("OutputUnavailable", json!(cause.to_string())), &[]);
            Err(cause)
        }
    }

    fn artifact_candidates(&mut self, root: &Path) -> io::Result<Vec<PathBuf>> {
        assert_eq!(root.file_name().unwrap(), OsStr::new(&self.root));
        let response = self.response(&["ArtifactCandidateList"]);
        Ok(response["value"]
            .as_array()
            .unwrap()
            .iter()
            .map(|id| root.join(id.as_u64().unwrap().to_string()))
            .collect())
    }

    fn reserve_artifact(&mut self, directory: &Path) -> io::Result<()> {
        let response = self.response(&["ArtifactReservation"]);
        let mut artifacts = self.artifacts.lock().unwrap();
        if artifacts.contains_key(directory) {
            return Err(io::Error::new(
                io::ErrorKind::AlreadyExists,
                "artifact directory already exists",
            ));
        }
        storage(&response["value"])?;
        artifacts.insert(directory.to_owned(), None);
        drop(artifacts);
        Ok(())
    }

    fn publish(&mut self, directory: &Path, name: &OsStr, bytes: &[u8]) -> io::Result<PathBuf> {
        let _started = self.response(&["EvidenceCopyStarted"]);
        let mut written = Vec::new();
        loop {
            let response = self.response(&["EvidenceCopyWritten", "EvidenceCopyFinished"]);
            if response["tag"] == "EvidenceCopyFinished" {
                if let Err(error) = storage(&response["value"]) {
                    self.artifacts.lock().unwrap().remove(directory);
                    return Err(error);
                }
                break;
            }
            let count = usize::try_from(response["value"].as_u64().unwrap()).unwrap();
            let chunk = &bytes[written.len()..count];
            written.extend_from_slice(chunk);
        }
        assert_eq!(written, bytes, "evidence published without all the bytes");
        let trace = self.output[&self.workspace_path().join(name)].trace;
        let file = json!({"path": self.evidence_path(trace, directory), "bytes": written});
        self.artifacts
            .lock()
            .unwrap()
            .insert(directory.to_owned(), Some(file));
        Ok(directory.join(name))
    }

    fn cleanup(&mut self, _: &Path) -> io::Result<()> {
        let response = self.response(&["WorkspaceCleanup"]);
        let effect = &response["value"];
        let remaining = &effect["removal"];
        match remaining["tag"].as_str() {
            Some("RemoveComplete") => self.output.clear(),
            Some("RemoveInterrupted") => {
                let traces = remaining["value"]["#set"].as_array().unwrap();
                self.output
                    .retain(|_, file| traces.contains(&json!(file.trace)));
            }
            _ => panic!("invalid cleanup operation"),
        }
        storage(&effect["result"])
    }

    fn run_event(&mut self, event: RunEvent<'_>) {
        match event {
            RunEvent::Prepared(plan) => self.prepared(plan),
            RunEvent::Reserved(workspace) => {
                assert_eq!(workspace, self.workspace_path());
                self.record("WorkspaceReserved", self.generation.clone());
            }
            RunEvent::ProcessStarted => self.record("ProcessStarted", self.generation.clone()),
            RunEvent::ProcessExitedSuccessfully => self.record("ProcessExitedSuccessfully", self.generation.clone()),
            RunEvent::ProcessIoFailed(problem) => {
                assert!(!problem.exit_confirmed);
                self.record("ProcessIoFailed", json!({"exit": unit("ExitUnconfirmed"), "generation": self.generation, "problem": io_problem(problem)}));
            }
            RunEvent::ExitConfirmed => self.record("ChildExitConfirmed", self.generation.clone()),
            RunEvent::CleanupDeferred(cause) => self.record("WorkspaceCleanupDeferred", json!({"workspace": self.workspace, "cause": cause.to_string()})),
            RunEvent::Listed(traces) => {
                let ids: Vec<_> = traces.iter().map(|trace| self.ids[&trace.path]).collect();
                let mut basenames: Vec<_> = traces.iter().zip(&ids).map(|(trace, id)| json!([id, trace.path.file_name().unwrap().to_str().unwrap()])).collect();
                basenames.sort_by_cached_key(Json::to_string);
                self.generation_event(&tagged("ProcessSucceeded", json!(ids)), &basenames);
            }
            RunEvent::ArtifactTried(directory, result) => {
                let status = match result {
                    Ok(()) => unit("DirectoryReserved"),
                    Err(error) if error.kind() == io::ErrorKind::AlreadyExists => unit("DirectoryCollision"),
                    Err(error) => tagged("DirectoryRejected", json!(error.to_string())),
                };
                self.record("ArtifactDirectoryTried", json!({"directory": directory_id(directory), "result": status, "root": self.root}));
            }
            RunEvent::ArtifactSaved(trace, result) => self.record("SaveAttempted",
                json!({"position": self.position(trace), "result": self.save_result(trace, result)})),
            RunEvent::CleanupAttempted(result) => self.record("CleanupAttempted", json!({"workspace": self.workspace, "result": storage_json(result)})),
        }
    }
}
fn option<T>(field: &Json, extract: impl FnOnce(&Json) -> T) -> Option<T> {
    match field["tag"].as_str() {
        Some("CliDefault") => None,
        Some("CliSpecified") => Some(extract(&field["value"])),
        _ => panic!("invalid CLI option {field}"),
    }
}

fn number(field: &Json) -> u64 {
    field.as_u64().unwrap()
}

fn string(field: &Json) -> String {
    field.as_str().unwrap().to_owned()
}

fn seed_digits(seed: u64) -> Json {
    json!(
        seed.to_string()
            .chars()
            .map(|digit| digit.to_string())
            .collect::<Vec<_>>()
    )
}

fn decode_seed(value: &Json) -> u64 {
    text_list(value).concat().parse().unwrap()
}

fn request(value: &Json) -> Request {
    let cli = &value["cli"];
    let config = &cli["config"];
    let fields = &config["value"];
    let samples = option(&fields["maxSamples"], number);
    let mode = match config["tag"].as_str() {
        Some("Simulation") => Mode::Simulation {
            init: option(&fields["init"], string),
            step: option(&fields["step"], string),
            samples,
            traces: option(&fields["nTraces"], number).unwrap_or(1),
            steps: option(&fields["maxSteps"], number),
        },
        Some("NamedTestMode") => Mode::NamedTest {
            name: fields["name"]
                .as_array()
                .unwrap()
                .iter()
                .map(|point| char::from_u32(u32::try_from(number(point)).unwrap()).unwrap())
                .collect(),
            samples,
        },
        _ => panic!("invalid mode {config}"),
    };
    assert_eq!(cli["executable"]["tag"], "ExecutablePath");
    Request {
        model: string(&cli["model"]["value"]).into(),
        executable: string(&cli["executable"]["value"]["value"]).into(),
        main: option(&cli["main"], string),
        backend: option(&cli["backend"], |tag| match tag["tag"].as_str() {
            Some("RustBackend") => Backend::Rust,
            Some("TypeScriptBackend") => Backend::TypeScript,
            _ => panic!("invalid backend {tag}"),
        }),
        mode,
        seed: option(&cli["seed"], decode_seed),
        artifact_dir: Some(string(&value["artifactRoot"]).into()),
    }
}

fn model_argument(path: &str, request: &Json) -> Json {
    let raw = &request["model"];
    let original = string(&raw["value"]);
    let origin = string(&request["callerDirectory"]);
    assert_eq!(Path::new(path), Path::new(&origin).join(&original));
    let target = if raw["tag"] == "RelativePath" {
        tagged(
            "AnchoredPath",
            json!({"directory": origin, "path": original}),
        )
    } else {
        tagged("AbsoluteTarget", json!(path))
    };
    tagged("ModelArgument", target)
}

fn command_argument(argument: &str) -> Json {
    let Some((flag, value)) = argument.split_once('=') else {
        return tagged("LiteralArgument", json!(argument));
    };
    match flag {
        "--seed" => tagged("SeedOption", seed_digits(value.parse().unwrap())),
        "--match" => tagged("MatchOption", json!(value)),
        "--max-samples" | "--n-traces" | "--max-steps" => tagged(
            "IntegerOption",
            json!({"flag": flag, "value": value.parse::<u64>().unwrap()}),
        ),
        _ => tagged("StringOption", json!({"flag": flag, "value": value})),
    }
}

impl GeneratedRun {
    fn prepared(&mut self, plan: &Plan) {
        let expectation = plan.trace_count.map_or_else(
            || unit("NamedTestOutput"),
            |count| tagged("SimulationCount", json!(count)),
        );
        let seed = seed_digits(plan.seed);
        self.generation = json!({
            "artifactRoot": self.root, "expectation": expectation, "seed": seed, "workspace": self.workspace,
        });
        let argv: Vec<_> = plan
            .arguments
            .iter()
            .enumerate()
            .map(|(index, argument)| {
                let argument = argument.to_str().unwrap();
                if index == 1 {
                    model_argument(argument, &self.request)
                } else {
                    command_argument(argument)
                }
            })
            .collect();
        let executable = tagged("AbsoluteTarget", json!(plan.executable));
        self.record(
            "CommandPrepared",
            json!({
                "request": self.request, "drawnSeed": self.drawn_seed,
                "target": tagged("ExplicitExecutable", executable.clone()),
                "command": {
                    "argv": argv, "executable": tagged("DirectExecutable", executable),
                    "seed": seed, "workspace": self.workspace,
                },
            }),
        );
    }

    fn outcome(&self, result: Result<(), Box<RunError<String>>>) -> Json {
        let Err(result) = result else {
            return unit("Passed");
        };
        let seed = seed_digits(result.seed.unwrap());
        let error = match result.failure {
            Failure::Spawn(cause) => tagged(
                "QuintFailed",
                json!({"seed": seed, "problem": tagged("SpawnFailure", json!(cause.to_string()))}),
            ),
            Failure::Exit {
                status,
                stdout,
                stderr,
            } => tagged(
                "QuintFailed",
                json!({"seed": seed, "problem": exit_problem(status, &stdout, &stderr)}),
            ),
            Failure::ChildIo(problem) => tagged(
                "QuintFailed",
                json!({"seed": seed, "problem": tagged("ProcessIoFailure", io_problem(&problem))}),
            ),
            Failure::Replay(ReplayError::InvalidTrace { trace, step, cause }) => {
                assert!(step.is_none(), "fixture needs a generated step location");
                let cause = match cause {
                    TraceCause::Read(cause) => cause.to_string(),
                    TraceCause::Decode(cause) => cause.into(),
                };
                tagged(
                    "TraceFailed",
                    json!({"location": tagged("AtGeneratedTrace", self.trace_details(&trace)), "cause": cause}),
                )
            }
            Failure::Replay(ReplayError::FailedTrace(failure)) => {
                let trace = &failure.trace;
                let saved = self.save_result(trace, &result.artifact.unwrap());
                let artifacts = tagged("FromGeneration", json!({"seed": seed, "save": saved}));
                match failure.problem {
                    TraceProblem::Mismatch(mismatch) => {
                        let mut detail = mismatch_json(trace, &mismatch);
                        detail["position"] = self.step_position(trace, mismatch.step_index);
                        tagged(
                            "StatesDiffer",
                            json!({"detail": detail, "artifacts": artifacts}),
                        )
                    }
                    TraceProblem::Driver { site, cause } => {
                        let location = site.step_index().map_or_else(
                            || tagged("AtTrace", self.position(trace)),
                            |index| tagged("AtStep", self.step_position(trace, index)),
                        );
                        let detail = json!({"location": location, "stage": driver_stage(site), "cause": *cause});
                        tagged(
                            "GeneratedDriverFailed",
                            json!({
                                "position": self.position(trace), "detail": detail, "artifacts": artifacts,
                            }),
                        )
                    }
                }
            }
            failure => panic!("unsupported fixture outcome {failure:?}"),
        };
        let cleanup = match result.cleanup {
            None => unit("NoCleanupError"),
            Some(Cleanup::Failed(cause)) => tagged("CleanupAlsoFailed", json!(cause.to_string())),
            Some(Cleanup::Deferred { workspace, cause }) => {
                assert_eq!(workspace, self.workspace_path());
                tagged(
                    "CleanupDeferred",
                    json!({"workspace": self.workspace, "cause": cause.to_string()}),
                )
            }
        };
        tagged("Failed", json!({"error": error, "cleanup": cleanup}))
    }
}

fn spawn_worker(call_id: u64, start: Json, artifacts: SharedArtifacts) -> Worker {
    let (to_worker, response) = mpsc::channel();
    let (notice, from_worker) = mpsc::channel();
    let thread = std::thread::spawn(move || {
        let request = request(&start);
        let selection = Selection {
            action_path: text_list(&start["selection"]["actionPath"]),
            state_path: text_list(&start["selection"]["statePath"]),
        };
        let caller = string(&start["cli"]["callerDirectory"]);
        let seed = decode_seed(&start["drawnSeed"]);
        let script = Rc::new(RefCell::new(Script {
            link: Some(Link {
                next: notice.clone(),
                response,
            }),
            ..Script::default()
        }));
        let mut environment = GeneratedRun {
            driver: SavedReplay {
                files: BTreeMap::new(),
                script: Rc::clone(&script),
            },
            workspace: number(&start["cli"]["workspace"]),
            root: string(&start["artifactRoot"]),
            request: start["cli"].clone(),
            drawn_seed: start["drawnSeed"].clone(),
            generation: Json::Null,
            output: BTreeMap::new(),
            ids: BTreeMap::new(),
            artifacts,
        };
        let result = run_from(
            &request,
            &selection,
            Path::new(&caller),
            None,
            seed,
            &mut environment,
        );
        let report = json!({
            "call": {"call_id": call_id, "events": script.borrow().events, "outcome": environment.outcome(result)},
            "workspace_files": environment.output.values().map(|file|
                json!({"path": environment.working_path(file.trace), "bytes": file.bytes})).collect::<Vec<_>>(),
        });
        notice.send(Pending::Finished(report)).unwrap();
    });
    let pending = from_worker
        .recv_timeout(TIMEOUT)
        .expect("call did not request its first effect");
    Worker {
        response: to_worker,
        next: from_worker,
        pending,
        thread,
    }
}

fn check(name: &str) {
    let fixtures: Json = serde_json::from_str(FIXTURES).unwrap();
    assert_eq!(fixtures["schema_version"], 2);
    let case = fixtures["cases"]
        .as_array()
        .unwrap()
        .iter()
        .find(|case| case["name"] == name)
        .unwrap();
    assert_eq!(case["input_files"], json!([]));
    let artifacts = SharedArtifacts::default();
    let mut workers = BTreeMap::new();

    // Wait for each response to reach the next effect boundary before allowing
    // another call to act on the shared filesystem.
    for entry in case["schedule"].as_array().unwrap() {
        let call = number(&entry["call_id"]);
        let input = &entry["input"];
        match input["tag"].as_str() {
            Some("Start") => {
                assert_eq!(input["value"]["tag"], "RunQuint");
                let worker = spawn_worker(
                    call,
                    input["value"]["value"].clone(),
                    Arc::clone(&artifacts),
                );
                assert!(workers.insert(call, worker).is_none());
            }
            Some("Respond") => workers.get_mut(&call).unwrap().respond(&input["value"]),
            _ => panic!("invalid scheduled input"),
        }
    }

    let reports: Vec<_> = workers.into_values().map(Worker::finish).collect();
    let calls: Vec<_> = reports
        .iter()
        .map(|report| report["call"].clone())
        .collect();
    let remaining = sorted(reports.iter().flat_map(|report| {
        report["workspace_files"]
            .as_array()
            .unwrap()
            .iter()
            .cloned()
    }));
    let saved = sorted(artifacts.lock().unwrap().values().flatten().cloned());
    let actual =
        json!({"calls": calls, "saved_files": saved, "remaining_workspace_files": remaining});
    let expected = &case["expected"];
    for (actual, expected) in actual["calls"]
        .as_array()
        .unwrap()
        .iter()
        .zip(expected["calls"].as_array().unwrap())
    {
        let events = actual["events"].as_array().unwrap();
        let expected_events = expected["events"].as_array().unwrap();
        for (index, (event, expected)) in events.iter().zip(expected_events).enumerate() {
            assert_eq!(event, expected, "{name}, event {index}");
        }
    }
    assert_eq!(actual, *expected, "{name}");
}

#[test]
fn artifact_directory_failure() {
    check("artifactDirectoryFailure");
}

#[test]
fn generated_driver_failure_saved() {
    check("generatedDriverFailureSaved");
}

#[test]
fn generated_mismatch_saved() {
    check("generatedMismatchSaved");
}

#[test]
fn named_generated_replay() {
    check("namedGeneratedReplay");
}

#[test]
fn nonzero_exit_with_output() {
    check("nonzeroExitWithOutput");
}

#[test]
fn output_collection_failure_after_exit_confirmation() {
    check("outputCollectionFailureAfterExitConfirmation");
}

#[test]
fn overlapping_artifact_reservation() {
    check("overlappingArtifactReservation");
}

#[test]
fn second_generated_read_failure() {
    check("secondGeneratedReadFailure");
}

#[test]
fn signal_exit_with_output_and_cleanup_failure() {
    check("signalExitWithOutputAndCleanupFailure");
}

#[test]
fn spawn_failure() {
    check("spawnFailure");
}

#[test]
fn wait_failure_with_deferred_cleanup() {
    check("waitFailureWithDeferredCleanup");
}
