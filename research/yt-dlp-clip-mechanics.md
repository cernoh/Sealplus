# yt-dlp clip mechanics: per-clip naming, sub-second cuts, and the cost of exactness

Research record for wayfinder ticket **#2** on map **#1** ("Sealplus video trimming, made usable"),
repo `cernoh/Sealplus`: <https://github.com/cernoh/Sealplus/issues/2>.

Findings only — this branch (`research/yt-dlp-clip-mechanics`) carries no app code.

The record merges two research agents' work with the session's own checks:

- **Part A** — the yt-dlp CLI contract: items 1, 2, 4, 5, 6.
- **Part B** — exact cuts and their cost: item 3.
- **Independent checks** — what the session re-ran or re-derived from primary sources, including the
  one point where the two parts first read differently (physical pre-roll versus presented start).
- **Answers in ticket order** — the compact per-item answer the ticket's acceptance asks for.

Method: primary sources only. Every version claim comes from the pinned Maven artifact itself; every
behaviour claim from the pinned yt-dlp source (yt-dlp **2025.11.12**, unpacked from
`library-0.18.1.aar` → `res/raw/ytdlp`), from the bundled ffmpeg (**7.1.1**), or from a measurement
run on this host against the pinned zipapp. Host: NixOS, x86_64, AMD Ryzen 7 3700X; no `java`, no
`adb`, no Android device or emulator.


## Part A — the yt-dlp CLI contract (ticket items 1, 2, 4, 5, 6)

_Research agent A. Its report, without its own top-level title._

Ticket: https://github.com/cernoh/Sealplus/issues/2 — items 1, 2, 4, 5, 6. Item 3
(`--force-keyframes-at-cuts` semantics and cost) is owned by a sibling agent and is not covered here.
Primary sources: the pinned artifact's own source, its bundled ffmpeg, official docs, and measurements run on this
host against the pinned zipapp itself.

### 0. Pinned source, extracted and verified (evidence for item 6)

```sh
mkdir -p /tmp/sealplus-research/scratch-A && cd /tmp/sealplus-research/scratch-A
curl -fsSL -o library-0.18.1.aar https://repo1.maven.org/maven2/io/github/junkfood02/youtubedl-android/library/0.18.1/library-0.18.1.aar
sha256sum library-0.18.1.aar          # 579b5fb480892b1abc2b218c2089699d52759cc8d7ba256bf876453f0365faef (== /tmp/yta.aar)
unzip -o library-0.18.1.aar res/raw/ytdlp
mkdir ytdlp-zipapp && cd ytdlp-zipapp && unzip -o ../res/raw/ytdlp
```

`res/raw/ytdlp` is a Python zipapp, 3 170 726 bytes, sha256
`89a0d9058ea9018e380b7771898ff46e393a1986dcd13fef331693c87ce1fca4` (line 1 `#!/usr/bin/env python3` — the 23
"extra bytes" unzip reports). `yt_dlp/version.py`: `__version__ = '2025.11.12'`,
`RELEASE_GIT_HEAD = '335653be82d5ef999cfc2879d005397402eebec1'`, `CHANNEL = 'stable'`. Identity check: the tag
archive `https://github.com/yt-dlp/yt-dlp/archive/refs/tags/2025.11.12.tar.gz` has a byte-identical `version.py`,
and `diff -rq ytdlp-zipapp/yt_dlp tag/yt_dlp` reports only packaging artifacts (`__main__.py` at the zipapp root,
`__pyinstaller/`, extractor READMEs, generated `lazy_extractors.py`); the commit tarball `335653be…` still says
`2025.10.22` because it is the pre-version-bump head, so the **tag** archive is the source matching the artifact.
Every `file:line` below is the extracted `ytdlp-zipapp`, equal to that source. Bundled ffmpeg:
`ffmpeg-0.18.1.aar` (sha256 `0a87ffa6cf912b0fe76c1a99b9107f543ee2f247935fae2c71f0822eb7bc5f49`) →
`jni/arm64-v8a/libffmpeg.so` contains `%s version 7.1.1` and `libavutil.so.59` ⇒ **FFmpeg 7.1.1**. The host ffmpeg
that ran the sections below is 6.1.6 (`/nix/store/cv6iw8f6r7pqnzx9i9fhqpl8w8r2gyf8-ffmpeg-6.1.6-bin/bin/ffmpeg`).

Measurements used a local Range-capable HTTP server (`scratch-A/serve_range.py`, 127.0.0.1:8188) serving
`media/src.mp4` (12 s, H.264+AAC, 15 fps, keyframes every 2 s at 0/2/4/6/8/10), driven by `python3 ytdlp-zipapp …`.

### 1. Per-section naming: there is NO per-section index for time ranges

Every non-empty requested range is expanded with these four keys, even when the value is `None`
(`ytdlp-zipapp/yt_dlp/YoutubeDL.py:3072-3086`):

```python
for fmt, chapter in itertools.product(formats_to_download, requested_ranges):
    offset, duration = info_dict.get('section_start') or 0, info_dict.get('duration') or float('inf')
    end_time = offset + min(chapter.get('end_time', duration), duration)
    if end_time == float('inf') or end_time > offset + duration + 1:
        end_time = None
    if chapter or offset:
        new_info.update({
            'section_start': offset + chapter.get('start_time', 0),
            'section_end': end_time,
            'section_title': chapter.get('title'),
            'section_number': chapter.get('index'),
        })
```

| case | `section_start` | `section_end` | `section_title` | `section_number` |
|---|---|---|---|---|
| **time range** `--download-sections "*a-b"` | float seconds (measured `2.4`, `2.0`) | float, or `None` when the range reaches/passes the media end (`:3078-3079`) | `None` | **`None` — absent** |
| **chapter range** `--download-sections "^regex"` | `offset + chapter['start_time']` (extractor numeric; float in practice) | chapter end (numeric) | str | **int, 0-based** |
| **chapter split** `--split-chapters`, `chapter:` template | chapter `start_time` (`yt_dlp/postprocessor/ffmpeg.py:1010-1015`) | chapter `end_time` | str | **int, 1-based** |

For a time range the `chapter` dict comes from `download_range_func`, which yields only
`{'start_time': …, 'end_time': …}` (`yt_dlp/utils/_utils.py:3346-3350`; chapter index at `:3342`) — no `index` — so `chapter.get('index')`
is `None`; `section_number` is written from exactly two places in the tree (`YoutubeDL.py:3085`,
`postprocessor/ffmpeg.py:1011`). The README documents the four fields as "Available only when using
`--download-sections` and for `chapter:` prefix when using `--split-chapters` for videos **with internal
chapters**" (`tag/README.md:1424-1428`).

