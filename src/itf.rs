mod json;

use self::json::{Document, Node, NodeId};
use crate::value::Value;
use std::collections::BTreeMap;

#[derive(Clone, Debug, Default)]
pub(crate) struct Selection {
    pub(crate) action_path: Vec<String>,
    pub(crate) state_path: Vec<String>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Action {
    pub(crate) name: String,
    pub(crate) arguments: BTreeMap<String, Value>,
}

#[derive(Debug, PartialEq, Eq)]
pub(crate) struct TraceStep {
    pub(crate) action: Action,
    pub(crate) expected: Value,
}

#[derive(Debug, PartialEq, Eq)]
pub(crate) enum ItfError {
    Empty,
    Invalid {
        step: Option<usize>,
        cause: &'static str,
    },
}

/// Decode an entire trace before a driver is allowed to perform an operation.
pub(crate) fn decode_trace(
    bytes: &[u8],
    selection: &Selection,
) -> Result<Vec<TraceStep>, ItfError> {
    let invalid = |cause| ItfError::Invalid { step: None, cause };
    let text = std::str::from_utf8(bytes).map_err(|_| invalid("invalid UTF-8"))?;
    let doc = Document::parse(text).map_err(|error| match error {
        json::ParseError::Syntax => invalid("invalid JSON"),
        json::ParseError::Duplicate => invalid("invalid JSON tree"),
    })?;
    let envelope = doc
        .object(doc.root)
        .filter(|fields| !fields.contains_key("loop"))
        .ok_or_else(|| invalid("invalid ITF envelope"))?;
    let vars = envelope
        .get("vars")
        .and_then(|&id| doc.array(id))
        .ok_or_else(|| invalid("invalid ITF envelope"))?;
    let vars = vars
        .iter()
        .map(|&id| doc.text(id))
        .collect::<Option<Vec<_>>>()
        .ok_or_else(|| invalid("invalid ITF envelope"))?;
    let states = envelope
        .get("states")
        .and_then(|&id| doc.array(id))
        .ok_or_else(|| invalid("invalid ITF envelope"))?;
    if states.is_empty() {
        return Err(ItfError::Empty);
    }
    states
        .iter()
        .enumerate()
        .map(|(index, &id)| {
            decode_step(&doc, id, &vars, selection).map_err(|cause| ItfError::Invalid {
                step: Some(index),
                cause,
            })
        })
        .collect()
}

const ACTION: &str = "mbt::actionTaken";
const PICKS: &str = "mbt::nondetPicks";
type Fields = BTreeMap<String, NodeId>;

fn decode_step(
    doc: &Document,
    id: NodeId,
    vars: &[&str],
    selection: &Selection,
) -> Result<TraceStep, &'static str> {
    let fields = doc.object(id).ok_or("ITF state must be a record")?;
    if !vars.iter().all(|&var| fields.contains_key(var)) {
        return Err("ITF state omits a declared variable");
    }
    let (name, members) =
        operation(doc, id, fields, &selection.action_path).ok_or("invalid operation")?;
    let mut arguments = BTreeMap::new();
    for (key, &id) in members.into_iter().flatten() {
        let inner = match tagged(doc, id) {
            Some(("None", payload)) if empty_tuple(doc, payload) => continue,
            Some(("Some", payload)) => payload,
            _ => id,
        };
        arguments.insert(
            key.clone(),
            decode_value(doc, inner).ok_or("invalid operation argument")?,
        );
    }
    let expected = if selection.state_path.is_empty() {
        fields
            .iter()
            .filter(|(name, _)| !matches!(name.as_str(), "#meta" | ACTION | PICKS))
            .map(|(key, &id)| Some((key.clone(), decode_value(doc, id)?)))
            .collect::<Option<_>>()
            .map(Value::Record)
    } else {
        pick_path(doc, id, &selection.state_path).and_then(|id| decode_value(doc, id))
    }
    .ok_or("invalid expected value")?;
    Ok(TraceStep {
        action: Action {
            name: name.to_owned(),
            arguments,
        },
        expected,
    })
}

fn operation<'a>(
    doc: &'a Document,
    id: NodeId,
    fields: &'a Fields,
    path: &[String],
) -> Option<(&'a str, Option<&'a Fields>)> {
    if path.is_empty() {
        return Some((
            doc.text(*fields.get(ACTION)?)?,
            Some(record(doc, *fields.get(PICKS)?)?),
        ));
    }
    let (name, payload) = tagged(doc, pick_path(doc, id, path)?)?;
    if name.is_empty() {
        return None;
    }
    if empty_tuple(doc, payload) {
        return Some((name, None));
    }
    Some((name, Some(record(doc, payload)?)))
}

fn tagged(doc: &Document, id: NodeId) -> Option<(&str, NodeId)> {
    let fields = doc.object(id)?;
    if fields.len() != 2 {
        return None;
    }
    Some((doc.text(*fields.get("tag")?)?, *fields.get("value")?))
}

