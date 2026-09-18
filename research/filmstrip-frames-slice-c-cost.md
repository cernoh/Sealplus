# Filmstrip frames for Sealplus — cost, memory, lazy extraction, partial files, remote URLs (Slice C)

Research for `cernoh/Sealplus#3`. Slice C = **cost / memory / lazy extraction / partial file / remote URL**.
Siblings own (A) what yt-dlp exposes, (B) running the bundled ffmpeg binary from the app. Nothing here
duplicates those.

## Question

1. What does frame extraction really cost — N seeks vs one pass, `-skip_frame nokey`, 10 min → 2 h?
2. What filmstrip frame count / frame size is sane, and what memory does it cost on Android?
3. Can frames be produced lazily while the user scrolls, and is seeking random-access?
4. Can frames come from a **partial** file (mid-download) or from the **remote stream URL**?
5. What is the fallback when no frame can be obtained at all?

## Method and environment

* Host: NixOS, AMD Ryzen 7 3700X (8C/16T, x86_64), 32 GB RAM, NVMe. **A desktop, not a phone** — see §1e.
* `ffmpeg 9.0.1` from nixpkgs,
  `/nix/store/nm4ih3jrw0zma6qxhk5s2ks2r0gppzfl-ffmpeg-9.0.1-bin/bin/ffmpeg`, built `--enable-network`
  with TLS via `--enable-gnutls` (measured with `ffmpeg -hide_banner -protocols` / `-version`).
* **Synthetic clip** (required by the ticket): `testsrc2=size=1920x1080:rate=30:duration=600` +
  `sine`, `libx264 -preset veryfast -crf 23 -pix_fmt yuv420p`, `-c:a aac`, `-movflags +faststart`.
  Result: 600.000 s, 18 000 frames, 438 176 183 B, **5.84 Mbps**, `ftyp`@0, **`moov`@32** (635 291 B),
  `mdat`@635 331. A twin with `moov` last (`-c copy`, no `+faststart`): `moov`@437 540 892.
  A **2-hour** twin was built in 59 s by stream-copy looping the 10-minute file
  (`-stream_loop 11 -c copy -movflags +faststart`): 7200.234896 s, 5 259 826 895 B, `moov`@32 (9 336 719 B).
  testsrc2 is high-entropy noise: a worst case for bitrate and for JPEG frame size.
* **Real remote source**: a sibling agent's `yt-dlp --dump-single-json` of a public YouTube video
  (`/tmp/sealplus-research/info.json`). Format `160` (256x144, `https`, 2 058 142 B, `duration=213.040`,
  `container=mp4_dash`) drove the remote, partial-file and storyboard tests. Its URL is never quoted here.
* **`-vsync` no longer exists in ffmpeg 9.0.1** (`Unrecognized option 'vsync'`); `-fps_mode passthrough`
  replaces it. All commands below use the ffmpeg 9 spelling.
* ⚠ **The app does not run ffmpeg 9.** It ships `io.github.junkfood02.youtubedl-android:ffmpeg:0.18.1`
  (`gradle/libs.versions.toml`), which is an older ffmpeg. Before any command below is copied into the
  app, **check the flag against the bundled binary** — `-fps_mode` does not exist before ffmpeg 5.0
  (use `-vsync 0` there), while `-ss`, `-skip_frame`, `-headers`, `-cookies` are old and stable.
  Whether that build even has the needed decoders is slice B's question.

Scripts, logs and extracted frames: `/tmp/sealplus-research/scratch-C/`
(`bench-seeks.sh`, `bench2.sh`, `bench-scale.sh`, `bench-pos.sh`, `bench-remote.sh`, `bench-http.sh`,
`bench-partial.sh`, `bench-partial2.sh`, `bench-partial3.sh`, `bench-storyboard.sh`, `atomscan.pl`,
`httpd.pl`).

## 1. Cost, measured

### 1a. N input-side seeks vs one pass with `-vf fps=…`

The shape a lazy filmstrip would use:

```
ffmpeg -nostdin -hide_banner -loglevel error -ss <T> -i <file> \
       -frames:v 1 -vf scale=160:-2 -f image2 -y frame_<i>.jpg
```

12 seeks at T = 25, 75, … 575 s on the 10-minute clip, three repetitions (milliseconds):

| rep | individual seeks | total |
| --- | --- | --- |
| 1 | 493 502 415 402 395 405 483 513 437 464 337 500 | **5346** |
| 2 | 453 422 453 329 415 386 354 381 367 391 361 340 | **4652** |
| 3 | 404 351 418 272 370 542 391 460 478 529 536 534 | **5285** |

**Mean 424 ms per seek** (36 runs, 15 283 ms; range 272–542 ms) and **flat across the timeline** —
T = 25 s and T = 575 s cost the same. Seeking is random access.

One pass over the same file:

```
ffmpeg -nostdin -hide_banner -loglevel error -i <file> \
       -vf "fps=1/50,scale=160:-2" -frames:v 12 -f image2 -y pass_%02d.jpg
```

| session | ms |
| --- | --- |
| first, quiet host | 73 110 / 75 431 |
| later, host shared with the other research agents | 112 315 / 82 396 / 119 155 / 96 400 |

