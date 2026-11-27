#!/usr/bin/env bash
set -euo pipefail

docker run --rm --volume "$PWD:/io" --workdir /io \
  --env RUSTUP_TOOLCHAIN --env CARGO_TARGET_DIR=/tmp/wheel-target \
  --entrypoint /bin/bash "$MATURIN_IMAGE" -euc '
    rustup toolchain install "$RUSTUP_TOOLCHAIN" --profile minimal
    maturin build --release --locked --compatibility manylinux2014 \
      --target x86_64-unknown-linux-gnu --out dist
  '
sudo chown -R "$(id -u):$(id -g)" dist
