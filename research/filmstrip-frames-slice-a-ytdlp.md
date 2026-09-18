# Slice A - What yt-dlp itself can report or produce for filmstrip frames

Wayfinder ticket: cernoh/Sealplus#3 ("Where can the app get filmstrip frames for any source, and can it
invoke the bundled ffmpeg to extract them?"), slice A: the yt-dlp side.

Scope: what frame or storyboard assets yt-dlp can report or produce for an arbitrary supported source.
Sibling slices own the ffmpeg execution path (B) and cost/lazy extraction/remote URLs (C).

## Question

For the trim editor, Sealplus needs several evenly spaced frames of a video at *configure* time (before
the yt-dlp download finishes, because trimming is `--download-sections` at download time). Does yt-dlp
give the app such frames directly? This report settles:

1. what the info JSON really contains (storyboard reality check),
2. what yt-dlp can write to disk and with which flags,
3. per source class, whether a multi-frame asset exists at all,
4. the concrete invocation an Android app would use, and what the app already does today.

Evidence classes used below: **observed** = I ran the command and read its output; **source** = read in
yt-dlp source at a named revision; **[INFERENCE]** = reasoning, not observed.

Revision facts used throughout:

- The app ships yt-dlp **2025.11.12** (`RELEASE_GIT_HEAD 335653be82d5ef999cfc2879d005397402eebec1`),
  extracted from `res/raw/ytdlp` in `library-0.18.1.aar` [bundled-version]. The same AAR also ships
  `jni/<abi>/libqjs.so` and `libpython.zip.so` [aar-listing].
- I also read current master [yt-master]. Storyboard handling is **identical** in both revisions
  (only line numbers differ), so the findings below hold for the shipped build and for any runtime
  yt-dlp update.
- I ran the *shipped* 2025.11.12 code path locally (extracted `res/raw/ytdlp`, run under `python3`)
  for most behavioural observations: the `-f sbN` downloads and file sizes, the MHTML dump,
  `--list-thumbnails`, `-f mhtml` selection, `--write-all-thumbnails` naming, the `--help` Thumbnail
  Options block and the storyboard-less source error. Two observations used the distro yt-dlp
  **2026.08.19** because it can solve YouTube's JS challenge locally: the 77-key `--dump-single-json`
  inspection (and the 4-entry storyboard format table with 42 thumbnails) and the
  `-f sb3 --write-thumbnail` run (46 thumbnails under the shipped build, 42 under 2026.08.19).

## 1. Reality check: there is no top-level `storyboards` key

**Refuted, as stated in the ticket.**

- **Observed** `yt-dlp --skip-download --dump-single-json <youtube url>` yields 77 top-level keys.
  `storyboards` is not among them. `thumbnails` is. The JSON does contain storyboards - as entries in
  `formats`.
- **Source** No code builds a top-level `storyboards` key. The string appears in `yt_dlp/` only in
  three roles: `MEDIA_EXTENSIONS.storyboards = ('mhtml', )` (`yt_dlp/utils/_utils.py:5107` master),
  `'storyboards': set(MEDIA_EXTENSIONS.storyboards)` in `YoutubeDL._format_selection_exts`
  (`yt_dlp/YoutubeDL.py:631` master, `:626` in the shipped file), and as the **player-response** key
  read by `_extract_storyboard()` (next bullet) - never as an info-dict output key.
- **Source** The `storyboards` key that the ticket probably remembers is in **YouTube's player
  response**, not in yt-dlp's info JSON: `_extract_storyboard()` reads
  `get_first(player_responses, ('storyboards', 'playerStoryboardSpecRenderer', 'spec'))`
  (`yt_dlp/extractor/youtube/_video.py:3768-3771`) and the results are appended to the format list with
  `formats.extend(self._extract_storyboard(player_responses, duration))` (`_video.py:4163`).

### The real JSON shape (observed, shipped 2025.11.12, `dQw4w9WgXcQ`)

Four storyboard formats (sb0-sb3) in `formats`; one entry, abridged:

