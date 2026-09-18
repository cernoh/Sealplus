# Build and screenshot loop on this host

How to build Sealplus and take a screenshot of the running app on this headless
x86_64 Linux host. Any later screen change can then be proven by running the app
instead of reading a diff.

Everything runs inside one Nix dev shell. Nothing is installed outside the Nix
store except the Gradle cache, the AVD and the emulator's user data.

- [Setup](#setup)
- [Build](#build)
- [Emulator](#emulator)
- [Screenshot](#screenshot)
- [Measured times](#measured-times)
- [Pitfalls](#pitfalls)
- [How this app differs from a plain Android project](#how-this-app-differs-from-a-plain-android-project)
- [Proof](#proof)

## Setup

One time, on a machine with no Android tooling:

```bash
git clone https://github.com/cernoh/Sealplus.git
cd Sealplus
```

The shell is `shell.nix` at the repository root. It provides JDK 21 and an
Android SDK built from nixpkgs (`androidenv.composeAndroidPackages`): platform
37 and 36, build-tools 37.0.0 and 36.0.0, platform-tools, emulator 37.1.11, and
the `android-36` default x86_64 system image. Enter it with:

```bash
nix-shell
```

The first entry builds the SDK and downloads its archives, so it takes a few
minutes. Later entries are instant.

The shell puts `adb`, `avdmanager`, `sdkmanager` and `emulator` on `PATH`: the
nixpkgs SDK composition lays them out inside the SDK tree and adds nothing to
`PATH` itself.

Point the caches at a large disk when `$HOME` is small. This host keeps them on
the 1.7 TB disk:

```bash
export GRADLE_USER_HOME=/mnt/2tb-ext4/.gradle-home
export ANDROID_AVD_HOME=/mnt/2tb-ext4/.android-avd
export ANDROID_USER_HOME=/mnt/2tb-ext4/.android-user
```

`local.properties` stays out of version control. The repository `.gitignore`
already lists `local.properties` and `local.properties` is written on every
build (see below), so never commit it and never edit it by hand.

## Build

```bash
scripts/android-build.sh
```

The script writes `local.properties` from `$ANDROID_HOME`, then runs:

```bash
./gradlew :app:assembleGenericDebug \
  -Pandroid.aapt2FromMavenOverride=$ANDROID_HOME/build-tools/37.0.0/aapt2
```

The `-Pandroid.aapt2FromMavenOverride` flag is **required** on NixOS. See
[Pitfalls](#pitfalls).

Output, one APK per ABI plus a universal one:

```
app/build/outputs/apk/generic/debug/SealPlus-3.0.0-x86_64.apk
app/build/outputs/apk/generic/debug/SealPlus-3.0.0-arm64-v8a.apk
app/build/outputs/apk/generic/debug/SealPlus-3.0.0-armeabi-v7a.apk
app/build/outputs/apk/generic/debug/SealPlus-3.0.0-x86.apk
app/build/outputs/apk/generic/debug/SealPlus-3.0.0-universal.apk
```

The emulator needs `SealPlus-3.0.0-x86_64.apk`.

`./gradlew buildGenericRelease` (what CI runs) also works in the shell, with the
same aapt2 flag.

## Emulator

One time, write the AVD:

```bash
scripts/android-emulator.sh create
```

Boot it headless:

```bash
scripts/android-emulator.sh start     # returns at once, logs to /tmp/sealplus-emulator-5554.log
scripts/android-emulator.sh wait      # blocks until sys.boot_completed=1
scripts/android-emulator.sh prepare   # animation scales to 0, for stable screenshots
```

`start` runs `emulator` under `setsid nohup`, so it outlives the shell:

```bash
emulator -avd sealplus36 -port 5554 \
  -no-window -no-audio -no-boot-anim -no-snapshot -no-metrics \
  -gpu swiftshader_indirect
```

KVM acceleration is active: `emulator -accel-check` reports
`KVM (version 12) is installed and usable.` `/dev/kvm` is world-writable, so no
group membership is needed.

Stop it with `scripts/android-emulator.sh stop`.

## Screenshot

With the emulator booted and the APK built:

```bash
scripts/android-screenshot.sh /tmp/sealplus-screen.png
```

The script installs the APK, starts the app, waits, and captures:

```bash
adb -s emulator-5554 install -r -g app/build/outputs/apk/generic/debug/SealPlus-3.0.0-x86_64.apk
adb -s emulator-5554 shell am start -n com.maheshtechnicals.sealplus.debug/com.junkfood.seal.MainActivity
sleep 6
adb -s emulator-5554 exec-out screencap -p > /tmp/sealplus-screen.png
```

`SETTLE_SECONDS` is the delay before the capture, 20 s by default. Under
software rendering the app sits on its splash screen for about 10 s on a cold
emulator, so a shorter delay captures the splash rather than a real screen. It
then prints the last 40 log lines of the app process, which is where a crash or
an exception shows up.

The debug build has `applicationIdSuffix ".debug"`, so the installed package is
`com.maheshtechnicals.sealplus.debug`, not `com.maheshtechnicals.sealplus`.

Drive the UI with `adb shell input tap X Y`, `input swipe`, and `input text`.
`screencap` writes 1080x2400 pixels, so `input tap` coordinates are in that
space. `adb shell uiautomator dump` plus `adb pull` lists the widgets and their
bounds when a coordinate has to be found rather than guessed.

A black or blank screenshot still writes a file: check the size. A rendered
screen is 60 KB and up; a blank one is a few KB.

## Measured times

Measured on this host, 16 cores, 31 GB RAM, `/dev/kvm` active.

| Run | Wall time |
| --- | --- |
| First build ever (downloads Gradle 9.5.1 and all dependencies) | 346 s |
| Clean build, warm caches (`./gradlew clean` first) | 94 s |
| Incremental, one Kotlin file touched | 12 s |
| No change at all | 5 s |
| Emulator cold boot to `sys.boot_completed=1` | 163 s |

The first build also fetches the Android SDK archives into the Nix store. A
no-op build is 5 s because the Gradle configuration cache is reused.

## Pitfalls

### AGP's aapt2 cannot start on NixOS

Without the override, the build fails in `:app:processGenericDebugResources`:

```
AAPT2 aapt2-9.2.1-15009934-linux Daemon #0: Daemon startup failed
```

with `--info`:

```
Could not start dynamically linked executable: .../aapt2-9.2.1-15009934-linux/aapt2
NixOS cannot run dynamically linked executables intended for generic linux environments out of the box.
```

AGP downloads its own `aapt2` from Google's Maven repository and runs it as a
daemon. That binary is dynamically linked for a generic Linux layout, which
NixOS does not support. The SDK's own `aapt2` from the Nix store works.

The override must be a **Gradle property**, not a `local.properties` entry:

- `-Pandroid.aapt2FromMavenOverride=<path>` works.
- `android.aapt2FromMavenOverride=<path>` in `local.properties` does **not**.
  AGP ignores it there and the same daemon failure returns.

This is why `scripts/android-build.sh` passes the flag rather than writing it
into `local.properties`.

### AGP wants build-tools 36, not only 37

`compileSdk = 37` alone is not enough. AGP resolves `build-tools;36.0.0` during
the build. With only 37.0.0 in the shell it tries to install 36.0.0 into the SDK
and fails, because the Nix store is read-only:

```
Failed to install the following SDK components:
    build-tools;36.0.0 Android SDK Build-Tools 36
  The SDK directory is not writable (/nix/store/...-androidsdk/libexec/android-sdk)
```

`shell.nix` therefore requests both versions:

```nix
buildToolsVersions = [ "37.0.0" "36.0.0" ];
```

### The SDK tree is read-only

The SDK is a Nix store path. Gradle may not install anything into it. Keep
`GRADLE_USER_HOME`, `ANDROID_AVD_HOME` and `ANDROID_USER_HOME` outside it, as
[Setup](#setup) does. `sdkmanager` cannot install packages either; add what is
needed to `shell.nix` instead.

### avdmanager reports a missing devices.xml

`scripts/android-emulator.sh create` prints:

```
Error: Could not load devices from .../system-images/android-36/default/x86_64/devices.xml
```

This is noise. The nixpkgs system image ships no `devices.xml`, and the chosen
device profile is written into the AVD's `config.ini` anyway
(`hw.device.name=pixel_6`). The AVD boots.

### `avdmanager` and `emulator` are not on `PATH` by default

The nixpkgs SDK composition adds nothing to `PATH`, and `cmdline-tools` is named
after the archive version (`22.0` today), so its path is not stable. `shell.nix`
globs it:

```bash
for dir in "$ANDROID_HOME"/cmdline-tools/*/bin \
           "$ANDROID_HOME/platform-tools" \
           "$ANDROID_HOME/emulator"; do
  PATH="$dir:$PATH"
done
```

### The first launch after a fresh install shows a battery dialog

A fresh install opens a "Battery configuration" dialog over the Home screen, on
every launch until it is dismissed. Dismiss it before capturing, or the
screenshot shows the dialog:

```bash
adb -s emulator-5554 shell input tap 336 1108   # Skip
```

`install -r` keeps the app's data, so a reinstall over an existing install does
not raise it again.

### A cold launch shows the splash screen for ~10 s

Under software rendering the app sits on its splash screen for about 10 s before
the first real screen draws. A screenshot taken too early shows the splash. The
default `SETTLE_SECONDS=20` covers it; raise it further on a busy host.

### A system ANR dialog can cover the first screenshot

On the first app launch under software rendering, SystemUI can raise an "isn't
responding" dialog. It is slow, not broken: the app itself draws. Wait, dismiss
the dialog, and capture again. `scripts/android-screenshot.sh` prints the app
process log, which distinguishes an ANR from an app crash.

### adb needs root to read the app's data directory

`/data/data/com.maheshtechnicals.sealplus.debug` is not readable by the `shell`
user:

```
ls: /data/data/com.maheshtechnicals.sealplus.debug/files/: Permission denied
```

Run `adb root` first, or use `adb shell run-as
com.maheshtechnicals.sealplus.debug <cmd>`.

## How this app differs from a plain Android project

- **compileSdk 37, Java 21.** `app/build.gradle.kts` sets `compileSdk = 37`,
  `targetSdk = 37`, `minSdk = 24`, `sourceCompatibility`/`targetCompatibility`
  `VERSION_21`, and `kotlin { jvmToolchain(21) }`. JDK 21 is required; the
  toolchain is not auto-downloaded, so `JAVA_HOME` must point at 21.
- **Two Gradle modules.** `settings.gradle.kts` includes `:app` and `:color`.
  `:color` is an `android.library` module (`namespace
  com.junkfood.seal.color`) that the app depends on with
  `implementation(project(":color"))`. Both use `compileSdk = 37`.
- **Split APKs by ABI.** `splitApks` is true unless `-PnoSplits` is passed, so
  `genericDebug` emits four per-ABI APKs and a universal one. `gradle.properties`
  sets `ABI_FILTERS=arm64-v8a`, but that value is used **only** when `-PnoSplits`
  is passed; with splits on it is ignored. Each output's `versionCode` is offset
  by an ABI code (arm64-v8a 2, x86_64 4), and output names are rewritten to
  `SealPlus-<version>-<abi>.apk`.
- **Native yt-dlp, ffmpeg, aria2c and Python.** The three binaries ship through
  `io.github.junkfood02.youtubedl-android:0.18.1` as `.so` files, one set per
  ABI: `libffmpeg.so` plus a 38 MB `libffmpeg.zip.so`, `libaria2c.so` plus
  `libaria2c.zip.so`, `libpython.so` plus `libpython.zip.so`, `libffprobe.so`
  and `libqjs.so`. The `.zip.so` files are packed payloads. The x86_64 APK
  carries 61.8 MB of native libraries in 10 entries.
- **The payload unpacks on first launch, not at install.** `App.kt` calls
  `YoutubeDL.init(this)`, `FFmpeg.init(this)` and `Aria2c.init(this)`, which
  extract the archives into
  `/data/data/<package>/no_backup/youtubedl-android/`. On a cold emulator this
  takes tens of seconds. The extracted tree contains
  `yt-dlp/yt-dlp`, `packages/ffmpeg/usr/lib/`, `packages/aria2c/` and
  `packages/python/usr/lib/python3.12/`.
- **Everything yt-dlp runs is built in one file.** Every yt-dlp argument is
  assembled in `app/src/main/java/com/junkfood/seal/util/DownloadUtil.kt`.
- **The download output path is not `Download/Seal`.** A completed download
  lands in `/storage/emulated/0/Download/SealPlus/`, named
  `<title> [<video-id>].<ext>`.
- **CI builds a different variant.** `.github/workflows/android_ci.yml` runs
  `./gradlew buildGenericRelease`; the screenshot loop uses `genericDebug`
  because it installs without a keystore.
- **The release build is signed only if `keystore.properties` exists.**
  `app/build.gradle.kts` reads it from the repository root and skips the signing
  config when it is absent, so a release build works unsigned on this host.

## Proof

Screenshots from the running app on this host, captured with
`adb exec-out screencap -p`:

- `docs/android/screenshot-home.png` — the Home screen after onboarding, with the
  completed download in Recent downloads.
- `docs/android/screenshot-ytdlp-version.png` — Settings, General, showing the
  bundled yt-dlp version **2026.08.19**. The version comes from
  `YoutubeDL.getInstance().version(context)`, so the native binary executed on
  the device.
- `docs/android/screenshot-download-complete.png` — a real download of
  `aqz-KE-bpKQ` (Big Buck Bunny 60fps 4K) reported as **Completed 100%**, also
  visible on the Home screen above. It wrote
  `/storage/emulated/0/Download/SealPlus/Big Buck Bunny 60fps 4K - Official Blender Foundation Short Film [aqz-KE-bpKQ].webm`
  at 1372474870 bytes.

That third screenshot exercises yt-dlp download plus the ffmpeg mux pass, so the
whole native pipeline is proven on the emulator, not only app startup.

### Not made to work

- **Reading the app's private data as a non-root `shell` user.** Needs
  `adb root` or `adb shell run-as`. Not a defect; noted in
  [Pitfalls](#pitfalls).
- **Installing SDK components from inside the build.** The Nix store is
  read-only, so every package the build needs must be listed in `shell.nix`.
  Only build-tools 36.0.0 was missing and it is now listed.
- **`avdmanager` device lookup.** The system image ships no `devices.xml`; the
  device profile is written into `config.ini` instead.
