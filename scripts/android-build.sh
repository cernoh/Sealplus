#!/usr/bin/env bash
# Build the genericDebug APK for the emulator.
#
# Run inside the dev shell:  nix-shell --run 'scripts/android-build.sh'
#
# Writes the untracked local.properties from $ANDROID_HOME on every run: the SDK
# is a Nix store path, so the path changes whenever shell.nix changes and a
# committed or stale file would break the build.
#
# The -Pandroid.aapt2FromMavenOverride flag is required on this host, and it
# must be a Gradle property, not a local.properties entry. AGP downloads its own
# aapt2 from Google's Maven repository and starts it as a daemon; on NixOS that
# binary cannot start:
#
#   Could not start dynamically linked executable: .../aapt2-9.2.1-...-linux/aapt2
#   NixOS cannot run dynamically linked executables intended for generic linux
#   environments out of the box.
#
# The build then fails in :app:processGenericDebugResources with
# "AAPT2 ... Daemon startup failed". An `android.aapt2FromMavenOverride` line in
# local.properties does NOT fix it: AGP reads that setting only from a Gradle
# property (command line -P, or gradle.properties).
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -z "${ANDROID_HOME:-}" ]; then
  echo "ANDROID_HOME is unset. Run this inside the dev shell: nix-shell" >&2
  exit 1
fi

AAPT2=${AAPT2_OVERRIDE:-"$ANDROID_HOME/build-tools/37.0.0/aapt2"}
if [ ! -x "$AAPT2" ]; then
  echo "no aapt2 at $AAPT2; check the build-tools version in shell.nix" >&2
  exit 1
fi

printf 'sdk.dir=%s\n' "$ANDROID_HOME" > local.properties

start=$(date +%s)
./gradlew :app:assembleGenericDebug "-Pandroid.aapt2FromMavenOverride=$AAPT2"
echo "build seconds: $(( $(date +%s) - start ))"

echo "APKs:"
ls -l app/build/outputs/apk/generic/debug/*.apk
