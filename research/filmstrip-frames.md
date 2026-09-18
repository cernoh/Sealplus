# Filmstrip frames for Sealplus: mechanism per source class, cost, and fallback

Resolution of wayfinder ticket `cernoh/Sealplus#3` (map: `cernoh/Sealplus#1`).

Three parallel slices produced the evidence. This file is the answer; the slices hold the detail:

- `research/filmstrip-frames-slice-a-ytdlp.md` — what yt-dlp reports or writes (slice A)
- `research/filmstrip-frames-slice-b-ffmpeg.md` — executing the bundled ffmpeg (slice B)
- `research/filmstrip-frames-slice-c-cost.md` — cost, memory, lazy extraction, partial and remote files (slice C)

Slice C's numbers are **x86_64 desktop with NVMe**, not Android: the ratios hold on a phone, the
absolute milliseconds do not. Slice C measured them with `ffmpeg 9.0.1`; the app ships an older
bundled ffmpeg (slice B), so check a flag against that binary before copying it.

## Answer in one screen

| Question | Answer |
| --- | --- |
| Which frame assets exist per source class? | A multi-frame sprite exists only where the extractor emits storyboard formats: YouTube, Twitch VODs, France.tv, Mediasite, Panopto, DASH sources with image AdaptationSets, SMIL `imagestream-*`. Every other source offers **one still** only. |
| Can yt-dlp write frames? | **No.** No flag writes individual frames. `-f sbN` writes **one** `.mhtml` whose MIME parts are whole sprites. Frame export is an open upstream feature request. |
| Can the app execute the bundled ffmpeg? | **Yes, with no new dependency.** `<nativeLibraryDir>/libffmpeg.so` is executable on Android 10+ (the app-home-directory exec ban does not cover `/data/app`). The library already executes binaries from that directory on every yt-dlp run. |
| Cost for a 2-hour video | 12 input-side seeks ≈ 5.3 s on 10 min of 1080p; a full decode pass ≈ 700 s for 2 h. A YouTube storyboard replaces all of it with 5 GETs / 109 KB / 0.87 s. |
| Frames mid-download | Fragmented MP4: yes, up to the received byte prefix. Non-fragmented MP4 with `moov` last: **no**, until the file is complete. |
| Frames from the remote URL | Yes: ffmpeg reads HTTPS and seeks by byte range (~80 KB, one request per frame). The URL expires in ~6 h and is IP-bound. |
| Fallback | Storyboard → remote ffmpeg frames → partial-file frames → single poster → solid placeholder strip. Trimming stays enabled in every case. |

## 1. Source classes: what exists, and what yt-dlp can write

**The ticket's premise is wrong on one point.** There is **no top-level `storyboards` key** in
`--dump-single-json` (observed: 77 top-level keys, `storyboards` absent). The `storyboards` key that
looks familiar is in **YouTube's player response**, which yt-dlp reads at
`yt_dlp/extractor/youtube/_video.py:3768-3771`.

Storyboards arrive as entries in `formats`, and a storyboard is a **tile sprite**, not a frame:

```json
{
  "format_id": "sb3", "format_note": "storyboard",
  "ext": "mhtml", "protocol": "mhtml", "acodec": "none", "vcodec": "none",
  "url": "https://i.ytimg.com/sb/<id>/storyboard3_L0/default.jpg?sqp=...&sigh=...",
  "width": 48, "height": 27, "fps": 0.4694835680751174,
  "rows": 10, "columns": 10,
  "fragments": [{"url": "https://i.ytimg.com/sb/<id>/storyboard3_L0/default.jpg?sqp=...", "duration": 213.0}]
}
```

- `frame_count` is not exposed; it is exactly `fps * duration` (`_video.py:3787-3800`).
- The **format-level `url` is a template** containing `$M` for multi-sprite levels. Only
  `fragments[].url` values are directly fetchable.
- Sprites are served as **`image/webp`** even from `.jpg` URLs (Android decodes WebP since API 14).
- Tiles are **row-major**; tile *i* is the frame at `t = i * duration / frame_count` (slice A verified
  this with PSNR against real video frames: 46.5 dB at the first tile, and the row-major reading beats
  the column-major reading by ~5 dB).
