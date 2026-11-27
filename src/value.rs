use num_bigint::BigInt;
use std::collections::{BTreeMap, BTreeSet};

#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub(crate) enum Value {
    Bool(bool),
    Integer(BigInt),
    Text(String),
    List(Vec<Value>),
    Tuple(Vec<Value>),
    Record(BTreeMap<String, Value>),
    Set(BTreeSet<Value>),
    Map(BTreeMap<Value, Value>),
}
