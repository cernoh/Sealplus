# Ticket 04 — What a YouTube embed in the app's existing WebView can actually do

Scope: decisions only, no code changes. Evidence classes are labelled on every claim:

- `[doc]` verified against primary documentation (URL given).
- `[observed]` a probe I ran; the exact probe is stated.
- `[parent]` a probe the parent session ran and reported to me over IRC; not re-run here.
- `[inference]` conclusion I derived, no direct source.
- Anything about **Android runtime behaviour** is marked `unverified-on-Android`.

## Evidence environment and its gap

- Repo facts read from the working checkout: `app/src/main/java/com/junkfood/seal/ui/page/settings/network/WebViewPage.kt` (613 lines),
  `app/build.gradle.kts`, `app/src/main/AndroidManifest.xml`, `app/src/main/java/com/junkfood/seal/util/DownloadUtil.kt`.
- Host has no JDK, no Android SDK, no emulator, no device. **No Android WebView behaviour was exercised.**
- Runtime probes were run on **desktop Brave `Chrome/152.0.7977.83`** on Linux x64, driven over the Chrome DevTools Protocol.
  Braver/Chromium is *not* Android WebView: engine policy details (autoplay gate wiring, hardware-accelerated video, Referer
  handling in WebView) may differ and are marked accordingly.
- Probing YouTube with plain `curl` from this host is treated as a robot: the fetched embed page shell carried
  `"DEVICE":"cbrand=robot&ceng=USER_DEFINED&cmodel=bot+or+crawler&cplatform=DESKTOP"`, and an InnerTube
  `WEB_EMBEDDED_PLAYER` request with no `Referer` returned
  `"errorCode":"PLAYABILITY_ERROR_CODE_EMBEDDER_IDENTITY_DENIED"`, `reason:"This video is unavailable"`,
  subreason `"Error code: 152 - 18"` `[observed]`. That probe denies **every** video without identity — including the embeddable
  control `dQw4w9WgXcQ` — so it is used here only as evidence that an identity/bot refusal of this shape exists, never to
  classify a per-video refusal. Server-side facts therefore come from docs plus a real browser, never from curl HTML.
- Probe harness for the playback observations (reusable): a local page served by `Bun.serve` on `http://127.0.0.1:8080/` that creates the
  player with the IFrame API; a headless Brave launched with `--remote-debugging-port=9222`; the target given
  `Network.setExtraHTTPHeaders {Referer: "https://com.maheshtechnicals.sealplus/"}`; player state sampled every 400 ms;
  `start`/`end` supplied as iframe player vars (identical to iframe URL params). Screenshots via `Page.captureScreenshot`.

---

## 1. `start`, `end`, loop, and the API signatures

### 1.1 Which iframe/playerVars parameters exist, are deprecated, or are honoured by the embedded player

Per the "YouTube Embedded Players and Player Parameters" page `[doc]`
<https://developers.google.com/youtube/player_parameters> (fetched 2026-09-18; the page body was last updated 2026-09-15):

| Parameter | Status in the embedded player |
|---|---|
| `start` | supported. Seconds from the start of the video, positive integer. "similar to the `seekTo` function, the player will look for the closest keyframe to the time you specify… sometimes the play head may seek to just before the requested time, usually no more than around two seconds" |
| `end` | supported. "the time, measured in seconds from the start of the video, when the player should stop playing the video. The parameter value is a positive integer. Note that the time is measured from the beginning of the video and not from either the value of the `start` player parameter or the `startSeconds` parameter" |
| `loop` | supported with a caveat: "**Note:** This parameter has limited support in IFrame embeds. To loop a single video, set the `loop` parameter value to `1` and set the `playlist` parameter value to the same video ID already specified in the Player API URL" |
| `playlist` | supported. "comma-separated list of video IDs to play. If you specify a value, the first video that plays will be the `VIDEO_ID` specified in the URL path, and the videos specified in the `playlist` parameter will play thereafter" |
| `autoplay` | supported. Default `0`. "If you enable Autoplay, playback will occur without any user interaction with the player" |
| `enablejsapi` | supported. Default `0`; "Setting the parameter's value to `1` enables the player to be controlled via IFrame Player API calls" |
| `origin` | supported, "only supported for IFrame embeds"; "you should always specify your domain as the `origin` parameter value" when `enablejsapi=1` |
| `playsinline` | supported **for iOS only**: "controls whether videos play inline or fullscreen on iOS… for `WebViews` created with the `allowsInlineMediaPlayback` property set to `YES`" (an iOS `WKWebViewConfiguration` property). No documented effect on Android `WebView` |
| `rel` | changed 2018-09-25: "you will not be able to disable related videos. Instead, if the `rel` parameter is set to `0`, related videos will come from the same channel" |
| `controls` | supported: `0` none, `1` (default) shown; the value `2` was deprecated 2017-09-15 |
| `cc_load_policy`, `cc_lang_pref`, `color`, `disablekb`, `fs`, `hl`, `iv_load_policy`, `list`, `listType`, `widget_referrer` | supported as documented. `listType=search` deprecated 2020-10-13 (4xx after 2020-11-15) |
| `modestbranding` | **deprecated, no effect** (announcement 2023-08-15) |
| `autohide`, `theme`, `showinfo` | deprecated/removed; no longer appear in the parameter table |
| `mute` | **not documented on that page at all**. Every documented parameter was checked; only the keyboard-shortcut text mentions mute (`[m]: Mute or unmute the video`). `mute=1` is community practice `[doc: absence]`, and it *was honoured* in my probe (`player.isMuted()` returned `true`) `[observed]`. Do not build the design on an undocumented parameter |

The Android entry point for the same list is the WebView URL itself; the parameters are identical because the player is the same page.

### 1.2 `end` on first load

- Documentation: "the player should stop playing the video" `[doc]` (player_parameters, `end`).
- Observed `[observed]`: iframe vars `start=30&end=40&autoplay=1&mute=1&enablejsapi=1`, valid Referer:
  playback began at `currentTime` 30.48, and at 40.01 the player reported `onStateChange` `data = 0` (**ended**) and held 40.01
  for the rest of a 19-second watch. `PlayerState 0` is "ended" `[doc]`.
- Conclusion: `end` is honoured on the first load, and it reports ENDED (not PAUSED).

### 1.3 The `loop` quirk, and whether a `[start, end]` range can be looped

- Documentation: single-video looping requires **both** `loop=1` **and** `playlist=<the same video id>` `[doc]`.
- Observed `[observed]`: iframe URL
  `https://www.youtube.com/embed/dQw4w9WgXcQ?start=210&end=213&loop=1&playlist=dQw4w9WgXcQ&autoplay=1&mute=1&playsinline=1&enablejsapi=1&origin=…`
  → played 210 → 213.25, then buffered and resumed at **0.09**, continuing past 20 s. The range was **not** looped; the loop
  restarted the whole video from 0.
