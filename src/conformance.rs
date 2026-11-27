use std::cell::RefCell;
use std::collections::{BTreeMap, VecDeque};
use std::io;
use std::path::{Path, PathBuf};
use std::rc::Rc;

mod generated;

use serde_json::{Value as Json, json};

use crate::itf::{Action, Selection, fixture_value};
use crate::replay::{
    Driver, DriverFailureSite, Mismatch, ReplayEnvironment, ReplayError, ReplayEvent, TraceCause,
    TraceFile, TraceProblem, replay, saved_files,
};
use crate::value::Value;

const FIXTURES: &str = include_str!("../spec/fixtures/runner-conformance.json");

fn tagged(tag: &str, value: Json) -> Json {
    Json::Object(
        [("tag".into(), json!(tag)), ("value".into(), value)]
            .into_iter()
            .collect(),
    )
}

fn unit(tag: &str) -> Json {
    tagged(tag, Json::Null)
}

fn sorted(values: impl Iterator<Item = Json>) -> Vec<Json> {
    let mut values: Vec<_> = values.collect();
    values.sort_by_cached_key(Json::to_string);
    values
}

fn value_json(value: &Value) -> Json {
    match value {
        Value::Bool(value) => json!(value),
        Value::Integer(value) => json!({"#bigint": value.to_string()}),
        Value::Text(value) => json!(value),
        Value::List(values) => Json::Array(values.iter().map(value_json).collect()),
        Value::Tuple(values) => json!({"#tup": values.iter().map(value_json).collect::<Vec<_>>() }),
        Value::Record(fields) => arguments_json(fields),
        Value::Set(values) => json!({"#set": sorted(values.iter().map(value_json)) }),
        Value::Map(values) => {
            json!({"#map": sorted(values.iter().map(|(key, value)| json!([value_json(key), value_json(value)]))) })
        }
    }
}

fn arguments_json(arguments: &BTreeMap<String, Value>) -> Json {
    Json::Object(
        arguments
            .iter()
            .map(|(key, value)| (key.clone(), value_json(value)))
            .collect(),
    )
}

fn action_json(action: &Action) -> Json {
    json!({"name": action.name, "arguments": arguments_json(&action.arguments)})
}

#[derive(Clone, Copy)]
struct TracePosition {
    id: u64,
    index: usize,
}

impl TracePosition {
    fn json(self) -> Json {
        json!({"trace": self.id, "traceIndex": self.index})
    }

    fn step(self, index: usize) -> Json {
        json!({"trace": self.json(), "stepIndex": index})
    }
}

#[derive(Clone, Copy)]
enum FixtureTrace<'a> {
    Saved(&'a TraceFile),
    Generated {
        trace: &'a TraceFile,
        id: u64,
        workspace: u64,
    },
}

impl FixtureTrace<'_> {
    fn position(self) -> TracePosition {
        match self {
            Self::Saved(trace) => TracePosition {
                id: u64::try_from(trace.index).unwrap(),
                index: trace.index,
            },
            Self::Generated { trace, id, .. } => TracePosition {
                id,
                index: trace.index,
            },
        }
    }

    fn path(self) -> Json {
        match self {
            Self::Saved(trace) => tagged("SavedFile", json!(trace.display_path)),
            Self::Generated { id, workspace, .. } => working_path(workspace, id),
        }
    }

    fn read_details(self) -> Json {
        let position = self.position().json();
        let path = self.path();
        match self {
            Self::Saved(_) => json!({"path": path, "position": position}),
            Self::Generated { trace, .. } => json!({
                "basename": trace.path.file_name().unwrap().to_str().unwrap(),
                "path": path,
                "position": position,
            }),
        }
    }
}

fn working_path(workspace: u64, trace: u64) -> Json {
    tagged(
        "WorkingFile",
        json!({"trace": trace, "workspace": workspace}),
    )
}

#[derive(Clone, Copy)]
struct DriverStep {
    driver: u64,
    position: TracePosition,
    index: usize,
}

