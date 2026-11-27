"""Export deterministic runner fixtures from Quint or check an adapter against them."""

import argparse
import difflib
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

# Quint's exported JSON includes heterogeneous model values.
Json = Any

ROOT = Path(__file__).resolve().parents[1]
SPEC = ROOT / "spec" / "quint_conformance.qnt"
FIXTURES = ROOT / "spec" / "fixtures" / "runner-conformance.json"
SCHEMA_VERSION = 2
BACKENDS = ("typescript", "rust")
EVENTS = {
    "CommandPrepared",
    "WorkspaceReserved",
    "ProcessStarted",
    "ProcessExitedSuccessfully",
    "ProcessIoFailed",
    "ChildExitConfirmed",
    "GenerationCompleted",
    "SavedReadAttempted",
    "GeneratedReadAttempted",
    "FactoryCalled",
    "DriverCreated",
    "OperationCalled",
    "DriverArgumentsChanged",
    "ObservationCalled",
    "ArtifactDirectoryTried",
    "SaveAttempted",
    "CleanupAttempted",
    "WorkspaceCleanupDeferred",
}


def canonical_json(value: object) -> str:
    """Serialize a JSON value for comparison or ordering."""
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def render_json(value: object) -> str:
    """Serialize a fixture with compact byte arrays."""
    text = json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2)
    # Keep numeric arrays (file contents and process output) on one line.
    return (
        re.sub(
            r"\[\n(?: +[0-9]{1,3},?\n)+ +\]",
            lambda match: json.dumps(json.loads(match.group())),
            text,
        )
        + "\n"
    )


def normalize_itf(value: Json, *, unpack_integers: bool = False) -> Json:
    """Order ITF sets and maps while preserving the order of plain arrays."""
    if isinstance(value, list):
        return [normalize_itf(item, unpack_integers=unpack_integers) for item in value]
    if not isinstance(value, dict):
        return value
    if unpack_integers and value.keys() == {"#bigint"}:
        return int(value["#bigint"])

    normalized = {
        key: normalize_itf(item, unpack_integers=unpack_integers)
        for key, item in value.items()
    }
    if normalized.keys() == {"#set"} or normalized.keys() == {"#map"}:
        ((tag, contents),) = normalized.items()
        if isinstance(contents, list):
            normalized[tag] = sorted(contents, key=canonical_json)
    return normalized


def from_code_points(points: list[int]) -> str:
    """Convert Quint's Unicode scalar sequence to text."""
    return "".join(chr(point) for point in points)


def itf_value(graph: dict[str, Json]) -> Json:  # noqa: C901 - A branch per value tag.
    """Render the reachable portion of a Quint Value graph as one ITF value."""
    nodes = graph["nodes"]

    def read(index: int) -> Json:  # noqa: PLR0911 - One result per value tag.
        if index < 0 or index >= len(nodes):
            msg = f"Invalid value reference {index}"
            raise ValueError(msg)
        node = nodes[index]
        value = node["value"]
        match node["tag"]:
            case "BooleanNode":
                return value
            case "IntegerNode":
                digits = "".join(str(digit) for digit in value["digits"])
                return {"#bigint": ("-" if value["negative"] else "") + digits}
            case "TextNode":
                return from_code_points(value)
            case "ListNode":
                return [read(child) for child in value]
            case "TupleNode":
                return {"#tup": [read(child) for child in value]}
            case "RecordNode":
                return {
                    from_code_points(key): read(child) for key, child in value["#map"]
                }
            case "SetNode":
                return {
                    "#set": sorted((read(child) for child in value), key=canonical_json)
                }
            case "MapNode":
                pairs = [[read(child) for child in pair["#tup"]] for pair in value]
                return {"#map": sorted(pairs, key=canonical_json)}
            case _:
                msg = f"Cannot export Quint value node {node['tag']}"
                raise ValueError(msg)

    return read(graph["root"])


