use std::cell::RefCell;
use std::collections::{BTreeMap, VecDeque};
use std::io;
use std::path::{Path, PathBuf};
use std::rc::Rc;

use serde_json::{Value as Json, json};

use crate::itf::{Action, Selection, fixture_value};
use crate::replay::{
    Driver, DriverStage, Mismatch, ReplayEnvironment, ReplayError, ReplayEvent, TraceCause,
    TraceFile, replay, saved_files,
};
use crate::value::Value;

const FIXTURES: &str = include_str!("../spec/fixtures/runner-conformance.json");

fn tagged(tag: &str, value: Json) -> Json {
    json!({"tag": tag, "value": value})
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

fn position(trace: &TraceFile) -> Json {
    json!({"trace": trace.index, "traceIndex": trace.index})
}

fn step_position(trace: &TraceFile, step: usize) -> Json {
    json!({"trace": position(trace), "stepIndex": step})
}

fn path(trace: &TraceFile) -> Json {
    tagged("SavedFile", json!(trace.display_path))
}

fn location(trace: &TraceFile, step: Option<usize>) -> Json {
    match step {
        Some(step) => tagged(
            "AtSavedStep",
            json!({"path": path(trace), "position": step_position(trace, step)}),
        ),
        None => tagged(
            "AtSavedTrace",
            json!({"path": path(trace), "position": position(trace)}),
        ),
    }
}

#[derive(Default)]
struct Script {
    responses: VecDeque<Json>,
    events: Vec<Json>,
    driver: u64,
    context: Json,
}

impl Script {
    fn receive(&mut self, tags: &[&str]) -> Json {
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

    fn step_context(&mut self, trace: &TraceFile, step: usize) -> Json {
        json!({"driver": self.driver, "position": step_position(trace, step)})
    }
}

struct ScriptedDriver(Rc<RefCell<Script>>);
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
            let context = script.context.clone();
            script.event(
                "DriverArgumentsChanged",
                json!({"arguments": arguments_json(&delivered.arguments), "context": context}),
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
        let mut script = self.script.borrow_mut();
        let response = script.receive(&["DriverFactory"]);
        let result = &response["value"];
        match result["tag"].as_str() {
            Some("FactorySucceeded") => {
                script.driver = result["value"].as_u64().unwrap();
                Ok(ScriptedDriver(Rc::clone(&self.script)))
            }
            Some("FactoryFailed") => Err(result["value"].as_str().unwrap().to_owned()),
            _ => panic!("invalid factory result {result}"),
        }
    }

    fn event(&mut self, event: ReplayEvent<'_>) {
        let mut script = self.script.borrow_mut();
        match event {
            ReplayEvent::Read(trace) => script.event(
                "SavedReadAttempted",
                json!({"path": path(trace), "position": position(trace)}),
            ),
            ReplayEvent::Factory(trace) => script.event("FactoryCalled", position(trace)),
            ReplayEvent::DriverCreated(trace) => {
                let driver = script.driver;
                script.event(
                    "DriverCreated",
                    json!({"driver": driver, "trace": position(trace)}),
                );
            }
            ReplayEvent::Apply(trace, step, action) => {
                let context = script.step_context(trace, step);
                script.context = context.clone();
                script.event(
                    "OperationCalled",
                    json!({"context": context, "operation": action_json(action)}),
                );
            }
            ReplayEvent::Observe(trace, step, expected) => {
                let context = script.step_context(trace, step);
                script.event(
                    "ObservationCalled",
                    json!({"context": context, "expected": value_json(expected)}),
                );
            }
        }
    }
}

fn mismatch_json(mismatch: &Mismatch) -> Json {
    json!({
        "position": step_position(&mismatch.trace, mismatch.step_index),
        "step": {"operation": action_json(&mismatch.step.action), "expected": value_json(&mismatch.step.expected)},
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
                json!({"path": path(&trace), "position": position(&trace)}),
            ),
        ),
        Err(ReplayError::InvalidTrace { trace, step, cause }) => {
            let cause = match cause {
                TraceCause::Read(error) => error.to_string(),
                TraceCause::Decode(error) => error.into(),
            };
            tagged(
                "TraceFailed",
                json!({"location": location(&trace, step), "cause": cause}),
            )
        }
        Err(ReplayError::Driver {
            trace,
            step,
            stage,
            cause,
        }) => {
            let stage = match stage {
                DriverStage::Factory => "Factory",
                DriverStage::Apply => "Apply",
                DriverStage::Observe => "Observe",
            };
            tagged(
                "DriverFailed",
                json!({"location": location(&trace, step), "stage": unit(stage), "cause": cause}),
            )
        }
        Err(ReplayError::Mismatch(mismatch)) => tagged(
            "StatesDiffer",
            json!({
                "detail": mismatch_json(&mismatch), "artifacts": tagged("FromSavedFile", path(&mismatch.trace)),
            }),
        ),
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
        state_path: text_list(&request["selection"]["statePath"]),
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