```json
{
  "format_id": "sb3",
  "format_note": "storyboard",
  "ext": "mhtml",
  "protocol": "mhtml",
  "acodec": "none",
  "vcodec": "none",
  "url": "https://i.ytimg.com/sb/dQw4w9WgXcQ/storyboard3_L0/default.jpg?sqp=...&sigh=rs$...",
  "width": 48, "height": 27,
  "fps": 0.4694835680751174,
  "rows": 10, "columns": 10,
  "fragments": [{"url": "https://i.ytimg.com/sb/.../default.jpg?sqp=...&sigh=rs$...", "duration": 213.0}],
  "resolution": "48x27", "aspect_ratio": 1.78, "vbr": 0, "abr": 0, "tbr": null
}
```

Per level for that video (observed): sb0 320x180 3x3 12 sprites; sb1 160x90 5x5 5 sprites;
sb2 80x45 10x10 2 sprites; sb3 48x27 10x10 1 sprite. `--simulate --print
"%(format_id)s %(format_note)s %(width)sx%(height)s rows=%(rows)s cols=%(columns)s %(fps)s"` works, so
the app can read `rows`/`columns` through `--print` too (observed). `rows`/`columns` are also declared
as format fields in `YoutubeDL._format_fields` (`YoutubeDL.py:608-612` master) and documented in
`yt_dlp/extractor/common.py:473-475`.

Not exposed: `frame_count` is not in the JSON. It is recoverable exactly, because the extractor sets
`fps = frame_count / duration` (`_video.py:3787-3800`), so `frame_count = fps * duration`
(108 for sb0-sb2, 100 for sb3 in the observation above).

## 2. What yt-dlp can write, and with which flags

### `--write-thumbnail`, `--write-all-thumbnails`, `--list-thumbnails`, `--convert-thumbnails` never touch storyboards

- **Source** `_write_thumbnails()` iterates `info_dict['thumbnails']` only
  (`yt_dlp/YoutubeDL.py:4503-4548` master, `:4453-4498` shipped). Storyboards are not in `thumbnails`,
  so they are unreachable from these flags.
- **Observed** for `dQw4w9WgXcQ` the `thumbnails` array has 42 entries (shipped build: 46), all
  `i.ytimg.com/vi/...` or `vi_webp/...` stills, ids `"0"..."41"`, no sprite.
- **Observed** `--list-thumbnails` prints only those `vi/vi_webp` rows (no sb rows).
- **Observed** `-f sb3 --write-thumbnail` downloaded and wrote `sb.webp` (the ordinary video thumbnail,
  id 41 = `maxresdefault.webp`), i.e. `--write-thumbnail` is orthogonal to the storyboard.
- **Observed** `--write-all-thumbnails --convert-thumbnails png` wrote 46 files named
  `c.<thumbnail-id>.png` (e.g. `c.0.png`, `c.31.png`) plus `c.mhtml` for the selected storyboard.
  Naming rule in source: `thumb_ext = f'{t["id"]}.{thumb_ext}'` when writing all
  (`YoutubeDL.py:4525-4529` master). `--convert-thumbnails` runs `FFmpegThumbnailsConvertorPP`
  (`yt_dlp/postprocessor/ffmpeg.py:1062`), whose input list is the thumbnail file list - storyboards
  are not in it.

### The exact arguments that make yt-dlp write individual storyboard frames to numbered image files

**There are none. This is the central negative finding of slice A.**

- **Source** The storyboard "download" is `MhtmlFD` (`yt_dlp/downloader/mhtml.py`), registered for
  `protocol: 'mhtml'` (`yt_dlp/downloader/__init__.py:50`). It writes **one** file: an MHTML container
  whose body is a HTML stub plus one MIME part per sprite fragment
  (`mhtml.py::real_download`, `_gen_stub`, `_gen_cid`). It never splits, never crops, and never calls
  ffmpeg.
- **Observed** `-f "sb0,sb1,sb2,sb3" -o "%(format_id)s.%(ext)s"` produced exactly four files:
  `sb0.mhtml`, `sb1.mhtml`, `sb2.mhtml`, `sb3.mhtml`; no image files, no numbered frames.
