"""Validate release files and verify each distribution published to an index."""

import argparse
import http
import os
import re
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path
from shutil import which

from pydantic import BaseModel
from pypi_attestations import Distribution, GitHubPublisher, Provenance

PROJECT = "quint-connect-py"
REPOSITORY = "HayaoSuzuki/quint-connect-py"
WORKFLOW = "release.yml"
SLSA = "https://slsa.dev/provenance/v1"
PUBLISH = "https://docs.pypi.org/attestations/publish/v1"
INDEXES = {
    "pypi": ("https://pypi.org", "files.pythonhosted.org"),
    "testpypi": ("https://test.pypi.org", "test-files.pythonhosted.org"),
}
VERSION = re.compile(r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)")


class IndexFile(BaseModel):
    """The name and download URL of a published distribution."""

    filename: str
    url: str


class IndexRelease(BaseModel):
    """The complete inventory reported by an index for one version."""

    urls: list[IndexFile]


def release_files(version: str, directory: Path) -> list[Path]:
    """Require a single source archive and one wheel per supported platform."""
    if VERSION.fullmatch(version) is None:
        message = f"invalid release version {version}"
        raise ValueError(message)

    project_version = f"quint_connect_py-{version}"
    assets = sorted([*directory.glob("*.whl"), *directory.glob("*.tar.gz")])
    patterns = (
        f"{project_version}.tar.gz",
        f"{project_version}-cp314-abi3-manylinux*x86_64.whl",
        f"{project_version}-cp314-abi3-macosx_*_arm64.whl",
        f"{project_version}-cp314-abi3-win_amd64.whl",
    )
    if len(assets) != len(patterns) or any(
        len(list(directory.glob(pattern))) != 1 for pattern in patterns
    ):
        message = f"unexpected release inventory: {[path.name for path in assets]}"
        raise ValueError(message)
    return assets


def download(url: str) -> bytes:
    """Fetch bytes from one of the configured HTTPS index or file hosts."""
    with urllib.request.urlopen(url, timeout=60) as response:  # noqa: S310
        payload = response.read()
    if not isinstance(payload, bytes):
        message = "expected bytes from the package index"
        raise TypeError(message)
    return payload


def verify_build(asset: Path, bundle: Path, commit: str) -> None:
    """Verify the bound source and signer's workflow against the release commit."""
    gh = which("gh")
    if gh is None:
        message = "gh is required to verify the build attestation"
        raise FileNotFoundError(message)
    subprocess.run(  # noqa: S603 - Resolved executable and fixed argv.
        [
            gh,
            "attestation",
            "verify",
            str(asset),
            "--bundle",
            str(bundle),
            "--repo",
            REPOSITORY,
            "--signer-workflow",
            f"{REPOSITORY}/.github/workflows/{WORKFLOW}",
            "--source-digest",
            commit,
            "--signer-digest",
            commit,
            "--deny-self-hosted-runners",
            "--predicate-type",
            SLSA,
        ],
        check=True,
        timeout=120,
    )


def verify_provenance(
    asset: Path,
    provenance: Provenance,
    index: str,
    commit: str,
) -> None:
    """Check both signatures, their publisher and the source of the build."""
    (bundle,) = provenance.attestation_bundles
    publisher = bundle.publisher
    if not isinstance(publisher, GitHubPublisher) or (
        publisher.repository,
        publisher.workflow,
        publisher.environment,
    ) != (REPOSITORY, WORKFLOW, index):
        message = f"unexpected {index} publisher for {asset.name}"
        raise ValueError(message)

    distribution = Distribution.from_file(asset)
    predicates = []
    for attestation in bundle.attestations:
        predicate, _ = attestation.verify(publisher, distribution)
        predicates.append(predicate)
        if predicate == SLSA:
            bundle_file = asset.with_name(f"{asset.name}.bundle.json")
            bundle_file.write_text(attestation.to_bundle().to_json(), encoding="utf-8")
            verify_build(asset, bundle_file, commit)
    if sorted(predicates) != sorted([SLSA, PUBLISH]):
        message = f"expected one build and one publish attestation for {asset.name}"
        raise ValueError(message)


def verify_index(
    index: str,
    version: str,
    assets: list[Path],
    commit: str,
) -> None:
    """Download the complete published release and compare it with the build."""
    base, files_host = INDEXES[index]
    release = IndexRelease.model_validate_json(
        download(f"{base}/pypi/{PROJECT}/{version}/json")
    )
    records = {record.filename: record for record in release.urls}
    if len(release.urls) != len(assets) or records.keys() != {
        asset.name for asset in assets
    }:
        message = f"published inventory on {index} differs from the build"
        raise ValueError(message)
    with tempfile.TemporaryDirectory(prefix="quint-index-") as directory:
        for asset in assets:
            url = records[asset.name].url
            if not url.startswith(f"https://{files_host}/packages/"):
                message = f"unexpected download URL for {asset.name}"
                raise ValueError(message)
            published = download(url)
            if published != asset.read_bytes():
                message = f"published bytes differ from the build for {asset.name}"
                raise ValueError(message)
            downloaded = Path(directory) / asset.name
            downloaded.write_bytes(published)
            endpoint = f"{base}/integrity/{PROJECT}/{version}/{asset.name}/provenance"
            provenance = Provenance.model_validate_json(download(endpoint))
            verify_provenance(downloaded, provenance, index, commit)


def verify_with_propagation(
    index: str,
    version: str,
    assets: list[Path],
    commit: str,
) -> None:
    """Allow the index to propagate a freshly uploaded release."""
    deadline = time.monotonic() + 300
    delay = 5
    while True:
        try:
            verify_index(index, version, assets, commit)
        except urllib.error.HTTPError as error:
            if error.code != http.HTTPStatus.NOT_FOUND or time.monotonic() >= deadline:
                raise
            time.sleep(delay)
            delay = min(delay * 2, 30)
        else:
            return


def main() -> None:
    """Validate a local build inventory or verify an upload."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("files", *INDEXES))
    parser.add_argument("version")
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    assets = release_files(args.version, args.directory)
    if args.mode != "files":
        verify_with_propagation(
            args.mode, args.version, assets, os.environ["GITHUB_SHA"]
        )


if __name__ == "__main__":
    main()
