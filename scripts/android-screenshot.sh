#!/usr/bin/env bash
# Install the built APK, start the app, and capture a screenshot.
#
# Run inside the dev shell after scripts/android-build.sh and a booted emulator:
#   scripts/android-screenshot.sh <output.png>
#
# Prints the output path and the file size on success. A screenshot of a black
# or blank screen is still written: check the size, it is a few hundred KB for a
# rendered screen and much smaller for a blank one.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -z "${ANDROID_HOME:-}" ]; then
  echo "ANDROID_HOME is unset. Run this inside the dev shell: nix-shell" >&2
  exit 1
fi

OUT=${1:-/tmp/sealplus-screen.png}
APK_DIR=${APK_DIR:-app/build/outputs/apk/generic/debug}
# The debug build carries applicationIdSuffix ".debug".
APP_ID=${APP_ID:-com.maheshtechnicals.sealplus.debug}
SERIAL=${SERIAL:-emulator-5554}

# The ABI split leaves one APK per ABI plus a universal one. The emulator is
# x86_64; a universal APK works too.
APK=$(ls "$APK_DIR"/*x86_64*.apk "$APK_DIR"/*universal*.apk 2>/dev/null | head -1)
if [ -z "$APK" ]; then
  echo "no APK in $APK_DIR; run scripts/android-build.sh first" >&2
  exit 1
fi

adb -s "$SERIAL" wait-for-device
adb -s "$SERIAL" install -r -g "$APK"
adb -s "$SERIAL" shell am start -n "$APP_ID/com.junkfood.seal.MainActivity"
# 20 s by default: under software rendering the app sits on its splash screen for
# about 10 s on a cold emulator, so a shorter delay captures the splash.
sleep "${SETTLE_SECONDS:-20}"

mkdir -p "$(dirname "$OUT")"
adb -s "$SERIAL" exec-out screencap -p > "$OUT"
ls -l "$OUT"

echo "--- recent app log ---"
adb -s "$SERIAL" logcat -d -t 40 --pid "$(adb -s "$SERIAL" shell pidof -s "$APP_ID" | tr -d '\r')" || true