Measured (`-O "%(section_start)#j | %(section_end)#j | %(section_number)#j | %(section_title)#j"`; file names from
the app's own template shape `%(title).200B [%(section_start)d-%(section_end)d].%(ext)s`):

```
*2-5  *7-10       →  2.0 | 5.0  | NA | NA   and  7.0 | 10.0 | NA | NA    files: src [2-5].mp4, src [7-10].mp4
*2.4-4.7  *6.1-8.2→  2.4 | 4.7  | NA | NA  (per range)                   files: src [2-4].mp4, src [6-8].mp4
*2.4-4.7  *2.9-4.1→  per-range floats                                    file:  src [2-4].mp4 (one file — collision)
*6.5-  (open end) →  6.5 | NA   | NA | NA                                file:  src [6-NA].mp4
*-5-8   (negative)                                                        file:  src [-5-8].mp4
"^Part [AB]"      →  num=0 … Part A ; num=1 … Part B                     files: src [0] Part A.mp4, src [1] Part B.mp4
--split-chapters  →  num 01/02/03 (ffmpeg.py:1054-1055 uses idx + 1)      files: 01 Part A.mp4, 02 Part B.mp4, 03 Part C.mp4
```

`%(section_start)d` on a fractional start **truncates toward zero** (Python `%d`), and a missing `section_number`
renders as the NA placeholder (default `"NA"`, `tag/README.md:670-671`) instead of raising.

#### Collision: the later clip is silently dropped (app shape)

Measured with the app's actual shape — **relative** `-o`, `-P <abs home>`, `-P temp:<abs>` — and its flags
(`--no-mtime --continue`), ranges 2.4-4.7 and 2.9-4.1:

```
[download] Destination: /tmp/…/outP1/temp/src [2-4].mp4
[download] /tmp/…/outP1/home/src [2-4].mp4 has already been downloaded
→ outP1/home/src [2-4].mp4  41.8 kB      (clip 1 only; clip 2 dropped, run reports success)
```

The controlling option in this shape is **`overwrites`**, not `--continue`: `YoutubeDL.py:3532-3539` calls
`existing_video_file(full_filename, temp_filename)` → `existing_file(filepaths, *, default_overwrite=False)`
(`YoutubeDL.py:3280-3283`: `if existing_files and not self.params.get('overwrites', default_overwrite):
return existing_files[0]`), and yt-dlp pops the param when no overwrite flag was given (`YoutubeDL.py:777-778`;
`options.py:1446-1456` maps `--no-overwrites`→False, `--force-overwrites`→True, default→None), so the default is
"skip":

| flags (app shape) | result |
|---|---|
| `--continue` (app default) | clip 2 **skipped**, home file = clip 1 (41.8 kB) |
| `--continue --no-continue` | clip 2 **skipped** — `--no-continue` changes nothing here |
| `--continue --force-overwrites` | both clips downloaded into temp, home file = clip 2 (35.0 kB) — clip 1 silently lost |

`--continue` decides the skip only when the final and temporary names resolve to the **same** path — i.e. when the
app adds no `-P temp:`, its `sdcard` mode (`DownloadUtil.kt:1285-1289`). Then `FileDownloader.download` applies
`continuedl_and_exists` (`yt_dlp/downloader/common.py:440-455`) and `--no-continue` overwrites (measured: skip kept
41.8 kB, `--no-continue` kept 35.0 kB).

#### Cheapest distinct names without post-download renaming

No per-time-section index exists anywhere in the pinned version — impossible, not merely undocumented — so an
ordinal cannot come from yt-dlp. Measured with the colliding pair 2.4-4.7 / 2.9-4.1:

1. **One-argument template change (cheapest):** `%(section_start)s-%(section_end)s` → `src [2.4-4.7].mp4` and
   `src [2.9-4.1].mp4`; fixed-width `%(section_start)07.3f-%(section_end)07.3f` → `src [002.400-004.700].mp4` and
   `src [002.900-004.100].mp4`. One invocation, no rename; a collision remains only when the rendered numbers match.
2. **One invocation per clip with its own `-o`:** verified → `src [clip1 2-4].mp4`, `src [clip2 2-4].mp4`, distinct
   even when the truncated timestamps are equal. Cost: one metadata extraction per clip unless `--load-info-json`
   reuses one. The app already loops over `videoClips` (`DownloadUtil.kt:1291-1295`), so this is a local change.
3. **`--exec`** renames after the download — available, but excluded by the question.
4. **`--parse-metadata` cannot help:** it derives fields from other fields (`TEMPLATE:FIELD:REGEX`) and so cannot
   invent a per-range ordinal; a literal `|` default (`tag/README.md:1300`) is constant per template.

### 2. `--download-sections` syntax and precision

Parsing is `parse_chapters()` (`yt_dlp/__init__.py:349-386`), called with `advanced=True` at `:391`. A value not
starting with `*` is a **chapter-title regex** (`:362-364`) matched against `info_dict['chapters']`
(`utils/_utils.py:3338-3343`); `*from-url` obeys the URL's `start_time`/`end_time` (`:359-361`,
`tag/README.md:623-625`). Otherwise `*` + comma-separated `start-end` pairs, both sides optional, whitespace
trimmed (`:369-386`), with `inf`/`infinite` → `float('inf')` (`:350`). Open ranges work (`*2.4-`, `*-5`,
`*inf-5`); `*-` alone is a hard usage error: `invalid --download-sections time range "*-". Must be of the form
"*start-end"`. Negative timestamps are allowed here (`--remove-chapters` rejects them, `:377-378`):
`*-1:00-2:00` → `-60.0…120.0`, resolved to an absolute time only when the extractor supplies `duration`
(`download_range_func._handle_negative_timestamp`, `utils/_utils.py:3361-3362`, `max(duration + time, 0)`) —
measured: with `duration=12`, `*-5-8` becomes `-ss 7.0 -t 1.0`; for a plain `generic` mp4 (no `duration`) the raw
`-ss -5.0 -t 13.0` reached ffmpeg. `--download-sections` requires ffmpeg (`tag/README.md:625`).

**Sub-second timestamps are accepted and preserved.** `parse_duration` (`utils/_utils.py:2071-2108`) accepts
`SS.mmm` and `H:M:S.mmm`; `*0:00:02.5-0:00:04.75` → exactly `2.5` and `4.75` (verified with
`-O "%(section_start)#j"`; the info line prints `:.1f`, `YoutubeDL.py:3068-3069`, so it *rounds* 4.75 to "4.8" —
do not read precision from it). Precision is lost only where the app drops it: `VideoClip` holds whole seconds
(`app/…/util/VideoInfo.kt:162-166`, `range.start.roundToInt()` over a seconds slider,
`app/…/configure/FormatPage.kt:620,987-995`) and `DownloadUtil.kt:1291-1295` formats `"*%d-%d"` — so today the app
cannot emit a sub-second range at all.

#### How the range reaches ffmpeg, and where the cut lands

`yt_dlp/downloader/external.py:527-530`, inside the per-format loop and **before** the input, appends
`['-ss', str(start_time)]` and `['-t', str(end_time - start_time)]`; then
`args += [*self._configuration_args(…), '-i', url]` (`:585`) and, at `:587-588`,
`if not (start_time or end_time) or not self.params.get('force_keyframes_at_cuts'): args += ['-c', 'copy']`.
So the range is an **input-side** `-ss`/`-t`, stream-copied unless `--force-keyframes-at-cuts` is set. Measured
command for `*2-5`: `ffmpeg … -ss 2.0 -t 3.0 -i http://… -c copy -f mp4 'file:…/src [2-5].mp4.part'`.

Cut start, per the official ffmpeg documentation (`https://ffmpeg.org/ffmpeg.html`, option `-ss position`):

> "When used as an input option (before `-i`), seeks in this input file to position. Note that in most formats it is
> not possible to seek exactly, so ffmpeg will seek to the closest seek point before position. When transcoding and
> `-accurate_seek` is enabled (the default), this extra segment between the seek point and position will be decoded
> and discarded. When doing stream copy or when `-noaccurate_seek` is used, it will be preserved."

* **`-c copy` (pinned default):** the file starts at the **closest keyframe at or before** the requested start, up
  to one GOP early. Measured (ffmpeg 6.1.6, 2 s GOP): `ffmpeg -ss 2.4 -t 2.3 -i src.mp4 -c copy` → first video
  packet `pts_time=-0.400000 flags=KD_` (the keyframe at 2.0, rebased to the requested 2.4), 43 frames.
