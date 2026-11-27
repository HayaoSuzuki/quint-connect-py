#!/usr/bin/env bash
set -euo pipefail

npm ci --prefix spec --ignore-scripts --no-audit --no-fund
quint_home="$RUNNER_TEMP/quint"
# Quint 0.34.0 uses evaluator v0.8.0 and downloads it on first use.
evaluator_dir="$quint_home/rust-evaluator-v0.8.0"
asset="quint_evaluator-x86_64-unknown-linux-gnu.tar.gz"
archive="$RUNNER_TEMP/$asset"
curl --fail --silent --show-error --location --retry 3 --output "$archive" \
  "https://github.com/quint-co/quint/releases/download/evaluator/v0.8.0/$asset"
echo "774020b648a887f511d040fd564a8223c62a996b80f8dc50ea24d8630235be51  $archive" | sha256sum -c -
mkdir -p "$evaluator_dir"
tar -xzf "$archive" -C "$evaluator_dir" quint_evaluator
test -x "$evaluator_dir/quint_evaluator"
echo "QUINT_HOME=$quint_home" >> "$GITHUB_ENV"
echo "$GITHUB_WORKSPACE/spec/node_modules/.bin" >> "$GITHUB_PATH"