**≈73–75 s quiet, up to ≈119 s contended, for the same 12 frames.** N seeks win by **15–20×**:
5.3 s versus 75 s on a 10-minute 1080p clip.

Control — the scale filter is *not* the cost: `-ss 300 -i file -frames:v 1` **without** `-vf scale`
(full 1920x1080 JPEG out) took 491 / 541 / 348 ms, i.e. the same as with `scale=160:-2`. The time goes
into process start, container open (`moov` parse), decode-to-seek-point and JPEG encode.

### 1b. `-skip_frame nokey`

| variant | ms |
| --- | --- |
| whole-file keyframe-only scan: `ffmpeg -skip_frame nokey -i f -vf "fps=1/50,scale=160:-2,tile=4x3" -frames:v 1 out.jpg` | 5036 / 4780 / 5448 |
| first 12 keyframes only: `ffmpeg -skip_frame nokey -i f -fps_mode passthrough -vf scale=160:-2 -frames:v 12 out_%02d.jpg` | 1239 / 1149 / 2313 |
| 12 keyframe-only **seeks**: `ffmpeg -skip_frame nokey -ss <T> -i f -fps_mode passthrough -frames:v 1 …` | 6321 total, 407–723 ms each |

* The **whole-file** keyframe-only scan is the real win: **≈5 s instead of ≈75 s** for the same 12
  frames, because only I-frames are decoded.
* `-skip_frame nokey` **does not help the per-seek case** (527 ms mean vs 424 ms): the demuxer still
  has to find the seek point and the process still has to start.
* The clip holds **72 keyframes in 600 s** ⇒ GOP ≈ 250 frames ≈ **8.33 s**. So keyframe-only frames
  snap to a keyframe, up to ~8 s off the requested time — fine for a filmstrip, not for exact trim
  preview. [INFERENCE] A 2-hour video at the same GOP has ≈ 864 keyframes and the keyframe-only scan
  costs ≈ 60 s; measured value at 2 h: **48 s** (§1c).

### 1c. Scaling 10 minutes → 2 hours (measured on the 5.26 GB twin)

| measurement | result |
| --- | --- |
| whole-file **keyframe-only** scan of the full 2 h (`fps=1/600,tile=4x3`) | **47 976 ms** |
| full pass over the first 10 min of the 2 h file | 61 615 / 54 125 ms |
| full pass over 20 min | **116 379 ms** |
| seeks at t = 100 / 1800 / 3600 / 5400 / 7000 s (round 1) | 447 / 1275 / 1480 / 1499 / 1466 ms |
| the same timestamps (round 2) | 542 / 1323 / 1308 / 1442 / 1672 ms |
| re-probe under heavier host load: 2 h at t=60 / t=5910 | 1003 / 1032 and 922 / 854 ms |

**Scaling law (observed):**

* **One full pass costs proportionally to duration.** 10 min → 54–62 s, 20 min → 116 s (×2 within 5 %),
  so 2 h → ≈ **700 s (≈12 min)**. [INFERENCE], extrapolated from the 20-minute measurement.
  Equivalently ≈ 5.8 s of decode per minute of this 1080p30 5.84 Mbps clip.
* **A keyframe-only scan costs ≈ 0.4–0.5 s per minute** (5 s per 10 min; 48 s per 120 min) — **~15×
  cheaper than a full pass, and it produces the whole 2-hour filmstrip in 12 tiles.**
* **Per-seek cost does not grow with file length.** Every position is directly addressable: a seek to
  t = 7000 s of a 2-hour file took ~1.5 s, against ~700 s for a full pass of the same file.
  The clean 36-run sweep on the 10-minute file is flat (272–542 ms at every position); later runs on
  the contended host scattered 0.4–2.0 s at the *same* positions in both files, so I **do not claim a
  position dependence** — the noise is host contention (parallel research agents, page cache), not
  file position. Design for **≈0.5 s (desktop) and up to ~2 s (worst observed)** per seek.

### 1d. The measure-zero path: YouTube storyboard sprites (measured)

A sibling slice reported that YouTube exposes `storyboard` formats. They are present in the
`--dump-single-json` produced by the app's shipped yt-dlp, as formats `sb0…sb3`
(`protocol: mhtml`, `format_note: storyboard`), and I measured all four levels against the live URLs
myself:

| level | tile | grid | sprite sheet | fragments | **total bytes** | **wall** |
| --- | --- | --- | --- | --- | --- | --- |
| sb0 | 320x180 | 3x3 | 960x540 | 12 | 298 158 | 1838 ms |
| sb1 | 160x90 | 5x5 | 800x450 (last 800x180) | 5 | **108 954** | **866 ms** |
| sb2 | 80x45 | 10x10 | 800x450 (last 640x45) | 2 | 44 094 | 310 ms |
| sb3 | 48x27 | 10x10 | 480x270 | 1 | **20 062** | **157 ms** |