* **re-encode:** the extra segment is decoded and discarded, so the file starts at the requested position. Same
  command plus `-c:v libx264 -c:a aac` → first packet `pts_time=0.000000 flags=K__`, 35 frames = 2.333 s for the
  requested 2.300 s (15 fps grid).

(End-to-end cut accuracy and the `--force-keyframes-at-cuts` cost are item 3, sibling agent.)

### 4. Several sections in one command

* **How many files:** one per (selected format entry × range). `YoutubeDL.py:3072` builds
  `itertools.product(formats_to_download, requested_ranges)` and each iteration runs `process_info` (`:3087-3092`).
  With one selected format (the app's case) that is one file per range: measured 2 ranges → 2 files.
* **Order:** the ranges in the order their `--download-sections` arguments were given, within each format entry.
  Measured destination order `src [2-5]` then `src [7-10]`, and `src [2-4]` then `src [6-8]`.
* **What must differ for the names to differ:** the rendered template result. The only per-range data are the four
  `section_*` fields of item 1, so `section_start` and/or `section_end` *as rendered* must differ — or the app must
  vary `-o` itself.
* **`-P temp:<dir>` and `.part` (app shape):** the app's `-o` is a **relative** template — the absolute base
  directory goes to `-P` (`DownloadUtil.kt:1288`), and `outputBuilder` only ever receives the optional
  `%(playlist)s/` prefix (`:1241`, `:1318`). So `full_filename = join(home, rendered)` and
  `temp_filename = join(home, temp, rendered)` (`YoutubeDL.py:3319-3320`; `get_output_path`,
  `YoutubeDL.py:1205-1212`); the downloader receives **temp_filename** (`YoutubeDL.py:3536`), and
  `ExternalFD.real_download` appends `.part` (`external.py:42-44` with `temp_name`,
  `downloader/common.py:218-222`) → **the `.part` lives in the temp dir**. Measured:
  `[download] Destination: …/outP4/temp/src [2-5].mp4`, ffmpeg
  `Output #0, mp4, to 'file:…/outP4/temp/src [2-5].mp4.part'`, then
  `[MoveFiles] Moving file "…/temp/src [2-5].mp4" to "…/home/src [2-5].mp4"` and an empty temp dir. So `-P temp:`
  **is honoured**. The `WARNING: --paths is ignored since an absolute path is given in output template`
  (`YoutubeDL.py:1532-1538`) appears only for an absolute `-o`; a control run with one reproduced it and put the
  `.part` beside the final file.
* **`--continue` resumes nothing for a clipped download:** the skip decision uses the temp/final path (above) and
  FFmpegFD always rebuilds its output (`args = [ffpp.executable, '-y']`, `external.py:482`). A leftover `.part` in
  the temp dir is ignored and left behind; a leftover *complete-looking* file at the temp filename is adopted and
  moved to the final name — measured: a stray 14-byte `temp/src [2-5].mp4` was reported
  `has already been downloaded` and moved into `home/`, while its 13-byte `.part` stayed behind.
* **Two sections resolving to the same final filename:** with the app's flags the later clip is skipped and
  reported as success; with `--force-overwrites` it silently replaces the earlier clip (item 1 table). Either way
  one clip's data is lost.

### 5. Download archive

* **A clipped download IS recorded.** After the per-range loop, `YoutubeDL.py:3100-3103` writes the archive when
  `True in write_archive and False not in write_archive`, where `write_archive` collects each range's
  `__write_download_archive`. The key comes from the **video** `info_dict`, not the per-range `new_info`:
  `make_archive_id(extractor, id)` → `f'{ie_key.lower()} {video_id}'` (`utils/_utils.py:5283-5285`;
  `record_download_archive`, `YoutubeDL.py:3833-3846`). No range data is written, so **all clips of one video
  collapse into one record** — measured: a `*2-5` clip wrote `generic src`.
* **The check runs before the ranges are applied.** `process_video_result` returns early on
  `if self._match_entry(info_dict, …) is not None` (`YoutubeDL.py:3001`), far above the range product (`:3072`);
  `_match_entry` consults `in_download_archive` (`:1614-1619`, `:3825-3831`). Measured: a later run of the same
  video with a *different* range was refused in full — `[download] src: src has already been recorded in the
  archive` — and produced no file. So a clip download marks the whole video as done for later runs.
* **Opt out for one run:** do not pass `--download-archive`. The pinned version also has `--no-download-archive`
  (`yt_dlp/options.py:782-785`: `dest='download_archive', action='store_const', const=None`), which disables both
  the read and the write — measured: the clip downloaded while the archive file stayed unchanged.
* App side: `--download-archive <path>` is the only archive flag the app emits (`DownloadUtil.kt:616-617`, called
  at `:1230`), and the app pre-checks the same key form itself, `"${videoInfo.extractor} ${videoInfo.id}"`
  (`DownloadUtil.kt:1216-1232`), which matched yt-dlp's `extractor_key.lower() + ' ' + id` (`generic src`).
* **Recently changed archive behaviour:** none. `tag/Changelog.md` (the 2025.11.12 notes, lines 1-72) lists no
  archive core change, and the master Changelog for the releases after it (2025.12.08 … 2026.08.19) has no core
  change to the archive, `--download-sections`, the section fields, or `--continue`.

### 6. Version evidence, and newer-version exposure

* yt-dlp **2025.11.12**, `RELEASE_GIT_HEAD 335653be82d5ef999cfc2879d005397402eebec1`, from
  `library-0.18.1.aar` → `res/raw/ytdlp` → `yt_dlp/version.py` (§0 commands and hashes). Bundled ffmpeg **7.1.1**.
* **Every answer above is available in that version:** every measurement ran the pinned zipapp itself, and every
  code citation is from the pinned extraction.
* **Nothing above needs a newer yt-dlp.** Against current master (fetched 2026-09-18): `download_range_func` is
  byte-identical (`diff` of the extracted function); the section block, the archive block and the overwrite guards
  match (master `YoutubeDL.py:3124-3129`, `:3143-3146`, `downloader/common.py:434-448`); `--no-download-archive`
  still exists (master `options.py:785-787`); `-ss`/`-t`/`-c copy` unchanged (master `external.py:453-456`,
  `:513-514`); chapter split still `idx + 1` (master `postprocessor/ffmpeg.py:1055`).

### Unverified

* **Android runtime.** No device, no `java`, no `adb` here: I could not run the app's own interpreter (the AAR's
  bundled libpython) or the bundled ffmpeg 7.1.1. Argument parsing, template rendering, filename derivation,
  archive and skip logic are pure Python and were exercised under CPython 3.14.7; the cut-boundary numbers came
  from ffmpeg 6.1.6, not 7.1.1 (item 3 owns the bundled-ffmpeg question).
* **App pre-check key equality in general:** `videoInfo.extractor` vs `extractor_key.lower()` matched for the
  `generic` extractor; equality for every supported extractor was not proven.
* **Negative-timestamp resolution on real sites:** provable only with a synthetic info JSON carrying `duration`,
  because the `generic` extractor supplies none.

### Practical answers for the app

1. **Stable distinct filename, no renaming:** yt-dlp exposes no per-time-section index, so `%(section_number)d` is
   `NA` for every time range. The cheapest fix is the template itself — change `CLIP_TIMESTAMP`
   (`DownloadUtil.kt:247`) from `%(section_start)d-%(section_end)d` to `%(section_start)s-%(section_end)s` (or the
   fixed-width `%(section_start)07.3f-%(section_end)07.3f`), keeping one invocation and no rename; distinctness
   then holds whenever the boundaries differ. A *clip index* in the name needs one invocation per clip with its own
   `-o` (verified: `src [clip1 2-4].mp4`, `src [clip2 2-4].mp4`).
