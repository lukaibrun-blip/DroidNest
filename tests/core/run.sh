#!/bin/bash
# DroidNest's Rust core checks (src/droidnest-core): cargo test, on whatever machine this is.
#
# No Xcode, no simulator, no iPhone: the crate is `no_std` and allocation-free, and its tests only need a Rust
# toolchain. This is the half of DroidNest's behaviour that can be proven anywhere -- what an import is, and why the
# last run stopped -- so it runs before the app is built, in CI and by hand.
#
# Usage: ./tests/core/run.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT/src/droidnest-core"

if ! command -v cargo >/dev/null 2>&1; then
    echo "cargo not found: install Rust (https://rustup.rs) to run DroidNest's core checks" >&2
    exit 1
fi

echo "==> cargo test (src/droidnest-core)"
cargo test --quiet
