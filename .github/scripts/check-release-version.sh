#!/usr/bin/env bash
set -euo pipefail

version=$(python3 -c 'import tomllib; from pathlib import Path; p, c = (tomllib.loads(Path(f).read_text()) for f in ("pyproject.toml", "Cargo.toml")); assert p["project"]["version"] == c["package"]["version"]; print(p["project"]["version"])')
[[ "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]
echo "version=$version" >> "$GITHUB_OUTPUT"
if [[ -n "$PUBLISH_VERSION" ]]; then
  test "$PUBLISH_VERSION" = "$version"
  test "$GITHUB_REPOSITORY" = HayaoSuzuki/quint-connect-py
  test "$GITHUB_REF" = refs/heads/main
  test "$(gh run list --workflow ci.yml --branch main --commit "$GITHUB_SHA" --event push --status success --limit 1 --json databaseId --jq length)" = 1
  echo "publish=true" >> "$GITHUB_OUTPUT"
fi