- **Source/upstream** Frame export is an **open** feature request, labelled `core:post-processor` +
  `enhancement`: yt-dlp#2048 "Add option to download youtube storyboard as jpg" (open since
  2021-12-19) and yt-dlp#11386 "Convert slides/storyboards to video" (open since 2024-10-28) [FR2048,
  FR11386].
- **Observed** nothing in the CLI help suggests otherwise: the shipped build's "Thumbnail Options"
  section is exactly `--write-thumbnail`, `--no-write-thumbnail`, `--write-all-thumbnails`,
  `--list-thumbnails`.

MHTML structure (observed, `sb.mhtml` for sb3, 21,656 bytes):

```
MIME-Version: 1.0
Content-type: multipart/related; boundary="606e..."; type="text/html"
X.yt-dlp.Origin: https://www.youtube.com/watch?v=dQw4w9WgXcQ

--606e...
Content-Type: text/html; charset=utf-8
Content-Length: 733
<!DOCTYPE html>...<figcaption>Slide #1: 00:00:00,000 - duration: 03:33,000</figcaption><img src="cid:0.606e...@yt-dlp.github.io.invalid">...
--606e...
Content-ID: <0.606e...@yt-dlp.github.io.invalid>
Content-type: image/webp
Content-length: 20062
Content-location: https://i.ytimg.com/sb/dQw4w9WgXcQ/storyboard3_L0/default.jpg?...
X.yt-dlp.Duration: 213.000000
<raw sprite bytes>
```

So the MIME part index is the only numbering yt-dlp adds, and each part is a whole sprite
(`rows x columns` tiles), not a frame. Part content type comes from `imghdr` on the fetched bytes
(`mhtml.py`), i.e. it follows what the CDN actually returns, not the URL suffix.

### Which storyboard yt-dlp picks by itself

- **Observed** `-f mhtml` selects sb0 (the 320x180 level) - the ext selector compares `ext == 'mhtml'
  and acodec == 'none' and vcodec == 'none'` (`YoutubeDL.py:2580-2581` shipped) and then applies normal
  quality sorting. `-f sb2` selects one exact level; `-f "sb0,sb1"` downloads several.
- **Source** The default format spec is `bestvideo*+bestaudio/best`
  (`YoutubeDL.py:2317-2340` master). Storyboards have `vcodec == acodec == "none"`, so a plain run
  never downloads them; **observed** runs without `-f` never produced a `.mhtml`.

### Extra HTTP requests (what a `-f sbN` run costs)

- **Source** one GET per `fragments[]` entry (`MhtmlFD._download_fragment`).
- **Observed** for the 3:33 video: sb0 = 12 fragment GETs (305,661 B `.mhtml`), sb1 = 5 (112,688 B),
  sb2 = 2 (46,219 B), sb3 = 1 (21,656 B). No video format is fetched. Cleanup: the app must delete the
  `.mhtml` it asked for; nothing else is left behind (except any `--write-thumbnail` file it also asked
  for).

## 3. Per source class: who has a sprite, who has only a still

The reliable detector is **not** `protocol`/`ext` alone but the codec pair plus the note:

> a format is a storyboard asset when `vcodec == "none" and acodec == "none"` and
> (`format_note` contains `"storyboard"` or `ext == "mhtml"`); it is a **tile sprite** only when it
> also carries `rows`, `columns` and `fragments[]`.

Reasons this framing matters (all source-verified):

- The DASH path sets `protocol: "mhtml"` only for `image/avif`/`image/jpeg` representations
  (`extractor/common.py:3187-3188`); other image MIME types become `http_dash_segments`.
- The SMIL path emits `format_id: "imagestream-N"` with `ext` from the MIME type, `format_note:
  "SMIL storyboards"`, **no** `protocol` field and **no** `rows`/`columns`/`fragments` at all
  (`extractor/common.py:2707-2721`): it is one image URL per entry, so it must not be treated as a
  tile grid without further verification.