impl DriverStep {
    fn json(self) -> Json {
        json!({"driver": self.driver, "position": self.position.step(self.index)})
    }
}

fn saved_location(trace: &TraceFile, step: Option<usize>) -> Json {
    let trace = FixtureTrace::Saved(trace);
    step.map_or_else(
        || tagged("AtSavedTrace", trace.read_details()),
        |index| {
            tagged(
                "AtSavedStep",
                json!({"path": trace.path(), "position": trace.position().step(index)}),
            )
        },
    )
}

#[derive(Default)]
struct Script {
    responses: VecDeque<Json>,
    link: Option<generated::Link>,
    events: Vec<Json>,
    driver: u64,
    context: Option<DriverStep>,
}

impl Script {
    fn receive(&mut self, tags: &[&str]) -> Json {
        if let Some(link) = &self.link {
            return link.receive(tags);
        }
        let response = self
            .responses
            .pop_front()
            .expect("the implementation requested an unscheduled response");
        let tag = response["tag"].as_str().expect("response tag");
        assert!(tags.contains(&tag), "requested {tags:?}, scheduled {tag}");
        response
    }

    fn event(&mut self, tag: &str, content: Json) {
        self.events.push(tagged(tag, content));
    }

    fn record_replay<'a>(
        &mut self,
        event: ReplayEvent<'a>,
        resolve: impl FnOnce(&'a TraceFile) -> FixtureTrace<'a>,
    ) {
        match event {
            ReplayEvent::Read(trace) => {
                let trace = resolve(trace);
                let tag = match trace {
                    FixtureTrace::Saved(_) => "SavedReadAttempted",
                    FixtureTrace::Generated { .. } => "GeneratedReadAttempted",
                };
                self.event(tag, trace.read_details());
            }
            ReplayEvent::Factory(trace) => {
                self.event("FactoryCalled", resolve(trace).position().json());
            }
            ReplayEvent::DriverCreated(trace) => self.event(
                "DriverCreated",
                json!({"driver": self.driver, "trace": resolve(trace).position().json()}),
            ),
            ReplayEvent::Apply(trace, index, action) => {
                let context = DriverStep {
                    driver: self.driver,
                    position: resolve(trace).position(),
                    index,
                };
                self.context = Some(context);
                self.event(
                    "OperationCalled",
                    json!({"context": context.json(), "operation": action_json(action)}),
                );
            }
            ReplayEvent::Observe(trace, index, expected) => {
                let context = DriverStep {
                    driver: self.driver,
                    position: resolve(trace).position(),
                    index,
                };
                self.event(
                    "ObservationCalled",
                    json!({"context": context.json(), "expected": value_json(expected)}),
                );
            }
            #[cfg(feature = "python")]
            ReplayEvent::Observed(..) => {}
        }
    }
}

struct ScriptedDriver(Rc<RefCell<Script>>);

impl ScriptedDriver {
    fn create(handle: &Rc<RefCell<Script>>) -> Result<Self, String> {
        let mut script = handle.borrow_mut();
        let response = script.receive(&["DriverFactory"]);
        let result = &response["value"];
        match result["tag"].as_str() {
            Some("FactorySucceeded") => {
                script.driver = result["value"].as_u64().unwrap();
                Ok(Self(Rc::clone(handle)))
            }
            Some("FactoryFailed") => Err(result["value"].as_str().unwrap().to_owned()),
            _ => panic!("invalid factory result {result}"),
        }
    }
}

impl Driver for ScriptedDriver {
    type Error = String;