- The **last sprite is trimmed** to the bounding box of its frames, so clamp by `frame_count`, not by
  `rows * columns`.

**`--write-thumbnail`, `--write-all-thumbnails`, `--list-thumbnails` and `--convert-thumbnails` never
touch storyboards**: `_write_thumbnails()` iterates `info_dict['thumbnails']` only
(`yt_dlp/YoutubeDL.py:4503-4548`), and storyboards are not in that array. `--convert-thumbnails`
runs `FFmpegThumbnailsConvertorPP` on the thumbnail list, so it cannot split sprites either.

**No flag writes frames.** The storyboard downloader is `MhtmlFD`
(`yt_dlp/downloader/mhtml.py`), registered for `protocol: 'mhtml'`; it writes one MHTML file and never
splits, crops or calls ffmpeg. Observed: `-f "sb0,sb1,sb2,sb3"` produced exactly four `.mhtml` files
and no images. Frame export is open upstream: yt-dlp#2048 (storyboard as jpg, open since 2021-12-19)
and yt-dlp#11386 (storyboards to video, open since 2024-10-28). No official plugin splits sprites.

**Detector to use in the app** (a format is a storyboard when both codecs are `none`):

> `vcodec == "none" and acodec == "none"` and (`format_note` contains `"storyboard"` or
> `ext == "mhtml"`); it is a **tile sprite** only when it also carries `rows`, `columns` and
> `fragments[]`.

That last clause matters: the SMIL class (`format_note: "SMIL storyboards"`) is one image URL per
entry with **no** tile metadata, and the DASH class sets `protocol: "mhtml"` only for
`image/avif`/`image/jpeg` representations (`extractor/common.py:3187-3188`).

Class table with per-extractor citations: slice A §3.

**The cheapest path uses no extra yt-dlp run at all.** The app already fetches `--dump-single-json`
(`util/DownloadUtil.kt:368`), so the sprite URLs are already in the payload it parses. Those
`fragments[].url` values answer a plain GET with no cookies and no special headers (observed:
`HTTP 200`, `image/webp`, 20,062 B), exactly as `util/ThumbnailUtil.kt:56-95` already fetches stills
through OkHttp. If the app prefers yt-dlp to fetch, the fallback is
`yt-dlp -f mhtml -o "%(id)s.sb.%(ext)s" <url>`, then parse the MIME parts and delete the file.

On a source with no storyboard, that request fails hard: `-f mhtml` on archive.org returns
`ERROR: Requested format is not available`. For that class yt-dlp offers nothing, and the app must
decode frames from the video itself.

## 2. Executing the bundled ffmpeg

**Verdict: the app can spawn it, with no new dependency, no manifest change and no SELinux change.**

- The pinned `youtubedlAndroid = "0.18.1"` resolves to upstream `yausername/youtubedl-android` tag
  `0.18.1` (the published sources are byte-identical to that tag; the `junkfood02` fork is stale at
  0.17.2 and has no ffmpeg-relevant difference).
- Executables ship inside the AARs as `jni/<abi>/*.so`, so they land in the **native library
  directory**: `libffmpeg.so` (a real ffmpeg 7.1.1 CLI), `libffprobe.so`, `libpython.so`,
  `libaria2c.so`. The shared-library payload arrives as `libffmpeg.zip.so` and is unzipped into
  `<noBackupFilesDir>/youtubedl-android/packages/ffmpeg/usr/lib`.
- **Android 10's ban** ("apps that target Android 10 cannot invoke `execve()` on files within the app's
  home directory") is enforced by SELinux and is label-scoped: `app_data_file` (the home directory)
  carries `neverallow … execute_no_trans`, while `appdomain` holds `execute` and `execute_no_trans`
  on `apk_data_file`, and `/data/app(/.*)?` is `apk_data_file`. The app declares `targetSdk = 37`,
  `minSdk = 24`, and its `packaging { jniLibs { useLegacyPackaging = true } }` extracts the libraries
  to disk, where AOSP `chmod`s them to 0755.