2. **One invocation or many:** one invocation can carry all clips, but only the section start/end can then
   distinguish the names — and `d` truncates, so 2.4-4.7 and 2.9-4.1 both become `[2-4]`, the later clip is skipped
   as already downloaded, and the user receives one clip for two. One invocation per clip is the only way to get an
   app-side index at download time without renaming.
3. **Archive:** yes — a clipped download writes one record for the whole video (`extractor_key + ' ' + id`), and the
   check happens before the ranges, so any later run with the archive enabled refuses the entire video. Opt out by
   not passing `--download-archive` (this version also accepts `--no-download-archive`, which suppresses the read
   and the write).
4. **Version:** everything above works in the pinned yt-dlp 2025.11.12 (`335653be…`) — all measurements ran against
   it — and nothing depends on a newer yt-dlp; the pinned bundled ffmpeg is 7.1.1.


## Part B — exact cuts and their cost (ticket item 3)

_Research agent B. Its report, without its own top-level title._

Scope: item **3** of https://github.com/cernoh/Sealplus/issues/2, plus the empirical
cut-precision measurements item 2 needs. Items 1, 4, 5, 6 are a sibling agent's.
Host: NixOS, x86_64, AMD Ryzen 7 3700X (8C/16T). No Android runtime on this host.

### 0. Artifacts verified (the brief's context, re-checked)

**yt-dlp**: `/tmp/ytdlp-src/yt_dlp/version.py` → `__version__ = '2025.11.12'`, `RELEASE_GIT_HEAD = '335653be82d5ef999cfc2879d005397402eebec1'`, `CHANNEL = 'stable'`; ran as `cd /tmp/ytdlp-src && python3 __main__.py`.

**ffmpeg AAR**: `https://repo1.maven.org/maven2/io/github/junkfood02/youtubedl-android/ffmpeg/0.18.1/ffmpeg-0.18.1.aar` — 139,371,444 B, sha256 `0a87ffa6cf912b0fe76c1a99b9107f543ee2f247935fae2c71f0822eb7bc5f49`, kept at `/tmp/sealplus-b-scratch/ffmpeg-0.18.1.aar`. Members: `jni/{arm64-v8a,armeabi-v7a,x86,x86_64}/{libffmpeg.so,libffmpeg.zip.so,libffprobe.so}`.

- `libffmpeg.so` is the ffmpeg CLI: an Android ELF with `DT_RUNPATH` `/data/data/com.termux/files/usr/lib` and `DT_NEEDED` on `libavdevice.so.61 libavfilter.so.10 libavformat.so.61 libavcodec.so.61 libpostproc.so.58 libswresample.so.5 libswscale.so.8 libavutil.so.59`.
- `libffmpeg.zip.so` starts with `PK\x03\x04`: a ZIP of `usr/lib/` (184 entries, symlinks preserved: `libx264.so.164`, `libavcodec.so.61.19.101`, `libmediandk.so`, …), 35.6 MB arm64 / 38.6 MB x86_64 — the CLI loads its libraries from it. `strings usr/lib/libavutil.so.59.39.100` → `FFmpeg version 7.1.1`.
- **App**: `DownloadUtil.kt:1292-1295` emits `--download-sections` `"*%d-%d"`; a search over `app/` finds no `--force-keyframes` and no `--postprocessor-args`.

### 1. Item 3a — what the flag does in the app's path

**Path.** `--download-sections` makes yt-dlp choose the external ffmpeg downloader: `_get_suitable_downloader` returns `FFmpegFD` whenever `section_start`/`section_end` is set and `FFmpegFD.can_download` is true — `yt_dlp/downloader/__init__.py:90-91`. `FFmpegFD.SUPPORTED_PROTOCOLS = ('http', 'https', 'ftp', 'ftps', 'm3u8', 'm3u8_native', 'rtsp', 'rtmp', 'rtmp_ffmpeg', 'mms', 'http_dash_segments')` — `external.py:455`; `file:` is absent, so a `file:` URL falls through to the native downloader and aborts at `yt_dlp/YoutubeDL.py:3433-3437` ("This format cannot be partially downloaded"). http(s) is therefore required, and the server must support HTTP Range for ffmpeg's seek.

**Argument shape.** `-ss <start>` and `-t <end-start>` are added *before* `-i` (`external.py:527-530`, `-i` at `external.py:584`); `-f <ext>` at `external.py:603`. Then, the entire effect of the flag:

    external.py:587-588   if not (start_time or end_time) or not self.params.get('force_keyframes_at_cuts'):
    external.py:588           args += ['-c', 'copy']

So the flag makes the downloader **omit `-c copy` and re-encode the whole clip**. It is not a
selective re-encode at the boundary. No `-force_key_frames` is passed on this path: a search of
the pinned tree shows the option name reaching only `external.py:587`, and `-force_key_frames`
appearing only in `postprocessor/ffmpeg.py:394`, used by `FFmpegSplitChaptersPP`
(`ffmpeg.py:1039-1040`, `--split-chapters`) and `FFmpegModifyChaptersPP`
(`postprocessor/modify_chapters.py:314-318`, `--remove-chapters`). The app uses neither.

Observed argv (from `--verbose`, headers elided), 40 s clip:

    # no flag
    ffmpeg -y -loglevel verbose -headers '…' -ss 20.0 -t 40.0 -i http://…/src_gop250.mp4 \
      -c copy -f mp4 'file:/tmp/…/[20-60].mp4.part'
    # --force-keyframes-at-cuts
    ffmpeg -y -loglevel verbose -headers '…' -ss 20.0 -t 40.0 -i http://…/src_gop250.mp4 \
      -f mp4 'file:/tmp/…/[20-60].mp4.part'

**Encoder choice.** With neither `-c:v` nor `-c:a`, the container default applies: the mp4 muxer
declares `Default video codec: h264. Default audio codec: aac`
(`ffmpeg -h muxer=mp4`). The CLI then resolves it with
`av_guess_codec()` + `avcodec_find_encoder()` — `fftools/ffmpeg_mux_init.c:93-94` at tag `n7.1.1`.
`avcodec_find_encoder()` returns the **first** registered encoder for the ID, deferring only
`AV_CODEC_CAP_EXPERIMENTAL` ones (`libavcodec/allcodecs.c`, `find_codec`), in `codec_list` order;
`configure:4243-4248` and `configure:8276-8308` build `codec_list` from the `allcodecs.c`
declaration order. Consequences:

- **On the host I measured with** (nixpkgs ffmpeg 9.0.1, libx264 present, no mediacodec) the log
  shows `Stream #0:0 -> #0:0 (h264 (native) -> h264 (libx264))`; libx264 then uses its own default
  CRF 23, which the measurements in §3 reflect.
- **On the bundled Android build** `h264_mediacodec` is declared at `allcodecs.c:152` and
  `libx264` at `allcodecs.c:808`, so the hardware encoder wins the lookup. It has no CRF: it writes
  `avctx->bit_rate` when non-zero (`libavcodec/mediacodecenc.c:309-310`) and the default is
  `#define AV_CODEC_DEFAULT_BITRATE 200*1000` (`libavcodec/options_table.h:47,50`); its I-frame
  interval is `round(avctx->gop_size / fps)` with default `gop_size = 12`
  (`options_table.h:98`), i.e. `round(12/30) = 0` → clamps to 1 (`mediacodecenc.c:323-328`).
  [INFERENCE, source-derived, not executed: an unparameterised cut-time re-encode on the device
  targets ~200 kbit/s with an I-frame per frame. This is the single most important thing for the
  app to know, and it is the one claim in this report that I could not measure.]

