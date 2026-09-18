# Slice B — Can the app execute the bundled ffmpeg, and with what exact invocation?

Issue: cernoh/Sealplus#3. Research only. No repo writes.

Pinned dependency (observed in the checkout): `gradle/libs.versions.toml:34` → `youtubedlAndroid = "0.18.1"`,
resolved as group `io.github.junkfood02.youtubedl-android`, artifacts `library`, `ffmpeg`, `aria2c` [S1][S2].
Verification method: the exact published artifacts were downloaded from Maven Central and opened
(`*.aar` + `*-sources.jar`); the sources jar for `library` and `ffmpeg` is **byte-identical** to upstream git
tag `0.18.1` (checked with `diff`) [S3][S4][S5]. The POM's `<scm>` points at
`https://github.com/yausername/youtubedl-android` [S3], so all code citations below use that repo and tag.
**The pin is exactly resolvable, not an approximation:** tag `0.18.1` → commit
`d725d5c9a18c3a99a13ee0308bf78275dc310760` ("Bump version 0.18.1", 2025-11-16T18:39:19Z), which was
`master` HEAD at release time; the GitHub release `0.18.1` was published 18:48:32Z and Maven Central's
`lastUpdated` for the group is 2025-11-16T19:38:37Z [S2][S37]. The stale `JunkFood02` fork survives only as
the Maven group id (§1); the bytes are upstream's [S12].
The bundled yt-dlp is version `2025.11.12` (`RELEASE_GIT_HEAD 335653be82d5ef999cfc2879d005397402eebec1`),
read out of `res/raw/ytdlp` inside `library-0.18.1.aar` [S6]; the claims about yt-dlp below were checked
against that exact shipped copy, not against a blog or the README.

## Question

Can the app process execute the ffmpeg binary that youtubedl-android unpacks, and what is the exact
invocation form — both for a direct spawn and for routing extraction through the existing yt-dlp call?

## 1. Where the binaries live

**Packaging (observed in the AARs, `unzip -l`).** The library used the same uniform trick at 0.15.0 [S7]
and 0.18.1 keeps it:

- Every payload is shipped as a file in the AAR's `jni/<abi>/` directory, i.e. it lands in the app's
  **native library directory** at install time. Nothing is shipped in `assets/`; the only non-`jni` payload
  is `res/raw/ytdlp` (a resource, see below).
- `ffmpeg-0.18.1.aar` contains, per ABI (arm64-v8a shown):
  `jni/arm64-v8a/libffmpeg.so` (317 120 B), `jni/arm64-v8a/libffprobe.so` (233 664 B),
  `jni/arm64-v8a/libffmpeg.zip.so` (35 624 931 B) [S8].
- `library-0.18.1.aar` contains `res/raw/ytdlp` (3 170 726 B — the yt-dlp Python zipapp),
  `jni/<abi>/libpython.so` (4 384 B launcher), `jni/<abi>/libpython.zip.so` (14 305 904 B),
  `jni/<abi>/libqjs.so` (916 104 B) [S9].
- `aria2c-0.18.1.aar` contains `jni/<abi>/libaria2c.so` (2 540 656 B) and `libaria2c.zip.so` (4 296 181 B) [S10].

So the split is: **the executable lives in `nativeLibraryDir`; its shared-library payload is a `.zip.so`
that gets unzipped into the app's private home directory** (which cannot be exec'd, see §2).

**Executables are real, dynamically-linked ELF files (observed, `readelf`/`strings` on the extracted AAR):**

- `libffmpeg.so` is `Type: DYN (Shared object file)`, `Machine: AArch64`, `NEEDED` `libavdevice.so.61`,
  `libavfilter.so.10`, `libavformat.so.61`, `libavcodec.so.61`, `libpostproc.so.58`, `libswresample.so.5`,
  `libswscale.so.8`, `libavutil.so.59`, `libm.so`, `libc.so`;
  `RUNPATH: [/data/data/com.termux/files/usr/lib]` (a Termux path, useless in an app process);
  embedded version string `"%s version 7.1.1"` and a Termux `configuration:` line → **ffmpeg 7.1.1 CLI,
  Termux cross-build** [S8].
- `libffprobe.so` has the same shape (same `NEEDED` set, same Termux `RUNPATH`) — the ffprobe CLI [S8].
- `libffmpeg.zip.so` contains **184 entries, all under `usr/lib/`** (e.g. `usr/lib/libavcodec.so.61.19.101`,
  `usr/lib/libavutil.so.59…`, plus `libass`, `libvpx`, `libsrt`, …). There is **no `usr/bin/`, no second
  ffmpeg executable and no non-`.so` binary** in the zip — the CLI in `nativeLibraryDir` is the only ffmpeg
  [S8].

**Concrete on-device path (from the library source, `FFmpeg.kt:20` and `YoutubeDL.kt:38,315`):**

```kotlin
binDir      = File(appContext.applicationInfo.nativeLibraryDir)      // FFmpeg.kt:20, YoutubeDL.kt:36
ffmpegPath  = File(binDir, "libffmpeg.so")                          // YoutubeDL.kt:38 + :315
ffprobePath = File(binDir, "libffprobe.so")                         // implied; no constant exists
```

Absolute path the app should build:

```
<applicationInfo.nativeLibraryDir>/libffmpeg.so
<applicationInfo.nativeLibraryDir>/libffprobe.so
```

