import json
import os
import subprocess
import sys
from pathlib import Path
from shutil import which

import pytest


def test_same_seed_artifacts_survive_two_workers(tmp_path: Path) -> None:
    if which("quint") is None:
        pytest.skip("requires Quint 0.34.0 on PATH")
    shared = tmp_path / "artifacts"
    shared.mkdir()
    environment = {**os.environ, "QUINT_TEST_SHARED_ARTIFACT_DIR": str(shared)}
    scenario = Path(__file__).with_name("test_quint_integration.py")
    command = [
        sys.executable,
        "-m",
        "pytest",
        "-q",
        "-n",
        "2",
        "--dist=each",
        f"{scenario}::test_generated_mismatch_can_be_replayed",
    ]

    # Run the same scenario to completion in two independent worker processes.
    completed = subprocess.run(  # noqa: S603 - Uses this interpreter and a fixed test.
        command,
        env=environment,
        capture_output=True,
        text=True,
        check=False,
        timeout=60,
    )

    assert completed.returncode == 0, completed.stdout + completed.stderr
    saved = sorted(shared.glob("*/trace_*.itf.json"))
    assert len(saved) == 2
    first, second = saved
    assert first.parent != second.parent
    # Quint includes generation time in the metadata of each trace.
    assert (
        json.loads(first.read_bytes())["states"]
        == json.loads(second.read_bytes())["states"]
    )