**Control.** `--ppa` / `--postprocessor-args` (already used by the app for artwork
`DownloadUtil.kt:262`) do **not** reach the external downloader: output arguments come from
`self._configuration_args(('_o1', '_o', ''))` — `external.py:627` — i.e. from
`--downloader-args ffmpeg_o:…` (`_configuration_args` in `utils/_utils.py:3599-3602`). Measured
(R14): with `--downloader-args "ffmpeg_o:-c:v libx264 -crf 30 -preset ultrafast"` the argv
became `-ss 20.0 -t 5.0 -i http://… -f mp4 -c:v libx264 -crf 30 -preset ultrafast 'file:…part'`
and ffmpeg logged `h264 (native) -> h264 (libx264)`. Setting the encoder for a forced cut
therefore needs a new flag in the app, e.g.
`--downloader-args "ffmpeg_o:-c:v libx264 -crf 23 -preset veryfast"`.

### 2. Item 3b — can the bundled ffmpeg do it

**arm64 build configuration** (verbatim from `strings libffmpeg.so`, wrapped):

    --arch=aarch64 --as=aarch64-linux-android-clang … --cross-prefix=aarch64-linux-android-
    --disable-indevs --disable-outdevs --enable-indev=lavfi --disable-static --disable-symver
    --enable-cross-compile --enable-gnutls --enable-gpl --enable-version3 --enable-jni
    --enable-lcms2 --enable-libaom --enable-libass … --enable-libmp3lame --enable-libopus
    --enable-librav1e --enable-librubberband --enable-libsoxr --enable-libsrt --enable-libssh
    --enable-libsvtav1 --enable-libtheora --enable-libv4l2 --enable-libvidstab --enable-libvmaf
    --enable-libvo-amrwbenc --enable-libvorbis --enable-libvpx --enable-libwebp --enable-libx264
    --enable-libx265 --enable-libxml2 --enable-libxvid --enable-libzimg --enable-libzmq
    --enable-mediacodec --enable-opencl --enable-shared
    --prefix=/data/data/com.termux/files/usr --target-os=android
    --extra-libs=-landroid-glob --disable-vulkan --enable-neon --disable-libfdk-aac

x86_64 differs only in the arch/cross-prefix fields. Evidence that the encoders really exist:

| item | evidence |
|---|---|
| libx264 | `--enable-libx264`; `readelf -d libavcodec.so.61.19.101` → `NEEDED libx264.so.164`, and that file is in the zip; descriptor string `libx264` present |
| MediaCodec H.264 | `--enable-mediacodec --enable-jni`; `NEEDED libmediandk.so`; descriptor string `h264_mediacodec` present; `configure:3353` gives `h264_mediacodec_encoder_deps="mediacodec"`, `configure:3147` gives `mediacodec_deps="android mediandk"` — both satisfied |
| AAC | `libavcodec/allcodecs.c:421` declares the built-in `ff_aac_encoder` in the audio block, before `aac_at_encoder` (`:739`, Apple only) and before `aac_mf_encoder` (`:825`, MediaFoundation); `aac_mediacodec` is a *decoder* only. So mp4→aac re-encode always works. |

**Provenance.** The brief's secondary source (`yausername/ffmpeg-android-maker`) does not exist — `gh api repos/yausername/ffmpeg-android-maker` returns 404. The library's own `BUILD_FFMPEG.md` (JunkFood02/youtubedl-android) says: *"FFmpeg can be built for android using the termux ffmpeg package"*, built with termux-packages' `build-package.sh ffmpeg`, then `zip --symlinks -r /tmp/ffmpeg_arm.zip usr/lib` — which matches the artifact exactly (termux prefix/cache paths `/home/builder/.termux-build/_cache/…`; a symlink-preserving zip of `usr/lib`). It does **not** match current termux master flag-for-flag (master has `--enable-libxcb* --enable-openssl --enable-vulkan`; the artifact has none of those and adds `--enable-neon`), so the recipe is an older or patched termux revision; the encoder verdict is unaffected.

**Verdict.** A cut-time re-encode can succeed on a device: with `-c:v libx264` it always can
(software), with the default lookup it asks MediaCodec for a hardware H.264 encoder and succeeds
only where the device provides one. There is no fallback: if no encoder exists for the codec,
`ffmpeg` dies with *"Automatic encoder selection failed … probably disabled. Please choose an
encoder manually."* (`fftools/ffmpeg_mux_init.c:95-99`); if a named encoder is absent it dies with
`Unknown encoder 'X'` — measured, see R12 — and yt-dlp then reports
`ERROR: ffmpeg exited with code 8` (`external.py:79-80`) with no output file. A runtime MediaCodec
failure fails inside `avcodec_open2` and is not retried with another encoder.

### 3. Item 3c — measured precision and cost

#### Method

Sources generated with nix ffmpeg 9.0.1 (`testsrc2` + `sine`, x264 `-preset veryfast -crf 23`,
keyframes pinned with `-g N -keyint_min N -sc_threshold 0`): `src_gop250.mp4` 120 s 720p IDR every
8.333 s (43.8 MB); `src_gop60.mp4` 120 s 720p IDR every 2.000 s (44.5 MB); `src1080_gop250.mp4`
120 s 1080p; `src240_gop250.mp4` 240 s 720p (stream-copy loop of the first).

Served over http by `static-web-server` on 127.0.0.1:8099 (Range verified: `curl -r 100-199` →
`HTTP/1.1 206`, `content-range: bytes 100-199/43834582`). Each run:

    cd /tmp/ytdlp-src && python3 __main__.py --no-mtime --continue --verbose \
      --download-sections "*<start>-<end>" [--force-keyframes-at-cuts] \
      -o "<dir>/%(title).200B [%(section_start)d-%(section_end)d].%(ext)s" http://127.0.0.1:8099/<src>

`wall_seconds` is the whole yt-dlp run (including the local HTTP transfer); ffmpeg's own final
progress line gives the encode-only time. Ground truth for where a cut starts: the output is
decoded (`ffmpeg -f framehash`) and the first frame's SHA-256 is matched against the source's
decoded frames; for re-encoded outputs the match is by SSIM against single source frames
(`select=eq(n,N)`; ffmpeg 9 dropped `-vsync`, so `-fps_mode passthrough`).

#### Requested range vs produced output

