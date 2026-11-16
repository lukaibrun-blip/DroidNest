#!/bin/bash
# DroidNest's own checks. The decisions the app makes -- which game to open, what it remembers, what it refuses to import,
# and when three fingers held down mean "back to your games" -- are Swift with no UIKit in them, so they compile and run on a
# Mac with no simulator, no signing and no iPhone.
#
# Usage: ./tests/solo/run.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

# Top-level code is only allowed in a file called main.swift, and these checks are top-level on purpose: no test framework to
# bring in, and the file reads in order.
cp "$ROOT/tests/solo/solo_core_test.swift" "$OUT/main.swift"

echo "==> compiling DroidNest's core and its checks"
swiftc -O -o "$OUT/solo_core_test" \
    "$ROOT/src/app/DroidNest/SoloCore.swift" \
    "$OUT/main.swift"

echo "==> running them"
"$OUT/solo_core_test"
