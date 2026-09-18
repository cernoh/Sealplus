# Android build shell for Sealplus on a headless x86_64 Linux host.
#
# Enter with:  nix-shell
#
# Provides:
#   - JDK 21 (the toolchain the build declares: compileOptions VERSION_21, jvmToolchain(21))
#   - Android SDK in the Nix store: platforms 37 and 36, build-tools 37.0.0 and
#     36.0.0 (AGP resolves 36.0.0 as well, see docs/android-build-and-screenshot.md),
#     platform-tools, emulator 37.1.11 and the android-36 default x86_64 system image.
#
# The SDK is read-only (a Nix store path). Gradle only reads it; AVDs and Gradle
# caches live outside, so set GRADLE_USER_HOME and ANDROID_AVD_HOME to writable
# directories on a large disk when the home directory is small.
#
# nixpkgs comes from the flake registry, so this file is not pinned. Pin it with
# a URL and hash when a build must be reproducible across machines.

let
  pkgs = import (builtins.getFlake "nixpkgs") {
    system = builtins.currentSystem;
    config = {
      android_sdk.accept_license = true;
      allowUnfree = true;
    };
  };

  androidComposition = pkgs.androidenv.composeAndroidPackages {
    cmdLineToolsVersion = "latest";
    platformToolsVersion = "latest";
    buildToolsVersions = [
      "37.0.0"
      "36.0.0"
    ];
    platformVersions = [
      "37"
      "36"
    ];
    includeEmulator = true;
    includeSystemImages = true;
    systemImageTypes = [ "default" ];
    abiVersions = [ "x86_64" ];
    includeSources = false;
    includeNDK = false;
    includeCmake = false;
  };

  androidSdk = androidComposition.androidsdk;
  androidHome = "${androidSdk}/libexec/android-sdk";
  jdk = pkgs.jdk21;
in
pkgs.mkShell {
  name = "sealplus-android";

  packages = [ jdk ];

  JAVA_HOME = jdk.home;
  ANDROID_HOME = androidHome;
  ANDROID_SDK_ROOT = androidHome;

  # AGP downloads `aapt2` from Google's Maven repository and runs it as a
  # daemon. That binary cannot start on NixOS (it is dynamically linked for a
  # generic Linux layout), which fails the build in :app:processGenericDebugResources.
  # The build script passes the SDK's aapt2 through -Pandroid.aapt2FromMavenOverride.
  # This variable only records which binary to use.
  AAPT2_OVERRIDE = "${androidHome}/build-tools/37.0.0/aapt2";

  shellHook = ''
    # The SDK composition lays the tools out inside the SDK tree and puts
    # nothing on PATH: adb, avdmanager/sdkmanager and emulator have to be
    # added by hand. The cmdline-tools directory is named after the archive
    # version (22.0 today), so glob it.
    for dir in "$ANDROID_HOME"/cmdline-tools/*/bin "$ANDROID_HOME/platform-tools" "$ANDROID_HOME/emulator"; do
      PATH="$dir:$PATH"
    done
    export PATH

    echo "Sealplus Android shell"
    echo "  JAVA_HOME=$JAVA_HOME"
    echo "  ANDROID_HOME=$ANDROID_HOME"
    echo "  aapt2 override: $AAPT2_OVERRIDE"
    if [ -z "''${GRADLE_USER_HOME:-}" ]; then
      echo "  note: GRADLE_USER_HOME is unset, so Gradle writes to \$HOME/.gradle"
    fi
  '';
}
