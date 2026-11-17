#!/bin/bash
# Build libdroidnest_core.a: DroidNest's own decisions, in Rust (src/droidnest-core).
#
# Only the DroidNest target links it. It is a staticlib for arm64 iOS, and it is
# `no_std`: the app already links one Rust library (libhusk_rppairing.a, for
# built-in StikJIT's pairing), and two copies of std in one binary is a linker
# problem for no benefit -- this crate is a pair of pure functions over bytes.
#
# The same crate's checks run on any machine with `cargo test`, with no Xcode and
# no iPhone: tests/core/run.sh does exactly that, and CI runs it before building.
set -euo pipefail

HUSK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CRATE="$HUSK_ROOT/src/droidnest-core"
OUT="$HUSK_ROOT/build/ios-arm64/lib"
TARGET=aarch64-apple-ios
# Match the app's deployment target, or the linker warns on every object.
export IPHONEOS_DEPLOYMENT_TARGET=15.5

cd "$CRATE"
if ! rustup target list --installed 2>/dev/null | grep -qx "$TARGET"; then
    echo "==> adding the $TARGET target"
    rustup target add "$TARGET"
fi

cargo build --release --target "$TARGET"
mkdir -p "$OUT"
cp "target/$TARGET/release/libdroidnest_core.a" "$OUT/libdroidnest_core.a"
echo "-> build/ios-arm64/lib/libdroidnest_core.a"