`nativeLibraryDir` is documented as "Full path to the directory where native JNI libraries are stored"
(`ApplicationInfo.java`) [S11]; its concrete form on API 30+ is
`/data/app/~~<random>==/<pkg>-<random>/lib/<abi>` [INFERENCE — from the AOSP `/data/app` layout; the app
should not hardcode it, and the library does not].

**Unpacked library directory (derived from `FFmpeg.kt:18-22` + `YoutubeDL.kt:34-50`):**

```
<noBackupFilesDir>/youtubedl-android/packages/ffmpeg/usr/lib    ← LD_LIBRARY_PATH entry for ffmpeg
<noBackupFilesDir>/youtubedl-android/packages/python/usr        ← PYTHONHOME
<noBackupFilesDir>/youtubedl-android/packages/python/usr/lib    ← LD_LIBRARY_PATH entry for python
<noBackupFilesDir>/youtubedl-android/yt-dlp/yt-dlp              ← res/raw/ytdlp copied here
```
(`noBackupFilesDir` = `/data/user/0/<pkg>/no_backup`; base name `"youtubedl-android"`, `packagesRoot =
`"packages"` — `FFmpeg.kt:54-58`, `YoutubeDL.kt:311-318`.)

**No public path accessor exists.** `FFmpeg` exposes only `init()`/`getInstance()`, and its `binDir` is
`private` [S4]; `YoutubeDL.ffmpegPath` is `private` and `getInstance()` returns the object without a getter
[S5]. Therefore **the app must compute the path itself** from `nativeLibraryDir` (one line). This is the only
missing API surface.

**Divergence between fork and pinned version (checked):** the `JunkFood02/youtubedl-android` fork (last push
2024-12-02, latest tag `0.17.2`) has a **stale `YoutubeDL.kt`** — 284 lines vs 324; it lacks the QuickJS
`--js-runtimes` wiring [S12][S13]. `FFmpeg.kt` is identical in both (59 lines, no ffmpeg-relevant
divergence); both already set `--ffmpeg-location` and the same environment block [S12][S13]. 0.18.1 is
published from upstream (`scm` = yausername) [S3].

## 2. The exec rule, and which side `libffmpeg.so` falls on

**Documented rule (Android 10, API 29+, section "Removed execute permission for app home directory").**
Untrusted apps that target Android 10 cannot invoke `execve()` directly on files within the app's home
directory; this is a W^X violation, and "apps should load only the binary code that's embedded within an
app's APK file" [S14].

**The app declares `targetSdk = 37`, `minSdk = 24`** (`app/build.gradle.kts`, `defaultConfig`) [S15] — so the
rule fully applies (any targetSdk ≥ 29).

**The rule is enforced in SELinux, and it is label-scoped exactly to the home directory:**

- AOSP `private/app_neverallows.te`: `neverallow { all_untrusted_apps -untrusted_app_25 -untrusted_app_27
  -runas_app } { app_data_file privapp_data_file }:file execute_no_trans;` — comment: "Block calling
  execve() on files in an apps home directory. … For compatibility, allow for targetApi <= 28. b/112357170"
  [S16].
- AOSP `private/file_contexts` labels `/data/app(/.*)?` → `u:object_r:apk_data_file:s0`; `app_data_file` is
  the label for `/data/data` (i.e. `filesDir`/`noBackupFilesDir`/`cacheDir`) [S17][S18].
- AOSP `private/app.te`: "Allow apps to read/execute installed binaries" →
  `allow appdomain apk_data_file:file { getattr open read ioctl lock map x_file_perms };` where
  `x_file_perms = { getattr execute execute_no_trans map }` [S19][S20].

**Conclusion:** `<nativeLibraryDir>/libffmpeg.so` is under `/data/app/…` → `apk_data_file`, and `appdomain`
(which includes `untrusted_app`) holds `execute` **and** `execute_no_trans` on it. So the binary **is on the
executable side of the rule**, while everything the library unzips into `noBackupFilesDir` is on the blocked
side. The 0755 mode question is settled too: AOSP extraction (`copyFileIfChanged` → `copyFile`) explicitly
`chmod`s each extracted native library to `0755` (`com_android_internal_content_NativeLibraryHelper.cpp`,
"// Set the mode to 755") [S21].

**That `nativeLibraryDir` really holds extracted files (not APK-resident libs) is decided by this app.**
The library's own `build.gradle.kts` sets nothing [S22]; the app sets
`packaging { jniLibs { useLegacyPackaging = true } }` (`app/build.gradle.kts`) [S15]. Per the Android
manifest reference, `android:extractNativeLibs` "indicates whether the package installer extracts native
libraries from the APK to the file system", and since AGP 4.2 `useLegacyPackaging` is the DSL that replaces
that attribute [S23]. This app setting is **load-bearing**: `FFmpeg.kt:28-30` measures
`File(binDir, "libffmpeg.zip.so").length()` as its version check, which can only work if the file exists on
disk [S4]. [INFERENCE, high confidence: `useLegacyPackaging = true` ⇒ `extractNativeLibs="true"` in the
merged manifest ⇒ the files in `nativeLibraryDir` are extracted and `chmod 0755`.]

## 3. Existence proof that this binary is executed today

Three independent proofs in the shipped code, strongest first:

1. **The library spawns a `nativeLibraryDir` binary directly, on every yt-dlp run.**
   `YoutubeDL.executeImpl` (`YoutubeDL.kt:177-261`):
   ```kotlin
   val command: MutableList<String?> = ArrayList()
   command.addAll(listOf(pythonPath!!.absolutePath, ytdlpPath!!.absolutePath))   // :211
   val processBuilder = ProcessBuilder(command).redirectErrorStream(...)         // :213-214
   ...
   processBuilder.environment().apply {
       this["LD_LIBRARY_PATH"] = ENV_LD_LIBRARY_PATH   // :217
       this["PATH"]            = System.getenv("PATH") + ":" + binDir!!.absolutePath  // :219
       this["PYTHONHOME"]      = ENV_PYTHONHOME        // :220
       this["HOME"]            = ENV_PYTHONHOME        // :221
       this["TMPDIR"]          = TMPDIR                // :222
   }
   ```
   `pythonPath` = `<nativeLibraryDir>/libpython.so` (`:37`, `:311`), and `libpython.so` is an ELF whose
   `NEEDED` entries are `libandroid-support.so` + `libpython3.12.so.1.0`, resolved through the
   `LD_LIBRARY_PATH` that points into `noBackupFilesDir` (observed by `readelf`) [S9]. So the app's own
   process executes from `nativeLibraryDir` and loads shared objects from the app home directory — the two
   halves of the rule, exercised in production, in the app that is in this repo's dependency graph.

2. **yt-dlp executes ffmpeg by path, and the library hands it the path.**
   `YoutubeDL.kt:201-202`: `/* Set ffmpeg location … */ request.addOption("--ffmpeg-location",
   ffmpegPath!!.absolutePath)` → `<nativeLibraryDir>/libffmpeg.so`. On the yt-dlp side (shipped 2025.11.12):
   - `postprocessor/ffmpeg.py:102-131` `_determine_executables()`: with a *file* location it takes
     `basename = 'ffmpeg'` (because `'ffmpeg' in 'libffmpeg.so'`), sets `dirname = nativeLibraryDir`, and
     then `os.path.join(dirname, filename.replace(basename, p))` → `libffprobe.so` **if it exists**. The
     `lib…so` naming therefore resolves *both* ffmpeg and ffprobe from one option [S24].
   - `_get_ffmpeg_version()` → `_get_exe_version_output(path, ['-bsfs'])` → `Popen.run([exe, '-bsfs'])`
     (`postprocessor/ffmpeg.py:132-136`, `utils/_utils.py:2153-2162`), and every conversion builds
     `cmd = [self.executable, …]` and runs `Popen.run(cmd)` (`postprocessor/ffmpeg.py:329-354`) [S24][S25].
     Both are direct `execve` of `<nativeLibraryDir>/libffmpeg.so`. **Precision:** construction of a
     `FFmpegPostProcessor` only resolves *path strings* (`_determine_executables` in `__init__`,
     `ffmpeg.py:89-90`); the `execve` is lazy — it happens the first time a version/feature query runs
     (`_version` → `_get_ffmpeg_version`, e.g. `check_version` before a merge/conversion). So ffmpeg is not
     exec'd on runs that never touch an ffmpeg postprocessor; it is exec'd on any run that does.
   - yt-dlp's ffmpeg postprocessors are reached by options the app already sets: `--add-metadata`
     (`DownloadUtil.kt:842`-region), `--convert-thumbnails png` + `--write-thumbnail`, and above all
     `--download-sections` (the clip feature, `DownloadUtil.kt:1292-1295`), which is ffmpeg-backed [S26][S27].
   - The app also drives a specific ffmpeg invocation today: `CROP_ARTWORK_COMMAND`
     (`DownloadUtil.kt:262-263`) = `--ppa "ffmpeg: -c:v mjpeg -vf crop=…"`, written into a config file and
     passed with `--config` (`DownloadUtil.kt:1032-1034`) [S26].

3. **A second `nativeLibraryDir` binary is exec'd by name off `PATH`, today.**
   `DownloadUtil.kt:802` → `.addOption("--downloader", "http,https,ftp,ftps:libaria2c.so")` [S26]; the child
   resolves that name through the `PATH` the library augmented with `nativeLibraryDir` (`YoutubeDL.kt:219`;
   `check_executable` in `utils/_utils.py:2143-2150` just `Popen`s the name and lets `PATH` resolve it)
   [S25]. `libaria2c.so` is in `jni/<abi>/` of the aria2c AAR [S10]. This proves the *whole* mechanism
   (app-home-dir libs + `nativeLibraryDir` executables + `PATH`) on a code path the app uses unconditionally
   whenever the user enables aria2c.

## 4. Can the app spawn it itself? (env, cwd, SELinux, ptrace, cancellation)

**Yes, mechanically identical to what the library already does.** Requirements, all observed in the library's
own environment block (`YoutubeDL.kt:216-223`) [S5]:

| Item | Value the app must set | Why |
|---|---|---|
| Executable | `<nativeLibraryDir>/libffmpeg.so` (absolute) | `apk_data_file` ⇒ `execute`/`execute_no_trans` granted to `appdomain` [S19] |
| `LD_LIBRARY_PATH` | `<noBackupFilesDir>/youtubedl-android/packages/ffmpeg/usr/lib` (the library also appends python's and aria2c's `usr/lib`) | the binary's `RUNPATH` is `/data/data/com.termux/files/usr/lib`, which does not exist for the app (observed) [S8]; without `LD_LIBRARY_PATH` it fails to find `libavcodec.so.61` etc. |
| `PATH` | optional, but prefixed the way the library does (`System.getenv("PATH") + ":" + nativeLibraryDir`) | needed only if a child of *ffmpeg* has to be found; ffmpeg itself needs none |
| `TMPDIR` | `context.cacheDir` (library sets exactly this at `YoutubeDL.kt:50,222`) | Android toolchain convention; harmless and consistent |
| Working directory | must not be relied on — use absolute paths everywhere | app-process cwd is inherited from zygote/init; [INFERENCE] it is `/`, and `/` is not writable. Mitigation is absolute paths, which the recommended command already uses |
| `HOME`/`PYTHONHOME` | not needed for ffmpeg (python-only) | `libffmpeg.so` has no python dependency (observed `NEEDED`) [S8] |
| stdin | add `-nostdin`, or redirect input | ffmpeg warns if stdin is not a tty; yt-dlp's own comment about SIGTTOU (`utils/_utils.py:2155-2157`) shows the same class of problem [S25] |

**SELinux:** app domain → `apk_data_file` exec is allowed (§2). No additional policy change, device-root, or
`android:debuggable` is needed. Two related constraints still apply and are not workarounds:
`neverallow appdomain storage_area_content_file:file execute` (storage areas) and, for the *unpacked*
libraries, `neverallow all_untrusted_apps app_exec_data_file:file { … write }` — libraries unpacked into the
home directory may be `dlopen`ed but never written by the app [S16]. That is exactly why the library ships
libs inside `*.zip.so` and unzips them read-once into `noBackupFilesDir` [S4].

**PTRACE:** apps cannot ptrace other processes: AOSP grants only `allow untrusted_app_all self:process
ptrace;` and `neverallow { … } self:global_capability_class_set sys_ptrace` [S28][S29]. This means no
`strace`/`gdb` of the spawned ffmpeg from the app; it does **not** block spawning. (Debug-only tooling can
still attach via `run-as`/adb, not from app code.)

**Cancellation and lifecycle:** if the app spawns ffmpeg itself it owns the child. The app already has the
idiom for the yt-dlp process (`YoutubeDL.destroyProcessById`, called from `DownloaderV2`, `Downloader`,
`DownloadDialogViewModel`) [S26]; a frame-extraction process should be held in the ViewModel and
`destroy()`ed on cancel/dismiss, otherwise an ffmpeg pass over a long video keeps running after the sheet
closes. Note the library's own child-kill helper shells out to `pstree -p | grep -oP | xargs kill`
(`YoutubeDL.kt:142-152`) — `pstree` is not part of AOSP by default, so treat that path as best-effort
[UNVERIFIED on device]; do not copy it.

**Also note:** nothing in the app source spawns a process today — a grep of `app/src` for
`ProcessBuilder|Runtime\.|nativeLibraryDir|exec\(` returns **no matches**; every process is started by the
library [S26]. So an app-side spawn introduces the first `ProcessBuilder` in the app, though the mechanism
is already proven inside the same process by the library.

## 5. Exact invocation form for N evenly spaced JPEG frames

Prerequisites that already exist at app start: `YoutubeDL.init(this)` then `FFmpeg.init(this)` in
`App.onCreate` (IO dispatcher) [S30]; `FFmpeg.init` unzips `libffmpeg.zip.so` into
`<noBackupFilesDir>/youtubedl-android/packages/ffmpeg/usr/lib` and is idempotent per library size
(`FFmpeg.kt:20-41`) [S4]. `VideoInfo.duration` (seconds, `Double?`) and `VideoClip(start, end)` (integer
seconds) already exist in the app [S31].

```kotlin
val ffmpeg = File(context.applicationInfo.nativeLibraryDir, "libffmpeg.so")        // §1
val ffLibs = File(context.noBackupFilesDir,
    "youtubedl-android/packages/ffmpeg").resolve("usr/lib")                        // §1, required env
val outDir = File(context.cacheDir, "filmstrip/$videoId").apply { mkdirs() }       // app-private
val n  = 8
val dur = (videoInfo.duration ?: 0.0).coerceAtLeast(1.0)
val fps = "%.6f".format(Locale.US, n / dur)                                        // Locale.US: no comma decimal

val cmd = listOf(
    ffmpeg.absolutePath,
    "-hide_banner", "-loglevel", "error", "-nostdin", "-y",
    "-i", inputFile.absolutePath,                 // absolute; local file
    "-an", "-sn",                                 // frames only, no audio/subtitle decode
    "-vf", "fps=$fps,scale=-2:120",               // evenly spaced; -2 keeps height even
    "-frames:v", n.toString(),                    // hard cap = N frames
    "-q:v", "5",                                  // mjpeg quality (2 best … 31 worst)
    "-f", "image2",                               // deterministic muxer for a numbered pattern
    File(outDir, "frame_%03d.jpg").absolutePath,
)

val p = ProcessBuilder(cmd)
    .redirectErrorStream(true)
    .apply {
        environment()["LD_LIBRARY_PATH"] = ffLibs.absolutePath
        environment()["TMPDIR"] = context.cacheDir.absolutePath
    }
    .start()
val log = p.inputStream.bufferedReader().readText()   // must be drained, else ffmpeg can block on stderr
val code = p.waitFor()                                // 0 = ok; non-zero ⇒ surface `log`
```

Notes and constraints, all grounded:

- **Even spacing:** the `fps` filter resamples the stream to a constant rate, so with rate `N/D` the N kept
  frames sit at `t ≈ 0.5·D/N, 1.5·D/N, …`; `-frames:v N` stops after N. This is one decode pass — cost and
  memory are slice C's subject, not settled here. An alternative (`-ss` per frame, N spawns) trades CPU for
  seeks.
- **Even dimensions:** `scale=-2:120` lets ffmpeg pick a width divisible by 2 (mJPEG requires it).
- **Formatting:** the app already uses `Locale.US` for `--download-sections` ([S26]); the same is required
  for the `fps=` value, since a comma decimal separator would break the filter graph.
- **Where to write:** an app-private directory. `context.cacheDir` is what the library passes as `TMPDIR`
  and what the app already uses for `cookies.txt`/config files (`FileUtil.kt`: `getConfigDirectory() =
  cacheDir`) [S32]. `filesDir/tmp` (`getInternalTempDir()`) is equally writable and not
  auto-evicted [S32]; either is fine — neither is execable, which does not matter for JPEGs.
- **Cleanup:** `outDir.deleteRecursively()` when the sheet closes, plus the process `destroy()` from §4.
  Nothing needs to be registered with the media scanner (`MediaStore`) or SAF, because the frames never
  leave the app sandbox.
- **Reading the frames:** plain framework APIs work on those absolute paths
  (`BitmapFactory.decodeFile(frame.absolutePath)`). [INFERENCE: the app's image loader also accepts a `File`;
  not verified here.]
- **Cancellation:** see §4.

### 5b. The other frame source: splitting a yt-dlp storyboard sprite (cross-slice with A)

Slice A found that `-f sbN` downloads a storyboard as **one** `.mhtml` whose MIME parts are sprite images
(rows × cols of tiles laid out row-major), i.e. yt-dlp hands over a grid, not frames; the splitting is the
app's job. Frame geometry, sprite sizes and the trimmed-last-sprite case below are **slice A's findings
(`YtdlpFrameSources`), not independently verified here**; the ffmpeg-side form is mine:

```kotlin
// one tile out of a rows×cols sprite, tile size w×h, tile index i (0-based)
val sp = ProcessBuilder(
    ffmpeg.absolutePath,
    "-hide_banner", "-loglevel", "error", "-nostdin", "-y",
    "-i", spriteFile.absolutePath,
    "-vf", "format=rgb24,crop=$w:$h:$x:$y",   // x = (i % cols) * w ; y = (i / cols) * h
    "-frames:v", "1",
    "-q:v", "4",
    File(outDir, "frame_%03d.jpg".format(i + 1)).absolutePath,
)
```

Two constraints that matter, both confirmed by slice A on real sprites:

- **Put `format=rgb24` before `crop`.** The sprites decode as `yuv420p`; cropping an odd-sized last row
  silently yields one row fewer (`crop=80:45` returned 80×44). Converting to `rgb24` first avoids the
  subsampled-chroma constraint entirely [slice A; [INFERENCE] the general AVFrame/crop constraint, not
  re-measured here].
- **The final sprite is trimmed to the bounding box of the frames it holds** (e.g. an 8-frame sb2 sprite
  that is 640×45 instead of the full grid), so a per-tile crop must clamp/stop at the real frame count, which
  is `fps × duration`; frame *i* corresponds to `t = i / fps` (equivalently `i × duration / frame_count`),
  so for a trim window `[start, end]` the strip is built by picking the tile nearest each target time, not by
  assuming the tiles span only the window [slice A].

This route needs the same spawn requirements as §4 (executable in `nativeLibraryDir`, `LD_LIBRARY_PATH`, no
exec from the sandbox, `-nostdin`, drained pipes, kill on cancel). Zero-ffmpeg alternative worth weighing in
the design (a slice C/UI decision, flagged, not verified): the app can draw the *unsplit* sprite directly —
clip a `Box` to one tile and offset the image by `-x/-y` in Compose — for which no process runs at all.

## 6. The no-new-wrapper alternative: let the existing yt-dlp call do it

The idea: add no Kotlin process-runner; instead pass extra yt-dlp options in the request the app already
builds (`DownloadUtil.kt`) so ffmpeg is run by yt-dlp.

- **`--ffmpeg-location` — already done, and it is not an extraction mechanism.** `YoutubeDL.kt:201-202`
  adds it to *every* request [S5], and yt-dlp resolves both `libffmpeg.so` and `libffprobe.so` from it
  (§3) [S24]. Nothing for the app to add; it only decides *which* ffmpeg yt-dlp postprocessing uses.
- **`--postprocessor-args` / `--ppa` — not viable for frames.** `--ppa NAME:ARGS` only alters the arguments
  of an ffmpeg run yt-dlp already performs for its own postprocessing (`--postprocessor-args`, `--ppa`,
  `postproc` option group) [S33]. It cannot add a second output; the app already uses it in exactly that
  sense for artwork cropping (`CROP_ARTWORK_COMMAND` + `--config`, `DownloadUtil.kt:262-263, 1032-1034`)
  [S26].
- **`--exec [WHEN:]CMD` — works, but only *after* a file exists.** Shipped yt-dlp 2025.11.12:
  `postprocessor/exec.py` `ExecPP.run` does `Popen.run(cmd, shell=True)` **inheriting yt-dlp's environment**
  (so `PATH` already contains `nativeLibraryDir` and `LD_LIBRARY_PATH` is set), supports multiple `--exec`,
  substitutes output-template fields, and appends the shell-quoted `filepath` when the template has no field
  [S34]. `WHEN` values are `pre_process, after_filter, video, before_dl, post_process, after_move,
  after_video, playlist`, default `after_move` (`options.py:1762-1769`, `utils/_utils.py:2841`) [S33][S25];
  `after_move` PPs run *after* `MoveFilesAfterDownloadPP`, so `{}` is the final file path
  (`YoutubeDL.py:3799-3803`) [S35]. Two hard limits:
  1. **Timing — fatal for this feature.** Trim happens at configure time, before `--download-sections` runs
     (`DownloadUtil.kt:1292-1295`) [S26]. `before_dl` fires before any file exists; `after_move` fires after
     the section has already been downloaded. Neither gives a filmstrip of the *source* before download.
     Using `--exec` therefore requires downloading first — the filmstrip would have to be produced from a
     throw-away low-quality download (extra network + time), i.e. a different product decision, not a
     wrapper-free shortcut.
  2. **Failure coupling.** `ExecPP.run` raises `PostProcessingError` on a non-zero exit code, and
     `YoutubeDL.py:3760-3764` re-raises unless `params['ignoreerrors'] is True` [S34][S35] — a failed frame
     extraction would mark the user's download as failed. The app sets `--ignore-errors` only on the info
     paths (`ignoreErrors()` in `DownloadUtil.kt`) [S26], so this coupling would have to be handled.
- **Custom command templates (existing app feature).** The app already writes a user-editable
  `CommandTemplate` to a file and passes it via `--config-locations`
  (`executeCustomCommandTask`, `DownloadUtil.kt:1422-1462`; `PreferenceUtil.getTemplate()` [S26]) [S36], so
  arbitrary yt-dlp options — including `--exec` — can reach yt-dlp **without any new code**. That confirms
  the "no new wrapper" route is mechanically open; it changes nothing about the timing and error-coupling
  limits above.

**Verdict.** Routing frame extraction through the *existing* yt-dlp invocation is **viable only for a
post-download use case** and only with `--ignore-errors`-style handling; for the configure-time filmstrip
that #3 requires it is **not viable**, because yt-dlp runs commands either before a file exists or after the
download has finished. A direct app-side spawn of `<nativeLibraryDir>/libffmpeg.so` (§4–§5) is the form that
matches the required timing, and it needs no new native code, no new dependency, and no SELinux or manifest
change — only a small Kotlin runner that sets `LD_LIBRARY_PATH` and uses absolute paths.

## Sources

- [S1] `gradle/libs.versions.toml` in `/mnt/2tb-ext4/Sealplus`, line 34 (`youtubedlAndroid = "0.18.1"`; group
  `io.github.junkfood02.youtubedl-android` for `library`/`ffmpeg`/`aria2c`). Establishes the pinned version.
- [S2] https://repo1.maven.org/maven2/io/github/junkfood02/youtubedl-android/library/maven-metadata.xml and
  `.../ffmpeg/maven-metadata.xml`. Establishes that 0.18.1 exists in Maven Central and is the latest release
  (`lastUpdated 20251116193837`).
- [S3] https://repo1.maven.org/maven2/io/github/junkfood02/youtubedl-android/library/0.18.1/library-0.18.1.pom
  — `scm` = `https://github.com/yausername/youtubedl-android`. Establishes the upstream provenance of the
  published bytes.
- [S4] https://github.com/yausername/youtubedl-android/blob/0.18.1/ffmpeg/src/main/java/com/yausername/ffmpeg/FFmpeg.kt
  (59 lines) — `binDir = nativeLibraryDir`; unzip of `libffmpeg.zip.so` into
  `noBackupFilesDir/youtubedl-android/packages/ffmpeg`; version check by file length; no path getter.
  Also confirmed byte-identical to `ffmpeg-0.18.1-sources.jar`.
- [S5] https://github.com/yausername/youtubedl-android/blob/0.18.1/library/src/main/java/com/yausername/youtubedl_android/YoutubeDL.kt
  (324 lines) — `ffmpegPath`, `ENV_LD_LIBRARY_PATH`, `TMPDIR`, `--ffmpeg-location`, `ProcessBuilder` +
  environment block, `destroyChildProcesses`. Byte-identical to `library-0.18.1-sources.jar`.
- [S6] `library-0.18.1.aar` → `res/raw/ytdlp` → `yt_dlp/version.py`
  (`__version__ = '2025.11.12'`, `RELEASE_GIT_HEAD = 335653be82d5ef999cfc2879d005397402eebec1`).
  Establishes the exact bundled yt-dlp used for the yt-dlp citations.
- [S7] https://github.com/yausername/youtubedl-android/blob/0.15.0/ffmpeg/src/main/java/com/yausername/ffmpeg/FFmpeg.kt
  — the same `libffmpeg.zip.so`-in-jniLibs design already present at 0.15.0. Establishes that the layout is
  not a 0.18 novelty.
- [S8] `ffmpeg-0.18.1.aar` (Maven Central) — `unzip -l` member list and sizes; `readelf -h -d` and
  `strings` of `jni/arm64-v8a/libffmpeg.so`, `libffprobe.so`; `unzip -l jni/arm64-v8a/libffmpeg.zip.so`
  (184 entries, all `usr/lib/…`, no `usr/bin`). Establishes the ELF facts, the `-bsfs`-runnable CLI, the
  Termux `RUNPATH`, and that no second ffmpeg binary exists in the payload.
- [S9] `library-0.18.1.aar` — `unzip -l` (res/raw/ytdlp, libpython.so, libpython.zip.so, libqjs.so);
  `readelf -d jni/arm64-v8a/libpython.so` (`NEEDED libpython3.12.so.1.0`, `libandroid-support.so`).
- [S10] `aria2c-0.18.1.aar` — `jni/<abi>/libaria2c.so` + `libaria2c.zip.so`.
- [S11] AOSP `ApplicationInfo.java` (main) — `nativeLibraryDir` = "Full path to the directory where native
  JNI libraries are stored."
  https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/core/java/android/content/pm/ApplicationInfo.java
- [S12] https://github.com/JunkFood02/youtubedl-android/blob/master/library/src/main/java/com/yausername/youtubedl_android/YoutubeDL.kt
  (284 lines; sets `--ffmpeg-location` and the same env block, but lacks `--js-runtimes`).
- [S13] https://raw.githubusercontent.com/JunkFood02/youtubedl-android/master/ffmpeg/src/main/java/com/yausername/ffmpeg/FFmpeg.kt
  — identical to 0.18.1 (`diff` clean).
- [S14] https://developer.android.com/about/versions/10/behavior-changes-10#execute-permission — section
  "Removed execute permission for app home directory": "Untrusted apps that target Android 10 cannot invoke
  `execve()` directly on files within the app's home directory." (Verified anchor: the page's ids include
  `execute-permission`; `#executable-files` does not exist.)
- [S15] `app/build.gradle.kts` in `/mnt/2tb-ext4/Sealplus` — `minSdk = 24`, `targetSdk = 37`,
  `packaging { jniLibs { useLegacyPackaging = true } }`.
- [S16] AOSP `system/sepolicy` (main), `private/app_neverallows.te` — the `execute_no_trans` neverallow on
  `app_data_file`/`privapp_data_file` for `untrusted_app_29`+ ("Block calling execve() on files in an apps
  home directory … b/112357170"); `app_exec_data_file` never-writable rule; `storage_area_content_file`
  exec denial. https://android.googlesource.com/platform/system/sepolicy/+/refs/heads/main/private/app_neverallows.te
- [S17] AOSP `private/file_contexts` — `/data/app(/.*)? u:object_r:apk_data_file:s0`; `/data/app/.../oat` →
  `dalvikcache_data_file`; no separate label for the app's `lib/` directory.
- [S18] AOSP `public/file.te` — `type apk_data_file, file_type, data_file_type, core_data_file_type;` and
  `type app_data_file, …` ("/data/data subdirectories - app sandboxes").
- [S19] AOSP `private/app.te` — "# Allow apps to read/execute installed binaries":
  `allow appdomain apk_data_file:file { getattr open read ioctl lock map x_file_perms };`
- [S20] AOSP `public/global_macros` — `define(\`x_file_perms', \`{ getattr execute execute_no_trans map }')`.
- [S21] AOSP `frameworks/base/core/jni/com_android_internal_content_NativeLibraryHelper.cpp` — `copyFile`
  sets extracted native libraries to mode 755 ("// Set the mode to 755", `S_IRUSR|S_IWUSR|S_IXUSR|…`);
  caller `copyFileIfChanged` receives `extractNativeLibs`.
  https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/core/jni/com_android_internal_content_NativeLibraryHelper.cpp
- [S22] https://github.com/yausername/youtubedl-android/blob/0.18.1/library/build.gradle.kts and
  `.../ffmpeg/build.gradle.kts` — no `packaging`/`useLegacyPackaging` setting (minSdk 24, compileSdk 34).
- [S23] https://developer.android.com/guide/topics/manifest/application-element#extractNativeLibs —
  "indicates whether the package installer extracts native libraries from the APK to the file system"; and
  "Starting with AGP 4.2.0, the DSL option `useLegacyPackaging` replaces the `extractNativeLibs` manifest
  attribute".
- [S24] yt-dlp 2025.11.12 `yt_dlp/postprocessor/ffmpeg.py` — `FFmpegPostProcessor.__init__` →
  `_determine_executables()` (lines 102-131: file-path location, `libffprobe.so` derivation),
  `_get_ffmpeg_version` → `_get_exe_version_output(path, ['-bsfs'])` (132-136), `executable` (198-199),
  `cmd = [self.executable, …]` + `Popen.run(cmd)` (329-354).
- [S25] yt-dlp 2025.11.12 `yt_dlp/utils/_utils.py` — `check_executable` (2143-2150, PATH resolution via
  `Popen`), `_get_exe_version_output` (2153-2162), `POSTPROCESS_WHEN` (2841).
- [S26] `app/src/main/java/com/junkfood/seal/util/DownloadUtil.kt` — `--download-sections` (1292-1295),
  `CROP_ARTWORK_COMMAND` (262-263) + `--config` (1032-1034), `aria2c` `--downloader …:libaria2c.so` (802),
  `--add-metadata` (841+), `YoutubeDL.getInstance().execute(...)` call sites,
  `executeCustomCommandTask` (1422-1462), `ignoreErrors`. Also: no `ProcessBuilder`/`Runtime.exec` anywhere in
  `app/src`.
- [S27] yt-dlp `options.py` `--ffmpeg-location` help: "Location of the ffmpeg binary; either the path to the
  binary or its containing directory" (1757-1760).
- [S28] AOSP `private/untrusted_app_all.te` — `allow untrusted_app_all self:process ptrace;`;
  `allow untrusted_app_all app_data_file:file { r_file_perms execute };` with `auditallow` (which the
  neverallow then restricts for targetSdk 29+).
- [S29] AOSP `private/domain.te` — `neverallow { domain … -system_server } self:global_capability_class_set
  sys_ptrace;` ("Limit ability to ptrace … processes with other UIDs").
- [S30] `app/src/main/java/com/junkfood/seal/App.kt` — `YoutubeDL.init(this)`, `FFmpeg.init(this)`,
  `Aria2c.init(this)` on the IO dispatcher.
- [S31] `app/src/main/java/com/junkfood/seal/util/VideoInfo.kt` — `VideoInfo.duration: Double?`,
  `data class VideoClip(val start: Int, val end: Int)`.
- [S32] `app/src/main/java/com/junkfood/seal/util/FileUtil.kt` — `Context.getConfigDirectory() = cacheDir`,
  `getConfigFile`, `getCookiesFile`, `getInternalTempDir() = File(filesDir, "tmp")`,
  `getExternalTempDir()`.
- [S33] yt-dlp 2025.11.12 `yt_dlp/options.py` — `--postprocessor-args`/`--ppa` (1637-1641), `--exec`
  `[WHEN:]CMD` + `when_prefix('after_move')` (1762-1769), `--ffmpeg-location` (1757-1760).
- [S34] yt-dlp 2025.11.12 `yt_dlp/postprocessor/exec.py` — `ExecPP.run` (`Popen.run(cmd, shell=True)`,
  `PostProcessingError` on non-zero return).
- [S35] yt-dlp 2025.11.12 `yt_dlp/YoutubeDL.py` — PP error handling (3760-3764), `after_move` ordering after
  `MoveFilesAfterDownloadPP` (3799-3803), exec PP assembly (`__init__.py:729-735`).
- [S36] `app/src/main/java/com/junkfood/seal/util/PreferenceUtil.kt` (`getTemplate()`) and
  `DatabaseUtil.kt` (`getTemplateList()`) — user-editable command templates.
- [S37] GitHub API on `yausername/youtubedl-android`: `git/ref/tags/0.18.1` → annotated tag object
  `864791ae…` → `object.sha = d725d5c9a18c3a99a13ee0308bf78275dc310760`; `commits/master` HEAD = the same
  `d725d5c9…` ("Bump version 0.18.1", 2025-11-16T18:39:19Z); `releases/tags/0.18.1` `published_at`
  2025-11-16T18:48:32Z. Establishes that the pinned 0.18.1 == tag == master HEAD at release, so citing tag
  files is exact.


## Unknowns

Flagged items — none of these change the verdict, but they were not verified on a device:

1. **No device or emulator was available**, so nothing in this report was observed running on Android. Every
   "it is executed" claim is a *code* proof (§3) plus the AOSP policy proof (§2), not a logcat capture.
   Corroboration available cheaply later: `adb shell run-as com.maheshtechnicals.sealplus ls -l` the
   `nativeLibraryDir` (not reachable via `run-as`; use `dumpsys package … | grep nativeLibrary` or
   `pm path`) and a single `ffmpeg -version` spawn from the app.
2. **`nativeLibraryDir`'s literal string** on this app's API 30+ devices (`/data/app/~~…==/<pkg>-…/lib/<abi>`)
   is [INFERENCE] from the AOSP layout; the app must read it from `applicationInfo`, and no source in the
   repo hardcodes it.
3. **`extractNativeLibs="true"` in the merged manifest** is [INFERENCE] from `useLegacyPackaging = true`
   ([S15][S23]); the merged manifest was not built (no Android SDK/JDK on this host).
4. **App-process working directory and base `PATH`** are [INFERENCE] (inherited from zygote/init). The
   recommended command is immune to both (absolute paths; `LD_LIBRARY_PATH` set explicitly), and the
   library's reliance on `System.getenv("PATH")` for `libaria2c.so` implies `PATH` is non-null.
5. **Whether the app's image loader accepts a `File`** for the frames (Coil 3) was not checked; the
   framework's `BitmapFactory.decodeFile` definitely works on those paths.
6. **`pstree`/`grep -oP` availability on device** (the library's `destroyChildProcesses`) is untested;
   irrelevant unless the frame runner copies that idiom (do not).
7. **16 KB page-size compatibility** of these Termux-built `libffmpeg.so`/`lib*` binaries with `targetSdk 37`
   was not examined — out of slice, but it is a build-time/packaging risk worth a sibling check.
