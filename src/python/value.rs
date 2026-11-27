use std::collections::{BTreeMap, BTreeSet, HashSet};

use num_bigint::BigInt;
use pyo3::exceptions::PyTypeError;
use pyo3::prelude::*;
use pyo3::types::{PyBool, PyBytes, PyDict, PyInt, PyList, PyString, PyTuple};

use crate::itf::Action;
use crate::value::Value;

pub(super) struct Types {
    action: Py<PyAny>,
    set: Py<PyAny>,
    map: Py<PyAny>,
}

enum Shape {
    List,
    Tuple,
    Record(Vec<String>),
    Set,
    Map,
}

impl Types {
    pub(super) fn load(py: Python<'_>) -> PyResult<Self> {
        let module = PyModule::import(py, "quint_connect")?;
        Ok(Self {
            action: module.getattr("Action")?.unbind(),
            set: module.getattr("QuintSet")?.unbind(),
            map: module.getattr("QuintMap")?.unbind(),
        })
    }

    pub(super) fn action<'py>(
        &self,
        py: Python<'py>,
        action: &Action,
    ) -> PyResult<Bound<'py, PyAny>> {
        let arguments = PyDict::new(py);
        for (key, value) in &action.arguments {
            arguments.set_item(key, self.write(py, value)?)?;
        }
        self.action
            .bind(py)
            .call1((action.name.as_str(), arguments))
    }

    pub(super) fn write<'py>(&self, py: Python<'py>, value: &Value) -> PyResult<Bound<'py, PyAny>> {
        enum Task<'a> {
            Visit(&'a Value),
            Assemble(Shape, usize),
        }
        let mut pending = vec![Task::Visit(value)];
        let mut complete = Vec::new();
        while let Some(task) = pending.pop() {
            let value = match task {
                Task::Assemble(shape, count) => {
                    let children = complete.split_off(complete.len() - count);
                    complete.push(self.write_container(py, shape, children)?);
                    continue;
                }
                Task::Visit(value) => value,
            };
            let (shape, children): (_, Vec<_>) = match value {
                Value::Bool(value) => {
                    complete.push(PyBool::new(py, *value).to_owned().into_any());
                    continue;
                }
                Value::Integer(value) => {
                    let bytes = PyBytes::new(py, &value.to_signed_bytes_le());
                    complete.push(py.get_type::<PyInt>().call_method(
                        "from_bytes",
                        (bytes, "little"),
                        Some(&signed(py)?),
                    )?);
                    continue;
                }
                Value::Text(value) => {
                    complete.push(PyString::new(py, value).into_any());
                    continue;
                }
                Value::List(values) => (Shape::List, values.iter().collect()),
                Value::Tuple(values) => (Shape::Tuple, values.iter().collect()),
                Value::Record(values) => (
                    Shape::Record(values.keys().cloned().collect()),
                    values.values().collect(),
                ),
                Value::Set(values) => (Shape::Set, values.iter().collect()),
                Value::Map(values) => {
                    (Shape::Map, values.iter().flat_map(<[_; 2]>::from).collect())
                }
            };
            pending.push(Task::Assemble(shape, children.len()));
            pending.extend(children.into_iter().rev().map(Task::Visit));
        }
        complete.pop().ok_or_else(invalid_shape)
    }

    fn write_container<'py>(
        &self,
        py: Python<'py>,
        shape: Shape,
        children: Vec<Bound<'py, PyAny>>,
    ) -> PyResult<Bound<'py, PyAny>> {
        match shape {
            Shape::List => Ok(PyList::new(py, children)?.into_any()),
            Shape::Tuple => Ok(PyTuple::new(py, children)?.into_any()),
            Shape::Set => self.set.bind(py).call1((PyTuple::new(py, children)?,)),
            Shape::Map => self
                .map
                .bind(py)
                .call1((PyTuple::new(py, pairs(children)?)?,)),
            Shape::Record(keys) => {
                let object = PyDict::new(py);
                for (key, value) in keys.into_iter().zip(children) {
                    object.set_item(key, value)?;
                }
                Ok(object.into_any())
            }
        }
    }

    pub(super) fn read(&self, object: &Bound<'_, PyAny>) -> PyResult<Value> {
        enum Task<'py> {
            Visit(Bound<'py, PyAny>),
            Assemble(Shape, usize, Bound<'py, PyAny>),
        }
        let mut pending = vec![Task::Visit(object.clone())];
        let mut complete = Vec::new();
        let mut active = HashSet::new();
        while let Some(task) = pending.pop() {
            let object = match task {
                Task::Assemble(shape, count, owner) => {
                    let children = complete.split_off(complete.len() - count);
                    complete.push(read_values(shape, children)?);
                    active.remove(&(owner.as_ptr() as usize));
                    continue;
                }
                Task::Visit(object) => object,
            };
            if let Ok(value) = object.cast::<PyBool>() {
                complete.push(Value::Bool(value.is_true()));
            } else if let Ok(value) = object.cast::<PyInt>() {
                complete.push(Value::Integer(integer(value)?));
            } else if let Ok(value) = object.cast::<PyString>() {
                complete.push(Value::Text(value.to_str()?.to_owned()));
            } else {
                let address = object.as_ptr() as usize;
                if !active.insert(address) {
                    return Err(PyTypeError::new_err("cyclic Quint value"));
                }
                let (shape, children) = self.read_container(&object)?;
                pending.push(Task::Assemble(shape, children.len(), object));
                pending.extend(children.into_iter().rev().map(Task::Visit));
            }
        }
        complete.pop().ok_or_else(invalid_shape)
    }

    fn read_container<'py>(
        &self,
        object: &Bound<'py, PyAny>,
    ) -> PyResult<(Shape, Vec<Bound<'py, PyAny>>)> {
        if let Ok(list) = object.cast::<PyList>() {
            return Ok((Shape::List, list.iter().collect()));
        }
        if let Ok(tuple) = object.cast::<PyTuple>() {
            return Ok((Shape::Tuple, tuple.iter().collect()));
        }
        if let Ok(dict) = object.cast::<PyDict>() {
            let mut keys = Vec::with_capacity(dict.len());
            let mut children = Vec::with_capacity(dict.len());
            for (key, value) in dict.iter() {
                keys.push(key.extract::<String>()?);
                children.push(value);
            }
            return Ok((Shape::Record(keys), children));
        }
        if object.is_instance(self.set.bind(object.py()))? {
            let values = object.getattr("values")?;
            return Ok((Shape::Set, values.cast::<PyTuple>()?.iter().collect()));
        }
        if object.is_instance(self.map.bind(object.py()))? {
            let entries = object.getattr("entries")?;
            let mut children = Vec::new();
            for entry in entries.cast::<PyTuple>()?.iter() {
                let pair = entry.cast::<PyTuple>()?;
                if pair.len() != 2 {
                    return Err(PyTypeError::new_err("QuintMap requires key/value pairs"));
                }
                children.push(pair.get_item(0)?);
                children.push(pair.get_item(1)?);
            }
            return Ok((Shape::Map, children));
        }
        Err(PyTypeError::new_err("unsupported Quint observation value"))
    }
}

