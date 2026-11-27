#!/usr/bin/env bash
set -euo pipefail

rustup toolchain install "$RUSTUP_TOOLCHAIN" --profile minimal
uvx --from "maturin==$MATURIN_VERSION" maturin sdist --out dist
git diff --exit-code -- Cargo.lock
tar -xzf dist/*.tar.gz -C "$RUNNER_TEMP"
source_tree=("$RUNNER_TEMP"/quint_connect_py-*/)
test "${#source_tree[@]}" = 1
uvx --from "maturin==$MATURIN_VERSION" maturin build --release --locked \
  --manifest-path "${source_tree[0]}Cargo.toml" --compatibility linux \
  --interpreter python --out "$RUNNER_TEMP/sdist-wheel"
wheels=("$RUNNER_TEMP"/sdist-wheel/*.whl)
test "${#wheels[@]}" = 1
python tools/check_wheel.py "${wheels[0]}"
