#!/bin/bash
# Build DroidNest (Husk Solo) and package one IPA, validating the bundle before shipping it.
#
# DroidNest is a target of the same project (docs/07-droidnest.md), so everything the shared sources need is built the same
# way Husk's are -- but this IPA carries no guest kernel and no download widget, and its JIT helper has its own name.
#
# No signing team is needed: AltStore / SideStore re-sign at install with the user's own profile. The IPA is signed ad hoc
# with the same entitlements embedded, which is what lets StikDebug or the built-in helper attach.
#
# Usage: ./scripts/package_droidnest_ipa.sh [output.ipa]
set -euo pipefail

DROIDNEST_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DD="${DD:-/tmp/droidnest_ipa}"
OUT="${1:-$HOME/Desktop/DroidNest.ipa}"
mkdir -p "$DD"

# A staged dylib older than the built one ships a build of QEMU nobody can find the source of. Same check as package_ipa.sh.
BUILT="$DROIDNEST_ROOT/third_party/build/qemu-10.0.12-utm/_husk_build/libqemu-aarch64-softmmu.dylib"
STAGED="$DROIDNEST_ROOT/build/ios-arm64/lib/libqemu-aarch64-softmmu.dylib"
if [ -f "$BUILT" ] && [ "$BUILT" -nt "$STAGED" ]; then
    echo "==> staged dylib is older than the built one; restaging"
    cp "$BUILT" "$STAGED"
fi

# project.yml is the source of truth and the checked-in .pbxproj is a build artefact of it.
if command -v xcodegen >/dev/null 2>&1; then
    echo "==> regenerating the project from project.yml"
    (cd "$DROIDNEST_ROOT/src/app" && xcodegen generate --quiet)
else
    echo "==> xcodegen not installed; using the checked-in project as-is" >&2
fi

echo "==> building DroidNest"
xcodebuild -project "$DROIDNEST_ROOT/src/app/Husk.xcodeproj" -scheme DroidNest \
    -sdk iphoneos -configuration Release -derivedDataPath "$DD" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
    build 2>&1 | tee "$DD/build.log" | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true

if ! grep -q "BUILD SUCCEEDED" "$DD/build.log"; then
    echo "build failed; refusing to package a stale app" >&2
    grep -E "error:" "$DD/build.log" | head -10 >&2
    exit 1
fi

APP="$DD/Build/Products/Release-iphoneos/DroidNest.app"
[ -d "$APP" ] || { echo "no app bundle at $APP" >&2; exit 1; }

# The Java runtime the shared sources read, copied from the build rather than trusted to be in the bundle.
JRT="$DROIDNEST_ROOT/build/java-runtime"
if [ -f "$JRT/husk-framework.dex" ]; then
    rsync -a --delete "$JRT/" "$APP/java-runtime/"
fi

APP_PLIST="$APP/Info.plist"
COMMIT="$(git -C "$DROIDNEST_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
git -C "$DROIDNEST_ROOT" diff --quiet 2>/dev/null || COMMIT="$COMMIT-dirty"
plutil -replace HuskBuildCommit -string "$COMMIT" "$APP_PLIST"
plutil -replace HuskBuildDate -string "$(date -u '+%Y-%m-%d %H:%M UTC')" "$APP_PLIST"
echo "==> stamped build $COMMIT"

echo "==> validating bundle"
rc=0
for key in CFBundleIdentifier CFBundleExecutable CFBundleName \
           CFBundlePackageType CFBundleVersion CFBundleShortVersionString \
           MinimumOSVersion UIDeviceFamily; do
    val="$(/usr/libexec/PlistBuddy -c "Print :$key" "$APP_PLIST" 2>/dev/null || true)"
    if [ -z "$val" ]; then
        echo "  MISSING  $key   <-- the app will not install" >&2
        rc=1
    else
        printf "  ok       %-28s %s\n" "$key" "$(echo "$val" | head -1)"
    fi
done

EXE="$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$APP_PLIST" 2>/dev/null || true)"
if [ -n "$EXE" ] && [ ! -f "$APP/$EXE" ]; then
    echo "  MISSING  executable '$EXE' named by CFBundleExecutable" >&2
    rc=1
fi

# The two libraries the app cannot launch without: QEMU is linked by the shared sources, ANGLE is opened by it at GL start.
for lib in libqemu-aarch64-softmmu.dylib libANGLE-shared.dylib; do
    if [ ! -f "$APP/Frameworks/$lib" ]; then
        echo "  MISSING  Frameworks/$lib" >&2
        rc=1
    else
        printf "  ok       %-28s %s\n" "$lib" "$(du -h "$APP/Frameworks/$lib" | cut -f1)"
    fi
done

# The JIT script is what a debugger runs: without it there is no executable memory at all.
for f in husk-jit.js; do
    if [ ! -f "$APP/$f" ]; then
        echo "  MISSING  $f" >&2
        rc=1
    else
        printf "  ok       %-28s %s\n" "$f" "$(du -h "$APP/$f" | cut -f1)"
    fi
done

# The built-in helper, under this app's own name, and StikJIT which it loads from the app's Frameworks.
for f in "$APP/PlugIns/DroidNestJITHelper.appex/DroidNestJITHelper" \
         "$APP/Frameworks/StikJIT.framework/StikJIT"; do
    if [ ! -f "$f" ]; then
        echo "  MISSING  ${f#$APP/}   <-- built-in JIT would be unavailable" >&2
        rc=1
    else
        printf "  ok       %-28s %s\n" "$(basename "$f")" "${f#$APP/}"
    fi
done

[ $rc -eq 0 ] || { echo "==> bundle is not installable; refusing to package" >&2; exit 1; }

echo "==> packaging"
STAGE="$(mktemp -d "$DD/stage.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/Payload"
cp -R "$APP" "$STAGE/Payload/"

ENT="$STAGE/entitlements.plist"
cp "$DROIDNEST_ROOT/src/app/Husk/Husk.entitlements" "$ENT"
SAPP="$STAGE/Payload/$(basename "$APP")"
sign() { codesign --force --sign - --timestamp=none "$@"; }
find "$SAPP" -name "*.dylib" -not -path "*/Frameworks/*.framework/*" | while read -r f; do sign "$f"; done
for fw in "$SAPP"/Frameworks/*.framework; do [ -d "$fw" ] && sign "$fw"; done
for ex in "$SAPP"/PlugIns/*.appex; do [ -d "$ex" ] && sign "$ex"; done
sign --entitlements "$ENT" "$SAPP"

EMBEDDED_ENTS=$(codesign -d --entitlements - "$SAPP" 2>&1 || true)
if ! grep -qE "get-task-allow|increased-memory|extended-virtual" <<< "$EMBEDDED_ENTS"; then
    echo "==> entitlements did not embed; refusing to package" >&2
    exit 1
fi

TMP_OUT="$STAGE/package.tmp"
( cd "$STAGE" && zip -qry "$TMP_OUT" Payload )
mv -f "$TMP_OUT" "$OUT"
echo "==> $OUT  ($(du -h "$OUT" | cut -f1))"