def project(value: Json) -> Json:  # noqa: C901, PLR0911, PLR0912 - Protocol projection.
    """Translate model records to the fixture schema without deriving any outcomes."""
    if isinstance(value, list):
        return [project(item) for item in value]
    if not isinstance(value, dict):
        return value
    if value.keys() == {"nodes", "root"}:
        return itf_value(value)
    if value.keys() == {"actionPath", "statePath"}:
        return {
            key: [from_code_points(segment) for segment in path]
            for key, path in value.items()
        }
    if value.keys() == {"name", "trace", "bytes"}:
        return {**value, "name": "".join(value["name"])}
    if value.keys() == {"tag", "value"}:
        tag, payload = value["tag"], value["value"]
        if payload == {"#tup": []}:
            payload = None
        elif tag == "MatchOption":
            payload = from_code_points(payload)
        else:
            payload = project(payload)
        return {"tag": tag, "value": payload}
    result: dict[str, Json] = {}
    for key, item in value.items():
        if key == "arguments":
            result[key] = {
                from_code_points(name): itf_value(argument)
                for name, argument in item["#map"]
            }
        elif key == "name" and "arguments" in value:
            result[key] = from_code_points(item)
        else:
            result[key] = project(item)
    if "basename" in result:
        result["basename"] = "".join(result["basename"])
    if "basenames" in result:
        result["basenames"] = {
            "#map": [
                [trace, "".join(name)] for trace, name in result["basenames"]["#map"]
            ]
        }
    return result


def state_variable(state: dict[str, Json], name: str) -> Json:
    """Read a state field by its unqualified Quint name."""
    (value,) = [value for key, value in state.items() if key.split("::")[-1] == name]
    return normalize_itf(value, unpack_integers=True)


def project_file(path: Json, contents: list[int]) -> dict[str, Json]:
    """Project a modeled path and its bytes."""
    return {"path": project(path), "bytes": contents}


def fixture_case(trace_file: Path) -> dict[str, Json]:
    """Read one exported scenario and its expected result."""
    trace = json.loads(trace_file.read_text(encoding="utf-8"))
    initial, terminal = trace["states"][0], trace["states"][-1]
    schedule = [
        {"call_id": entry["callId"], "input": project(entry["input"])}
        for entry in state_variable(terminal, "schedule")
    ]
    requests = {
        entry["call_id"]: entry["input"]["value"]
        for entry in schedule
        if entry["input"]["tag"] == "Start"
    }
    call_states = dict(state_variable(terminal, "calls")["#map"])
    calls = []
    for call_id in sorted(requests):
        call = call_states[call_id]
        if call["phase"]["tag"] != "Finished":
            msg = f"Call {call_id} did not finish: {trace_file.name}"
            raise ValueError(msg)
        calls.append(
            {
                "call_id": call_id,
                "events": [
                    project(event)
                    for event in call["history"]
                    if event["tag"] in EVENTS
                ],
                "outcome": project(call["phase"]["value"]),
            }
        )
    paths = {
        path
        for request in requests.values()
        if request["tag"] == "ReplayPaths"
        for path in request["value"]["paths"]
    }
    input_files = [
        project_file(path, contents)
        for path, contents in state_variable(initial, "filesystem")["files"]["#map"]
        if path["tag"] == "SavedFile" and path["value"] in paths
    ]
    final_files = state_variable(terminal, "filesystem")["files"]["#map"]
    return {
        "name": trace_file.name.removeprefix("case-").removesuffix("Test.itf.json"),
        "schedule": schedule,
        "input_files": input_files,
        "expected": {
            "calls": calls,
            "saved_files": [
                project_file(path, contents)
                for path, contents in final_files
                if path["tag"] == "EvidenceFile"
            ],
            "remaining_workspace_files": [
                project_file(path, contents)
                for path, contents in final_files
                if path["tag"] == "WorkingFile"
            ],
        },
    }