* Every sprite is served as **`image/webp`** (magic `RIFF`/WEBP) even though the URL ends `.jpg`;
  a fetch **with no headers and no cookies** returned `200`, 20 062 B, `image/webp`. Android decodes
  WebP from **API 14 / 4.0** (lossy) onward, so `BitmapFactory`/Coil handle these natively
  (Android "Supported media formats", image table: WebP decoder "Android 4.0+").
* Geometry is fixed per level and the **last sprite is trimmed** to the bounding box of its frames
  (measured: sb1's 5th sheet is 800x180, sb2's 2nd is 640x45), so tiles must be clamped by the real
  frame count. `sb1` declares `rows=5, columns=5, fps=0.507` ⇒ ≈1.97 s per frame and 108 frames for
  this 213 s video; frame *i* is at `i × duration / frame_count`, tiles row-major (the row-major
  ordering is slice A's PSNR verification, not mine).
* **This beats ffmpeg extraction by orders of magnitude.** 108 frames at 160x90 arrive in **109 KB
  and 0.87 s**, in 5 GETs and **zero ffmpeg processes**; the local equivalent (108 × 424 ms) would be
  ≈46 s of ffmpeg. Even the finest level (`sb0`, 320x180 tiles) costs only 298 KB / 1.8 s.
* **But it is not a replacement for ffmpeg:** it exists only where the extractor produces a
  storyboard (YouTube today), it is fixed-interval (~2 s here), and it needs new app-side plumbing —
  see §4c.

### 1e. Android is not this host (caveat)

[INFERENCE] All figures above are x86_64 desktop with NVMe. The app ships `arm64-v8a`,
`armeabi-v7a`, `x86`, `x86_64` (`app/build.gradle.kts:21,60`), and a mid-range phone has a much
slower single-thread CPU, cold caches and flash. Expect absolute per-seek and per-pass costs several
times higher; the **ratios** (N seeks ≪ one pass; keyframe-only ≪ full pass; ~50–100 KB per
storyboard level vs seconds of ffmpeg) are structural and hold. Do not quote 424 ms / 75 s as
Android numbers.

## 2. A sane budget

### 2a. Where the strip is drawn

The trim UI already exists — `VideoSelectionSlider` / `VideoClipDialog`
(`app/src/main/java/com/junkfood/seal/ui/page/download/VideoSectionSlider.kt:66-160`) is a full-width
Material3 `RangeSlider` with `padding(horizontal = 12.dp)` inside a `Row`, and the range is in
**seconds**: `videoDurationRange = 0f..(videoInfo.duration?.toFloat() ?: 0f)`
(`ui/page/downloadv2/configure/FormatPage.kt:620`). The strip it would sit behind is therefore
≈ **screen width − 24 dp** (≈336 dp on a 360 dp phone) with a 24 dp thumb.

At one frame per tile: 8 tiles ⇒ 42 dp/tile, 12 tiles ⇒ 28 dp/tile. At density 4 (xxxhdpi) that is
168 px and 112 px; at density 3 (xxhdpi) 126 px and 84 px. Frame widths of **128–160 px** cover every
density with headroom, and Coil/`BitmapFactory` downsample to the drawn size anyway.

### 2b. Decoded bitmap cost

Android stores pixels per `Bitmap.Config`: `ARGB_8888` — "Each pixel is stored on 4 bytes", the
default since API 9; `RGB_565` — "Each pixel is stored on 2 bytes"; `ARGB_4444` — 2 bytes but
deprecated in API 29 and coerced to `ARGB_8888` since KITKAT; `HARDWARE` — "stored only in graphic
memory … optimal for cases, when the only operation with the bitmap is to draw it on a screen".
<https://developer.android.com/reference/android/graphics/Bitmap.Config>
The same 4-byte rule is stated on the official performance page (a 4048x3036 photo at `ARGB_8888`
"takes about 48MB of memory (4048*3036*4 bytes)"): <https://developer.android.com/topic/performance/graphics>

`bytes = w × h × bpp`:

| frame size (16:9) | ARGB_8888 | RGB_565 |
| --- | --- | --- |
| 48 x 27 | 5 184 B (5.1 KiB) | 2 592 B |
| 80 x 45 | 14 400 B (14.1 KiB) | 7 200 B |
| 96 x 54 | 20 736 B (20.3 KiB) | 10 368 B |
| 128 x 72 | 36 864 B (36.0 KiB) | 18 432 B |
| **160 x 90** | **57 600 B (56.3 KiB)** | 28 800 B |
| 320 x 180 | 230 400 B (225 KiB) | 115 200 B |

Totals for a frame count (ARGB_8888):

| count | @80x45 | @96x54 | @128x72 | @160x90 | @320x180 |
| --- | --- | --- | --- | --- | --- |
| 8 | 113 KiB | 162 KiB | 288 KiB | 450 KiB | 1.76 MiB |
| 12 | 169 KiB | 243 KiB | 432 KiB | **675 KiB** | 2.64 MiB |
| 24 | 338 KiB | 486 KiB | 864 KiB | 1.32 MiB | 5.3 MiB |
| 100 | 1.37 MiB | 1.98 MiB | 3.52 MiB | 5.49 MiB | 21.9 MiB |
| 300 | 4.1 MiB | 5.9 MiB | 10.5 MiB | 16.5 MiB | 65.8 MiB |
| 3 653 | 50 MiB | 72 MiB | 128 MiB | **200 MiB** | 800 MiB |

For contrast, the Java-heap ceiling is device-defined — `ActivityManager.getMemoryClass()`
"Return the approximate per-application memory class of the current device"
<https://developer.android.com/reference/android/app/ActivityManager#getMemoryClass()> — commonly
128–512 MB, lower on 32-bit `armeabi-v7a` devices, which this app still ships.

**Three memory traps, all quantified:**

1. **Never hold every storyboard frame.** For a 2-hour video the storyboard has ≈ `fps × 7200` ≈
   3 650 frames; decoded at `sb1`'s 160x90 that is **200 MiB** (last row above). Decode **one sprite
   sheet at a time**: `sb1`'s sheet is 800x450 = **1.37 MiB**, `sb3`'s is 480x270 = **506 KiB**,
   and draw tiles out of it with a source rect. That is the difference between 200 MiB and ~1.4 MiB
   for the same filmstrip.
2. **A 12-frame ffmpeg filmstrip at 160x90 is 675 KiB** (or 432 KiB at 128x72, or half that in
   `RGB_565`) — 0.13 % of a 512 MB heap, 0.5 % of a 128 MB one. Safe.
3. **Disk cost is negligible.** Measured JPEG sizes at 160x90: mean **5.8 KB** (worst-case synthetic
   noise, 75 files), 3.6 KB for keyframe-only frames, 2.8 KB for real 144p YouTube frames.
   12 frames ≈ **35–70 KB** on disk against a 438 MB source.

### 2c. Recommendation

| path | frames | frame size | download/decoded cost | when |
| --- | --- | --- | --- | --- |
| **1. YouTube storyboard** | 108 (video length ≈ 213 s; interval ≈ 2 s) | 160x90 (`sb1`) or 80x45 (`sb2`) | 109 KB / 0.87 s / 5 GETs, **no ffmpeg**; decode one 800x450 sheet = 1.37 MiB | YouTube (the common case) |
| **2. ffmpeg seeks** | **12**, interval = `duration / 12`, capped 8…24 | **160 x 90** (`scale=160:-2`) | ≈5.3 s desktop for 12 seeks; 675 KiB decoded | any other source, local or remote |
| 3. keyframe-only ffmpeg | 12 | 160x90 | 5 s for 10 min, 48 s for 2 h | when one process is cheaper than 12 |
| 4. poster / placeholder | 1 or 0 | any | already cached / free | fallback (§5) |

Prefer `Bitmap.Config.HARDWARE` for the tiles — they are only drawn, which is the documented optimal
case, and it moves the pixels off the Java heap. Otherwise decode with
`BitmapFactory.Options.inSampleSize`/`inPreferredConfig` ("requests the decoder to subsample the
original image, returning a smaller image to save memory",
<https://developer.android.com/reference/android/graphics/BitmapFactory.Options#inSampleSize>), or
let Coil do the size-aware decode it already performs everywhere else in this app.

Time budget [INFERENCE] for path 2 on a phone: 12 seeks at 1–2 s serial ⇒ 12–24 s. Run them on a
small dispatcher (2–4 concurrent ffmpeg processes) and paint each tile as it arrives; the first tile
then lands within ~1–2 s.

## 3. Lazy extraction

**Verdict: yes.** Frames can be produced on demand, and lazily is strictly cheaper than eagerly.

* **Random access is real** (§1a): 36 seeks across a 10-minute file are flat at 272–542 ms regardless
  of position, and a seek 7000 s into a 2-hour file costs ~1.5 s where a full pass costs ~700 s.
* **Cost is per process, not per position or per pixel.** `SEEK_FULLRES` ≈ `SEEK_SCALED`
  (348–541 ms) shows the scale filter is free, and 12 keyframes inside *one* process took 1.1–2.3 s
  (`KEYFIRST`) ≈ 100–190 ms/frame once the container is open. So the design is:
  * paint the strip **before** any frame exists (empty tiles on a `surfaceVariant` track), then fill
    tiles as results arrive;
  * **lookahead:** request the visible window + ~1 window ahead, at most `2 × visible` in flight;
  * key requests by **quantised tile index** (`floor(T / interval)`), never by raw slider pixels;
  * cache by `(videoId, formatSelector, intervalIndex)`; a 12-frame cache is 675 KiB of bitmaps and
    ~50 KB of JPEGs — small enough to hold for the whole configure session;
  * for storyboards, the whole strip is one 109 KB download, so "lazy" degenerates to "fetch 5 sprites
    in parallel and paint as they land".
* **The container decides whether *any* seek works before the download finishes** — measured in §4a.

## 4. Partial file and remote URL

### 4a. What a partially downloaded file can give (measured)

Real YouTube format `160` URL (2 058 142 B, 213.04 s); the first 524 288 B were fetched and handed to
ffmpeg as a file:

| observation | result |
| --- | --- |
| byte layout of the prefix | `ftyp`@0 (28), **`moov`@28 (711 B)**, `sidx`@739 (488), `moof`@1227 (1664), `mdat`@2891 |
| `ffprobe` on 524 288 B | `width=256 height=144` and **`duration=213.040000`** — full metadata from a quarter of the bytes |
| first frame, no seek | rc=0, 133 ms |
| seeks to t = 5/10/15/20/25/30/40 s | **all rc=0** |
| seeks to t = 50/60/80/100 s | rc=234, `Invalid NAL unit size` |
| decode to end | `frame= 1235 time=00:00:49.40`, then `Packet corrupt` |

524 288 B is **25.5 % of the bytes** and yields **49.4 s of 213 s = 23.2 % of the timeline** (not
exactly proportional — bitrate is not uniform across fragments). Because `ftyp`+`moov`+`sidx` arrive
in the first ~1.2 KB, ffmpeg knows the resolution *and the total duration* from a 1 % download; only
the media data is missing, and requests past the received prefix fail with a **decode error**, not a
clean "not found" — so the usable prefix must be derived from download progress, not from a probe.

Truncation across container layouts (each cut at a byte offset, then ffmpeg asked for one frame):

| container | where `moov` is | truncated to | result |
| --- | --- | --- | --- |
| fragmented (YouTube `160`) | @28, front | 524 288 B | opens; frames up to 49.4 s; `sidx` gives total duration |
| non-fragmented **+faststart** | @32 of 438 MB | 1 000 000 B | opens, first frame OK, decode reaches 00:00:00.53 |
| non-fragmented +faststart | @32 | 512 288 B (cuts the 635 KB `moov` itself) | rc=183, `error reading header` |
| non-fragmented +faststart (30 s clip) | @32 (33 KB moov) | 1000 B short | opens, decodes the whole 30.06 s |
| non-fragmented, **no faststart** (438 MB file) | @437 540 892, end | 420 000 000 B (no `moov`) | rc=183, **`moov atom not found`** |
| non-fragmented, no faststart (438 MB file) | end | 438 170 000 B (`moov` cut ~6 KB short) | rc=183, `contradictionary STSC and STCO`, `error reading header` |
| non-fragmented, no faststart (30 s clip) | @21 945 724 | 10 000 000 B (no `moov`) | rc=183, **`moov atom not found`** |
| non-fragmented, no faststart (30 s clip) | end | 1000 B short | rc=183, `contradictionary STSC and STCO` |
| non-fragmented, no faststart (30 s clip) | end | 100 B short | rc=0 — opens |
| ffmpeg `-c copy` clip written by `FFmpegFD` (30 s) | @21 945 724, end | – | layout measured: `mdat`@40, `moov`@21 945 724 |

**Verdicts.**

* **Non-fragmented MP4, `moov` at the end (`+faststart` absent) — no frames at all until the file is
  essentially complete.** Measured twice locally: `moov atom not found`, even when 420 MB of a 438 MB
  file is present. Measured **over HTTP as well**: serving a 21 978 795-byte clip whose `moov` is last,
  ffmpeg's very first request was `Range: bytes=0-` — it asked for and received the **entire file**
  (`206 ... len=21978795`) before it could produce a single frame, and in that test it had still not
  finished 60 s later (the 60 s cap was a limitation of my single-threaded test server, but the byte
  count is unambiguous: **100 % of the file for the first frame**, versus ~80 KB for the moov-first
  remote case in §4b). This is the box order, not an ffmpeg quirk: the sample tables live in `moov`,
  and Android's own streaming requirement says the same thing — "For 3GPP and MPEG-4 containers, the
  `moov` atom must precede any `mdat` atoms, but must succeed the `ftyp` atom" (Android "Supported media
  formats" → Video streaming requirements,
  <https://developer.android.com/media/platform/supported-formats>). The W3C ISOBMFF byte-stream
  spec makes the structure explicit too: the initialization segment is "a single File Type Box
  (`ftyp`) followed by a single Movie Box (`moov`)", and a media segment is "one optional Segment
  Type Box (`styp`) followed by a single Movie Fragment Box (`moof`) followed by one or more Media Data
  Boxes (`mdat`)", with `mvex` in `moov` signalling that fragments follow
  <https://www.w3.org/TR/2024/NOTE-mse-byte-stream-format-isobmff-20240723/> §3–§4.
* **Fragmented MP4 (DASH-style) — usable mid-download**, measured: frames decode as soon as their
  `moof`+`mdat` have arrived.
* **WebM/Matroska — streamable by design, but seeking needs `Cues`.** The WebM container guidelines
  require a keyframe-only `Cues` element, recommend it "before any clusters, so that the client can
  seek to a point in the data that has not yet been downloaded in a single seek operation", and state
  that "Seeking will be disabled if the webm file does not have a key frame `Cues` element"
  <https://www.webmproject.org/docs/container/>. **Documented, not measured here** — no WebM source
  was available in this session.
* **The app's own trim output is the bad case.** `--download-sections` hands the job to ffmpeg
  (`yt_dlp/downloader/__init__.py:85`: `if (info_dict.get('section_start') or info_dict.get('section_end')) and FFmpegFD.can_download(...): return FFmpegFD`),
  and `FFmpegFD._call_downloader` appends `-c copy` without `+faststart`
  (`yt_dlp/downloader/external.py`). A `-c copy` mp4 gets `moov` last (measured above), and the app
  passes no `--downloader` override (`util/DownloadUtil.kt` builds every option by hand), so
  [INFERENCE] a clip that is still downloading is **opaque to an extraction ffmpeg process** — for
  clips, frames must come from the remote URL or wait for the file.

### 4b. Remote URL

**Protocol support (measured):** `ffmpeg -protocols` lists `http`, `https`, `tls`, `httpproxy`,
`sftp`, `rtmp*`; `ffmpeg -demuxers` lists `dash`, `hls`, `matroska,webm`, `mov,mp4,m4a,3gp,3g2,mj2`.
TLS is `--enable-gnutls`. ffmpeg reads an `https://` URL directly.

**Cookie/header plumbing (documented, inside the app's own dependency):** ffmpeg's http protocol
accepts `headers`, `cookies`, `user_agent`, `referer`, `seekable`, `multiple_requests`,
`request_size`, `short_seek_size` and the `reconnect*` family (`man ffmpeg-protocols`, HTTP section);
`request_size` is documented as "useful for some pathological servers that throttle unbounded range
requests, as well as when expecting to seek frequently", with `multiple_requests` and `short_seek_size`
recommended alongside. yt-dlp already builds exactly this for ffmpeg: `-cookies
'<name>=<value>; path=…; domain=…;'` from its cookiejar and `-headers '<Key>: <value>\r\n…'` from the
format's `http_headers` (`yt_dlp/downloader/external.py`, `FFmpegFD._call_downloader`; the trailing
`\r\n` is required). Per-format `http_headers` is populated by extractors
(`yt_dlp/extractor/common.py:3465-3468` sets `Referer` on every format).

**Seeking over HTTP is real and byte-exact (measured)** on the live YouTube URL, `-loglevel trace`:

```
Range: bytes=0-          → Content-Range: bytes 0-2058141/2058142      (open: ftyp/moov/sidx; 16 384 B read)
Range: bytes=979374-     → Content-Range: bytes 979374-2058141/2058142  (the moof containing t = 100 s)
[AVIOContext] Statistics: 65536 bytes read, 1 seeks
```

ffmpeg indexes with `sidx`, then re-requests only the byte range of the target fragment: ~80 KB and
**one extra HTTP request** per frame.

| remote case | wall |
| --- | --- |
| `-ss 100` with the extractor's `http_headers` | **1472 ms** |
| `-ss 200` (near the end of a 213 s video) | **1936 ms** |
| `-ss 100` with **no** `-headers` at all | **1208 ms, rc=0** |
| 12 seeks at t = 5…192 s | **12 605 ms total** (670–1553 ms each) |

So a remote frame costs ~1.2 s against ~0.42 s locally: the extra cost is TLS/HTTP round trips, not
bytes.

**Risks, stated with what was actually observed:**

* **Headers were not needed for this YouTube URL.** The URL carries its own signature params
  (`sig`, `lsig`, `lsparams`, `sparams`); with no `-headers` ffmpeg still returned a frame. [INFERENCE]
  Other sites, and some age/region-gated YouTube videos, do need `Referer`/`Cookie` — slice A owns
  which sites those are.
* **The app throws `http_headers` away.** `grep http_headers` over `app/src/main/java` → **no
  matches**: the Kotlin `Format` / `RequestedDownload` / `VideoInfo` models
  (`util/VideoInfo.kt:100-155`) deserialize `url`, `format_id`, `protocol`, `ext`, `width`, `height`
  … but not `http_headers`, not cookies, and not `rows`/`columns`/`fragments`. Any remote-frame or
  storyboard feature needs those fields added first.
* **URLs expire and are IP-bound.** Observed in the sibling dump: `expire=1789770990` — **≈6 hours**
  of validity at fetch time (21 080 s remaining) — plus `ip=<this host's egress IP>`, `sig`, `lsig`, `sparams`.
  So a remote frame grab fails after expiry (re-run yt-dlp), and [INFERENCE] an IP change mid-session
  (Wi-Fi ⇄ cellular) invalidates it. The app never persists format URLs (they are absent from
  `DownloadedVideoInfo`), so a remote filmstrip must consume the URL inside the same configure session.
* **Range hostility / throttling.** googlevideo answered byte ranges with `206` but **refused a suffix
  range** (`curl -r -8192` → `416`) — so never implement "read the tail for `moov`". 12 consecutive
  range-request seeks were served without error, ~1 s apart.

### 4c. What the app knows at configure time — and the existing precedent

The app **already fetches and shows a remote image before the download**: the configure screen renders
the extractor's thumbnail URL through Coil 3 with an OkHttp network fetcher and a desktop Chrome
`User-Agent`, no cookies,

```kotlin
// app/src/main/java/com/junkfood/seal/ui/page/home/NewHomePage.kt:1563
state.videoInfo?.thumbnail?.let { thumbnailUrl ->
    AsyncImage(model = thumbnailUrl, contentDescription = null,
               modifier = Modifier.size(60.dp)…, contentScale = ContentScale.Crop)
}
```

(`App.kt:79-104`; also `ThumbnailUtil.downloadThumbnailBytes()` / `resolveBestThumbnailUrl()`,
which `HEAD`s `i.ytimg.com/vi/<id>/maxresdefault.jpg` and decodes bytes with `BitmapFactory`,
`util/ThumbnailUtil.kt:55-135`). **"Fetch a remote image at configure time and show it before the
download" is therefore already shipped behaviour** — a remote filmstrip, or a storyboard fetch, is
that same pattern with more requests.

At configure time the app holds `videoInfo: VideoInfo` with `formats: List<Format>` (`url`,
`formatId`, `protocol`, `ext`, `width`, `height`, `formatNote`) and the clip range in seconds
(`VideoClip(start, end)`, turned into `--download-sections "*%d-%d"` at `util/DownloadUtil.kt:1292-1295`).
It does **not** hold per-format `http_headers`, cookies, `rows`/`columns`, or `fragments`, and it has
no local file for the video yet. Note for the storyboard path specifically: the `sb*` format's
top-level `url` is a **template** containing `$M` (`…/storyboard3_L2/M$M.jpg?sqp=…`), so the real
sprite URLs must come from `fragments[i].url`, and the tile grid from `rows`/`columns`.

## 5. Fallback

Ordered so the strip degrades instead of breaking:

1. **YouTube storyboard sprites** (§1d) — 1–5 HTTP GETs, ~20–109 KB, no ffmpeg. Best case where
   available.
2. **Remote ffmpeg frames** — 12 seeks on the format URL, ~1.2 s each measured, painted per tile.
   Needs the `http_headers` plumbing from §4b for non-YouTube sites.
3. **Local frames while downloading** — extract from the `.part` file, but only when it is fragmented
   or already carries `moov` (§4a): true for direct `https` downloads of YouTube formats, false for
   `--download-sections` clip output.
4. **Single poster.** Fall back to the thumbnail the app already holds (`videoInfo.thumbnail` before
   download, `SavedVideoInfo.thumbnailUrl` / `DownloadedVideoInfo.thumbnailUrl` after). Draw it once,
   cropped across the strip and dimmed, under the same slider: identical gestures and hit targets,
   already cached by Coil.
5. **Placeholder strip.** Offline, private/deleted video, or a throttled request: a solid
   `MaterialTheme.colorScheme.surfaceVariant` track with a subtle gradient — fully draggable. This is
   also the correct state *while* lazy frames are in flight, so the user never sees a hole.
6. **Trim stays enabled.** The existing clip dialog copy (`R.string.clip_video_dialog_msg`,
   `ui/.../DownloadFormatPreferences.kt:393`) is the only place a failure may be mentioned, and only
   when the user must be told. A missing frame must never block cutting, and needs no error toast —
   the placeholder *is* the error state.

## Sources

| # | source | establishes |
| --- | --- | --- |
| S1 | `ffmpeg -protocols` / `-version` / `-demuxers`, local ffmpeg 9.0.1 (`nixpkgs#ffmpeg`) | `http/https/tls/httpproxy/…` input protocols, `--enable-network --enable-gnutls`, `dash`/`hls`/`matroska,webm`/`mov,mp4` demuxers |
| S2 | `man ffmpeg` (ffmpeg 9.0.1 man page) §`-ss position (input/output)` | input `-ss` "seeks in this input file to position … to the closest seek point before"; `-accurate_seek` (default) decodes and discards the extra segment |
| S3 | `man ffmpeg-protocols`, HTTP section | `headers`, `cookies`, `user_agent`, `referer`, `seekable`, `multiple_requests`, `request_size` ("when expecting to seek frequently"), `short_seek_size`, `reconnect*` |
| S4 | `yt_dlp/downloader/external.py`, `FFmpegFD._call_downloader` (yt-dlp master @ `594bd50c2c78ac432f81600d309fdc4e0a92d82c`) | ffmpeg is given `-cookies`, `-headers` (trailing `\r\n`), and `-ss`/`-t` **before** `-i <url>` for sections; `-c copy` when cuts are not forced |
| S5 | `yt_dlp/downloader/__init__.py:85` | `--download-sections` forces `FFmpegFD` |
| S6 | `yt_dlp/downloader/http.py:42-116` | the native downloader uses `Range: bytes=start-end` for resume/chunks and merges `http_headers` |
| S7 | `yt_dlp/extractor/common.py:3465-3468` | extractors set per-format `http_headers` (e.g. `Referer`) |
| S8 | yt-dlp README, `--download-sections`, `--force-keyframes-at-cuts` | time-range sections; forcing keyframes at cuts is "slow due to needing a re-encode" |
| S9 | `yt_dlp/extractor/youtube/_video.py:3768-3792,4163` | `_extract_storyboard` builds `sb<i>` formats with `rows`/`columns` and one fragment per sprite, `protocol: mhtml` |
| S10 | W3C *ISO BMFF Byte Stream Format*, NOTE 2024-07-23 §3–§5 — <https://www.w3.org/TR/2024/NOTE-mse-byte-stream-format-isobmff-20240723/> | init segment = `ftyp`+`moov`; media segment = `styp`+`moof`+`mdat`; `mvex` signals fragments; random access points |
| S11 | Android *Supported media formats*, "Video streaming requirements" + image table — <https://developer.android.com/media/platform/supported-formats> | "the `moov` atom must precede any `mdat` atoms, but must succeed the `ftyp` atom"; WebP decoder "Android 4.0+" |
| S12 | WebM Container Guidelines — <https://www.webmproject.org/docs/container/> | keyframe-only `Cues`; `Cues` before clusters for single-seek streaming; seeking disabled without it |
| S13 | Android `Bitmap.Config` — <https://developer.android.com/reference/android/graphics/Bitmap.Config> | ARGB_8888 4 B/px (default since API 9), RGB_565 2 B/px, ARGB_4444 deprecated/coerced, HARDWARE = graphic memory, draw-only |
| S14 | Android *Handling bitmaps* — <https://developer.android.com/topic/performance/graphics> | `4048*3036*4 bytes` ≈ 48 MB for one 12 MP ARGB_8888 bitmap; bitmaps exhaust the app budget |
| S15 | Android `BitmapFactory.Options#inSampleSize` — <https://developer.android.com/reference/android/graphics/BitmapFactory.Options#inSampleSize> | subsampling "returning a smaller image to save memory"; also `inPreferredConfig`, `inJustDecodeBounds` |
| S16 | Android `ActivityManager#getMemoryClass()` — <https://developer.android.com/reference/android/app/ActivityManager#getMemoryClass()> | per-application memory class is device-defined |
| S17 | Sealplus `ui/page/download/VideoSectionSlider.kt:66-160`; `ui/page/downloadv2/configure/FormatPage.kt:620,1377-1382` | existing range-slider trim UI; 12 dp padding; seconds-based range |
| S18 | Sealplus `ui/page/home/NewHomePage.kt:1563`; `App.kt:79-104`; `util/ThumbnailUtil.kt:55-135` | remote image fetched/decode at configure time (Coil3 + OkHttp + Chrome UA, no cookies) — the precedent |
| S19 | Sealplus `util/VideoInfo.kt:100-155`; `util/DownloadUtil.kt:1292-1295` | `Format` has `url` but no `http_headers`/cookies/`rows`/`columns`/`fragments`; clips become `--download-sections` |
| S20 | Sealplus `gradle/libs.versions.toml`; `app/build.gradle.kts:21,60` | `youtubedl-android` 0.18.1 (older bundled ffmpeg); ABIs arm64-v8a/armeabi-v7a/x86/x86_64 |
| S21 | Measurements in `/tmp/sealplus-research/scratch-C/` (this session) | every timing, atom offset, byte range, partial-file result, remote seek trace and storyboard total |
| S22 | `/tmp/sealplus-research/info.json` (yt-dlp `--dump-single-json`) | real format URL (`expire` ≈ +6 h, `ip=`, `sig/lsig/sparams`), `http_headers` = Accept/Accept-Language/Sec-Fetch-Mode/User-Agent, `container=mp4_dash`, 2 058 142 B / 213.040 s; `sb0…sb3` geometry, `rows`/`columns`/`fps`, `$M` URL template |

## Unknowns

* **Android absolute cost** — no device and no Android SDK here; §1 numbers are desktop only.
  Whether the bundled ffmpeg has a hardware h264 decoder and which flags it accepts is slice B's.
* **Non-YouTube storyboards** — the sprite path was measured only on YouTube. Whether other
  extractors expose anything comparable is slice A's.
* **Storyboard frame counts for long videos** — measured only for a 213 s video (108 frames). The
  `fps` field implies frames = `fps × duration`, hence ≈3 650 frames for 2 h; not measured.
* **WebM mid-download behaviour** — documented (S12) but not measured; no WebM source available here.
* **Local-HTTP control for a `moov`-first file** — not obtained: my single-threaded test server wedged
  while streaming the 22 MB trailing-`moov` case, so the paired faststart run returned no number. The
  positive `moov`-first network case is instead the real YouTube measurement in §4b (byte-exact
  `Range: bytes=979374-`, 64 KB read, ~1.5 s, frame produced).
* **Other remote hosts** — only one googlevideo URL was exercised. Referer/Cookie-gated CDNs, HLS/DASH
  manifest URLs, and hotlink protection are untested; whether ffmpeg needs the extractor's
  `Accept`/`Sec-Fetch-Mode` headers elsewhere is open.
* **`sidx`-less fragmented MP4** — seeking then costs scanning `moof` headers; not measured.
* **Genuine parallel ffmpeg seeks** (2–4 concurrent) — not benchmarked for wall-clock gain or peak
  memory; the 2–4-way dispatcher in §2c is [INFERENCE] from per-process cost.
* **Seek-cost position dependence** — the 36-run sweep on the 10-minute file is flat, but later runs
  on this shared host scattered 0.4–2.0 s at identical positions in both files. I could not separate
  a real position effect from host contention, so no claim is made.
* The 2-hour results come from a file built by looping a 10-minute clip: seek behaviour is
  representative, but a real 2-hour video's decode mix (motion, B-frames) differs from `testsrc2`.
