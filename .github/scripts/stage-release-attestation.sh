#!/usr/bin/env bash
set -euo pipefail

files=(dist/*)
test "${#files[@]}" = 1
file="${files[0]}"
gh attestation verify "$file" --bundle "$BUNDLE" --repo "$GITHUB_REPOSITORY" \
  --signer-workflow "$GITHUB_REPOSITORY/.github/workflows/release.yml" \
  --source-digest "$GITHUB_SHA" --signer-digest "$GITHUB_SHA" --deny-self-hosted-runners
uv run --locked --no-sync pypi-attestations convert "$BUNDLE" --output-file "$file.slsa.attestation"
