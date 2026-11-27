use num_bigint::BigInt;
use std::collections::{BTreeMap, BTreeSet};

#[derive(Debug)]
pub enum Value {
    Bool(bool),
    Integer(BigInt),
    Text(String),
    List(Vec<Self>),
    Tuple(Vec<Self>),
    Record(BTreeMap<String, Self>),
    Set(BTreeSet<Self>),
    Map(BTreeMap<Self, Self>),
}

pub fn with_stack<T>(operation: impl FnOnce() -> T) -> T {
    stacker::maybe_grow(64 * 1024, 2 * 1024 * 1024, operation)
}

impl Value {
    const fn kind(&self) -> u8 {
        match self {
            Self::Bool(_) => 0,
            Self::Integer(_) => 1,
            Self::Text(_) => 2,
            Self::List(_) => 3,
            Self::Tuple(_) => 4,
            Self::Record(_) => 5,
            Self::Set(_) => 6,
            Self::Map(_) => 7,
        }
    }

    fn take_children(&mut self, pending: &mut Vec<Self>) {
        match self {
            Self::List(values) | Self::Tuple(values) => pending.append(values),
            Self::Record(fields) => pending.extend(std::mem::take(fields).into_values()),
            Self::Set(values) => pending.extend(std::mem::take(values)),
            Self::Map(entries) => {
                for (key, value) in std::mem::take(entries) {
                    pending.push(key);
                    pending.push(value);
                }
            }
            Self::Bool(_) | Self::Integer(_) | Self::Text(_) => {}
        }
    }
}

impl Clone for Value {
    fn clone(&self) -> Self {
        with_stack(|| match self {
            Self::Bool(value) => Self::Bool(*value),
            Self::Integer(value) => Self::Integer(value.clone()),
            Self::Text(value) => Self::Text(value.clone()),
            Self::List(values) => Self::List(values.clone()),
            Self::Tuple(values) => Self::Tuple(values.clone()),
            Self::Record(fields) => Self::Record(fields.clone()),
            Self::Set(values) => Self::Set(values.clone()),
            Self::Map(values) => Self::Map(values.clone()),
        })
    }
}

impl Ord for Value {
    fn cmp(&self, other: &Self) -> std::cmp::Ordering {
        with_stack(|| match (self, other) {
            (Self::Bool(a), Self::Bool(b)) => a.cmp(b),
            (Self::Integer(a), Self::Integer(b)) => a.cmp(b),
            (Self::Text(a), Self::Text(b)) => a.cmp(b),
            (Self::List(a), Self::List(b)) | (Self::Tuple(a), Self::Tuple(b)) => a.cmp(b),
            (Self::Record(a), Self::Record(b)) => a.cmp(b),
            (Self::Set(a), Self::Set(b)) => a.cmp(b),
            (Self::Map(a), Self::Map(b)) => a.cmp(b),
            _ => self.kind().cmp(&other.kind()),
        })
    }
}

impl PartialOrd for Value {
    fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
        Some(self.cmp(other))
    }
}

impl PartialEq for Value {
    fn eq(&self, other: &Self) -> bool {
        self.cmp(other).is_eq()
    }
}

impl Eq for Value {}

impl Drop for Value {
    fn drop(&mut self) {
        // Empty each descendant before dropping it, including map keys.
        let mut pending = Vec::new();
        self.take_children(&mut pending);
        while let Some(mut child) = pending.pop() {
            child.take_children(&mut pending);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;

    proptest! {
        #[test]
        fn set_equality_ignores_order_and_duplicate_compound_values(values in prop::collection::vec(any::<i64>(), 0..20)) {
            let make = |value: i64| Value::List(vec![Value::Integer(value.into())]);
            let forward = Value::Set(values.iter().copied().map(make).collect());

            let reordered = Value::Set(values.iter().rev().chain(&values).copied().map(make).collect());

            prop_assert_eq!(forward, reordered);
        }
    }

    #[test]
    fn map_keys_keep_boolean_and_integer_distinct() {
        let keys = [Value::Bool(true), Value::Integer(1.into())];

        let map: BTreeMap<_, _> = keys
            .into_iter()
            .map(|key| (key, Value::Bool(false)))
            .collect();

        assert_eq!(map.len(), 2);
    }
}