- **Proof that this path is already exercised**: `YoutubeDL.executeImpl` builds
  `ProcessBuilder(<nativeLibraryDir>/libpython.so, <noBackup>/…/yt-dlp/yt-dlp, args)` and sets
  `LD_LIBRARY_PATH`, `PATH += nativeLibraryDir`, `PYTHONHOME`, `HOME`, `TMPDIR`. It also passes
  `--ffmpeg-location <nativeLibraryDir>/libffmpeg.so`, which yt-dlp resolves to both `libffmpeg.so`
  and `libffprobe.so` and then executes with `Popen`. The app additionally resolves `libaria2c.so` by
  name off `PATH` (`util/DownloadUtil.kt:802`).
- **No public accessor exists** for the path (`FFmpeg.binDir` and `YoutubeDL.ffmpegPath` are private),
  so the app computes it: `File(context.applicationInfo.nativeLibraryDir, "libffmpeg.so")`. That one
  line is the only missing API surface. `FFmpeg.init(context)` (already called at `App.kt:144`)
  unpacks the shared libraries, and it is idempotent.
- **Required environment**: `LD_LIBRARY_PATH=<noBackupFilesDir>/youtubedl-android/packages/ffmpeg/usr/lib`
  (the binary's `RUNPATH` is the Termux path `/data/data/com.termux/files/usr/lib`, which does not
  exist here), `TMPDIR=context.cacheDir`, **absolute paths everywhere** (cwd is not writable and must
  not be relied on), `-nostdin`, and drain stdout or ffmpeg can block.
- **PTRACE is unavailable** (self only), so no `strace` from app code; it does not block spawning.
- The app has **zero** `ProcessBuilder`/`Runtime.exec` today, so this introduces the first one.
  Cancellation is the app's job: hold the `Process` in the ViewModel and `destroy()` it on dismiss,
  or an ffmpeg pass over a long video outlives the sheet. Do not copy the library's
  `pstree | grep | xargs kill` helper; `pstree` is not in AOSP.

Concrete form (slice B §5, with `Locale.US` for the `fps=` value — a comma decimal breaks the filter
graph):

```kotlin
val ffmpeg = File(context.applicationInfo.nativeLibraryDir, "libffmpeg.so")
val ffLibs = File(context.noBackupFilesDir, "youtubedl-android/packages/ffmpeg").resolve("usr/lib")
val outDir = File(context.cacheDir, "filmstrip/$videoId").apply { mkdirs() }
val n    = 8
val dur  = (videoInfo.duration ?: 0.0).coerceAtLeast(1.0)
val fps  = "%.6f".format(Locale.US, n / dur)

val cmd = listOf(
    ffmpeg.absolutePath,
    "-hide_banner", "-loglevel", "error", "-nostdin", "-y",
    "-i", inputFile.absolutePath,
    "-an", "-sn",
    "-vf", "fps=$fps,scale=-2:120",
    "-frames:v", n.toString(),
    "-q:v", "5",
    "-f", "image2",
    File(outDir, "frame_%03d.jpg").absolutePath,
)
val p = ProcessBuilder(cmd).redirectErrorStream(true).apply {
    environment()["LD_LIBRARY_PATH"] = ffLibs.absolutePath
    environment()["TMPDIR"] = context.cacheDir.absolutePath
}.start()
val log = p.inputStream.bufferedReader().readText()
val code = p.waitFor()   // 0 = ok; non-zero ⇒ surface `log`
```

Cleanup: `outDir.deleteRecursively()` when the sheet closes, plus `Process.destroy()`. The frames
never leave the app sandbox, so no media-scanner or SAF work is needed.

**The no-new-wrapper alternative does not work for a configure-time filmstrip.** `--ffmpeg-location`
is already set by the library (it is not an extraction mechanism); `--ppa` only alters yt-dlp's own
ffmpeg run (the app already uses it for artwork cropping); `--exec` runs at `before_dl` (no file yet)
or `after_move` (download finished), and a non-zero exit raises `PostProcessingError`, which fails the
user's download. So routing extraction through yt-dlp is post-download only.

## 3. Cost, memory, and lazy extraction

Measured on a synthetic 10-minute 1920x1080 30 fps H.264 clip (438 MB, `+faststart`) and a 2-hour
twin, plus a live YouTube format-160 URL:

