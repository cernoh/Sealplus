#!/usr/bin/env bash
# Headless x86_64 Android emulator for Sealplus.
#
# Run inside the dev shell:  nix-shell
#
#   scripts/android-emulator.sh create   # one time: write the AVD
#   scripts/android-emulator.sh start    # boot it headless in the background
#   scripts/android-emulator.sh wait     # block until Android reports boot complete
#   scripts/android-emulator.sh prepare  # turn animations off for stable screenshots
#   scripts/android-emulator.sh stop
#
# Environment (defaults are fine on this host):
#   AVD_NAME          default sealplus36
#   ANDROID_AVD_HOME  default $HOME/.android/avd
#   EMULATOR_PORT     default 5554
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -z "${ANDROID_HOME:-}" ]; then
  echo "ANDROID_HOME is unset. Run this inside the dev shell: nix-shell" >&2
  exit 1
fi

AVD_NAME=${AVD_NAME:-sealplus36}
AVD_IMAGE=${AVD_IMAGE:-"system-images;android-36;default;x86_64"}
AVD_DEVICE=${AVD_DEVICE:-pixel_6}
EMULATOR_PORT=${EMULATOR_PORT:-5554}
SERIAL="emulator-$EMULATOR_PORT"
LOG=${EMULATOR_LOG:-"/tmp/sealplus-emulator-$EMULATOR_PORT.log"}
export ANDROID_AVD_HOME=${ANDROID_AVD_HOME:-"$HOME/.android/avd"}
export ANDROID_USER_HOME=${ANDROID_USER_HOME:-"$HOME/.android"}

case ${1:-} in
  create)
    mkdir -p "$ANDROID_AVD_HOME" "$ANDROID_USER_HOME"
    # avdmanager prints "Could not load devices from .../devices.xml" because the
    # Nix system image has no devices.xml. It is noise: the device profile is
    # written into config.ini anyway.
    avdmanager --silent create avd \
      --name "$AVD_NAME" \
      --package "$AVD_IMAGE" \
      --device "$AVD_DEVICE" \
      --force
    echo "AVD $AVD_NAME: $ANDROID_AVD_HOME/$AVD_NAME.avd"
    ;;

  start)
    if adb -s "$SERIAL" get-state >/dev/null 2>&1; then
      echo "already running: $SERIAL"
      exit 0
    fi
    # KVM acceleration is on by default; swiftshader renders the GPU in software
    # because this host has no display and no GPU.
    setsid nohup emulator \
      -avd "$AVD_NAME" \
      -port "$EMULATOR_PORT" \
      -no-window -no-audio -no-boot-anim -no-snapshot -no-metrics \
      -gpu swiftshader_indirect \
      > "$LOG" 2>&1 < /dev/null &
    echo "emulator pid $!, log $LOG"
    ;;

  wait)
    adb -s "$SERIAL" wait-for-device
    printf 'waiting for boot'
    until [ "$(adb -s "$SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do
      printf '.'
      sleep 3
    done
    echo
    adb -s "$SERIAL" shell getprop ro.build.version.sdk
    ;;

  prepare)
    for scale in window_animation_scale transition_animation_scale animator_duration_scale; do
      adb -s "$SERIAL" shell settings put global "$scale" 0
    done
    echo "animations off"
    ;;

  stop)
    adb -s "$SERIAL" emu kill || true
    ;;

  *)
    sed -n '2,20p' "$0"
    exit 1
    ;;
esac