| run | source | section | flag | wall s | file B | presented dur. | frames | output frame 0 == source | first IDR (presented) |
|---|---|---|---|---|---|---|---|---|---|
| R1 | gop250 | 20–60 | no | 2.83 | 15,868,065 | 40.066667 | 1202 | frame 600 = **20.0000 s** (hash) | 5.000 s |
| R2 | gop250 | 20–60 | yes | 30.57 | 13,717,302 | 40.000000 | 1200 | frame 600 (SSIM 0.980) | 0.000 s |
| R3 | gop250 | 20.4–23.9 | no | 3.54 | 2,693,789 | 3.600000 | 107 | frame 612 = **20.4000 s** (hash) | *none* |
| R4 | gop250 | 20.4–23.9 | yes | 10.10 | 1,195,436 | 3.500000 | 105 | frame 612 (SSIM 0.976) | 0.000 s |
| R11 | gop250 | 20.41–23.91 | no | 2.86 | 2,701,815 | 3.589974 | 107 | frame 613 = **20.4333 s** (hash) | *none* |
| R5 | gop60 | 20–60 | no | 5.69 | 14,855,534 | 40.066667 | 1202 | frame 600 = **20.0000 s** (hash) | 0.000 s |
| R6b | gop60 | 20–60 | yes | 27.68 | 13,746,417 | 40.000000 | 1200 | — (re-encoded) | 0.000 s |
| R7 | 1080p | 20–60 | yes | 54.05 | 27,379,324 | 40.000000 | 1200 | — (re-encoded) | 0.000 s |
| R8 | 1080p | 20–60 | no | 3.88 | 31,838,607 | 40.100000 | 1202 | (R1 structure: pre-roll + edit list) | 5.000 s |
| R9 | 240 s src | 20–200 | yes | 122.81 | 61,733,270 | 180.033333 | 5400 | — (re-encoded) | 0.000 s |
| R10 | 240 s src | 20–200 | no | 3.36 | 67,019,109 | 180.121354 | 5402 | frame 600 = **20.0000 s** (hash) | 5.000 s |

"presented" = video-stream duration with the MP4 edit list applied (`ffprobe -count_frames`);
"frames" is the number of decoded video frames on the presented timeline. For every flagged run
presented and physical counts are identical (no edit list: R6b 40.000000/1200, R7 40.000000/1200,
R9 180.033333/5400); for every copy run they are not (R8 40.100000/1202 vs 43.400000/1302;
R10 180.121354/5402 vs 183.421354/5502).

SSIM detail (first frame, neighbours 1/30 s apart) — the flagged cut lands on the exact frame,
not merely somewhere near it:

    R2 out frame 0  vs source 599 = 0.922023 | 600 = 0.979547 | 601 = 0.922787
    R4 out frame 0  vs source 611 = 0.919588 | 612 = 0.975999 | 613 = 0.921633

#### What the default (no flag) cut actually is

Both flags and no flags are frame-exact in *timing*; they differ in file structure and in what
a decoder can start from. Measured structure of the copy cut (R1):

| view | frames | start | duration |
|---|---|---|---|
| `ffprobe -ignore_editlist 1` (physical) | 1302 | 0.066667 | 43.400000 |
| default (edit list applied) | 1202 | 0.000000 | 40.066667 |

1302 − 1202 = 100 frames = 3.333 s = exactly the source segment 16.667→20.000 s. The MP4 muxer
kept the frames back to the preceding IDR and wrote an **edit list** that trims them, so playback
starts exactly at 20.000 s. Keyframes show the same split: presented `5.0, 13.33, 21.67…`,
physical `0.0667, 8.4, 16.73…` (i.e. source 16.667, 25.0, 33.33…). Consequences, all measured:

- The clip carries **1,204,691 B (1.15 MiB, 7.6 % of the file)** of pre-roll beyond 20.000 s, and
  the pre-roll IDR is trimmed, so the presented timeline has **no IDR in its first 5.000 s**. R3 is
  the extreme case: a 3.6 s clip with **zero** keyframes (physical 219 frames / 7.3 s vs presented
  107 frames / 3.6 s — the pre-roll is longer than the clip).
- Decoding the file from its first byte reproduced the source frames exactly with no warnings,
  because the pre-roll IDR is physically present. A consumer that ignores or rewrites the edit list
  (re-mux, some editors/streaming paths) starts up to one GOP early instead of at 20.000 s.
- End boundary overshoots by 2–3 frames: R1 1202 frames for 1200 (+0.0667 s), R3 107 for 105
  (+0.067 s), R8 1202 for 1200 (+0.100 s), R10 5402 for 5400 (+0.121 s).
- A non-frame-aligned range rounds **up** to the next frame: 20.41 → frame 613 (20.4333 s), not
  the nearer frame 612 (20.400 s).
- With a 2 s GOP (R5) the default cut happens to start on an IDR (20.0 is on the 2 s grid), so copy
  and re-encode agree.

The flagged cut (R2, R4, R9) is exact by construction: the frame count is exactly `range × 30`
(1200, 105, 5400), the container duration is within 0.034 s of the request (40.000000, 3.500000,
180.033333), and frame 0 is an IDR, so the clip is self-contained from its first frame.

#### Cost

`ffmpeg`'s own encode time, from its progress line (`R1/R5/R10` are copy):

| run | clip | encode elapsed s | fps | speed | s of encode per s of clip |
|---|---|---|---|---|---|
| R6b (720p, gop60) | 40 s | 25.11 | 48 | 1.59x | 0.628 |
| R2 (720p) | 40 s | 27.12 | 44 | 1.47x | 0.678 |
| R9 (720p, 3 min) | 180 s | 119.58 | 45 | 1.51x | 0.664 |
| R4 (720p, 3.5 s) | 3.5 s | 4.87 | 22 | 0.718x | 1.391 (startup-dominated) |
| R7 (1080p) | 40 s | 50.31 | 24 | 0.795x | 1.258 |
| R1 (720p copy) | 40 s | 0.08 | — | 488x | 0.002 |
| R10 (720p copy, 3 min) | 180 s | 0.83 | — | 216x | 0.005 |

Whole-run wall clock for the same work: 40 s 720p clip **2.83 s without** the flag vs **30.57 s with** it; 3-minute 720p clip **3.36 s → 122.81 s**; 40 s 1080p clip **3.88 s → 54.05 s**. The copy runs are transfer-bound, so their cost is essentially "download the bytes up to `-t`".

Extrapolation (labelled as one): the 3-minute 720p figure is itself *measured* (R9 = 119.6 s). For
1080p only 40 s is measured (50.3 s encode); scaled linearly, a 3-minute 1080p clip is ~227 s
(~3.8 min) of x264 on this 8-core desktop. This is an x86_64 desktop; an arm64 phone SoC running
libx264 in software is substantially slower, so expect multiples of these times. The synthetic
`testsrc2` content encodes faster than camera footage, so every software number is a **lower
bound**. If the device resolves the encoder to `h264_mediacodec` (the default in this artifact,
§1) time drops to hardware speed but quality drops to the 200 kbit/s all-intra defaults unless the
app passes `--downloader-args ffmpeg_o:…`.

### 4. Could not verify

- No Android/bionic runtime, device, or emulator here, so no bundled binary was executed: the
  device-side encoder resolution (`h264_mediacodec` winning `avcodec_find_encoder`), the
  200 kbit/s / gop 1 defaults in practice, and any MediaCodec-open failure are source-derived, not
  measured. Every such claim is marked above.
- The re-encode measurements ran on nixpkgs ffmpeg **9.0.1** with libx264, not on the bundled
  7.1.1; the raw encode times are therefore x264-on-x86_64 figures, not this artifact's own.
- yt-dlp's issue tracker was not reachable for a known-issue note on the download-time re-encode;
  only the README at the pinned tag (`README.md:1082-1088`) was used.

### Practical answers for the app

- **(a) `--force-keyframes-at-cuts` is usable, with strings attached.** In 2025.11.12 it only
  removes `-c copy` (`external.py:587-588`), so the app gets a frame-exact cut starting on an IDR.
  But the encoder is chosen by container default, and in the bundled build that is
  `h264_mediacodec` at `AV_CODEC_DEFAULT_BITRATE` (200 kbit/s) with an I-frame per frame — useless
  quality. The app must also pass `--downloader-args "ffmpeg_o:-c:v libx264 -crf 23 -preset
  veryfast"` (`external.py:627`); `--ppa`, which the app already uses, does not reach the
  downloader. A device whose MediaCodec has no H.264 encoder fails the whole download
  (`ffmpeg exited with code 8`) with no fallback.