- Conclusion: with URL parameters, `loop` + `playlist` gives a repeating `[0, end]` interval. `start` is applied to the first
  load only. **A repeating `[start, end]` range cannot be produced by URL parameters** `[inference from the observation]`.
  A range loop must be re-seeked from the app side (see §4).

### 1.4 `loadVideoById` / `cueVideoById` signatures — which accept `endSeconds`

From the IFrame API reference `[doc]` <https://developers.google.com/youtube/iframe_api_reference> (fetched 2026-09-18;
page last updated 2026-09-15). The document states the rule directly: "Note that the object syntax supports the `endSeconds`
property, which the argument syntax does not support."

- `player.loadVideoById(videoId:String, startSeconds:Number):Void` — argument syntax, **no** `endSeconds`.
- `player.loadVideoById({videoId:String, startSeconds:Number, endSeconds:Number}):Void` — object syntax, **yes**.
  "If it is specified, then the video will stop playing at the specified time."
- `player.cueVideoById({videoId, startSeconds, endSeconds})` — object syntax only for `endSeconds`; argument syntax is
  `cueVideoById(videoId, startSeconds)`. Cue "loads the specified video's thumbnail and prepares the player to play the video.
  The player does not request the video until `playVideo()` or `seekTo()` is called" and broadcasts state `5` (cued).
- Documented caveat that matters for a trimmer: for `cueVideoById` **and** `cueVideoByUrl`, "If you specify an `endSeconds`
  value and then call `seekTo()`, the `endSeconds` value will no longer be in effect." The same sentence is **not** attached to
  `loadVideoById`.
- Observed `[observed]`: `loadVideoById({videoId:'dQw4w9WgXcQ', startSeconds:60, endSeconds:63})` played from 60 and fired
  `state 0` at exactly 63.00, holding there. So the object-syntax end is enforced on Android-agnostic player code the same way
  the URL `end` is.
- Live cost of that call, same probe: `loadVideoById` call → `state 1` (playing) took **≈1.09 s**, with `state 2 → -1 → 3`
  transitions in between (a re-load of the video stream, not a seek) `[observed]`.

### 1.5 Is `end` still honoured after the viewer seeks forward past it?

- Documentation is **silent** for the URL `end` parameter. The only related documented sentence is the `seekTo` caveat on
  `cueVideoById`/`cueVideoByUrl` quoted above `[doc]`.
- Observed `[observed]`: after `end=40` had already stopped the video at 40.01, `player.seekTo(100, true)` resumed playback and
  `currentTime` kept climbing (102.6 → 108.6 over 6 s). The end boundary was **not** re-applied.
- Observed after an object-syntax load: `loadVideoById({startSeconds:60, endSeconds:63})` stopped at 63, then
  `seekTo(120, true)` played on past 63 (124.7 → 126.8 over 5 s) `[observed]`.