    fn apply(&mut self, action: &Action) -> Result<(), String> {
        let mut script = self.0.borrow_mut();
        let response = script.receive(&["DriverApply", "DriverApplyWithMutation"]);
        let outcome = if response["tag"] == "DriverApplyWithMutation" {
            let mut delivered = action.clone();
            for (key, value) in response["value"]["arguments"].as_object().unwrap() {
                assert!(
                    delivered.arguments.contains_key(key),
                    "mutation of unexpected argument {key}"
                );
                delivered
                    .arguments
                    .insert(key.clone(), fixture_value(&value.to_string()).unwrap());
            }
            let context = script.context.expect("an operation was recorded");
            script.event(
                "DriverArgumentsChanged",
                json!({"arguments": arguments_json(&delivered.arguments), "context": context.json()}),
            );
            &response["value"]["result"]
        } else {
            &response["value"]
        };
        match outcome["tag"].as_str() {
            Some("OperationApplied") => Ok(()),
            Some("OperationFailed") => Err(outcome["value"].as_str().unwrap().into()),
            _ => panic!("invalid driver response {outcome}"),
        }
    }

    fn observe(&mut self) -> Result<Value, String> {
        let response = self.0.borrow_mut().receive(&["DriverObserve"]);
        let outcome = &response["value"];
        match outcome["tag"].as_str() {
            Some("Observed") => fixture_value(&outcome["value"].to_string())
                .ok_or_else(|| "invalid driver observation".to_owned()),
            Some("ObservationFailed") => Err(outcome["value"].as_str().unwrap().into()),
            _ => panic!("invalid observation {outcome}"),
        }
    }
}

struct SavedReplay {
    files: BTreeMap<PathBuf, Vec<u8>>,
    script: Rc<RefCell<Script>>,
}
impl ReplayEnvironment for SavedReplay {
    type Driver = ScriptedDriver;

    fn read(&mut self, trace: &TraceFile) -> io::Result<Vec<u8>> {
        let response = self.script.borrow_mut().receive(&["SavedRead"]);
        let access = &response["value"];
        match access["tag"].as_str() {
            Some("ReadSucceeded") => self
                .files
                .get(&trace.path)
                .cloned()
                .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "file not found")),
            Some("ReadFailed") => Err(io::Error::other(
                access["value"].as_str().unwrap().to_owned(),
            )),
            _ => panic!("invalid read result {access}"),
        }
    }

    fn create_driver(&mut self) -> Result<ScriptedDriver, String> {
        ScriptedDriver::create(&self.script)
    }

    fn event(&mut self, event: ReplayEvent<'_>) {
        self.script
            .borrow_mut()
            .record_replay(event, FixtureTrace::Saved);
    }
}

fn driver_stage(stage: DriverFailureSite) -> Json {
    unit(match stage {
        DriverFailureSite::Factory => "Factory",
        DriverFailureSite::Apply(_) => "Apply",
        DriverFailureSite::Observe(_) => "Observe",
        DriverFailureSite::Compare(_) => "Compare",
        DriverFailureSite::Exit => "Exit",
    })
}

fn mismatch_json(trace: FixtureTrace<'_>, mismatch: &Mismatch) -> Json {
    json!({
        "position": trace.position().step(mismatch.step_index),
        "step": {"operation": action_json(&mismatch.action), "expected": value_json(&mismatch.expected)},
        "actual": value_json(&mismatch.actual),
    })
}

fn outcome(result: Result<(), ReplayError<String>>) -> Json {
    let error = match result {
        Ok(()) => return unit("Passed"),
        Err(ReplayError::NoInput) => tagged("EmptyTrace", unit("NoInputPaths")),
        Err(ReplayError::NoStates(trace)) => tagged(
            "EmptyTrace",
            tagged(
                "NoSavedTraceStates",
                FixtureTrace::Saved(&trace).read_details(),
            ),
        ),
        Err(ReplayError::InvalidTrace { trace, step, cause }) => {
            let cause = match cause {
                TraceCause::Read(error) => error.to_string(),
                TraceCause::Decode(error) => error.into(),
            };
            tagged(
                "TraceFailed",
                json!({"location": saved_location(&trace, step), "cause": cause}),
            )
        }
        Err(ReplayError::FailedTrace(failure)) => {
            assert!(failure.driver_cleanup.is_none());
            match failure.problem {
                TraceProblem::Driver { site, cause } => tagged(
                    "DriverFailed",
                    json!({"location": saved_location(&failure.trace, site.step_index()), "stage": driver_stage(site), "cause": *cause}),
                ),
                TraceProblem::Mismatch {
                    detail: mismatch, ..
                } => tagged(
                    "StatesDiffer",
                    json!({
                        "detail": mismatch_json(FixtureTrace::Saved(&failure.trace), &mismatch),
                        "artifacts": tagged("FromSavedFile", FixtureTrace::Saved(&failure.trace).path()),
                    }),
                ),
            }
        }
    };
    tagged(
        "Failed",
        json!({"error": error, "cleanup": unit("NoCleanupError")}),
    )
}