fn empty_tuple(doc: &Document, id: NodeId) -> bool {
    doc.object(id)
        .filter(|fields| fields.len() == 1)
        .and_then(|fields| fields.get("#tup"))
        .and_then(|&id| doc.array(id))
        .is_some_and(<[_]>::is_empty)
}

fn reserved(key: &str) -> bool {
    matches!(
        key,
        "#bigint" | "#tup" | "#set" | "#map" | "#unserializable"
    )
}

fn record(doc: &Document, id: NodeId) -> Option<&Fields> {
    doc.object(id)
        .filter(|fields| !fields.keys().any(|k| reserved(k)))
}

fn pick_path(doc: &Document, start: NodeId, path: &[String]) -> Option<NodeId> {
    path.iter()
        .try_fold(start, |id, key| record(doc, id)?.get(key).copied())
}

/// A fixture or trace value uses exactly the same decoding and normalization rules.
fn decode_value(doc: &Document, id: NodeId) -> Option<Value> {
    match &doc.nodes[id] {
        Node::Bool(value) => Some(Value::Bool(*value)),
        Node::Text(text) => Some(Value::Text(text.clone())),
        Node::Array(items) => items
            .iter()
            .map(|&i| decode_value(doc, i))
            .collect::<Option<_>>()
            .map(Value::List),
        Node::Object(fields) => {
            if let Some((tag, &payload)) = fields.iter().next().filter(|_| fields.len() == 1) {
                match tag.as_str() {
                    "#bigint" => {
                        let value = doc.text(payload)?;
                        let digits = value.strip_prefix('-').unwrap_or(value);
                        if digits.is_empty() || !digits.bytes().all(|digit| digit.is_ascii_digit())
                        {
                            return None;
                        }
                        return value.parse().ok().map(Value::Integer);
                    }
                    "#tup" => {
                        return doc
                            .array(payload)?
                            .iter()
                            .map(|&i| decode_value(doc, i))
                            .collect::<Option<_>>()
                            .map(Value::Tuple);
                    }
                    "#set" => {
                        return doc
                            .array(payload)?
                            .iter()
                            .map(|&i| decode_value(doc, i))
                            .collect::<Option<_>>()
                            .map(Value::Set);
                    }
                    "#map" => {
                        let mut map = BTreeMap::new();
                        for &pair in doc.array(payload)? {
                            let &[key, value] = doc.array(pair)? else {
                                return None;
                            };
                            if map
                                .insert(decode_value(doc, key)?, decode_value(doc, value)?)
                                .is_some()
                            {
                                return None;
                            }
                        }
                        return Some(Value::Map(map));
                    }
                    _ => {}
                }
            }
            record(doc, id)?
                .iter()
                .map(|(k, &v)| Some((k.clone(), decode_value(doc, v)?)))
                .collect::<Option<_>>()
                .map(Value::Record)
        }
        Node::Number | Node::Null => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use rstest::rstest;

    #[rstest]
    #[case::invalid_utf8(b"\xff", "invalid UTF-8")]
    #[case::bom(b"\xef\xbb\xbf{}", "invalid JSON")]
    #[case::isolated_surrogate(br#"{"vars":[],"states":[],"unused":"\uD800"}"#, "invalid JSON")]
    #[case::decoded_duplicate(br#"{"vars":[],"states":[],"v":0,"\u0076":1}"#, "invalid JSON tree")]
    fn rejects_invalid_trace(#[case] bytes: &[u8], #[case] cause: &'static str) {
        let selection = Selection::default();

        let error = decode_trace(bytes, &selection).unwrap_err();

        assert_eq!(error, ItfError::Invalid { step: None, cause });
    }

    #[test]
    fn accepts_large_exponent_in_unselected_metadata() {
        let bytes = br##"{"vars":["n"],"states":[{"n":{"#bigint":"-00"},"mbt::actionTaken":"","mbt::nondetPicks":{}}],"unused":1e900000000000000000000000}"##;
        let selection = Selection {
            state_path: vec!["n".into()],
            ..Selection::default()
        };

        let trace = decode_trace(bytes, &selection).unwrap();

        assert_eq!(
            trace,
            vec![TraceStep {
                action: Action {
                    name: String::new(),
                    arguments: BTreeMap::new()
                },
                expected: Value::Integer(0.into()),
            }]
        );
    }

    #[test]
    fn accepts_deep_unselected_metadata() {
        let metadata = format!("{}0{}", "[".repeat(150), "]".repeat(150));
        let bytes = format!(r#"{{"vars":[],"states":[],"unused":{metadata}}}"#);

        let error = decode_trace(bytes.as_bytes(), &Selection::default()).unwrap_err();

        assert_eq!(error, ItfError::Empty);
    }
}