- **(b) Cost.** A 3-minute 720p clip cost 119.6 s of x264 on this desktop (measured, R9) versus
  0.8 s to copy (R10); a 40 s 720p clip is 2.8 s → 30.6 s. 1080p is slower than real time here
  (0.795x). On a phone, assume multiples of these times for the software path; the hardware path is
  fast but needs explicit quality parameters to be acceptable.
- **(c) The default cut (no flag) is already exact in time — but structurally odd.** The file
  starts at the requested frame (20.0000 s for `*20-60`, 20.4000 s for `*20.4-23.9`, 20.4333 s for
  `*20.41-23.91`), yet it physically carries up to one GOP of pre-roll (1.15 MiB / 3.33 s here) and
  hides it behind an MP4 edit list. The presented timeline has no keyframe until the first source
  IDR at or after the cut (5.0 s in for an 8.33 s-GOP source, *never* for a short clip), so any
  consumer that drops the edit list silently starts early. The default is the right choice for
  speed; the flag is the right choice when a self-contained, seek-safe clip matters.


## Independent checks by the session

Made after both parts were written, to test the claims the ticket's decisions hang on rather than take
them on trust. Each line names what was run or read.

1. **Version.** The session extracted `res/raw/ytdlp` from its own download of `library-0.18.1.aar`
   and read `yt_dlp/version.py` (`2025.11.12`, head `335653be82d5ef999cfc2879d005397402eebec1`); part A
   downloaded the same artifact into a separate directory and got the same AAR sha256
   (`579b5fb480892b1abc2b218c2089699d52759cc8d7ba256bf876453f0365faef`). Two independent extractions
   agreeing is what makes the source a primary source here.
2. **Truncation and collision, measured twice.** With the app's template shape, ranges `*2-5`/`*7-10`
   produced `src [2-5].mp4` and `src [7-10].mp4`; ranges `*2.4-4.7`/`*6.1-8.2` produced
   `src [2-4].mp4` and `src [6-8].mp4`; the colliding pair `*2.4-4.7`/`*2.9-4.1` produced **one** file,
   with the second print `[download] …/src [2-4].mp4 has already been downloaded` and a run that still
   reported success.
3. **No index for time ranges.** `-o "…%(section_number)d…"` with a time range rendered `src clipNA.mp4`
   — the field is absent, not an error.
4. **Both replacement templates render distinct names** for the colliding pair:
   `%(section_start)s-%(section_end)s` → `src [2.4-4.7].mp4`, `src [2.9-4.1].mp4`;
   `%(section_start)07.3f-%(section_end)07.3f` → `src [002.400-004.700].mp4`, `src [002.900-004.100].mp4`.
5. **Archive gates, read in the pinned source.** `YoutubeDL.py:3100-3103` writes the record only when no
   requested range reported `__write_download_archive=False`; `:1614-1619` consults `in_download_archive`
   before `process_video_result` expands the ranges (`:3058`, `:3072`); `:3825-3831` returns early when
   the archive set is empty; `:3833-3845` returns early when `download_archive` is `None`;
   `options.py:782-785` maps `--no-download-archive` to exactly that. So one run can opt out of both the
   read and the write, and a clip download's record keys the whole video.
6. **Cut structure, reconciled.** The session cut `*2.4-4.7` from a 12 s source with 2 s keyframes using
   `ffmpeg -ss 2.4 -t 2.3 -i src.mp4 -c copy`, then matched decoded frames against the source by
   SHA-256 (`ffmpeg -f framehash`) and counted both ways:

   | view | frames | span | first frame |
   |---|---|---|---|
   | default (edit list applied) | 60 | 2.44 s | **source frame 60 = exactly 2.400 s** |
   | `-ignore_editlist 1` (physical) | 70 | 2.88 s | source frame 50 = 2.000 s |

   The 10 extra frames (0.4 s, exactly one GOP of 2 s) are pre-roll kept in the stream and hidden by the
   MP4 edit list. Part A's "starts at the closest seek point before the position" is true of the physical
   stream; part B's "presented start is exact" is true of the demuxed timeline; a consumer that drops or
   rewrites the edit list starts up to one GOP early. Both readings are measurements of the same file —
   this is the resolution, not a conflict.
7. **Which encoder the bundled ffmpeg would pick.** Checked against FFmpeg `n7.1.1` sources fetched by
   the session: `ff_h264_mediacodec_encoder` is declared at `libavcodec/allcodecs.c:152` and
   `ff_libx264_encoder` at `:808`, and `find_codec` (`:981-1000`) returns the first non-experimental
   registration for the codec ID, so with both enabled the MediaCodec encoder wins
   `avcodec_find_encoder(AV_CODEC_ID_H264)`. The unparameterised defaults follow:
   `AV_CODEC_DEFAULT_BITRATE 200*1000` (`libavcodec/options_table.h:47,50`) and `gop_size` default 12
   (`:98`) → `round(12 / fps)` = 0, clamped to 1 (`libavcodec/mediacodecenc.c:323-334`). Device behaviour
   remains unverified: no Android runtime was available.
8. **Where the download-time ffmpeg gets its output arguments.** `external.py:627` uses
   `self._configuration_args(('_o1', '_o', ''))`, i.e. `--downloader-args ffmpeg_o:…`; `--ppa`
   (which the app already uses for artwork) and `--postprocessor-args` cannot reach the downloader.


## Answers in ticket order

Each item gives the exact flag or template field, the source that supports it, and an explicit
statement where something is impossible or unverified.

### 1. Does a stable per-section index exist for a clip's file name?

**No — impossible in the pinned version, not merely undocumented.** `section_number` is written from
exactly two places: `YoutubeDL.py:3085` (`chapter.get('index')`, 0-based, chapter-regex ranges only)
and `postprocessor/ffmpeg.py:1011` (1-based, `--split-chapters`). A time range comes from
`download_range_func` (`utils/_utils.py:3346-3350`), which yields only `start_time`/`end_time`, so for
`--download-sections "*a-b"` the fields `section_number` and `section_title` are `None` and render as
the `NA` placeholder (`README.md:670-671`), while `section_start`/`section_end` are floats
(`section_end` is `None` when the range reaches the media end). `%(section_start)d` truncates toward
zero, which is why `2.4-4.7` and `2.9-4.1` both render `[2-4]`.

Cheapest stable naming **without post-download renaming**, cheapest first:

1. Change the template — `CLIP_TIMESTAMP` (`DownloadUtil.kt:247`) from `%(section_start)d-%(section_end)d`
   to `%(section_start)s-%(section_end)s` (`src [2.4-4.7].mp4`) or the fixed-width
   `%(section_start)07.3f-%(section_end)07.3f` (`src [002.400-004.700].mp4`). One invocation, no rename;
   distinctness holds whenever the boundaries differ.
2. One yt-dlp invocation per clip with its own `-o` (verified: `src [clip1 2-4].mp4`,
   `src [clip2 2-4].mp4`). This is the only way to put an app-side clip index in the name. The app
   already loops over `videoClips` (`DownloadUtil.kt:1291-1295`), so the change is local; the cost is
   one metadata extraction per clip unless `--load-info-json` reuses one.
3. `--exec` renames after the download — available, excluded by the question.
4. `--parse-metadata` cannot help: it derives a field from other fields (`TEMPLATE:FIELD:REGEX`) and has
   no per-range ordinal to read.