| Measurement | Result |
| --- | --- |
| 12 input-side `-ss` seeks, one frame each | **5.3 s total, 424 ms mean** (36 runs, range 272–542 ms), flat across the timeline |
| One pass, `-vf fps=1/50 -frames:v 12` | **73–75 s** quiet (up to 119 s on a loaded host) — the seek path wins **15–20×** |
| `-skip_frame nokey`, whole-file scan | **5 s per 10 min, 48 s per 2 h**, but **no gain per seek** (527 ms vs 424 ms); frames snap to a keyframe, up to ~8 s off |
| Scaling | A full pass costs ∝ duration (20 min = 116 s ⇒ 2 h ≈ 700 s [INFERENCE]); keyframe-only ≈ 0.4–0.5 s per minute; per-seek cost does **not** grow with length (~1.5 s at t = 7000 s of a 2 h file) |
| Remote seek | ~1.2–1.5 s per frame; 12 remote seeks = 12.6 s |
| YouTube storyboard | sb0 298 KB / 1.8 s; **sb1 109 KB / 0.87 s (108 tiles at 160x90, 5 GETs)**; sb3 20 KB / 0.16 s — replacing ~46 s of ffmpeg work |

The scale filter is free: a full-resolution single frame costs the same 348–541 ms as a scaled one.
The cost is process start, container open and decode-to-seek-point.

**Recommended budget**: **12 frames** (8–24 is the sane band), interval `duration / 12`, frame size
**160x90**. The existing slider is a full-width Material 3 `RangeSlider` with 12 dp padding
(`ui/page/download/VideoSectionSlider.kt`), so the strip is roughly screen width − 24 dp: 28 dp per
tile at 12 frames.

**Memory**: 160x90 `ARGB_8888` is 56.3 KiB per frame ⇒ **675 KiB for 12 frames** (432 KiB at
128x72, halved in `RGB_565`), against a device heap of 128–512 MB. Disk cost is 35–70 KB of JPEG.
Prefer `Bitmap.Config.HARDWARE` for tiles that are only drawn.

The trap is the storyboard path: a 2-hour video holds ~3,650 frames, which as decoded 160x90 bitmaps
is **200 MiB**. Decode **one sprite sheet** (800x450 = 1.37 MiB) at a time and draw tiles with a
source rect.

**Lazy extraction works**: seeking is true random access and the cost is per process, not per
position or per pixel. Paint empty tiles on a `surfaceVariant` track, then fill by quantised tile
index (`floor(t / interval)`, never raw slider pixels), with a one-window lookahead and a per-session
cache keyed by `(videoId, formatSelector, intervalIndex)`. A 12-frame cache is 675 KiB of bitmaps.
For storyboards, "lazy" degenerates to fetching 5 sprites and painting as they land. On a phone,
expect 12 serial seeks at 1–2 s each; 2–4 concurrent ffmpeg processes put the first tile on screen in
1–2 s [INFERENCE].

## 4. Partial file and remote URL

**Fragmented MP4 mid-download: usable.** The YouTube format-160 prefix is
`ftyp` + `moov` (711 B) + `sidx` + `moof` + `mdat`, so a **1.2 KB** head carries the resolution *and*
the full duration. 524,288 B (25.5 % of the bytes) decoded 49.4 s of 213 s (23.2 % of the timeline);
seeks past the prefix fail with a **decode error** (`Invalid NAL unit size`, rc=234), not a clean
"not found". Derive the usable prefix from download progress, not from a probe.

**Non-fragmented MP4 with `moov` last: unusable until complete.** Measured twice locally —
`moov atom not found` with 420 MB of a 438 MB file. Measured over HTTP: ffmpeg's first request was
`Range: bytes=0-`, i.e. the whole 21.98 MB file before one frame. This is the container's requirement,
and Android states it too: for 3GPP and MPEG-4, "the `moov` atom must precede any `mdat` atoms".
**The app's own clip output is this bad case**: `--download-sections` forces `FFmpegFD`, which appends
`-c copy` without `+faststart` (`yt_dlp/downloader/__init__.py:85`, `downloader/external.py`), so a
clip still downloading is opaque to an extraction ffmpeg. For clips, frames must come from the remote
URL or wait for the file. WebM is streamable by design but needs a keyframe `Cues` element to seek
(documented, not measured).