fn text_list(list: &Json) -> Vec<String> {
    list.as_array()
        .unwrap()
        .iter()
        .map(|value| value.as_str().unwrap().to_owned())
        .collect()
}

fn assert_saved_case(name: &str) {
    // Arrange from the exported model's requests and responses.
    let fixtures: Json = serde_json::from_str(FIXTURES).unwrap();
    assert_eq!(fixtures["schema_version"], 2);
    let case = fixtures["cases"]
        .as_array()
        .unwrap()
        .iter()
        .find(|case| case["name"] == name)
        .expect("fixture case");
    let schedule = case["schedule"].as_array().unwrap();
    let call = schedule[0]["call_id"].as_u64().unwrap();
    assert_eq!(schedule[0]["input"]["tag"], "Start");
    assert_eq!(schedule[0]["input"]["value"]["tag"], "ReplayPaths");
    let request = &schedule[0]["input"]["value"]["value"];
    let paths: Vec<_> = text_list(&request["paths"])
        .into_iter()
        .map(PathBuf::from)
        .collect();
    let caller = Path::new("/fixture");
    let files = saved_files(&paths, caller);
    let selection = Selection {
        action_path: text_list(&request["selection"]["actionPath"]),
        state_path: Some(text_list(&request["selection"]["statePath"])),
    };
    let input_files = case["input_files"]
        .as_array()
        .unwrap()
        .iter()
        .map(|file| {
            assert_eq!(file["path"]["tag"], "SavedFile");
            let name = file["path"]["value"].as_str().unwrap();
            let bytes = serde_json::from_value(file["bytes"].clone()).unwrap();
            (caller.join(name), bytes)
        })
        .collect();
    let script = Rc::new(RefCell::new(Script {
        responses: schedule[1..]
            .iter()
            .map(|entry| {
                assert_eq!(entry["call_id"], call);
                assert_eq!(entry["input"]["tag"], "Respond");
                entry["input"]["value"].clone()
            })
            .collect(),
        ..Script::default()
    }));
    let mut environment = SavedReplay {
        files: input_files,
        script: Rc::clone(&script),
    };

    // Act through the production replay loop.
    let result = replay(&files, &selection, &mut environment);

    // Assert the observed interaction order as well as the returned result.
    let script = script.borrow();
    let actual = json!({
        "calls": [{"call_id": call, "events": script.events, "outcome": outcome(result)}],
        "saved_files": [], "remaining_workspace_files": [],
    });
    assert!(
        script.responses.is_empty(),
        "{name}: unused responses: {:?}",
        script.responses
    );
    assert_eq!(actual, case["expected"], "{name}");
}

#[test]
fn anonymous_operation_normalizes_mismatch_values() {
    assert_saved_case("anonymousOperationNormalizesMismatchValues");
}

#[test]
fn driver_apply_failure() {
    assert_saved_case("driverApplyFailure");
}

#[test]
fn invalid_second_saved_file() {
    assert_saved_case("invalidSecondSavedFile");
}

#[test]
fn nested_argument_mutation_mismatch() {
    assert_saved_case("nestedArgumentMutationMismatch");
}

#[test]
fn repeated_multistep_replay() {
    assert_saved_case("repeatedMultistepReplay");
}
