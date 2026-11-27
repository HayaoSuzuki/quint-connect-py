use std::sync::Arc;

use pyo3::prelude::*;

use crate::replay::{ReplayEvent, ReplayReporter};

use super::value::Types;

pub(super) fn reporter(types: Arc<Types>, log_steps: bool) -> ReplayReporter {
    Box::new(move |event| {
        if matches!(
            event,
            ReplayEvent::Factory(_) | ReplayEvent::DriverCreated(_)
        ) || (!log_steps && !matches!(event, ReplayEvent::Read(_)))
        {
            return;
        }
        // Diagnostics may be dropped, for example if a custom logging handler raises.
        let _ = Python::attach(|py| -> PyResult<()> {
            let diagnostics = py.import("quint_connect._diagnostics")?;
            match event {
                ReplayEvent::Read(trace) => diagnostics
                    .call_method1("trace_started", (trace.index, trace.display_path.as_path()))?,
                ReplayEvent::Apply(trace, index, action) => diagnostics.call_method1(
                    "step_started",
                    (trace.index, index, types.action(py, action)?),
                )?,
                ReplayEvent::Observe(trace, index, value) => diagnostics.call_method1(
                    "expected_state",
                    (trace.index, index, types.write(py, value)?),
                )?,
                ReplayEvent::Observed(trace, index, value) => diagnostics.call_method1(
                    "observed_state",
                    (trace.index, index, types.write(py, value)?),
                )?,
                ReplayEvent::Factory(_) | ReplayEvent::DriverCreated(_) => return Ok(()),
            };
            Ok(())
        });
    })
}

pub(super) fn state_diff(expected: &Bound<'_, PyAny>, actual: &Bound<'_, PyAny>) -> String {
    expected
        .py()
        .import("quint_connect._diagnostics")
        .and_then(|diagnostics| diagnostics.call_method1("state_diff", (expected, actual)))
        .and_then(|diff| diff.extract::<String>())
        .unwrap_or_default()
}