fn read_values(shape: Shape, children: Vec<Value>) -> PyResult<Value> {
    Ok(match shape {
        Shape::List => Value::List(children),
        Shape::Tuple => Value::Tuple(children),
        Shape::Set => Value::Set(children.into_iter().collect::<BTreeSet<_>>()),
        Shape::Record(keys) => Value::Record(keys.into_iter().zip(children).collect()),
        Shape::Map => {
            let mut map = BTreeMap::new();
            for (key, value) in pairs(children)? {
                if map.insert(key, value).is_some() {
                    return Err(PyTypeError::new_err("duplicate QuintMap key"));
                }
            }
            Value::Map(map)
        }
    })
}

fn pairs<T>(children: Vec<T>) -> PyResult<Vec<(T, T)>> {
    let mut pairs = Vec::with_capacity(children.len() / 2);
    let mut children = children.into_iter();
    while let Some(key) = children.next() {
        pairs.push((key, children.next().ok_or_else(invalid_shape)?));
    }
    Ok(pairs)
}

fn invalid_shape() -> PyErr {
    PyTypeError::new_err("invalid Quint value")
}

fn signed(py: Python<'_>) -> PyResult<Bound<'_, PyDict>> {
    let kwargs = PyDict::new(py);
    kwargs.set_item("signed", true)?;
    Ok(kwargs)
}

fn integer(value: &Bound<'_, PyInt>) -> PyResult<BigInt> {
    let py = value.py();
    let int = py.get_type::<PyInt>();
    let bits = int
        .getattr("bit_length")?
        .call1((value,))?
        .extract::<usize>()?;
    let bytes = int
        .getattr("to_bytes")?
        .call((value, bits / 8 + 1, "little"), Some(&signed(py)?))?;
    Ok(BigInt::from_signed_bytes_le(
        bytes.cast::<PyBytes>()?.as_bytes(),
    ))
}