- Attempted UI test (the literal question — a user dragging the embed's own scrubber): a CDP
  `Input.dispatchMouseEvent` click at (500, 342) inside a 640×360 embed that was sitting in the ended state produced **no**
  state change and no new samples; the click did not register on the progress bar `[observed: failed probe]`. Treat the
  UI-scrubber case as **unverified**.
- Conclusion: the API seek result is that an `end` boundary set once is consumed by a forward seek. Whether the embed's own
  scrubber behaves identically is **inference from the API result plus the documented `seekTo` caveat**, not directly observed.

**Confidence (1):** verified-by-primary-doc for the parameter inventory, the `end`/`start`/`loop` definitions and the API
signatures; observed for `end` on first load, the loop restart point, object-syntax `endSeconds`, seek-past-end and the reload
latency — all observed on desktop Chromium 152, **unverified-on-Android**.

---

## 2. WebView configuration on modern Android, and what the existing page already does

### 2.1 What the repo actually sets today (read from the file, not from memory)

`WebViewPage.kt` (`app/src/main/java/com/junkfood/seal/ui/page/settings/network/WebViewPage.kt`):

| Line | Setting |
|---|---|
| 350–367 | `settings.run { … }`: `javaScriptEnabled = true`, `domStorageEnabled = true`, `databaseEnabled = true`, `setSupportMultipleWindows(true)`, `loadWithOverviewMode = true`, `useWideViewPort = true`, `cacheMode = LOAD_DEFAULT`, `mixedContentMode = MIXED_CONTENT_COMPATIBILITY_MODE`, `allowFileAccess = false`, `allowContentAccess = true`, `setSupportZoom(true)`, `builtInZoomControls = true`, `displayZoomControls = false`, `blockNetworkImage = false`, `loadsImagesAutomatically = true`, `javaScriptCanOpenWindowsAutomatically = true`, **`mediaPlaybackRequiresUserGesture = false`** (line 367) |
| 370–372 | UA string with `\swv\b` stripped, set with `setUserAgentString` and mirrored into `USER_AGENT_STRING` |
| 390–432 | `WebSettingsCompat.setUserAgentMetadata()` rebuilds `UserAgentMetadata` with the `Android WebView` brand replaced by `Google Chrome`, guarded by `WebViewFeature.USER_AGENT_METADATA` |
| 435–436 | `cookieManager.setAcceptCookie(true)`; `cookieManager.setAcceptThirdPartyCookies(this, true)` |
| 438–500 | `WebViewClient`: `onPageStarted` (evaluateJavascript fallback), `onPageFinished` (+ `cookieManager.flush()`), `shouldOverrideUrlLoading` (only `http`/`https` stay in the view; other schemes go to an external `Intent`), `onReceivedError`, `onReceivedSslError` (cancels) |
| 505–570 | `WebChromeClient`: `onReceivedTitle`, `onProgressChanged`, `onPermissionRequest` → `request.deny()`, `onCreateWindow` → captures the popup URL into the main WebView and destroys the helper |
| 578–580 | `WebViewCompat.addDocumentStartJavaScript(this, ANTI_DETECTION_SCRIPT, setOf("*"))` guarded by `WebViewFeature.DOCUMENT_START_SCRIPT` |
| 587 | `loadUrl(websiteUrl)` — the single-argument overload, **no** additional HTTP headers |
| — | no `addJavascriptInterface`, no `WebViewCompat.addWebMessageListener`, no `shouldInterceptRequest`, no `WebViewAssetLoader`, no `onShowCustomView`/`onHideCustomView` (confirmed by search over `app/src/main`) |

Build facts: `compileSdk = 37`, `minSdk = 24`, `targetSdk = 37`, `applicationId = "com.maheshtechnicals.sealplus"`
(`app/build.gradle.kts:27,45–47`); dependency `androidx.webkit:webkit:1.16.0` (line 184).
`app/src/main/AndroidManifest.xml` contains **no** `android:hardwareAccelerated` attribute (search returned no match).

### 2.2 Hardware acceleration

- `[doc]` "Hardware acceleration is enabled by default." <https://developer.android.com/topic/performance/hardware-accel>.
- `[doc]` `<application android:hardwareAccelerated>`: "The default value is `"true"` if you set either `minSdkVersion` or
  `targetSdkVersion` to `"14"` or higher. Otherwise, it's `"false"`"
  <https://developer.android.com/guide/topics/manifest/application-element>.
- Therefore this app already runs hardware accelerated (minSdk 24 / targetSdk 37, attribute absent) `[inference from the two docs plus the manifest read]`.
- Compose detail that matters if the preview is hosted in Compose: "In Compose, there is no per-composable switch to disable
  hardware acceleration"; forcing software rendering requires hosting a legacy View and `setLayerType(View.LAYER_TYPE_SOFTWARE, null)`
  `[doc]` (same hardware-acceleration page). Do not force software rendering under the video view.

### 2.3 The autoplay gate: WebView's gate vs Chrome's policy

- `[doc]` `WebSettings.setMediaPlaybackRequiresUserGesture(boolean)`: "Sets whether the WebView requires a user gesture to play
  media. The default is `true`." (API 17+)
  <https://developer.android.com/reference/android/webkit/WebSettings#setMediaPlaybackRequiresUserGesture(boolean)>.
  The app sets it to `false` (line 367), so WebView's own gate is already lifted for this WebView instance.
- `[doc]` Chrome's autoplay policy: "Muted autoplay is always allowed. Autoplay with sound is allowed if: the user has interacted
  with the domain…; on desktop, the user's Media Engagement Index threshold has been crossed; the user has added the site to
  their home screen…"; and "Top frames can delegate autoplay permission to their iframes"
  <https://developer.chrome.com/blog/autoplay/>.
- `[doc]` The IFrame API exposes exactly this failure: `onAutoplayBlocked` "fires any time the browser blocks autoplay or scripted
  video playback features… This includes playback attempted with… `autoplay` parameter, `loadPlaylist`, `loadVideoById`,
  `loadVideoByUrl`, `playVideo`" <https://developers.google.com/youtube/iframe_api_reference>.
- `[observed]` Desktop Chromium 152, page with no user activation:
  - `autoplay=1&mute=1` → playback started, `isMuted()` `true`, no `onAutoplayBlocked`.
  - `autoplay=1` **without** `mute` → `onAutoplayBlocked` fired immediately after `onReady`, player stayed in state `-1`
    (unstarted), no playback.
- `[inference]` `mediaPlaybackRequiresUserGesture=false` removes *WebView's* gesture requirement; it does not by itself promise
  that the YouTube player will play unmuted without a user gesture, because the player additionally meets the Blink autoplay
  policy and reports `onAutoplayBlocked`. Community reports of exactly this split (muted autoplay works, unmuted needs a tap)
  are secondary evidence: Stack Overflow "YouTube Autoplay does not work with iFrame" (mute=1 or the `allow="autoplay"` iframe
  attribute is the fix) <https://stackoverflow.com/questions/40685142>, and the Flutter issue asking for
  `mediaPlaybackRequiresUserGesture` to be exposed as a JS-settable property
  <https://github.com/flutter/flutter/issues> (secondary, cited for the behaviour split only).
- Practical rule for the editor: **preview autoplay must be muted, or it must follow a tap.** Marked `unverified-on-Android`.

### 2.4 What is missing for a YouTube embed in this app

1. **Embedder identity (`Referer`)** — the biggest gap `[doc]`.
   - `[doc]` "API Clients that use the YouTube embedded player (including the YouTube IFrame Player API) must provide
     identification through the `HTTP Referer` request header", and for a mobile app without a local HTML file:
     "You set the `Referer` by adding it as an HTTP Header: Android `loadUrl` with the `Referer` HTTP Header added to the
     `additionalHttpHeaders` parameter" — <https://developers.google.com/youtube/terms/required-minimum-functionality>
     (§ API Client Identity and Credentials). The Referer must be `HTTPS` and use the app ID: "the domain name must be your
     application identifier ("app ID")… a reversed domain name", e.g. `com.google.android.youtube`.
   - `[doc]` YouTube Help: "If this information is missing, viewers attempting to watch embedded YouTube videos will encounter
     blocked playback and an error screen ("error 153")… Note that directly accessing the embedded player without an enclosing
     webpage or context… will typically not have a HTTP Referer"
     <https://support.google.com/youtube/answer/171780>.
   - `[observed]` a `file://` page (origin `file://`, no Referer) that created the player got `onReady`, then
     `onError 153` immediately, with no playback. `[observed]` the same page on `http://127.0.0.1:8813` (origin matched via the
     `origin` playerVar) got `onError 150` for an embeddable video. Only after setting a browser-level
     `Referer: https://com.maheshtechnicals.sealplus/` did playback work.
   - `[observed, parent]` the parent session saw the same ladder: public https plays, loopback http gets `onError 150`,
     no-referrer direct load shows error 153.
   - Therefore `WebViewPage.kt` line 587 `loadUrl(websiteUrl)` (single-argument) cannot host a YouTube embed as written: it
     sends no Referer. The documented fixes are `loadUrl(url, mapOf("Referer" to "https://<applicationId>/"))`, or a local HTML
     file loaded with `loadDataWithBaseURL(…, baseUrl = "https://<app-id>/", …)` `[doc]`. CustomTabs would need
     `Intent.EXTRA_REFERRER` with an `android-app://` scheme `[doc]`.
2. **A real origin for `enablejsapi` postMessage** — a `file://` or `data:` page has an opaque origin, so no `origin` value can
   match it `[inference]`.
   - `[doc]` "As an extra security measure, you should also include the `origin` parameter to the URL, specifying the URL scheme
     … and full domain of your host page"; "While `origin` is optional, including it protects against malicious third-party
     JavaScript being injected into your page and hijacking control of your YouTube player"
     <https://developers.google.com/youtube/iframe_api_reference>.
   - `[doc]` The working route is `WebViewAssetLoader`: "Loading local files using web-like URLs instead of `"file://"` is
     desirable as it is compatible with the Same-Origin policy", default domain constant
     `DEFAULT_DOMAIN = "appassets.androidplatform.net"`, used from `WebViewClient.shouldInterceptRequest`
     <https://developer.android.com/reference/androidx/webkit/WebViewAssetLoader>. The same page repeats the Android guidance to
     keep `setAllowFileAccessFromFileURLs`/`setAllowUniversalAccessFromFileURLs` off and to use the asset loader instead (both
     setters are deprecated since API 30 "This setting is not secure, please use androidx.webkit.WebViewAssetLoader").
   - `[observed]` counter-detail worth knowing: the IFrame API *did* deliver `onReady` and answered `getPlayerState()`,
     `getCurrentTime()`, `isMuted()` from a `file://` page with no `origin` playerVar — so the postMessage handshake is not
     blocked outright by an origin mismatch; that run still could not play anything (error 153). Do not read this as a licence
     to skip `origin`: the docs mandate it, and the app must still provide identity.
3. **A JS bridge to receive player events** — absent.
   - `[doc]` `WebViewCompat.addWebMessageListener(webView, jsObjectName, allowedOriginRules, listener)`: "Adds a
     `WebMessageListener` to the `WebView` and injects a JavaScript object into each frame that the `WebMessageListener` will
     listen on" — with per-origin rules
     <https://developer.android.com/reference/androidx/webkit/WebViewCompat>. The listener's `allowedOriginRules` must include
     the preview page origin **and** `https://www.youtube.com` if the embed frame itself is to post messages.
   - The app currently has no `addJavascriptInterface` and no web-message listener, so today nothing can reach Kotlin. The
     existing `addDocumentStartJavaScript` (line 578) is the natural place to start the player and forward events.
4. **Fullscreen** — absent.
   - `[doc]` `WebChromeClient.onShowCustomView(View, CustomViewCallback)`: "Notify the host application that the current page has
     entered full screen mode", with `onHideCustomView()` for the exit
     <https://developer.android.com/reference/android/webkit/WebChromeClient>. `WebViewPage.kt` overrides neither, so the
     player's fullscreen button (the `fs` parameter defaults to `1`, meaning it is shown) has no handler. Either implement both
     callbacks or set `fs=0` to hide the button `[doc]` (player_parameters).
5. **Player size and overlay policy** `[doc]` <https://developers.google.com/youtube/terms/required-minimum-functionality>:
   players must be at least 200×200 px (recommended 480×270 for 16:9); a screen must not have more than one autoplaying player;
   autoplay must not start until the player is more than half visible; any thumbnail that starts playback must be at least
   120×70 px; "You must not display overlays, frames, or other visual elements in front of any part of a YouTube embedded player,
   including player controls". This constrains the edit sheet's layout (no trim handles or scrub bars drawn over the preview).
6. **WebView type** `[doc]` (same page): "When integrating the YouTube embedded player in a WebView, use one of the OS-provided
   WebView types when available. For example: Android OS: `WebView` or `CustomTabs`." The app's Android `WebView` qualifies.
7. **Open, load-bearing question: will YouTube's gate accept the app's own local origin?** `[observed]` my runs show the gate
   is driven by the parent origin and the Referer: `file://` → `153`, `http://127.0.0.1:8813` with a matching `origin` → `150`,
   and only a plausible non-loopback identity
   (`Referer: https://com.maheshtechnicals.sealplus/`) played `dQw4w9WgXcQ`. `[observed, parent]` the parent reproduced the same
   ladder (public HTTPS parent plays; loopback HTTP parent refuses with `150`; a top-level embed load with no referrer shows
   "Video player configuration error. Error 153") and notes the consequence: `https://appassets.androidplatform.net` and any
   `file://`/`data:` page are not public domains, so whether the gate accepts them is **unknown** and is the single most
   load-bearing question for the preview design. `[doc]` The identity that YouTube's terms require is the **Referer using the
   app ID**, not the page origin, which is why the design must set the Referer explicitly rather than rely on the asset-loader
   origin. `[inference]` Reserve a fallback: if the local origin is refused, the preview must move to a publicly reachable
   origin (the parent's gist-origin trick shows that works) or the range preview must fall back to a non-embed surface.
8. **Android WebView Media Integrity API** `[doc]` (IFrame API reference, section "Android WebView Media Integrity API integration"):
   "YouTube has extended the Android WebView Media Integrity API to enable embedded media players, including YouTube player
   embeds in Android applications, to verify the embedding app's authenticity… embedding apps automatically send an attested
   app ID to YouTube", with an opt-out configuration available
   (`WebViewMediaIntegrityApiStatusConfig`). No action is needed for the trim preview, but the design should not claim that
   playback is anonymous.

**Confidence (2):** verified-by-primary-doc for every Android API and the identity/autoplay/policy requirements;
verified-by-repo-read for what `WebViewPage.kt` sets today; observed for the autoplay-block and identity ladder on desktop
Chromium 152; **unverified-on-Android** for all runtime behaviour (the app was never built or run).

---

## 3. Which videos refuse embedding, how the refusal arrives, and what the embed renders

### 3.1 Documented error codes

From the `onError` table in the IFrame API reference `[doc]`
<https://developers.google.com/youtube/iframe_api_reference>:

| Code | Documented meaning |
|---|---|
| `2` | "The request contains an invalid parameter value. For example, this error occurs if you specify a video ID that does not have 11 characters, or if the video ID contains invalid characters" |
| `5` | "The requested content cannot be played in an HTML5 player or another error related to the HTML5 player has occurred" |
| `100` | "The video requested was not found. This error occurs when a video has been removed (for any reason) or has been marked as private" |
| `101` | "The owner of the requested video does not allow it to be played in embedded players" |
| `150` | "This error is the same as `101`. It's just a `101` error in disguise!" |
| `153` | "The request does not include the `HTTP Referer` header or equivalent API Client identification" (links to the Required Minimum Functionality page) |

The API reference also lists one error screen outside the numeric table: the `onAutoplayBlocked` event, and `subreason` strings
such as `Watch on YouTube`.

### 3.2 Mapping refusal classes to codes — where the docs stop

- **Embedding disabled by the owner** → `101`/`150` `[doc]`. The owner-side control is documented too: "Uncheck the box next to
  'Allow embedding' and SAVE" `[doc]` <https://support.google.com/youtube/answer/171780>. There is no documented code that
  distinguishes "embedding disabled" from "not embeddable for another reason", because `150` is by definition an alias of `101`.
- **Age-restricted** → **no code is documented for this class**. `[doc]` YouTube Help states only: "Age-restricted videos can't
  be watched on most 3rd party websites. These videos will redirect viewers back to YouTube when played"
  <https://support.google.com/youtube/answer/171780>. Google's own help-community answer says the same in stronger words:
  "Even if you are logged in with an eligible account in your browser, playing embedded restricted videos will always require
  the video to be watched directly on YouTube" `[secondary, dated 2026-02-02]`
  <https://support.google.com> (thread "embed age restricted video from YouTube directly").
- **Not found / removed / private** → `100` `[doc]`.
- **Missing Referer / client identity** → `153` `[doc]`, corroborated by community reports of "Error code: 153" inside Android
  WebView and Flutter apps `[secondary]` (Stack Overflow 79761743; a Capacitor/React Native/Flutter write-up on error 150/153).
- **Invalid video ID** → `2` `[doc]`. **HTML5 player failure** → `5` `[doc]`. Region lock has no documented code at all —
  YouTube Help and the API reference never assign one `[doc: absence]`. A region-locked refusal surfaces as the player's own
  "not available in your country" screen; the numeric code for it is **unknown/unverified**.
- `[observed]` Warning against trusting the split: in my probe environment the code for both a **nonexistent** ID
  (`aaaaaaaaaaa`, which the docs map to `100`) and an **age-restricted** ID (`1s5-HEr0UMU`) was **`150`**. So `150` behaves as a
  catch-all "refused" code here. `[observed, parent]` the parent session also recorded `onError 150` for both an
  embedding-disabled video (oEmbed 401) and an age-gated video. Treat 100/101/150 as one "preview unavailable" bucket unless a
  device probe shows otherwise.

### 3.3 What the embedded player renders in each refusal case

Ground truth came from clipped screenshots of the player frame, read back with vision. Each case was a **fresh page load with a
single player** (`http://127.0.0.1:8080/?v=<id>`, one `YT.Player` per page), so the shared `150` code below is the per-video
result of that page, not an artefact of a second player instance on a reused page:

- Nonexistent ID (`aaaaaaaaaaa`), `onError 150` `[observed]`: the frame is a near-black gradient with one centred white line,
  verbatim `This video is unavailable`; **no controls, no thumbnail, no buttons**
  (screenshot `.research/ticket-04-embed-render-missing.png`).
- Age-restricted ID (`1s5-HEr0UMU`), `onError 150` `[observed]`: the frame shows the YouTube logo, the heading
  `Sorry, this content is age-restricted`, the line `This video is age restricted and only available on YouTube`, and two
  buttons, `Watch on YouTube` and `Learn more` (screenshot `.research/ticket-04-embed-render-age-restricted.png`).
  This matches the primer: "These videos will redirect viewers back to YouTube when played" `[doc]`.
- Embedding-disabled: **not observed here** (see §3.5 — I could not source an ID). The parent session reports the
  embedding-disabled case also arrives as `onError 150` `[observed, parent]`. The rendered string is expected to be the
  owner-disabled message with a `Watch on YouTube` action; label that expectation `[inference]` until a device probe captures it.
- Blank rectangle risk: the two refusal screens above arrived ~0.3–0.8 s after `onReady`, not as an indefinitely blank box
  `[observed]`. A design that waits for a timeout before showing its own note should use a short one (2–3 s) and must treat a
  late `onError` as the authoritative signal.

### 3.4 Do the app's cookies make age-restricted or bot-checked videos playable?

- Cookies in this app: `CookieManager.getInstance()` with `setAcceptCookie(true)` and `setAcceptThirdPartyCookies(this, true)`
  (`WebViewPage.kt:435–436`), and the page exists so the user can sign in to sites whose cookies are harvested for yt-dlp.
  `[doc]` `CookieManager.setAcceptThirdPartyCookies(WebView, boolean)`: "Sets whether the WebView should allow third party
  cookies to be set" <https://developer.android.com/reference/android/webkit/CookieManager>.
- `[doc]` YouTube's own statement is that age-restricted content cannot be watched on most third-party sites and redirects to
  YouTube — no cookie exemption is documented. The help-community answer is explicit that being signed in does not help.
- `[observed]` A bot/identity refusal exists in the same family: an InnerTube `WEB_EMBEDDED_PLAYER` request without Referer
  returned `errorCode PLAYABILITY_ERROR_CODE_EMBEDDER_IDENTITY_DENIED` with subreason `Error code: 152 - 18` and the reason
  `This video is unavailable`. This is an *identity* failure, fixable by supplying the Referer `[inference from the doc's 153
  rule and this observation]` — not a cookie failure.
- `[inference]` The app's YouTube cookies cannot be relied on to unlock age-restricted playback inside the embed. What they can
  plausibly affect is third-party-cookie-dependent player behaviour and any signed-in surfaces; no primary source documents a
  cookie path to age-restricted embed playback.
- `[doc]` One documented cookie caveat from the Android side: `CookieManager.getCookie` notes "Any cookies set with the
  `"Partitioned"` attribute will only be returned for the top-level partition of `url`" — relevant if the app ever inspects the
  jar for a partitioned YouTube cookie.

### 3.5 Concrete video IDs for the parent's browser probe

- **Embeddable baseline (control):** `dQw4w9WgXcQ` — `[observed]` played muted 0→end in the probe harness; `yt-dlp 2026.08.19`
  reports `playable_in_embed=True`; oEmbed HTTP 200 `[observed]`.
- **Age-restricted (this class is sourced):** `[observed]` `yt-dlp 2026.08.19` without cookies fails these with
  `ERROR: [youtube] <id>: Sign in to confirm your age`, and `https://www.youtube.com/oembed?...` returns HTTP 200 with the title
  and channel:
  - `1s5-HEr0UMU` — "Maestro Don, Starface, Trizo - TRIO (Official Music Video) [Explicit]", MaestroDonVEVO
  - `410VPUJ8OQ4` — "Julia Volkova - Didn't Wanna Do It (Explicit/Uncensored)", Julia Volkova
  - `kC4drvtPgoQ` — "LIZOT, Holy Molly - Menage A Trois (Official Uncensored Video)", Club Sounds
  - `x4VaEMUgc54` — "Big Grojo - Cocaine [ft. Daivin] (Uncensored Music Video)", 6PAC
  In the probe harness `1s5-HEr0UMU` produced `onError 150` and the age-restricted screen quoted in §3.3 `[observed]`.
  `[observed, parent]` `iLKV0aL4ZQA` and `ZR-5-DyN1sI` are further age-gated samples (watch-page text "Sign in to confirm your
  age", `/oembed` 200, `onError 150`, `getDuration() = 0`).
- **Video not found (this class is sourced):** any obviously invalid 11-character ID, e.g. `aaaaaaaaaaa` `[observed]`
  (`onError 150` + "This video is unavailable"; oEmbed returns HTTP 400 for it).
- **Embedding disabled by the owner: sourced by the parent session, not by me.** `[observed, parent]` `UgvSg_Cws-o`
  ("Final Destination 5") — watch page shows `"playableInEmbed": false` with `"status":"UNPLAYABLE"`, `/oembed` returns
  **HTTP 401 Unauthorized**, and the player returned `onError 150` with `getDuration() = 0` and the state stuck at `-1`.
  The parent's 203-ID scan of YouTube search results found exactly one such video, so the class is rare but real.
  `[observed, parent]` This makes `/oembed` a usable **pre-flight oracle for this class only**: 401 = refuse before mounting the
  player; 200 does **not** mean the video will play (both age-gated samples returned 200 and still refused with `150`).
  `[observed]` My own `yt-dlp 2026.08.19` scan over ~150 videos — 24 top-chart music videos, 40 UFC/audio-corpus hits,
  40 Formula 1 and WWE channel uploads, and 55 UMG/Sony/Warner "Provided to YouTube by …" auto-generated uploads — returned
  `playable_in_embed=True` for every one, which agrees with the parent's "rare but real" rate. The reusable discovery recipe is:

  ```
  yt-dlp --skip-download --print "%(id)s|%(playable_in_embed)s|%(title)s" \
    --match-filter "playable_in_embed=False" <playlist-or-search-url>
  ```
  and cross-check any candidate with `curl -s -o /dev/null -w '%{http_code}\n' \
  "https://www.youtube.com/oembed?url=https%3A//www.youtube.com/watch%3Fv%3D<ID>&format=json"` (401 = not embeddable).
- **Region-locked: I could not source an ID with a justification.** This host has one fixed egress region, so a region lock
  cannot be demonstrated or falsified from here; no primary doc names a region-locked example `[doc: absence]`. To source one,
  probe the same embed from two regions (or with a trust-worthy geo-varying route) and compare the player's own screen text.

**Confidence (3):** verified-by-primary-doc for the error-code table, the owner-side embedding switch and the age-restriction
statement; observed for the codes and the two rendered refusal screens (desktop Chromium 152) and for the video-ID sourcing
probes; secondary for the help-community/Stack Overflow corroboration; **unverified-on-Android**; the embedding-disabled ID is
sourced only from the parent session, and no region-locked ID could be sourced at all.

---

## 4. Updating the range without reloading, and the cost

### 4.1 Documented event surface and method list

`[doc]` <https://developers.google.com/youtube/iframe_api_reference>:

- Events: `onReady` (no `data`); `onStateChange` with `data` ∈ `-1` unstarted, `0` ended, `1` playing, `2` paused,
  `3` buffering, `5` video cued; `onPlaybackQualityChange`; `onPlaybackRateChange`; `onError` (§3.1);
  `onApiChange`; `onAutoplayBlocked`. Handlers are attached in the `YT.Player` constructor or with
  `addEventListener(event, listener)` / `removeEventListener`.
- Methods available for a trim editor: `loadVideoById`, `cueVideoById`, `loadVideoByUrl`, `cueVideoByUrl`, `loadPlaylist`,
  `cuePlaylist`, `playVideo`, `pauseVideo`, `stopVideo`, `seekTo(seconds, allowSeekAhead)`, `mute`, `unMute`, `isMuted`,
  `setVolume`, `getVolume`, `getPlayerState`, `getCurrentTime`, `getDuration`, `getVideoLoadedFraction`, `setLoop`, `setShuffle`,
  `getPlaybackRate`, `setPlaybackRate`, `getAvailablePlaybackRates`, `getVideoUrl`, `getVideoEmbedCode`, `getPlaylist`,
  `getPlaylistIndex`, `setSize`, `getIframe`, `destroy`, `getOptions`/`getOption`/`setOption` (captions module).
- `getCurrentTime` "Returns the elapsed time in seconds since the video started playing" (it is the media position, not a
  wall-clock measure) and `getDuration` returns the full duration (`[observed]`: 213.061 s / 214 s in the probes for a video
  where the range end was 40) — so duration cannot be used to detect a trimmed range.

### 4.2 Changing the end time: reload vs watchdog

- **End time in the player config requires a fresh load.** `loadVideoById({videoId, startSeconds, endSeconds})` is a queueing
  function: it loads and plays the video. `[doc]` `setLoop` in the API reference is documented only for playlists
  ("indicates whether the video player should continuously play a playlist"), and no API method sets a *range* end; the
  documented way to set an end is the `endSeconds` property on a load/cue call, or the `end` URL parameter `[doc]`.
- `[observed]` cost of the reload path: `loadVideoById` call → playing ≈ **1.09 s** (states 2 → -1 → 3 → 1) in my probe;
  the parent session measured ≈0.6–1.1 s. The player re-requests the stream at the new start keyframe; `[doc]` `startSeconds`
  "the video will start from the closest keyframe to the specified time" — expect a sub-2-second visual snap.
- **A JS-side watchdog avoids the reload for repeat playback.** `[observed]` the boundary itself is reported promptly:
  with `end=40` the transition to `state 0` arrived with `currentTime` at 40.01 and my 400 ms sampler had last read 39.6, i.e.
  the API/sampler granularity bounded the overshoot, not the player. Two viable watchdogs, both using documented surface:
  - event-driven: `onStateChange` → if `data === 0` (or `getCurrentTime() >= end`) call `seekTo(startSeconds, true)` then
    `playVideo()`;
  - timer-driven: poll `getCurrentTime()` every ~250–400 ms and stop/loop at the boundary.
  `[observed, parent]` The parent session confirmed this watchdog works and measured its seam: with `end=40` and no
  `loop`/`playlist`, an `onStateChange` handler that re-seeks when `e.data === 0` produced `0@40 → seekTo(30) → 1@30.0 → 0@40`
  with a seam of about **0.1 s** and no media reload, over two cycles.
  `[observed]` `seekTo(120, true)` → playing took **≈0.25 s** on an already-buffered video, so a watchdog re-seek is roughly
  4× cheaper than a reload when the target is buffered. `[doc]` `allowSeekAhead` decides whether the player fetches new data
  when the target lies outside the buffer, so a re-seek to an unbuffered point costs a stream request again.
- `[inference]` Design consequence: hold the range in the preview page; use `loadVideoById({videoId, startSeconds, endSeconds})`
  when the range changes, and a `seekTo` watchdog when the range repeats (loop). Do not fight the URL `loop` parameter for a
  `[start, end]` loop — §1.3 shows it restarts at 0.
- `[observed]` `setLoop(true)` was not exercised against a single video in my probe; the docs describe it as playlist-only, so
  treat "API setLoop loops a single-video range" as unsupported `[inference from the docs]`.

### 4.3 `origin` / `widget_referrer` requirements, and the failure mode

- `[doc]` `origin`: "This parameter provides an extra security measure for the IFrame API and is only supported for IFrame embeds.
  If you are using the IFrame API, which means you are setting the `enablejsapi` parameter value to `1`, you should always
  specify your domain as the `origin` parameter value." The API reference adds the mechanism: the API requires HTML5
  `postMessage`, and warns that without `origin`, injected third-party JavaScript could hijack the player.
- `[doc]` The Required Minimum Functionality page names one environment where `origin` substitutes for the Referer: on iOS
  `SFSafariViewController`, "which does not support setting the `Referer`. In this case, set the `origin` player parameter
  instead." So the two are treated as equivalent identity carriers by YouTube's own documentation.
- `[doc]` `widget_referrer` "identifies the URL where the player is embedded. This value is used in YouTube Analytics reporting"
  — analytics only; it is not an identity or control mechanism.
- Failure mode without a matching origin `[inference + partial observation]`: the player posts control replies to the origin it
  was told about, so a container whose real origin differs may never receive events. My one unmatched-origin run (a `file://`
  page, `origin` omitted) still received `onReady` and answered getters, so "no events at all" is not guaranteed — but that page
  was also refused with error 153, so it produced no playback evidence either way. On Android the clean answer is to host the
  page on `https://appassets.androidplatform.net` through `WebViewAssetLoader` and pass that exact value as `origin`, keeping the
  Referer on `https://<applicationId>/` `[doc]` (both sources cited in §2.4).

**Confidence (4):** verified-by-primary-doc for the event/method surface, the `origin`/`widget_referrer` rules and the
`allowSeekAhead` semantics; observed for reload and seek latencies, the boundary timing and the watchdog mechanics (desktop
Chromium 152); **unverified-on-Android**.

---

## 5. Does the app's existing injected JavaScript matter?

The shim is `ANTI_DETECTION_SCRIPT` in `WebViewPage.kt` (lines 83–204, registered as a document-start script on all frames at
lines 578–580 with `setOf("*")`, with an `evaluateJavascript` fallback in `onPageStarted` at lines 451–453). Judged strictly
from its text, item by item:

| Shim part | Verdict | Reason |
|---|---|---|
| `Object.defineProperty(window, 'chrome', {value: chromeDef, …})` inside `if (typeof window.chrome === 'undefined' \|\| window.chrome === null)` | **unknown** | It only installs when `window.chrome` is absent, which is the Android WebView case, so the YouTube embed page will always see a *fake* `chrome` object whose `runtime.connect()` returns stubs and whose `loadTimes()`/`csi()` return zeroed data. Nothing in the shim patches media APIs, so it cannot break playback mechanically; whether YouTube's page code branches on `window.chrome` and takes a path WebView cannot follow is not something I can settle from the shim text alone. |
| `Object.defineProperty(navigator, 'webdriver', {get: () => false, configurable: true})` | **neutral** | It replaces one boolean on `navigator`; the shim text contains no other navigation, media, or messaging interaction, and no source I read ties `navigator.webdriver` to player behaviour. It is a fingerprint inconsistency rather than a functional risk. |
| `navigator.userAgentData.brands` rewrite (and a rebuilt `userAgentData` with hardcoded `architecture:'arm'`, `bitness:'64'`, `platformVersion:'14.0.0'`, `uaFullVersion:'<ver>.0.0.0'`) | **risky** | It *replaces* an existing object rather than filling a gap. YouTube does use client hints; the hardcoded high-entropy values can contradict the native `Sec-CH-UA` metadata that `WebSettingsCompat.setUserAgentMetadata()` writes (line 422), and a mismatch between the header and the JS mirror is exactly the kind of inconsistency anti-bot systems look for. No player API is touched. |
| `navigator.languages` fill (`['en-US','en']` when the array is empty) | **neutral** | Only fires on an empty array; it influences caption/UI language selection, nothing in the playback path. |
| Whole-script structure: one IIFE, everything inside `try/catch`, no `addEventListener`, no `postMessage`, no `HTMLMediaElement` prototypes touched, no DOM access | **neutral, and load-bearing** | There is no mechanism in this text by which the IFrame API's `postMessage` channel or the player's `<video>` element could be altered. It defines one missing global and replaces two values. |
| Registration scope: `setOf("*")` at document start, plus the `onPageStarted` fallback on every navigation | **risky (scope, not content)** | The shim runs inside the YouTube iframe and inside every nested frame of it, not just on the page under test. A preview host that registers the same script inherits the same all-frame injection; a narrower `allowedOriginRules` set for the preview WebView would keep the shim off `youtube.com`. This is a scoping decision the editor can take independently of the shim's content. |
| `[observed, parent]` the parent session reports the app shim caused no interference in its embed probe | **observed elsewhere** | Recorded here as a reported observation, not re-run in my session. |

`[doc]` Supporting detail: `WebViewCompat.addDocumentStartJavaScript(webview, script, allowedOriginRules)` executes "in any frame
whose origin matches `allowedOriginRules` when the document begins to load", and `addWebMessageListener` injects per-frame objects
with the same origin-rule semantics <https://developer.android.com/reference/androidx/webkit/WebViewCompat> — so the rules set is
the lever for any future preview WebView.

**Confidence (5):** inference from the shim's text for every verdict (the shim was not executed against the embed in this
session); verified-by-primary-doc for the injection-scope semantics; the parent's no-interference result is observed-elsewhere.

---

## Minimum WebView setup

The smallest setup that plays an embedded video, honours a `[start, end]` range, loops that range, and surfaces a refusal.

1. **Container**: keep the existing `WebSettings` block as the baseline — `javaScriptEnabled`, `domStorageEnabled`,
   `mediaPlaybackRequiresUserGesture = false` (needed: default is `true` `[doc]`), hardware acceleration on (already the manifest
   default `[doc]`). Add `WebViewClient.shouldInterceptRequest` returning `assetLoader.shouldInterceptRequest(url)` from a
   `WebViewAssetLoader` `[doc]`.
2. **Page origin**: serve the preview page from
   `https://appassets.androidplatform.net/assets/preview/index.html` (`WebViewAssetLoader.DEFAULT_DOMAIN` `[doc]`). This gives a
   real https origin that `origin=` can match and that keeps the Same-Origin policy intact `[doc]`.
3. **Identity**: load the page — or the embed directly — with a Referer header of
   `https://com.maheshtechnicals.sealplus/` via `loadUrl(url, mapOf("Referer" to …))`, or use
   `loadDataWithBaseURL(…, baseUrl = "https://com.maheshtechnicals.sealplus/", …)` `[doc]`
   <https://developers.google.com/youtube/terms/required-minimum-functionality>. Without it the player reports `153`
   `[doc + observed]`.
4. **Player frame**: `https://www.youtube.com/embed/<VIDEO_ID>?enablejsapi=1&origin=https://appassets.androidplatform.net&start=<s>&end=<e>&playsinline=1&rel=0&controls=1&mute=1`, created through the IFrame API (`https://www.youtube.com/iframe_api`, then
   `onYouTubeIframeAPIReady` → `new YT.Player(div, {videoId, playerVars, events})`) `[doc]`. Keep the player ≥ 200×200 px, and
   ≥ ~480×270 `[doc]`.
5. **Range**: `loadVideoById({videoId, startSeconds, endSeconds})` for the initial range (object syntax is the only one that
   accepts `endSeconds` `[doc]`; ≈1 s to playing `[observed]`). Re-apply the range by calling it again when the trim changes;
   do **not** expect `end` to survive a forward seek `[observed]`, and do not expect `setLoop` to loop a single video `[doc]`.
6. **Loop**: run a watchdog in the page — `onStateChange` with `data === 0`, or `getCurrentTime() >= end` on a 250–400 ms poll —
   then `seekTo(startSeconds, true)` + `playVideo()` (≈0.25 s when buffered `[observed]`). URL `loop=1&playlist=<id>` restarts at
   0 and is therefore only usable as `[0, end]` `[observed]`.
7. **Events to the app**: `WebViewCompat.addWebMessageListener(webView, "sealPreview", setOf("https://appassets.androidplatform.net", "https://www.youtube.com"), listener)` `[doc]`; the page script forwards
   `onError`, `onStateChange`, `onReady` and (if needed) `onAutoplayBlocked` to that object. No `addJavascriptInterface` is needed,
   and the app already has the document-start machinery for the page-side half.
8. **Refusal UX**: on `onError` (`100`/`101`/`150`/`153`/`2`/`5`) show the editor's own inline "preview unavailable" note and
   stop waiting — the embed paints its own message inside the frame but the app cannot read it (cross-origin) and cannot style it
   `[inference]`. Distinguish `153` from the rest: it means the identity/Referer is missing and is fixable at the host level
   `[doc]`.
9. **Autoplay**: for an automatic preview, mute (`mute=1` in the URL, or `player.mute()` after `onReady` — the API method is
   documented; the parameter is not `[doc]`). Otherwise require a tap; unmuted autoplay is refused by the browser/player and
   reported through `onAutoplayBlocked` `[doc + observed]`.
10. **Optional fullscreen**: override `onShowCustomView`/`onHideCustomView`, or pass `fs=0` to hide the button `[doc]`.
11. **Do not add overlays over the player** and do not autoplay more than one player on a screen `[doc]` (policy).

**Confidence (Minimum WebView setup):** verified-by-primary-doc for each setting's existence, default and requirement, and for
the identity recipes; observed for the ranges/latencies/loop behaviour on desktop Chromium 152; the composition into one recipe
is inference; **unverified-on-Android** as a whole (never built or run here).

---

## What the editor can rely on / cannot rely on

**Can rely on** (each with its basis):

- `start` and `end` as iframe params, and `endSeconds` in object syntax, bound playback on load: `end` stopped playback at
  exactly the requested second and reported state ENDED `[doc + observed]`.
- `getCurrentTime`, `getPlayerState`, `getDuration`, `seekTo`, `playVideo`/`pauseVideo`, `mute`/`unMute` are all documented and
  all answered correctly in the probe, so the page can implement its own transport and its own range watchdog
  `[doc + observed]`.
- The refusal of a video arrives as a numeric `onError` before or instead of playback (observed within ~1 s of `onReady`), so a
  "preview unavailable" state can be driven by an event, not by a timeout `[doc + observed]`.
- Error `153` specifically means "no Referer / client identity" and has a documented Android fix (`loadUrl` with
  `additionalHttpHeaders`) `[doc]`; my no-Referer run reproduced it `[observed]`.
- Age-restricted content is documented as not playable on most third-party sites and redirects to YouTube — plan for refusal,
  not for a workaround `[doc]`.
- Muted autoplay works; the API's `mute()` is documented, so the preview can start muted and offer an unmute action
  `[doc + observed]`.
- A `[0, end]` loop is available from URL parameters alone (`loop=1&playlist=<id>`) `[doc]`.

**Cannot rely on:**

- A `[start, end]` loop from URL parameters: `loop` restarts at 0, not at `start` `[observed]`. Any range loop needs the
  watchdog (or a full `loadVideoById` reload per iteration, ≈1 s each `[observed]`).
- `end` surviving a forward seek: after `seekTo` past the boundary, playback continued `[observed]`; the UI-scrubber variant was
  not successfully probed `[failed probe]` and is inference.
- Distinct error codes per refusal class: docs give 100/101/150/153, but in practice a missing video and an age-gated video both
  arrived as `150` here `[observed]`, and the parent session saw `150` for both embedding-disabled and age-gated `[observed,
  parent]`. Map 100/101/150 to one "unavailable" state.
- Reading or styling the player's own refusal screen: it lives inside the cross-origin iframe ("This video is unavailable",
  "Sorry, this content is age-restricted" + "Watch on YouTube" were read from pixels, not from the DOM) `[observed]`. The app
  must render its own note.
- The `mute` parameter as a stable contract: it is **not** in the documented parameter table `[doc]`, even though it was honoured
  in the probe `[observed]`. Prefer the documented `player.mute()`.
- Cookies unlocking age-restricted playback: contradicted by YouTube's own help text and the help-community answer `[doc +
  secondary]`; no primary source documents a cookie path.
- Unmuted autoplay without a gesture: `onAutoplayBlocked` fired and playback stayed unstarted `[observed]`; only the muted path
  is safe.
- Whether YouTube's gate accepts the app's own local origin. The gate follows the parent origin/Referer (`file://` → 153,
  loopback http → 150, plausible https identity → plays `[observed]`), and `https://appassets.androidplatform.net` is not a
  public domain, so the asset-loader origin is **unproven** as an embed host `[observed + inference]`. This must be tested on a
  device or against the real network before the preview design is frozen.
- Predicting region locks, or mapping them to a code: no documented code exists for the class `[doc: absence]`, and no
  region-locked ID could be sourced from a single-region host (§3.5).
- `playsinline` doing anything on Android: the parameter is documented for iOS/mobile Safari and iOS WebViews only `[doc]`.
- Any Android runtime claim in this report: the app was never built or run here; the host has no JDK, no Android SDK and no
  device. Everything engine-level is `unverified-on-Android`.

**Confidence (reliance section):** mixed and stated per bullet; the section as a whole is verified-by-primary-doc for the
documented parts and observed-on-desktop-Chromium for the behavioural parts, with all Android runtime claims
unverified-on-Android.
