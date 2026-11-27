"""Check the package metadata and replay a trace from a built wheel."""

import argparse
import subprocess
import tempfile
from email.parser import BytesParser
from pathlib import Path
from shutil import which
from zipfile import ZipFile

SMOKE = """
import os
from pathlib import Path
from shutil import which

os.environ["PATH"] = ""
import quint_connect
import quint_connect._native

Path("trace.itf.json").write_bytes(
    b'{"vars":["n"],"states":[{"n":true,"mbt::actionTaken":"init","mbt::nondetPicks":{}}]}'
)

class Driver:
    def step(self, action):
        assert action.name == "init"

    def observe(self):
        return True

quint_connect.replay("trace.itf.json", Driver, state_path=("n",))
"""


def check_metadata(wheel: Path) -> None:
    """Check the ABI tag and distribution metadata before installing the wheel."""
    with ZipFile(wheel) as archive:
        (path,) = (
            name for name in archive.namelist() if name.endswith(".dist-info/METADATA")
        )
        metadata = BytesParser().parsebytes(archive.read(path))
        license_file = f"{path.rsplit('/', 1)[0]}/licenses/LICENSE"
        requirements = metadata["Requires-Python"]
        if (
            metadata["License-Expression"] != "Apache-2.0"
            or requirements is None
            or {bound.strip() for bound in requirements.split(",")}
            != {">=3.14", "<3.16"}
        ):
            message = f"unexpected license or Python version metadata in {wheel.name}"
            raise ValueError(message)
        if (
            metadata.get_all("Requires-Dist") is not None
            or license_file not in archive.namelist()
        ):
            message = f"unexpected dependencies or missing license in {wheel.name}"
            raise ValueError(message)
        if (
            "-cp314-abi3-" not in wheel.name
            or "quint_connect/py.typed" not in archive.namelist()
        ):
            message = f"unexpected ABI or missing type marker in {wheel.name}"
            raise ValueError(message)


def check_wheel(wheel: Path) -> None:
    """Exercise a single installed distribution on both Python versions."""
    wheel = wheel.resolve()
    check_metadata(wheel)
    launcher = which("uv")
    if launcher is None:
        message = "uv is required to create isolated wheel test environments"
        raise FileNotFoundError(message)
    executable = Path(launcher).resolve()
    with tempfile.TemporaryDirectory(prefix="quint-wheel-") as directory:
        for version in ("3.14", "3.15"):
            # A local wheel is the sole package installed in each isolated environment.
            subprocess.run(  # noqa: S603 - Installs a local wheel into an isolated venv.
                [
                    str(executable),
                    "run",
                    "--offline",
                    "--isolated",
                    "--no-project",
                    "--python",
                    version,
                    "--with",
                    str(wheel),
                    "python",
                    "-I",
                    "-c",
                    SMOKE,
                ],
                cwd=directory,
                check=True,
            )


def main() -> None:
    """Read the wheel path and run all release smoke checks."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("wheel", type=Path)
    args = parser.parse_args()
    check_wheel(args.wheel)


if __name__ == "__main__":
    main()