- YouTube and Twitch do set `protocol: "mhtml"` and the full tile metadata
  (`_video.py:3788-3804`, `twitch.py:554-570`), which is why `-f mhtml` works for them.

| Class | Source of the sprite | Citation |
|---|---|---|
| YouTube | `playerStoryboardSpecRenderer.spec` -> `sb0..sbN` | `extractor/youtube/_video.py:3768` |
| Twitch VODs | `seekPreviewsURL` storyboard JSON -> `sb0..` | `extractor/twitch.py:539-566` |
| France.tv | `spritesheets` | `extractor/francetv.py:218-226` |
| Mediasite | lecture "slides" -> mhtml | `extractor/mediasite.py:153-159` |
| Panopto | slides via `_extract_mhtml_formats` | `extractor/panopto.py:298-322` |
| Any DASH source with image AdaptationSets (`image/jpeg`, `image/avif`) | `_parse_mpd_formats` emits `format_note: "DASH storyboards (jpg)"`, `ext: mhtml`, `protocol: mhtml` | `extractor/common.py:3044-3049`, `:3187-3188` (test case `VikiIE`) |
| SMIL `imagestream-*` | `format_note: "SMIL storyboards"` - one image URL per entry, no tile metadata | `extractor/common.py:2707-2721` |

Everything else (the large majority of the ~1000+ extractors, e.g. archive.org) provides only a single
`thumbnail`/`thumbnails` entry. **Observed** on such a source, `-f mhtml` fails hard:

```
ERROR: [archive.org] BigBuckBunny_124: Requested format is not available. Use --list-formats for a list of available formats
```

For that class yt-dlp cannot produce several evenly spaced frames by any means:

- No CLI option exists for it (help text above; `yt_dlp/options.py`, Thumbnail Options group).
- `--exec` / `--postprocessor-args` run an **app-supplied** command; they do not make yt-dlp generate
  frames, and there is no postprocessor that consumes storyboards (grep for `storyboard` in
  `yt_dlp/postprocessor/` finds nothing). `--exec` is also the wrong stage for a configure-time
  filmstrip: its stages are the PP `when` values, so `after_move:` runs only once the video is
  downloaded, and `before_dl:` has no file yet (`yt_dlp/__init__.py:552-553`, `:730-736`); a non-zero
  exit from the hook raises `PostProcessingError` and fails the whole download
  (`yt_dlp/postprocessor/exec.py::ExecPP.run`).
- The single thumbnail (`thumbnails[0]`) is one still frame; `--write-all-thumbnails` writes several
  *different crops/resolutions of the same still*, not different times.
- Third-party plugins: postprocessor plugins are a genuine extension point
  (`README.md` "PLUGINS"; enabled with `--use-postprocessor NAME`; loaded from
  `yt_dlp_plugins/postprocessor/`), so a plugin *could* split sprites - but none exists in the official
  plugin list [wiki-plugins], and shipping a plugin is app-side work with no guarantee of maintenance.

[INFERENCE] Therefore: for non-storyboard sources the app must decode frames from the video itself
(ffmpeg / MediaMetadataRetriever on a partial download), which is slice B/C territory - yt-dlp provides
nothing there.

## 4. Invocation form for the app

Three viable shapes, in decreasing preference for a trim-time filmstrip:

**(a) No extra yt-dlp process at all - fetch the sprites the app already knows about.**
The info JSON the app already fetches via `--dump-single-json` contains `formats[].fragments[].url`.
**Observation that matters:** the **format-level `url` is an unsubstituted template** for multi-sprite
levels - observed sb0/sb1/sb2 carry a literal `M$M.jpg` segment (`$M` is the fragment index, `$N`/`$L`
the other placeholders, substituted per fragment at `_video.py:3784` and `:3799-3801`), while the
single-sprite sb3 has a plain `default.jpg`. Only `fragments[].url` values are directly fetchable;
use them and ignore `format.url`.
**Observed**: those fragment URLs are plain CDN URLs that answer a bare `curl` (no cookies, no special
headers, default User-Agent) with `HTTP 200`, `content-type: image/webp`, e.g. the sb3 sprite =
20,062 B, 480x270. The app already does exactly this kind of direct fetch for stills: `ThumbnailUtil`
uses OkHttp against `i.ytimg.com` and decodes with Android bitmap APIs (`util/ThumbnailUtil.kt:56-95`).
This path adds zero yt-dlp invocations, zero temp files, and works before/independently of the download.