Collision behaviour, measured in the app's exact shape: the later clip prints
`has already been downloaded` and is dropped while the run still reports success; the controlling
option is `overwrites`, not `--continue` (`--no-continue` still skips; `--force-overwrites` overwrites,
silently losing the earlier clip). Either way **one clip's data is lost**, so a download carrying
several sub-second clips cannot keep the current template.

### 2. `--download-sections` syntax and sub-second precision

Accepted forms from `parse_chapters` (`__init__.py:349-386`, `advanced=True` at `:391`): a value that
does not start with `*` is a chapter-title regex; `*from-url` obeys the URL's own `start_time`/
`end_time`; otherwise `*` plus comma-separated `start-end` pairs, both sides optional, `inf`/`infinite`
allowed, whitespace trimmed. `*-` alone is a usage error. Negative timestamps are allowed and resolved
against the extractor's `duration` only (`utils/_utils.py:3361-3362`), so a source without `duration`
passes a negative `-ss` straight to ffmpeg.

**Sub-second boundaries are accepted and preserved**: `parse_duration` handles `SS.mmm` and
`H:M:S.mmm`, and `*0:00:02.5-0:00:04.75` arrived as exactly `2.5`/`4.75`. The range reaches ffmpeg as
input-side `-ss <start>` / `-t <end-start>` before `-i` (`external.py:527-530`, `:585`), with
`-c copy` unless `--force-keyframes-at-cuts` (`:587-588`).

Where the cut lands: with `-c copy` the physical stream starts at the closest keyframe at or before the
request, and the MP4 muxer hides that pre-roll behind an edit list, so the presented timeline starts at
the request while the file physically carries up to one GOP extra (measured: 0.4 s / 10 frames of
pre-roll on a 2 s-GOP source; 3.33 s / 1.15 MiB on an 8.33 s-GOP source). A consumer that ignores the
edit list starts early. With a re-encode the extra segment is decoded and discarded, so the cut is
exact and the first frame is a keyframe. **The app cannot emit a sub-second range at all today**:
`VideoClip` holds whole seconds (`util/VideoInfo.kt:161-166`) and `DownloadUtil.kt:1291-1295` formats
`"*%d-%d"`; that truncation, not yt-dlp, is what loses precision.

### 3. What `--force-keyframes-at-cuts` does, and what it costs

On the app's path it **removes `-c copy` and re-encodes the whole clip**; it is not a boundary-only
re-encode and it passes no `-force_key_frames` (`external.py:587-588`; that option only reaches
`--split-chapters` and `--remove-chapters`, which the app does not use).

The consequence is the sharp edge: with no `-c:v`, ffmpeg resolves the encoder from the container
default (mp4 → h264) through `avcodec_find_encoder`, which returns the first registered
non-experimental encoder — and in the bundled build that is `h264_mediacodec`, not libx264, with
`AV_CODEC_DEFAULT_BITRATE` (200 kbit/s) and an I-frame per frame. The bundled ffmpeg 7.1.1 **does**
carry libx264 (`--enable-libx264`, `NEEDED libx264.so.164`) and a working AAC encoder, so an acceptable
re-encode is reachable — but only if the app names the encoder:
`--downloader-args "ffmpeg_o:-c:v libx264 -crf 23 -preset veryfast"` (`external.py:627`). `--ppa`,
already used for artwork cropping, **does not reach the downloader**. If a device's MediaCodec offers no
H.264 encoder the download fails with `ffmpeg exited with code 8`; there is no fallback.

Cost on this host (x86_64 desktop, x264, synthetic content — a lower bound for a phone):

| clip | copy (no flag) | forced re-encode |
|---|---|---|
| 40 s 720p | 2.83 s wall | 30.6 s wall / 27.1 s encode (1.47x) |
| 180 s 720p | 3.36 s wall | 122.8 s wall / 119.6 s encode (1.51x) |
| 40 s 1080p | 3.88 s wall | 54.1 s wall / 50.3 s encode (0.795x) |

So ≈ 0.66 s of encode per second of 720p clip and ≈ 1.26 s per second of 1080p; a 3-minute 1080p clip
extrapolates to ≈ 3.8 minutes of desktop x264. Software x264 on a phone is slower than this by a factor
that was not measured here.

### 4. Several `--download-sections` in one command

One file per (selected format × requested range), in the order the arguments were given
(`YoutubeDL.py:3072`, `:3087-3092`). With one selected format — the app's case — that is one file per
range. Names differ only by the rendered `section_*` values (item 1). The app's `-o` is relative and
the base directory comes from `-P`, so `-P temp:<dir>` is honoured: the `.part` is written in the temp
directory and moved to the final name on completion (`YoutubeDL.py:3319-3320`, `:3536`;
`external.py:42-44`). An **absolute** `-o` instead produces
`WARNING: --paths is ignored since an absolute path is given in output template` — relevant to the app
because its `outputBuilder` is relative by construction. `--continue` resumes nothing on this path:
FFmpegFD always rebuilds its output, a leftover `.part` is ignored, and a leftover complete-looking file
at the temp name is adopted and moved.

### 5. Does the archive record a clipped download?

**Yes**, and it records the **whole video**: the key is `extractor_key.lower() + ' ' + id`
(`utils/_utils.py:5283-5285`), written from the parent `info_dict`, never per range
(`YoutubeDL.py:3100-3103`). The check runs before the ranges are expanded (`:1614-1619` vs `:3058`,
`:3072`), so a download carrying clips marks the video done and a later run with the archive enabled
refuses the entire video — measured: `has already been recorded in the archive`, no file. Also note the
write is all-or-nothing across ranges: if any range reports
`__write_download_archive=False`, no record is written at all. One run opts out of both the read and the
write with `--no-download-archive` (`options.py:782-785`, `download_archive=None`); removing
`--download-archive` has the same effect (it is opt-in, default off). The pinned version and every
release after it carry no core archive or section-field change.

### 6. Pinned artifact evidence

- **yt-dlp 2025.11.12**, `RELEASE_GIT_HEAD 335653be82d5ef999cfc2879d005397402eebec1`, `CHANNEL stable`,
  from `library-0.18.1.aar` → `res/raw/ytdlp` (3 170 726 B, sha256
  `89a0d9058ea9018e380b7771898ff46e393a1986dcd13fef331693c87ce1fca4`) → `yt_dlp/version.py`. The
  unpacked tree is byte-identical to the upstream tag archive except packaging artifacts, so it is a
  valid primary source for every `file:line` above.
- **ffmpeg 7.1.1**, from `ffmpeg-0.18.1.aar` (sha256
  `0a87ffa6cf912b0fe76c1a99b9107f543ee2f247935fae2c71f0822eb7bc5f49`);
  `jni/arm64-v8a/libffmpeg.so` reports `version 7.1.1`, `libavutil.so.59`, and its termux-package
  configuration line carries `--enable-libx264 --enable-mediacodec --enable-jni` among others.
- **Everything above is available in those versions**; no answer depends on a newer yt-dlp or ffmpeg.

**Not verified.** No Android runtime, device or emulator was available, so the bundled binaries were
never executed: the on-device encoder resolution (MediaCodec winning), its 200 kbit/s all-intra
defaults in practice, and any MediaCodec-open failure are source-derived, not measured. The re-encode
timings come from nixpkgs ffmpeg with libx264 on x86_64, not from the bundled 7.1.1 on arm64.
App-side key equality for the archive pre-check (`videoInfo.extractor` vs `extractor_key.lower()`) was
confirmed for the `generic` extractor only.