def export(backend: str) -> dict[str, Json]:
    """Generate fixture data with one Quint evaluator."""
    with tempfile.TemporaryDirectory(prefix=f"quint-fixtures-{backend}-") as scratch:
        result = subprocess.run(
            [
                "quint",
                "test",
                str(SPEC),
                "--backend",
                backend,
                "--seed",
                "1",
                "--max-samples",
                "1",
                "--out-itf",
                str(Path(scratch) / "case-{test}.itf.json"),
            ],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
        )
        if result.returncode:
            msg = f"Quint {backend} scenarios failed\n{result.stdout}{result.stderr}"
            raise ValueError(msg)
        traces = sorted(Path(scratch).glob("case-*Test.itf.json"))
        if not traces:
            msg = f"Quint {backend} emitted no conformance traces"
            raise ValueError(msg)
        return {
            "schema_version": SCHEMA_VERSION,
            "cases": [fixture_case(path) for path in traces],
        }


def require_equal(
    expected: str, actual: str, expected_label: str, actual_label: str
) -> None:
    """Report any output difference as a unified diff."""
    if expected != actual:
        diff = difflib.unified_diff(
            expected.splitlines(keepends=True),
            actual.splitlines(keepends=True),
            fromfile=expected_label,
            tofile=actual_label,
        )
        raise ValueError("".join(diff).rstrip())


def check_adapter(command: list[str]) -> None:
    """Drive an adapter with inputs and compare its output with the model."""
    fixture = json.loads(FIXTURES.read_text(encoding="utf-8"))
    if fixture["schema_version"] != SCHEMA_VERSION:
        msg = f"Unsupported fixture schema version {fixture['schema_version']}"
        raise ValueError(msg)
    for case in fixture["cases"]:
        inputs = {key: value for key, value in case.items() if key != "expected"}
        inputs["schema_version"] = SCHEMA_VERSION
        result = subprocess.run(
            command,
            input=canonical_json(inputs) + "\n",
            check=False,
            capture_output=True,
            text=True,
            encoding="utf-8",
        )
        if result.returncode:
            msg = (
                f"Adapter failed for {case['name']} (exit {result.returncode})\n"
                f"{result.stderr}"
            )
            raise ValueError(msg)
        try:
            actual = normalize_itf(json.loads(result.stdout))
        except ValueError as error:
            msg = f"Adapter output for {case['name']} is invalid JSON: {error}"
            raise ValueError(msg) from error
        require_equal(
            render_json(case["expected"]),
            render_json(actual),
            case["name"],
            "adapter output",
        )
    print(f"Adapter matched all {len(fixture['cases'])} conformance cases.")


def main() -> int:
    """Export fixtures, verify fixture freshness, or check an adapter."""
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--check",
        action="store_true",
        help="compare both Quint backends with the checked-in JSON",
    )
    mode.add_argument(
        "--adapter",
        nargs=argparse.REMAINDER,
        metavar="COMMAND",
        help="run a command per fixture with inputs on stdin and results on stdout",
    )
    args = parser.parse_args()
    if args.adapter == []:
        parser.error("--adapter requires a command")

    try:
        if args.adapter:
            check_adapter(args.adapter)
            return 0

        typescript = export(BACKENDS[0])
        expected = render_json(typescript)
        require_equal(
            expected, render_json(export(BACKENDS[1])), BACKENDS[0], BACKENDS[1]
        )
        if args.check:
            require_equal(
                FIXTURES.read_text(encoding="utf-8"),
                expected,
                str(FIXTURES),
                "Quint export",
            )
        else:
            FIXTURES.parent.mkdir(parents=True, exist_ok=True)
            FIXTURES.write_text(expected, encoding="utf-8")
        print(
            f"Both Quint backends agree on {len(typescript['cases'])} cases in "
            f"{FIXTURES.relative_to(ROOT)}."
        )
    except (OSError, ValueError) as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