**(b) Ask yt-dlp for the sprite container (if the app prefers yt-dlp to do the fetching):**

```
yt-dlp -f mhtml        -o "%(id)s.sb.%(ext)s" <url>     # best level (sb0 on YouTube)
yt-dlp -f sb2          -o "%(id)s.sb.%(ext)s" <url>     # one chosen level, cheaper
```
Result: one file `<id>.sb.mhtml`; parse the MIME parts (one per sprite) or just accept that a splitter
must run on them. Add `--no-part`/`--no-progress` as the app already does elsewhere; delete the file
afterwards. Additional network: 1-12 sprite GETs (observed sizes in section 2).

**(c) Not recommended:** merging the storyboard into the main download
(`-f "bv*+ba+sb2"`). `+` means "merge into a single file"; [INFERENCE] an image sprite cannot be muxed
with video/audio by ffmpeg, so this either fails or corrupts the output. Keep the storyboard fetch
separate from the video download.

### What the app already does today (exact flags and lines)

- Info probe already carries the storyboard metadata: `fetchVideoInfoFromUrl` builds
  `--dump-single-json` (`DownloadUtil.kt:368`, and `:278` for playlist/video info), so
  `formats[].format_note == "storyboard"` entries are already in the payload the app parses into
  `VideoInfo.formats` (`util/VideoInfo.kt:13`, `data class Format` at `:100`).
  The parsed `Format` has `formatId`, `formatNote`, `ext`, `url`, `width`, `height`, `fps`
  (`util/VideoInfo.kt:100-117`) but **not** `protocol`, `rows`, `columns` or `fragments` - all four
  must be added to the model (or the raw JSON read directly) before a sprite can be located and tiled.
- Storyboard formats do **not** pollute the format-selection UI: `FormatPage.kt:459-471` keeps only
  `vcodec != none && acodec == none` (video-only), `acodec != none && vcodec == none` (audio-only) and
  both-non-none (muxed); a storyboard (`none`/`none`) matches none of them.
- Caution: `Format.isAudioOnly()` returns true for a storyboard (`vcodec == "none"`,
  `util/VideoInfo.kt:120`), so `download/Task.kt:162-163` and `download/TaskFactory.kt:39-41` count
  storyboards as audio-only formats. Any new code that reasons about "audio-only" must exclude
  `format_note == "storyboard"` / `ext == "mhtml"` explicitly.
- Existing thumbnail flags (unchanged by this ticket): `--write-thumbnail` + `--convert-thumbnails png`
  when the `createThumbnail` preference is on (`DownloadUtil.kt:1277-1280`, preference key
  `THUMBNAIL = "create_thumbnail"` at `PreferenceUtil.kt:36`, read at `:531`, absent from
  `BooleanPreferenceDefaults` so it defaults to `false` at `:325-326`); `--embed-thumbnail` for audio
  (`:897`, `:1028-1029` with `--convert-thumbnails jpg`).
- Nothing in `app/src/main/java` mentions `storyboard`, `mhtml` or `sprite` today (grep, no matches).
  So the app neither requests nor consumes storyboards at present.
- The effective yt-dlp version can differ from the bundled 2025.11.12: the library auto-updates from
  yt-dlp's own release API (`UpdateUtil.updateYtDlp` -> `YoutubeDL.updateYoutubeDL`,
  `UpdateUtil.kt:64-87`; channels at `libsrc/.../YoutubeDL.kt:289-294`). Both that shipped build and
  current master lack frame export, so the finding is version-stable.

## 5. Turning a sprite into frames: geometry, ordering, trimmed tail

Not slice A's deliverable (splitting is B/C), but these facts decide whether yt-dlp's asset is usable,
so they were measured:

