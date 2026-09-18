# Ticket #4 — desktop probe evidence (YouTube embed in a Chromium-family browser)

Probe run 2026-09-18 on the NIXPC host (x86_64 Linux, no display), driving Brave 1.94
(bundled Chromium 153) over CDP from an agent session. This is **not** an Android WebView
and **not** a device. Everything below is marked with how it was obtained.

Harness: `/tmp/ytprobe/index.html` (also published as a scratch gist
`cernoh/02ed4050d3b79577ef887a8566f7d7e4`), loaded through `https://gist.githack.com/...`
so the page has a public HTTPS origin. The harness uses `https://www.youtube.com/iframe_api`,
creates a player, and samples `getCurrentTime()` / `getPlayerState()` every 500 ms.

Video used: `dQw4w9WgXcQ` (Rick Astley — Never Gonna Give You Up). Embeddable: the
`/oembed` endpoint returns HTTP 200 with title metadata from this host.

## 1. Origin and referrer gate — observed

| Parent page origin | Player result |
|---|---|
| `https://gist.githack.com` (public HTTPS) | plays; `duration = 214` |
| `http://127.0.0.1:8791` (loopback HTTP) | `onError 150` at load, `getDuration() = 0`, state never leaves `-1` |
| direct navigation to `https://www.youtube.com/embed/<id>` (top level, no referrer) | page renders its own message: **"Video player configuration error. Error 153"** |

Same browser, same video, same playerVars. The discriminator is the parent page's
origin/referrer, not automation: the automated browser plays the embed from a public HTTPS
origin. Adding `widget_referrer=https://example.com` to a loopback-HTTP parent did **not**
lift the refusal (still `onError 150`).

Nonexistent video IDs (`aaaaaaaaaaa`, `zz1zz2zz3zz`) also return `onError 150` from the
loopback origin — so in that environment `150` is a blanket environment refusal, not a
per-video verdict. **Error-code -> refusal-class mapping could not be established by
observation here.**

Consequence to verify on-device: the app's local asset origin
(`https://appassets.androidplatform.net` via `WebViewAssetLoader`, or any `file://`/`data:`
page) is not a public domain. Whether YouTube's gate accepts it is **unknown**, and it is
the single most load-bearing open question for the preview design (see ticket #20).

## 2. `start` and `end` — observed

- `start=30` on the initial iframe URL: honoured. First playback sample after buffering is
  `30.0`; the player reports state `-1` at `30` while buffering, then `1` at `30.2`.
- `end=40` on the initial iframe URL: honoured. Playback ran `30.7 ... 39.2` and left
  state `1` at `40` (`0@40`, state `0` = ENDED).
- `getDuration()` returns the **full video length** (`213.061` / `214`), never the clip
  length. A range UI must compute `end - start` itself.
- `end` is not re-applied by a forward seek: after `seekTo(100, true)` on a player loaded
  with `end=40`, playback continued `100.1 ... 108.2` with no stop. A seek that lands
  *before* `end` is still bounded: after `seekTo(30)` on an `end=40` player, playback
  stopped at `40` again.

## 3. Updating the range without reloading the page — observed

`loadVideoById` replaces the loaded media; it does not re-aim the current one.

- `player.loadVideoById({videoId, startSeconds: 120, endSeconds: 130})` — accepted. State
  sequence `2 -> -1 -> 3 -> -1@120 -> 1@120.1`; playback stopped exactly at `130`
  (state `0`). Call to playing: **0.6 s** in this run.
- `player.loadVideoById(id, 80, 90)` (positional form) — accepted, restarted at `80`.
  Call to playing: **1.0 s** in the earlier run.
- Cost: a real media reload (unstarted `-1`, buffering `3`), and the visible player
  re-renders. `getDuration()` afterwards is still the full duration.

## 4. `loop` and `playlist` — observed, and they do not do what a clip preview needs

`start=30&end=40&loop=1&playlist=<same id>`:

```
30.0 -> 39.2 (10 s of range playback)
then state -1 at 0.0, buffering, playing from 0.0 -> 12.7 (the whole video)
```

The loop restarts the **playlist item at 0**, ignoring `start`. `loop` + `playlist`
therefore cannot express "loop the range 30-40".

Tight range loop that does work, observed:

```
onStateChange(e) { if (e.data === 0) { e.target.seekTo(30, true); e.target.playVideo(); } }
```

`end=40`, no `loop`/`playlist`. Timeline: `39.2 -> 0@40 -> seekTo(30) -> 1@30.0 ->
... -> 0@40` again. The seam is about **0.1 s** (state `0` at 11.8 s wall, state `1` at
11.9 s wall), with no media reload. Confirmed over two cycles.

## 5. Chrome the player carries, and refusals

`embed-range-playing.webp` (same directory) shows the player sitting at `0:40 / 3:34` after
the range end: full YouTube chrome is present — title overlay, channel avatar, captions,
settings, fullscreen, a "More videos" card and the YouTube logo. The app does not control
that chrome beyond the documented playerVars.

Refusal reporting surface, observed: `onError(event.data)` with a numeric code, while
`getDuration()` stays `0` and the state never leaves `-1`. Nothing else in the API
(no `getVideoData` error field) reported the reason. The rendered message for the
no-referrer case was YouTube's own "Error 153" panel inside the embed.

## 6. The app's injected shim — observed, no interference

The exact `ANTI_DETECTION_SCRIPT` was extracted from
`ui/page/settings/network/WebViewPage.kt` and placed in the page's `<head>` before the
`iframe_api` script, with `window.chrome` forced to `null` first so the shim takes its
WebView branch. Verified live in the page: `window.chrome.runtime.connect` is a function,
`navigator.webdriver` is `false`, and `navigator.userAgentData.brands` reads
`Not/A)Brand 8 / Chromium 136 / Google Chrome 136` (rewritten by the shim).

Range playback in that state: identical to the unshimmed run. `start=30` honoured,
playback `30.3 ... 39.3`, state `0` at `40`, no `onError`, `getDuration() = 214`.
The shim does not interfere with the embedded player in this environment.

## Not verified here

- Any Android WebView behaviour. No JDK, no SDK, no emulator: the WebView settings that
  matter (`mediaPlaybackRequiresUserGesture` after `setUserMediaPlaybackRequiresUserGesture`,
  hardware acceleration, `WebViewAssetLoader` origin acceptance) are unprobed.
- Error-code mapping for embedding-disabled / age-restricted / region-locked videos. No
  such video was found: 85 candidate IDs scanned through `/oembed` all returned 200.
  `/oembed` returns 401 for a non-embeddable video, so the oracle works; the samples were
  all embeddable.
- `rel=0` effectiveness (the "More videos" card was visible in a run that did not set it).
- Whether the shim's `navigator.userAgentData` rewrite lands the same way on a real WebView,
  and whether YouTube reacts to the rewritten brands differently there.