**Remote URL: works, byte-exact.** ffmpeg indexes with `sidx` and re-requests only the target byte
range: `Range: bytes=979374-` for `t = 100 s`, ~80 KB and one extra request per frame. Headers were
**not** needed for the tested googlevideo URL (1,208 ms, rc=0 with no `-headers`); per-format
`http_headers` and cookies are the documented route for hosts that need them
(`man ffmpeg-protocols`: `headers`, `cookies`, `user_agent`, `request_size` "when expecting to seek
frequently").

Risks: the URL carries `expire` (**~6 h**), `ip=` and signature params, so it is time- and IP-bound
and must be consumed inside the configure session; googlevideo answered byte ranges but **refused a
suffix range** (`416`), so never implement "read the tail for `moov`".

**What the app must add before any of this works** (grep-confirmed gaps, slice C §4c):

- The Kotlin models drop `http_headers`, `rows`, `columns` and `fragments`
  (`util/VideoInfo.kt:100-155` has `url`, `formatId`, `protocol`, `ext`, `width`, `height`,
  `formatNote` only). Storyboard and remote-frame paths both need them.
- `Format.isAudioOnly()` (`util/VideoInfo.kt:120`) returns true for a storyboard (`vcodec == "none"`),
  so `download/Task.kt:162-163` and `download/TaskFactory.kt:39-41` already **mis-count storyboards
  as audio-only formats**. New code must exclude `format_note == "storyboard"` / `ext == "mhtml"`.
- Storyboard formats do **not** leak into the format UI today (`FormatPage.kt:459-471` keeps only
  video-only, audio-only and muxed), and nothing in `app/src/main/java` mentions `storyboard`,
  `mhtml` or `sprite`.

**The precedent already ships**: the configure screen fetches a **remote image** before the download
and renders it through Coil 3 with an OkHttp fetcher and a desktop Chrome `User-Agent`, no cookies
(`ui/page/home/NewHomePage.kt:1563`, `App.kt:79-104`, `util/ThumbnailUtil.kt:55-135`). A remote
filmstrip or a storyboard fetch is that same pattern with more requests.

## 5. Fallback chain

Ordered so the strip degrades instead of breaking:

1. **Storyboard sprites** — 1–5 GETs, 20–109 KB, no ffmpeg. Where available (YouTube today).
2. **Remote ffmpeg frames** — 12 seeks on the format URL, ~1.2 s each, painted per tile. Needs the
   header plumbing for non-YouTube hosts.
3. **Local frames while downloading** — only when the partial file is fragmented or already carries
   `moov` (true for direct `https` downloads of YouTube formats; false for clip output).
4. **Single poster** — the thumbnail the app already holds, cropped across the strip and dimmed,
   under the same slider: identical gestures and hit targets, already cached.
5. **Placeholder strip** — a solid `surfaceVariant` track with a subtle gradient, fully draggable.
   This is also the correct state *while* lazy frames are in flight.
6. **Trim stays enabled.** A missing frame must never block cutting and needs no error toast; the
   placeholder *is* the error state.

## Unknowns

- **Android absolute cost** — no device or SDK on this host. Every timing is desktop x86_64; the
  ratios are structural, the milliseconds are not.
- **Storyboard coverage beyond YouTube** — the sprite path was measured on YouTube; the other
  extractors are source-read only. Whether every YouTube video and client supplies `sb` formats is
  untested.
- **Sprite URL lifetime** — the ~6 h `expire` and IP binding were read from the dump, not stress
  tested.
- **Flag availability in the bundled ffmpeg** — slice B confirmed the binary is a 7.1.1 CLI; individual
  flags (`-fps_mode` vs `-vsync 0`) must be checked against it, not against ffmpeg 9.
- **Parallel ffmpeg seeks** — 2–4 concurrent processes were not benchmarked.
- **WebM mid-download** and **`sidx`-less fragmented MP4** — documented/search behaviour only.

## Acceptance check

The ticket asked for "a report naming the concrete mechanism per source class, the exact invocation
form (arguments, output paths, cleanup), the documented or measured cost, and the fallback when no
frames can be obtained at all." §1 gives the mechanism per class, §2 the exact invocation with paths
and cleanup, §3 and §4 the measured cost, §5 the fallback chain.