- **Observed** tiles are laid out **row-major** and tile *i* is the video frame at
  `t = i * duration / frame_count`, with `frame_count = fps * duration`. Verified numerically: for sb2
  (80x45 tiles, 108 frames, 1.9722 s apart) I downloaded a 25 s segment of the video and compared with
  PSNR against sprite crops - tile (0,0) vs video t=0 s: **46.5 dB**; tile (0,45) (= row-major frame 10)
  vs t=19.72 s: **16.07 dB**; tile (80,0) (= column-major reading of frame 10) vs t=19.72 s: **10.74 dB**;
  tile (0,45) vs t=1.97 s: **11.74 dB**. Row-major wins decisively.
- **Observed** the **last sprite is trimmed to the bounding box of the frames it carries** - it is not
  padded to `columns x rows`: sb1's last sprite is 800x180 (2 rows of 5), sb2's last sprite is 640x45
  (8 tiles in one row = the 8 remaining frames), sb3's single sprite is a full 480x270 (100 frames).
  Consequence for the app: clamp to `frame_count` (or to the sprite's pixel bounds) instead of assuming
  `rows*columns` tiles in every sprite.
- **Observed** frame size = `width x height` from the JSON; sprite size = `width*columns x
  height*rows` for full sprites (sb0: 320x3 x 180x3 = 960x540 for all 12 sprites; sb3: 48x10 x 27x10 =
  480x270).

## Related observations (useful to the sibling slices)

- The sprite CDN returns **WebP regardless of the URL suffix** (`.jpg` URLs, `content-type: image/webp`,
  both with the default curl UA and with `Accept: image/jpeg`). **Observed**: ffprobe reports the sb2
  sprite as `webp,800,450,yuv420p`.
- **Observed trap**: because that sprite decodes as yuv420p, `ffmpeg -vf crop=80:45:0:45` silently
  returned an 80x44 image; `format=rgb24` before `crop` is required for exact tiles. (Shared with
  sibling B; irrelevant to Android bitmap cropping, which works on decoded pixels.)
- The AAR ships yt-dlp as `res/raw/ytdlp`, a zip with **23 extra leading bytes** (unzip reports them);
  `yt_dlp/version.py` inside it says 2025.11.12 [bundled-version, observed].

## Sources

| Key | Source | What it establishes |
|---|---|---|
| [bundled-version] | `https://repo1.maven.org/maven2/io/github/junkfood02/youtubedl-android/library/0.18.1/library-0.18.1.aar` -> `res/raw/ytdlp` -> `yt_dlp/version.py` | Shipped yt-dlp is `__version__ = '2025.11.12'`, `RELEASE_GIT_HEAD = 335653be82d5ef999cfc2879d005397402eebec1`. That revision is the code the app runs (unless auto-updated). |
| [aar-listing] | same AAR, archive listing | Ships `res/raw/ytdlp` (3,170,726 B), `jni/*/libpython.zip.so`, `jni/*/libqjs.so`, `jni/*/libpython.so`. |
| [yt-master] | `https://raw.githubusercontent.com/yt-dlp/yt-dlp/master/yt_dlp/...` (YoutubeDL.py, extractor/youtube/_video.py, extractor/common.py, extractor/twitch.py, extractor/francetv.py, extractor/mediasite.py, extractor/panopto.py, downloader/mhtml.py, downloader/__init__.py, postprocessor/ffmpeg.py, postprocessor/exec.py, __init__.py, utils/_utils.py, README.md) | Storyboards are formats with `ext/protocol mhtml`; `_write_thumbnails` covers `thumbnails` only; `MhtmlFD` writes one MIME container; no storyboard-splitting postprocessor; plugin system and thumbnails-only plugin list. |
| [bundled-src] | the same files extracted from `res/raw/ytdlp` inside the shipped AAR | Identical storyboard handling at the shipped revision (`YoutubeDL.py:626`, `:2580`, `:4453-4479`; `_video.py:3768`, `:4163`). |
| [FR2048] | `https://github.com/yt-dlp/yt-dlp/issues/2048` | Open FR "Add option to download youtube storyboard as jpg" (labels core:post-processor, enhancement, site:youtube). No implementation. |
| [FR11386] | `https://github.com/yt-dlp/yt-dlp/issues/11386` | Open FR "Convert slides/storyboards to video"; notes the mhtml representation blocks stitching; mentions per-fragment start/end/duration as the usable data. |
| [wiki-plugins] | `https://github.com/yt-dlp/yt-dlp/wiki/Plugins` | Official list of known extractor/postprocessor plugins; none handles storyboards. |
| [sealplus-app] | `/mnt/2tb-ext4/Sealplus` (read-only): `gradle/libs.versions.toml:34,106-108`, `util/DownloadUtil.kt:278,368,897,1277-1280`, `util/ThumbnailUtil.kt:56-95`, `util/VideoInfo.kt:13,100-126`, `util/PreferenceUtil.kt:36,325-326,531`, `util/UpdateUtil.kt:64-87`, `ui/page/downloadv2/configure/FormatPage.kt:459-471`, `download/Task.kt:162-163`, `download/TaskFactory.kt:39-41` | App pins youtubedl-android 0.18.1; already dumps single JSON (so storyboard formats reach the app); already does direct OkHttp image fetches from i.ytimg.com; requests thumbnails only via `--write-thumbnail`/`--embed-thumbnail`; no storyboard handling; `create_thumbnail` default false. |
| [libsrc] | `https://repo1.maven.org/maven2/io/github/junkfood02/youtubedl-android/library/0.18.1/library-0.18.1-sources.jar` -> `YoutubeDL.kt`, `YoutubeDLUpdater` | `updateYoutubeDL` fetches yt-dlp releases from GitHub (stable/nightly/master), so the runtime yt-dlp can be newer than the bundled one. |
| [run-shipped] | Local run of the shipped 2025.11.12 code (`python3` + extracted zip) plus the distro yt-dlp 2026.08.19 for cross-checks | All "observed" statements: JSON keys, `--list-thumbnails` output, `-f sbN`/`-f mhtml` file naming and sizes, mhtml structure, `--write-all-thumbnails` naming, PSNR tile-order test, plain-curl sprite fetch. |

## Unknowns

1. **Storyboard URL lifetime.** The `fragments[].url` values carry `sqp`/`sigh` query parameters. I did
   not test whether they expire or are bound to IP/session. They behaved as plain unauthenticated CDN
   URLs in one session. [INFERENCE] They are likely as stable as `i.ytimg.com` stills (the app's
   `ThumbnailUtil` already relies on that), but this is unverified.
2. **Non-YouTube sprite behaviour.** twitch/francetv/mediasite/panopto/DASH-image storyboards were
   established by reading extractor source only; I did not fetch a live sprite from any of them, so
   tile ordering and "last sprite trimmed" are confirmed for YouTube alone. Do not assume the trimming
   rule for other sites; clamp by `frame_count` from `fps * duration`, which is site-agnostic.
3. **Coverage per video on YouTube.** Which client/player response supplies `storyboards` was not
   swept (e.g. live streams, age-gated videos, `--extractor-args player_client=...` variations). At
   least one YouTube video (`BaW_jenozKc`) failed extraction entirely in this environment, so
   "every YouTube video has sb0-sb3" is not proven; the app must handle "no mhtml format".
4. **Frame count rounding.** `frame_count = fps * duration` is exact in the two videos inspected, but
   if a future extractor reports a rounded `fps`, the last-tile index could be off by one; clamping
   against the last sprite's pixel dimensions is the safe secondary signal.
5. **Whether a plugin-based splitter exists in the wild.** GitHub code search for such a plugin was
   unavailable (503) and web search engines were blocked during this session; only the official wiki
   plugin list was checked. A third-party plugin may exist unlisted.
6. **`--write-thumbnail` on a storyboard is not a documented contract.** I observed that it writes the
   ordinary video still while a storyboard format is selected; nothing in the docs promises that.
