# Material Symbols glyphs → committed Compose `ImageVector`s

Research ticket: `cernoh/Sealplus#10`. Feeds `cernoh/Sealplus#14` (which glyph replaces which icon) and
`cernoh/Sealplus#12` (the tier migration plan) on map `cernoh/Sealplus#19`.

Date of all measurements: **2026-09-18**. Checkout: `/mnt/2tb-ext4/Sealplus`.

**Method note.** This host has no JDK and no Android SDK, so **no Gradle build, no APK, and no
`javap`/D8 measurement was run**. Every number below is either (a) measured over HTTP, over an
archive, or in a real Chromium page on this host, or (b) read out of a primary source (an upstream
repository, an androidx source file, a published `.pom`/`.aar`/`-sources.jar`, or Google's own
documentation). Numbers are marked **[measured]** or **[estimate]**; reasoning that is neither is
marked `[INFERENCE]`. Reproduction commands are in Appendix C.

Upstream revision pinned for every fetch in this report:
`google/material-design-icons` @ `27e9ef1dbeedc13d682fece4a58e1eda4cb0961a` (default branch
`master`, committer date 2026-09-18T02:14:48Z, [measured] via `gh api repos/google/material-design-icons/commits/master`).

---

## 1. Sources: where the glyphs come from, under what licence, in what format

### 1.1 The upstream repository

**There is no `google/material-symbols` repository.** `gh api repos/google/material-symbols` returns
HTTP 404, and `https://github.com/google/material-symbols` answers 404 (both [measured], 2026-09-18).
Do not cite it.

The canonical home of **both** icon sets is **`google/material-design-icons`**:

- `gh api repos/google/material-design-icons` → `default_branch: master`, `license.spdx_id: Apache-2.0`,
  `description: "Material Design icons by Google (Material Symbols)"`, `archived: false`
  [measured], <https://api.github.com/repos/google/material-design-icons>.
- Repo root listing (GitHub contents API): `.github/`, `.gitignore`, `LICENSE`, `README.md`,
  `android/`, `font/`, `ios/`, `png/`, `src/`, `symbols/`, `update/`, `variablefont/` [measured].
- Upstream `README.md` states: *"Material Symbols is the current set, introduced in April 2022, built
  on variable font technology. Material Icons is the classic set, but no longer updated."* and, of
  Material Symbols, *"although there is no separate Filled font, the Fill axis allows access to filled
  styles, in all three fonts. It can also be manipulated for an animated fill effect, to indicate user
  selection."* It lists the axes as opsz 20–48 (default 24), weight 100–700 (regular 400), grade
  −50…200 (default 0), fill 0…100 (default 0), and notes *"there are no two-tone icons"*
  [measured], <https://raw.githubusercontent.com/google/material-design-icons/master/README.md>.

That last sentence matters for the migration: Material Symbols has **three** shape styles
(outlined, rounded, sharp) × **two** fill states, not the five styles `material-icons-extended` ships.

### 1.2 Licence

- `LICENSE` at the repo root is the **Apache License, Version 2.0** — 11,357 bytes, opening lines
  `Apache License / Version 2.0, January 2004` [measured],
  <https://raw.githubusercontent.com/google/material-design-icons/master/LICENSE>.
  There is **no `NOTICE` file** at the repo root [measured: the root listing in §1.1 contains none].
- Consequence for this app (committing derived vectors is redistribution of the artwork):
  Apache-2.0 §4 requires the licence text to travel with a redistribution, and §4(d) adds the NOTICE
  obligation *only if* the redistributed work includes a NOTICE file — upstream has none, so the
  binding obligation is the licence text plus attribution. The app is licensed GPL-3.0
  (`LICENSE:1-2`), which is compatible with Apache-2.0 [INFERENCE, standard licence compatibility].
- The app **already carries the attribution**: `app/src/main/java/com/junkfood/seal/ui/page/settings/about/CreditsPage.kt:83`
  renders `Credit("Material Icons", APACHE_V2, materialIcon)` where the constant is
  `APACHE_V2 = "Apache License, Version 2.0"` (`CreditsPage.kt:37`) and
  `materialIcon = "https://fonts.google.com/icons"` (`CreditsPage.kt:46`). There is no
  `app/src/main/assets/` directory today [measured: `glob app/src/main/assets/**` finds nothing].
- **Required action for the migration ticket:** keep that credit, and add the repo URL
  (`https://github.com/google/material-design-icons`) so the credit names the actual source of the
  artwork, not only the browsing site. Shipping the Apache-2.0 text in-app is optional under the
  reading above but is the low-risk choice if the project ever wants a clean licence manifest.

### 1.3 Formats available

Three independent routes reach the same artwork; a generator should pick one and record it.

**Route A — the source repository, per glyph, per style, per size, per axis.** Layout is
`symbols/web/<glyph>/materialsymbols<outlined|rounded|sharp>/` (also `symbols/android/` and
`symbols/ios/` with the same subtree shape) [measured]. For `content_cut`, `symbols/web/content_cut/`
contains `materialsymbolsoutlined/`, `materialsymbolsrounded/`, `materialsymbolssharp/`, and the
rounded directory holds a flat set of variants [measured, contents API]:

| file | bytes |
|---|---|
| `content_cut_20px.svg` | 1,012 |
| `content_cut_24px.svg` | 723 |
| `content_cut_40px.svg` | 1,225 |
| `content_cut_48px.svg` | 728 |
| `content_cut_fill1_24px.svg` | 723 |
| `content_cut_grad200_24px.svg` | 973 |
| `content_cut_grad200fill1_24px.svg` | 973 |
| `content_cut_gradN25_24px.svg` | 965 |

So one glyph's path data **is** fetchable per icon — no whole-set download is needed.

**Route B — `variablefont/`**, the whole set per style: nine files,
`MaterialSymbols{Rounded,Outlined,Sharp}[FILL,GRAD,opsz,wght].{codepoints,ttf,woff2}` [measured].
Byte sizes [measured]: codepoints 79,029 each; TTF 15,141,224 (rounded) / 10,678,048 (outlined) /
8,867,868 (sharp); WOFF2 5,374,220 / 3,981,232 / 3,520,256. The `.codepoints` file is the name
dictionary: 4,284 names in the rounded file [measured].

**Route C — the `fonts.gstatic.com` CDN**, one request per glyph per axis slot:
`https://fonts.gstatic.com/s/i/short-term/release/materialsymbolsrounded/<glyph>/<slot>/24px.svg`.
All [measured] today: `content_cut` `default` → 200, 758 B; `content_cut` `fill1` → 200, 758 B
(byte-identical to `default` for this glyph — the parent session measured `favorite` and `star`,
where the two differ, so `default` is *not* a synonym for either fill value in general
`[INFERENCE: the CDN `default` is the FILL=0 instance, as the font's default FILL is 0 per the
README; the identical bytes for `content_cut` follow from its two variants being the same drawing]`).
Slot vocabulary [measured by the parent session]: `default`, `fill1`, `wght100`…`wght700`, `grad200`
→ 200; `fill0`, `opsz24`, and compound slots such as `fill1wght700grad200opsz24` → 404. The CDN sets
no licence header; the obligations come from the Apache-2.0 licence of the content it mirrors.

**Repo payload vs CDN payload differ in serialization.** Both are 24 × 24 SVGs on the same grid, but
the repo file for rounded `content_cut` is 723 bytes, while the CDN serves 758 bytes for the same
glyph [measured]. The difference is *serialization only*, not geometry: the repo file keeps the two
small circles on shared implicit smooth quadratics (`…ZM240-640q33 0 56.5-23.5T320-720q0-33-23.5-56.5…`),
while the CDN expands them into explicit pairs with rounded coordinates
(`…ZM296.5-663.5Q320-687 320-720t-23.5-56.5Q273-800 240-800t-56.5 23.5…`). Neither uses arcs. A
converter must therefore parse both `q/T` and `Q/t` forms, and must not assume one serialization.

**Two grid dialects coexist upstream — this is a real trap** [measured over the 178 glyphs this app
needs]:

- **960-unit grid**: `viewBox="0 -960 960 960"`, `width="24" height="24"`, coordinates in the
  thousands with a negative Y origin — 171 of 178 files.
- **24-unit grid**: no `viewBox` at all, only `width="24" height="24"`, coordinates in 0…24 — 7 of
  178 files: `auto_awesome`, `drive_file_rename_outline`, `file_download`, `generating_tokens`,
  `settings_suggest`, `smart_button`, `tips_and_updates`.

A converter must read `viewBox` and fall back to `width`/`height`. Hard-coding `0 0 24 24` silently
shrinks 171 glyphs to a corner; hard-coding the 960 grid breaks the other 7.

The payload itself is minimal: **one `<path>` element, no `fill`, no `fill-rule`, no `clip-rule`, no
`<g>`, no `<defs>`** in all 178 files [measured]. Colour therefore comes from the tint at render
time, never from the file — which is exactly what `Icon(tint = …)` expects.

Sample payload, rounded `content_cut` (723 B) [measured]:

```svg
<svg xmlns="http://www.w3.org/2000/svg" height="24" viewBox="0 -960 960 960" width="24"><path d="m480-400-94 94q8 15 11 32t3 34q0 66-47 113T240-80q-66 0-113-47T80-240q0-66 47-113t113-47q17 0 34 3t32 11l94-94-94-94q-15 8-32 11t-34 3q-66 0-113-47T80-720q0-66 47-113t113-47q66 0 113 47t47 113q0 17-3 34t-11 32l438 438q27 27 12 61.5T783-120q-11 0-21.5-4.5T743-137L480-400Zm120-120-80-80 223-223q8-8 18.5-12.5T783-840q38 0 52.5 35T823-743L600-520ZM240-640q33 0 56.5-23.5T320-720q0-33-23.5-56.5T240-800q-33 0-56.5 23.5T160-720q0 33 23.5 56.5T240-640Zm240 180q8 0 14-6t6-14q0-8-6-14t-14-6q-8 0-14 6t-6 14q0 8 6 14t14 6ZM240-160q33 0 56.5-23.5T320-240q0-33-23.5-56.5T240-320q-33 0-56.5 23.5T160-240q0 33 23.5 56.5T240-160Z"/></svg>
```

### 1.4 Commands actually present

Command-letter histogram over all 178 needed glyphs (parser output, [measured]): `M` 251, `m` 500,
`L` 151, `l` 700, `H` 305, `h` 527, `V` 3, `v` 779, `Q` 48, `q` 3034, `T` 1908, `t` 1002, `Z` 751.
**No `C`, `S`, or `A` at all in this app's 178 files** [measured] — upstream writes every curve as a
quadratic or reflective quadratic. A *general* converter should still map `C/c`, `S/s` and `A/a`
hand-built SVGs and other icon sets use them (the repo's own `ui/svg/drawablevectors/Download.kt` calls
`arcTo`), but for this glyph set 13 command letters suffice.

---

## 2. Tooling: what turns one glyph into an `ImageVector`

### 2.1 Google's own generator (primary source, in the androidx tree)

Google's generator for the `material-icons-*` artifacts lives at
`compose/material/material/icons/generator/` in `androidx/androidx`
[measured, `gh api repos/androidx/androidx/contents/...?ref=68fb2b10554f7bffd6670d3d10145c80e1955d17`].
Its module README, `compose/material/material/icons/README.md` (4,433 bytes at that revision),
describes the pipeline in Google's own words:

> 1. Icons are downloaded (manually) using the Google Fonts API, using the script in the `generator`
>    module. This downloads vector drawables for every single Material icon to the `raw-icons` folder.
> 2. During compilation … these icons are processed to remove theme attributes that we cannot
>    generate code for, checked to ensure that all icons exist in all themes, and then an API
>    tracking file … is generated. … the build will fail at this point if there are differences
>    between the checked in API file and the generated API file.
> 3. Once these icons are processed, we then parse each file, create a Vector-like representation,
>    and convert this to `VectorAssetBuilder` commands … Each XML file creates a corresponding Kotlin
>    file, containing a `by lazy` property representing that icon.

with an icon-testing section that is the model for §4:

> 1. Similar to how we generate Kotlin source for each icon, we also generate a 'testing manifest' …
>    This allows us to run screenshot comparison tests (`CoreIconComparisonTest`, and
>    `ExtendedIconComparisonTest`) that compare each pixel of the generated and source drawables, to
>    ensure we generated the correct code … **It's important to run this test locally after every
>    icons update.**

Concrete parts of that generator, all read at the pinned androidX revision above:

- `download_material_icons.py` (80 lines) — queries `http://fonts.google.com/metadata/icons`, reads
  `asset_url_pattern` and `host` from the response, and downloads **`24px.xml` VectorDrawables** per
  icon into `raw-icons/<theme>/<name>.xml`. Its `THEME_MAPPING` maps only the *Material Icons*
  families: `materialicons→filled`, `materialiconsoutlined→outlined`, `materialiconsround→rounded`,
  `materialiconstwotone→twotone`, `materialiconssharp→sharp` [measured]. **Material Symbols is not in
  that list** — see §6.
- `IconProcessor.kt:66-77` — `process()` ensures every icon exists in every theme, writes the API
  file, and `checkApi` (`:192-205`) fails the build when the generated list differs from the
  checked-in one (`api/icons.txt`, `api/automirrored_icons.txt`). Measured sizes of those files at
  that revision: **9,934 lines** and **724 lines**.
- `IconProcessor.kt:213-218` — naming: `CaseFormat.LOWER_UNDERSCORE.to(UPPER_CAMEL, name)`, with a
  leading `_` when the name starts with a digit; plus `AllowedDuplicateIconNames = ["AddChart",
  "Addchart"]` at `:221` for case-insensitive-filesystem clashes [measured].
- `IconProcessor.kt:143-144` — auto-mirroring is read from the source drawable:
  `isAutoMirrored(content) = content.contains("android:autoMirrored=\"true\"")` [measured].
- `IconParser.kt`, `Vector.kt`, and `vector/PathNode.kt` — the parser and its Kotlin emitter.
  `PathNode.kt:381-386` maps SVG/VectorDrawable arc arguments **1:1**:
  `isMoreThanHalf = args[3] != 0`, `isPositiveArc = args[4] != 0`, then `x`, `y`; and
  `PathNode.kt:160` emits `"arcTo(${rx}f, ${ry}f, ${theta}f, $isMoreThanHalf, $isPositiveArc, $x}f, $y}f)"`
  [measured]. That is the same argument order and flag meaning as SVG `A`.
- `tasks/IconGenerationTask.kt`, `IconSourceTasks.kt` — `build.gradle` calls
  `IconGenerationTask.registerExtendedIconMainProject(project, android)` [measured]; the icon sources
  are **generated at build time, not committed**.

**Where it went.** `androidx/androidx` commit `fda069fe217246933ccb671d5f34f4eff803f275`
(2024-05-31, *"Remove material-icons-* projects"*) deleted the modules from `androidx-main`
[measured]. `compose/material/material-icons-extended` therefore **does not exist on `androidx-main`
today** (contents API → 404) and the generator is only reachable at older revisions of that path.
The readable, primary view of Google's *output* is the published sources jar (see §4.2).

### 2.2 The precedent that matters most: androidx commits vectors by hand

`compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/internal/Icons.kt` on
`androidx-main` (Apache-2.0, `internal object Icons`) is a hand-written icon file that depends on
**nothing** from the icon artifacts: its imports are `androidx.compose.ui.graphics.{Color,
PathFillType,SolidColor,StrokeCap,StrokeJoin}`, `androidx.compose.ui.graphics.vector.{DefaultFillType,
ImageVector,PathBuilder,path}` and `androidx.compose.ui.unit.dp` only [measured]. It carries
`KeyboardArrowLeft`/`KeyboardArrowRight` (auto-mirrored), `Close`, `Check`, `Edit`, `DateRange`,
`ArrowDropDown`, `MoreVert`, `Schedule` and more, and ends with its own ~35-line private helpers:

```kotlin
private inline fun materialIcon(
    name: String,
    autoMirror: Boolean = false,
    block: ImageVector.Builder.() -> ImageVector.Builder,
): ImageVector = ImageVector.Builder(
    name = name,
    defaultWidth = MaterialIconDimension.dp,
    defaultHeight = MaterialIconDimension.dp,
    viewportWidth = MaterialIconDimension,
    viewportHeight = MaterialIconDimension,
    autoMirror = autoMirror,
).block().build()

private inline fun ImageVector.Builder.materialPath(
    fillAlpha: Float = 1f, strokeAlpha: Float = 1f,
    pathFillType: PathFillType = DefaultFillType,
    pathBuilder: PathBuilder.() -> Unit,
) = path(
    fill = SolidColor(Color.Black), fillAlpha = fillAlpha, stroke = null,
    strokeAlpha = strokeAlpha, strokeLineWidth = 1f, strokeLineCap = StrokeCap.Butt,
    strokeLineJoin = StrokeJoin.Bevel, strokeLineMiter = 1f,
    pathFillType = pathFillType, pathBuilder = pathBuilder,
)

private const val MaterialIconDimension = 24f
```

Two consequences, both load-bearing here:

1. **No new dependency is needed.** Re-implementing `materialIcon`/`materialPath` is ~35 lines of
   plain Compose code, and Google's own Material 3 library does exactly that.
2. **Where the grid is not 24, that file does not use its own helper** — its `swipe_vertical` entry
   calls `ImageVector.Builder(…, viewportWidth = …, viewportHeight = …).apply { path(…) }.build()`
   directly [measured]. That is the precedent for handling Material Symbols' `0 -960 960 960` grid
   without rescaling.

### 2.3 Third-party converters, checked against their own repositories

- **`DevSrSouza/svg-to-compose`** — [measured] `gh api repos/DevSrSouza/svg-to-compose`: MIT,
  471 stars, last push 2024-09-15, `description: "Converts SVG and Android Vector Drawable in Compose
  Multiplatform source code"`. Its README states it *"uses Android's `Svg2Vector`… and uses a
  customized material icon code generator from the Jetpack Compose source code"* — i.e. it is a fork
  of the generator in §2.1 — and its primary output shape is an **accessor object** built from a
  vector directory (`allAssetsPropertyName = "AllAssets"` in the README example), not per-icon `val`s
  on an `Icons`-like object. It is a viable converter; it is not the shape this repo wants, and its
  last release predates both the Material Symbols artwork and current Compose.
- **Android Studio's Vector Asset importer** produces **`VectorDrawable` XML**, not `ImageVector`
  Kotlin (Google's own page, <https://developer.android.com/studio/write/vector-asset-studio>, HTTP
  200 [measured]). Using it means adding a second conversion step (`VectorDrawable` XML → Kotlin)
  — the step Google's own generator implements.
- There is no maintained `material-symbols-to-compose` generator from Google. `compose-icons`
  (referenced in the `svg-to-compose` README) is a third-party pack built with that tool, not a
  Google artifact [measured README].

**Decision: no external tool.** Write a ~190-line converter, keep it in-repo (§2.5), and treat its
output as committed source. Rationale: the mapping is 13 command letters plus a two-dialect
viewport rule (§1.3, §2.4); a third-party tool would still need the Material Symbols CDN/repo fetch,
the alias table (§6.3), the auto-mirror list (§6.4) and the verification harness (§4) — none of which
it provides — while adding a build-plugin dependency the project does not want.

### 2.4 The converter I wrote and ran

I wrote `/tmp/svg2compose.js` (Bun/Node, no dependencies, 186 lines) and ran it over the 178 glyphs
this app needs plus the 16 distinct FILL=1 variants — **194 artifacts converted, 0 parse failures,
0 residual-input failures** [measured]. The full listing is in Appendix B; the rules that matter:

| SVG construct | Compose mapping | Source of the mapping |
|---|---|---|
| `viewBox="0 -960 960 960"` | `viewportWidth = 960f`, `viewportHeight = 960f`, wrap paths in `group(translationY = 960f)` — coordinates kept verbatim | `ImageVector.kt:690-698` (`group(… translationY …)`); the negative Y origin is the font's design grid |
| `width`/`height` only (24-unit dialect) | `viewportWidth/Height = 24f`, no group | 7 measured files, §1.3 |
| `M/m L/l H/h V/v C/c Q/q S/s T/t Z` | `moveTo`/`moveToRelative`, `lineTo…`, `horizontalLineTo…`, `verticalLineTo…`, `curveTo…`, `quadTo…`, `reflectiveCurveTo…`, `reflectiveQuadTo…`, `close()` | `PathBuilder.kt:29-293`, all 19 function names verified present |
| `A/a rx ry rot large-arc sweep x y` | `arcTo(rx, ry, theta, isMoreThanHalf = large-arc, isPositiveArc = sweep, x, y)`, `arcToRelative` likewise | `PathBuilder.kt:322-345` (*"`isMoreThanHalf` … sweep greater than or equal to 180 degrees"*, *"`isPositiveArc` … counter-clockwise"*, `theta` *"in degrees"*) and Google's own generator `vector/PathNode.kt:378-386` |
| `fill-rule` | `pathFillType = EvenOdd` when `evenodd`, else `NonZero` | none of the 178 glyphs carry the attribute [measured]; kept for generality |
| absent `fill` | `fill = SolidColor(Color.Black)` — the tint does the colouring | the same default as `materialPath` in `material-icons-core/.../Icons.kt:233-256` and material3's internal copy |
| per-path parameters | `fillAlpha = 1f`, `stroke = null`, `strokeLineWidth = 0f`, `strokeLineCap = Butt`, `strokeLineJoin = Miter`, `strokeLineMiter = 4f` | mirrors the shape of the repo's own `Download.kt:27-34` |
| implicit command repeats, packed arc flags, `.5`-style numbers | tokenizer emits implicit repeats as explicit commands and asserts **every number in `d` is consumed** | assertion fires on any misparse; 194/194 clean [measured] |

Emitted shape for the 960-grid dialect (abridged `content_cut`; full text in Appendix A):

```kotlin
ImageVector.Builder(
        name = "Rounded.ContentCut",
        defaultWidth = 24.dp,
        defaultHeight = 24.dp,
        viewportWidth = 960.0f,
        viewportHeight = 960.0f,
    )
    .apply {
    group(translationX = 0.0f, translationY = 960.0f) {
        path(
            fill = SolidColor(Color.Black),
            fillAlpha = 1.0f,
            stroke = null,
            strokeLineWidth = 0.0f,
            strokeLineCap = Butt,
            strokeLineJoin = Miter,
            strokeLineMiter = 4.0f,
            pathFillType = NonZero,
        ) {
            moveToRelative(480.0f, -400.0f)
            lineToRelative(-94.0f, 94.0f)
            quadToRelative(8.0f, 15.0f, 11.0f, 32.0f)
            …
            close()
        }
    }
    }
    .build()
```

**Two grid routes, and which to take.** (a) Keep the 960-unit grid and translate with
`group(translationY = 960f)` — upstream numbers are preserved verbatim, so a machine check can
compare generated arguments against the upstream `d` (§4.2). (b) Rescale by 1/40 into a 24-unit
viewport — matches the classic idiom but rewrites every literal and loses the exact-equality check.
**Take (a)**, for the verification property alone; the `group` is one extra line per glyph, and the
material3 `swipe_vertical` precedent (§2.2) shows Google avoids the 24-unit assumption when the
drawing is not on that grid.

**Do not follow the repo's existing `drawablevectors` idiom for these 184 glyphs.**
`ui/svg/drawablevectors/Download.kt:21-35` builds a themed vector
(`SolidColor(MaterialTheme.colorScheme.surfaceContainerHigh)`, `LocalFixedColorRoles.current…`, a
765.59973 × 667.7441 viewport) and `ui/svg/__DrawableVectors.kt:3` exposes it through
`public object DynamicColorImageVectors`; `ui/svg/VectorPreviews.kt` previews them. Those are
**illustrations** that must read the theme at composition time. Material Symbols glyphs are
**system icons**: fill must stay `Color.Black` so `Icon(tint = …)` (and `LocalContentColor`)
recolours them. Baking `MaterialTheme.colorScheme.*` into 178 committed vectors would freeze the
theme and break every `Icon` call site.

### 2.5 How the converter should be committed

- **Script**: `tools/svg2compose.js` (or `.kts`), with no dependency except a JS/Kotlin runtime,
  committed with the glyph manifest.
- **Manifest**: `tools/material-symbols.manifest.tsv`, one row per glyph artifact (see §6.5 for the
  call-site table): `glyph`, `variant` (`default`/`fill1`), `codepoint`, `auto_mirror`,
  `upstream_url`. This is the pinned-revision record and the review surface (§5.2).
- **Output**: `app/src/main/java/com/junkfood/seal/ui/svg/symbols/`, one file per glyph, plus an
  `object SealSymbols { object Rounded { … } }` accessor mirroring the `__DrawableVectors.kt`
  convention. A single file for all 199 vectors is also possible (material3's `Icons.kt` model); with
  ~1.9 KB of source per vector (§3.4) that is a ~373 KiB single file — split it.
- **Determinism**: the script must be pure (no timestamps, stable ordering, fixed float formatting),
  so re-running it on an unchanged manifest produces a byte-identical tree and `git diff` is empty.

---

## 3. How large the glyph set is, and what it costs

### 3.1 Enumeration method (reproducible; supersedes the parent's first pass)

Scope: every `.kt` file under `app/src/main/java` (165 files). Regexes:

```
Icons\.(AutoMirrored\.)?(Default|Outlined|Rounded|Sharp|Filled|TwoTone)\.([A-Za-z0-9_]+)
```

`Default` is folded into `Filled` because androidx defines `val Default = Filled`
(`material-icons-core/.../Icons.kt:184`, and `:178` inside `AutoMirrored`) [measured] — a scan that
omits `Default` under-counts.

What this method **misses**, in ascending order of likelihood:

1. **Fully-qualified or aliased imports** — `import androidx.compose.material.icons.outlined.ContentCut
   as Cut; Cut` is invisible. Not present in this app [measured: `grep 'import androidx\.compose\.material\.icons[^\n]* as '`
   over `app/src/main/java` returns no match]. Wildcard imports **are** present —
   `ui/integration/IntegrationExamples.kt:14` is `import androidx.compose.material.icons.outlined.*` —
   but a wildcard import still requires the `Icons.Outlined.X` reference, so the scan is unaffected;
   it only means the import list is not a usable source of truth. Scan references, not imports.
2. **Icons reached through an indirection**: a `val icon: ImageVector` parameter, a `when` branch
   returning an icon, an icon list. `Icons.*` text still appears at the definition, so the count
   survives; a re-export into another module would not (single-module app, so none).
3. **Reflection / string names** — not possible for `ImageVector` properties; ruled out.
4. **Hand-built `ImageVector`s** — `ui/svg/drawablevectors/` (4 files) and
   `ui/svg/__DrawableVectors.kt`. These are **not** in the glyph count and are not affected by this
   migration.
5. **Non-Kotlin usages** — an icon referenced from XML is impossible for Compose; ruled out.

One false positive survives the scan and **must be excluded by hand**: `Icons.Outlined.Icon` inside a
KDoc example at `app/src/main/java/com/junkfood/seal/ui/page/settings/appearance/GradientDarkExample.kt:199`
(`*    PremiumSectionHeader(title = "Section Title", icon = Icons.Outlined.Icon)`), and that file is
on the map's tier-1 delete list.

### 3.2 Counts [measured]

| Quantity | Count |
|---|---|
| `.kt` files scanned | 165 |
| files that reference `Icons.*` | **78** — two of them only through the `Icons.Default` alias (`ui/page/security/LockScreen.kt`, `ui/page/security/SetPinDialog.kt`), so a scan that omits `Default` reports 76 |
| distinct call-site names (style + name, `AutoMirrored` kept distinct) | **226** |
| of which real call sites (excluding the KDoc `Icon`) | **225** |
| distinct base names (`AutoMirrored` folded in) | **184** |
| base names used in more than one style | 32 |
| distinct call-site names per style: `Outlined` / `Filled` (incl. `Default`) / `Rounded` | 175 / 27 / 24 |
| call-site occurrences per style (parent's count, distinct-name-stable): `Outlined` 506 / `Filled` 52 / `AutoMirrored.Outlined` 24 / `Rounded` 31 / `AutoMirrored.Filled` 2 | 615 |
| `Sharp` and `TwoTone` call sites | **0** |
| `AutoMirrored` base names | **12**: `ArrowBack`, `ArrowForward`, `ArrowForwardIos`, `ArrowRight`, `DriveFileMove`, `List`, `OpenInNew`, `PlaylistAdd`, `PlaylistPlay`, `Sort`, `TextSnippet`, `ViewList` |

### 3.3 What the redesign actually needs to commit

Two decisions, and the measured answer to each:

**(a) 184 base names, or 226 call sites?** Commit **per glyph, not per call site**. Name-to-glyph is
many-to-one in two ways that the migration must respect:

- Six app names are **aliases with no per-glyph file of their own**: `clear`, `error_outline`,
  `help_outline`, `restore`, `warning_amber`, `audiotrack`. Upstream the name exists in the
  `.codepoints` dictionary but `symbols/web/<name>/` does not exist (HTTP 404 for the glyph file)
  [measured]; the CDN serves each one as byte-identical bytes to its canonical partner [measured]:
  `clear`→`close` (331 B), `error_outline`→`error` (627 B), `help_outline`→`help` (774 B),
  `restore`→`history` (657 B), `warning_amber`→`warning` (530 B), `audiotrack`→`music_note` (293 B).
  `help` is **not** otherwise in the app's set, so it adds one file.
- Two pairs of app names are **byte-identical artwork** in the repo: `image` ≡ `photo`,
  `new_releases` ≡ `verified` [measured, md5 of the fetched payloads].

**(b) Preserve the app's styles, or normalise to one?** Both are defensible; the measured cost
difference is 16 files.

| Plan | SVG files needed | Generated `ImageVector`s | Notes |
|---|---|---|---|
| **A. Preserve style** (Filled call sites get the FILL=1 drawing, everything else FILL=0) | **194** | **199** | 178 `default` + 16 extra `fill1` (11 of the 27 Filled glyphs are already solid, so their `fill1` file is byte-identical to `default`); **192** distinct artworks after byte-dedupe; +5 mirrored duplicates (§3.3c) |
| B. Normalise every call site to one variant | **178** | 183 | **176** distinct artworks after byte-dedupe; 27 Filled call sites change drawing weight |

All 178 glyphs exist in both variants [measured: 178/178 `_fill1_24px.svg` fetched, 200 OK]; the two
variants differ for 111 of 178 glyphs and are identical for 67.

**(c) Mirrored and plain call sites share artwork but not code.** Five of the 12 auto-mirrored names
are *also* used in a non-mirrored call site: `ArrowForward`, `OpenInNew`, `PlaylistAdd`,
`PlaylistPlay`, `Sort` [measured: e.g. `Icons.Outlined.Sort` and `Icons.AutoMirrored.Outlined.Sort`
both appear]. `Icons.AutoMirrored.Outlined.Sort` and `Icons.Outlined.Sort` are two different
`ImageVector`s with the same path data and different `autoMirror` values, so those five glyphs are
generated twice — 199 vectors from 194 SVG files (the extra five cost 7,754 B of source [measured]).

**Recommendation: Plan A.** 21 glyphs are used today in *both* a Filled and a non-Filled style
(`build`, `cancel`, `check_circle`, `close`, `download`, `error`, `info`, `lock`, `settings`,
`subscriptions`, `subtitles`, `terminal`, `timer`, `video_library`, `warning`, …) — the app is already
using fill as a state signal, and Material's own README describes exactly this use (*"the Fill axis …
can be manipulated for an animated fill effect, to indicate user selection"*). Plan A costs 16 extra SVG files plus 5 mirrored duplicates (~46 KB of source) and keeps 27 call sites
visually faithful; Plan B changes their weight in one sweep, which `#14` must then accept.

Plan A is therefore: **194 SVG files → 199 generated `ImageVector`s for 184 base names / 225 real call
sites**, of which 17 vectors (12 names, 5 of them duplicated) carry `autoMirror = true` (§6.4) and 6
names are reached through the alias table (§3.3a).

### 3.4 APK cost: measured inputs, estimated output

**The deleted dependency, measured** [measured from Google Maven today]:

| Artifact / measure | Value |
|---|---|
| BOM `2026.05.01` → `androidx.compose.material:material-icons-extended` | **1.7.8** (`compose-bom-2026.05.01.pom:198-199`) |
| same BOM → `androidx.compose.ui:ui` | 1.11.2 (`:918-919`) |
| same BOM → `androidx.compose.material3:material3` | 1.4.0 (`:272-273`) |
| `material-icons-extended-1.7.8.aar` | 298 B (a stub) |
| `material-icons-extended-android-1.7.8.aar` | **35,720,998 B (34.07 MiB)** |
| `classes.jar` inside it | 37,425,981 B, 11,123 entries |
| entries under `androidx/compose/material/icons/` | **11,117 classes, 85,390,331 B uncompressed** |
| `material-icons-core-android-1.7.8.aar` | 823,515 B (804 KiB) |
| per-class cost, outlined | 15,837,212 B / 2,084 classes = **7,599 B/class** |
| per-class cost, rounded | 16,005,027 B / 2,084 classes = **7,679 B/class** |

Method: `curl -L -D -` for `Content-Length`, `unzip -l` on the AAR and on the extracted
`classes.jar`, `awk` sums (Appendix C). Note the icon artifact sits on a **frozen 1.7.8 line** while
the rest of Compose in the same BOM is 1.11.2 — the version catalog is already mixing lines here.

**The generated side, measured as source** [measured]: 194 artifacts → 10,719 path commands and
24,863 numeric literals. Generated Kotlin source, in the two plausible emission styles:

| Emission style | Total bytes (194 SVG files) | Bytes / vector |
|---|---|---|
| explicit `path(fill = …, fillAlpha = …, stroke = …) { … }` per glyph (Appendix A) | 667,058 | 3,438 |
| with a local ~35-line `materialIcon`/`materialPath` helper (§2.2) | **374,278** | **1,929** |
| the 5 mirrored duplicates (helper form) | +7,754 | 1,551 |
| **Plan A total, helper form (199 vectors)** | **382,032** | **1,920** |

**Compiled size, estimate.** Using the measured rounded per-class cost as the calibration proxy,
199 vectors ≈ 199 × 7,679 B ≈ **1.46 MiB of uncompressed `.class`** `[estimate]`; DEX output is
smaller again after R8 `[INFERENCE: R8 was not run — no JDK/SDK on this host]`.

**What this means for the APK, honestly.**

- Today's release build has `isMinifyEnabled = true` and `isShrinkResources = true`
  (`app/build.gradle.kts:97-98`), and androidx's own README states the library *"should only be used
  if Proguard / R8 is enabled"* and holds *"over 5000"* icons. R8 removing the unreferenced icon
  properties is therefore what that README assumes, and by construction `ImageVector` properties are
  reachable only from a reference to them `[INFERENCE: not observed — no shrinker run on this host]`.
- Consequently the **APK-size saving from deleting the dependency is small and is not measured here**
  `[INFERENCE]`: both schemes end up shipping ~200 icon classes. Anyone claiming a large APK win is
  not measuring it.
- The **measured** costs of the dependency are build-side and certain: a 34.07 MiB AAR download per
  clean build, 11,123 jar entries and 85.39 MB of class bytes for R8 to read and shrink, and a
  library that no longer moves with the rest of Compose.
- The compressed DEX cost of 199 committed vectors cannot be stated without a build; treat
  "1.46 MiB uncompressed class" as the ceiling of the new scheme and re-measure after the first
  release build if the number matters to `#12` `[estimate, residual uncertainty]`.

---

## 4. How a generated glyph is verified

Four checks, from cheapest to strongest. Each catches a different failure; none subsumes the others.

### 4.1 Mechanical existence and style (catches: wrong style, missing glyph, alias drift)

1. The script's HTTP status must be asserted per glyph. **This is not theoretical**: my run over the
   183 names failed 6 times with 404 because those names have no per-glyph file (§3.3a). A generator
   that "skips 404s" silently ships a missing icon; the script must fail loudly and require the
   alias table.
2. Check the name is in the style's `.codepoints` dictionary (`MaterialSymbolsRounded[...].codepoints`,
   4,284 names [measured]) — this catches a mis-derived snake_case name.
   *Does not catch*: a name that exists but whose artwork changed, or an alias that maps to the wrong
   canonical partner.
3. Check `viewBox` is one of the two known grids (`0 -960 960 960` or absent with 24 × 24 `width`/
   `height`) — catches a silent upstream grid change that would rescale a glyph.

### 4.2 Path-data equality against the pinned upstream SVG (catches: converter regressions)

The generated Kotlin must contain exactly the upstream numbers, in order. I ran this as an **inverse
round trip**: parse each upstream `d`, emit the Kotlin, re-read the Kotlin call lines back into SVG
commands, and compare command letters and argument values.

Result: **194 of 194 SVG files matched exactly, 0 mismatches** [measured]. Combined with the parser's
own invariant (all numbers in `d` consumed), this pins parse and emission.

*Does not catch*: a mapping that is self-consistent but semantically wrong in Compose (e.g. swapping
`isMoreThanHalf` and `isPositiveArc`). That is why the mapping table in §2.4 cites
`PathBuilder.kt:322-345` and Google's `PathNode.kt:378-386` argument-by-argument; for this glyph set
no arcs occur at all, which removes that residual risk entirely [measured: 0 `A/a` commands].

### 4.3 Rendered comparison (catches: everything the text checks cannot)

Two levels:

**(a) Converter-level, already run.** I re-serialized each parsed path into an SVG of the same
`viewBox`, rendered the original and the round-tripped SVG side by side in real Chromium at 96 × 96 px
via `canvas.drawImage` + `getImageData`, and compared pixels. Result: **194/194 glyphs with 0 pixels
differing beyond a delta of 8, max delta 0, and 0 blank renders** [measured]. Fixture and page:
`/tmp/rt/roundtrip.html`, `/tmp/rt/roundtrip.json` (Appendix C).

**(b) In-app, required before the migration lands.** The repo's harness already exists:
`ui/svg/VectorPreviews.kt` renders vectors in a `@Preview` with light/night variants. Add an
analogous `SymbolsPreview.kt` that lays the generated set out in a grid at 24 dp (and at 48 dp) over
`SealTheme`, then diff against the corresponding Material Symbols tiles from
`fonts.google.com/icons` in the same style. This is the only check that catches "the artwork is the
right glyph but the wrong drawing" — see §6.2, where `download` and `file_download` share a codepoint
but not their artwork.

*Cannot*: be automated inside this repository without screenshot infrastructure; Google solves the
same problem with generated screenshot tests (`ExtendedIconComparisonTest`, marked `@Ignore` for
runtime cost and run manually after each icon update, §2.1).

### 4.4 Diff against the icons the app ships today (catches: wrong glyph chosen for a call site)

The current icons are readable Kotlin in the published sources jar — **but note the path the ticket
suggests no longer exists**: `androidx/compose/material/material-icons-extended/src/commonMain/…` is
**absent from `androidx-main`** (module removed 2024-05-31, §2.1; contents API → 404) [measured].
The readable route is the release artifact:

```
https://dl.google.com/dl/android/maven2/androidx/compose/material/material-icons-extended-android/1.7.8/material-icons-extended-android-1.7.8-sources.jar
```

[measured] HTTP 200, 12,086,044 bytes, 11,105 `.kt` files, laid out as
`commonMain/androidx/compose/material/icons/<style>/<Name>.kt` and `…/automirrored/<style>/<Name>.kt`
[measured]. Extracted excerpt for `Outlined.ContentCut`:

```kotlin
public val Icons.Outlined.ContentCut: ImageVector
    get() {
        if (_contentCut != null) { return _contentCut!! }
        _contentCut = materialIcon(name = "Outlined.ContentCut") {
            materialPath {
                moveTo(9.64f, 7.64f)
                curveToRelative(0.23f, -0.5f, 0.36f, -1.05f, 0.36f, -1.64f)
                …
                close()
            }
        }
        return _contentCut!!
    }
private var _contentCut: ImageVector? = null
```

Use this for a **call-site-level before/after render** (old vector vs new glyph at the same size, per
`#14`'s mapping). Do **not** use it as the target values for the new vectors: it is Material *Icons*
artwork on a 24-unit grid (`viewportWidth = 24f` in `materialIcon`,
`material-icons-core/.../Icons.kt:212-223`) [measured], while the redesign commits Material
*Symbols* artwork on a 960-unit grid. Equality of names is not equality of drawings (§6.2).

*Cannot*: catch a wrong **style** choice between Material Symbols variants — the old artwork has no
FILL axis.

### 4.5 Auto-mirroring verification (the one behaviour with no glyph-side evidence)

`ImageVector.Builder` takes `autoMirror: Boolean = false` (`ImageVector.kt:119`) and the 12 app names
in §3.2 must set it. The API is present in the version the map pins: I extracted the string table of
`androidx/compose/ui/graphics/vector/ImageVector$Builder.class` from
`ui-android-1.11.2.aar` (the `ui` version resolved by BOM `2026.05.01`,
`compose-bom-2026.05.01.pom:918-919`) and it contains the constructor descriptor
`(Ljava/lang/String;FFFFJIZ)V` — `name`, four floats, `tintColor`, `tintBlendMode`, `autoMirror` —
plus the names `autoMirror` and `getAutoMirror` on `ImageVector` itself [measured].

Verify with a `@Preview(locale = "ar")` (or `@Preview` + `CompositionLocalProvider(LocalLayoutDirection
provides LayoutDirection.Rtl)`) rendering those glyphs next to their LTR form: a wrong flag shows as a
`playlist_add` glyph whose plus sign is on the wrong side, which text checks cannot see.

---

## 5. Maintenance cost

### 5.1 Adding one glyph later

| Step | Cost |
|---|---|
| 1. Derive the Material Symbols name from the call site (rule §6.1) | seconds |
| 2. Add the glyph to `tools/material-symbols.manifest.tsv` (glyph, variant, codepoint, auto_mirror, URL) | ~1 min |
| 3. Run `tools/svg2compose.js` (fetches only missing glyphs; regeneration is deterministic) | seconds for one glyph; ~25 s for all 178 at 8-way concurrency [measured] |
| 4. Review the diff (1 new file, ~1.9 KB) and the call site | ~2 min |
| 5. Optionally add the tile to `SymbolsPreview.kt` | ~1 min |

**Total ≈ 5 minutes**, with a converter run — no hand-editing needed. A hand edit is also viable (the
material3 precedent, §2.2): copy one generated file, replace the path data with the four `moveTo/…/
close()` calls a designer supplies, and retain the `group` wrapper for the 960 grid. Hand edits must
not be re-run over by the script, so either the script gains an `--only-new` mode or hand edits live
outside the generated directory.

### 5.2 Upstream updates to a glyph

There is **no dependency to bump** once the vectors are committed: Material Symbols is not a Gradle
coordinate here. The app therefore does not notice an upstream change at all unless someone asks it
to. The review surface must be created deliberately:

- Record the upstream SHA in the manifest (this report uses
  `27e9ef1dbeedc13d682fece4a58e1eda4cb0961a`) and in `tools/README` §"updating".
- Add a `--check` mode that re-fetches at a **newer** SHA and diffs the generated tree against the
  committed one. Cost per review: one command, then a diff. A full-set re-export touches up to 194
  files / 382,032 B of source; in practice an upstream release changes a handful of glyphs.
- Cadence: on demand, not on a schedule. Material Symbols adds glyphs continuously; this app needs a
  new glyph when a feature needs one, and that path is §5.1.

### 5.3 A glyph renamed or removed upstream — measured, not theoretical

My first full-set fetch got **6 × HTTP 404 out of 183** names [measured]: `Audiotrack`, `Clear`,
`ErrorOutline`, `HelpOutline`, `Restore`, `WarningAmber`. Their names are in the `.codepoints`
dictionary (so a name-membership check passes) but their `symbols/web/<name>/` directory does not
exist; the CDN resolves each to its canonical partner byte-for-byte (§3.3a). Failure modes and their
cost:

- **Script that ignores 404s** → ships a missing icon; caught only in QA. *Fix:* fail the run and
  require an alias entry.
- **Script that trusts the CDN** → works, but `fonts.gstatic.com/s/i/short-term/release/...` is an
  unversioned path; a change there is invisible in review. *Fix:* pin the repo SHA and use the CDN
  only as a fallback, recording which route produced each file.
- **Glyph removed upstream later** → the pinned SHA keeps builds reproducible; the failure appears
  only when someone re-runs at a newer SHA, where the script fails loudly on the 404 and the alias
  table shows what to remap to. Cost: minutes, plus a review decision on the replacement glyph.

### 5.4 What the committed set costs to keep honest

- **Review surface**: 194 generated files → 199 vectors (192 distinct artworks) = 382,032 B of Kotlin,
  one manifest file, one ~190-line script.
- **Drift risks** that exist only with the committed approach, each needing a guard: the alias table
  (§3.3a), the `autoMirror` set (12 names → 17 vectors, §6.4), the 27 FILL=1 choices (§3.3b), the
  pinned SHA (§5.2). All four live in one manifest file; there is no other state.
- **Compare with today's cost**: a version-catalog line, a bundle entry
  (`gradle/libs.versions.toml:57`, `:127`), and a 34.07 MiB AAR per clean build — but zero per-glyph
  review, and no control over which drawing ships.

---

## 6. The naming trap, and the rule from a call site to a Material Symbols name

### 6.1 The rule (verified, not remembered)

```
snake(name) = name
  .replace(/([a-z0-9])([A-Z])/g, "$1_$2")      # lowercase/digit → uppercase
  .replace(/([A-Z]+)([A-Z][a-z])/g, "$1_$2")   # acronym end → word start (QRCode → QR_Code)
  .replace(/([A-Za-z])([0-9])/g, "$1_$2")      # letter → digit
  .replace(/([0-9])([A-Za-z])/g, "$1_$2")      # digit → letter
  .toLowerCase()
```

Run over the app's **184 base names** against the 4,284 rounded Material Symbols names: **183 match,
1 does not** [measured]. The single miss is `Icon` → `icon`, and `Icons.Outlined.Icon` is a KDoc
example (`GradientDarkExample.kt:199`), not a call site. So the rule is **clean for this app's real
call-site set**, including the awkward shapes: `Hd`→`hd`, `Sd`→`sd`, `SdCardAlert`→`sd_card_alert`,
`QrCode`-style acronym capitalisation (not present here, but the second rule handles it),
`SignalCellular4Bar`→`signal_cellular_4_bar`,
`SignalCellularConnectedNoInternet4Bar`→`signal_cellular_connected_no_internet_4_bar`,
`DriveFileRenameOutline`→`drive_file_rename_outline`.

### 6.2 Where the trap actually lives

Not in name shape — in four other places:

1. **`Icons.Default.X` is `Icons.Filled.X`.** `val Default = Filled` in both `Icons`
   (`material-icons-core/.../Icons.kt:184`) and `Icons.AutoMirrored` (`:178`) [measured]. A scan that
   only looks for `Filled` under-counts call sites; a migration that treats `Default` as a third style
   will invent a style that does not exist.
2. **Name equality is not artwork equality.** `material-icons-extended` 1.7.8 is built from the
   *Material Icons* families (`download_material_icons.py`'s `THEME_MAPPING` maps to
   `filled/outlined/rounded/twotone/sharp` [measured]), while this migration commits *Material
   Symbols* artwork. Same name, different drawing, different grid (24 vs 960). The measured proof that
   even upstream's own codepoints do not imply identical artwork: `download` and `file_download` share
   codepoint `f090` yet their 24px SVGs **differ in bytes** [measured]; `image` ≡ `photo` and
   `new_releases` ≡ `verified`, on the other hand, are byte-identical [measured]. Any "same
   codepoint ⇒ same file" shortcut is wrong in both directions.
3. **Auto-mirroring is not a name property.** The rounded `.codepoints` file contains **no
   `_mirrored` names at all** [measured: 0 matches in 4,284 names]. Mirroring is a per-icon attribute
   upstream (`android:autoMirrored="true"` in Google's raw drawables, `IconProcessor.kt:139`
   [measured]) and an `ImageVector.Builder(autoMirror = …)` property in Compose
   (`ImageVector.kt:119`). The app's 12 auto-mirrored call sites therefore map to the **plain** glyph
   name plus a flag (§6.4).
4. **Aliases.** Six call-site names have no glyph file; they resolve to a canonical partner whose name
   is different (§3.3a). Nothing in the call site hints at this — `Icons.Outlined.HelpOutline` maps to
   the glyph `help`, not `help_outline`.

### 6.3 The full mapping table

`/tmp/sealplus-glyph-mapping.tsv` (host-local, 226 rows + header) has one row per call site:

```
call_site  compose_style  compose_name  auto_mirrored  material_symbols_name  glyph_file
resolution  codepoint  auto_mirror_flag_in_code  svg_variant  upstream_svg_url
```

`resolution` is `direct` for 219 rows, `alias-><canonical>` for 6, and
`NOT_A_CALL_SITE (KDoc example)` for 1 [measured]. `svg_variant` is `fill1_24px` for Filled call sites
and `24px` otherwise, and `upstream_svg_url` is the exact pinned URL for that row.
Regeneration recipe: Appendix C step 7.

The exception list, in full (the only 7 rows that the naive rule does not resolve):

| Call site name | snake_case | Codepoint | Resolution | Why |
|---|---|---|---|---|
| `Audiotrack` | `audiotrack` | `e405` | `music_note` | alias: no per-glyph file; CDN serves `music_note` bytes |
| `Clear` | `clear` | `e5cd` | `close` | same artwork as `close` (both drawn, and `close` also in the app) |
| `ErrorOutline` | `error_outline` | `f8b6` | `error` | alias of `error` |
| `HelpOutline` | `help_outline` | `e8fd` | `help` | alias; **`help` is not otherwise used by the app** — one extra file |
| `Restore` | `restore` | `e8b3` | `history` | alias of `history` |
| `WarningAmber` | `warning_amber` | `f083` | `warning` | alias of `warning` |
| `Icon` | `icon` | — | *not a call site* | KDoc example, `GradientDarkExample.kt:199` |

Additional collapses that the rule resolves but the migration must still decide about, because two
call sites share one artwork: `image`/`photo` and `new_releases`/`verified` (byte-identical files,
[measured]) — and, under the aliases above, `Clear`/`Close`, `Error`/`ErrorOutline`,
`History`/`Restore`, `Warning`/`WarningAmber`, `MusicNote`/`Audiotrack`.

Names worth a look when `#14` picks replacements, because Material Symbols renamed or repurposed the
concept: `exit_to_app` (Material Symbols also carries `logout` for the same idea), `audiotrack`
(→ `music_note`), and the alias family above. `Hd`, `Sd`, `SdCardAlert` resolve exactly, as do the
digit-bearing names — no invented exceptions.

### 6.4 The 12 auto-mirrored call sites [measured]

| Call site | glyph file | generated flag |
|---|---|---|
| `Icons.AutoMirrored.Outlined.ArrowBack` | `arrow_back` | `autoMirror = true` |
| `Icons.AutoMirrored.Filled.ArrowBack` | `arrow_back` | `autoMirror = true` |
| `Icons.AutoMirrored.Outlined.ArrowForward` | `arrow_forward` | `autoMirror = true` |
| `Icons.AutoMirrored.Filled.ArrowForward` | `arrow_forward` | `autoMirror = true` |
| `Icons.AutoMirrored.Outlined.ArrowForwardIos` | `arrow_forward_ios` | `autoMirror = true` |
| `Icons.AutoMirrored.Outlined.ArrowRight` | `arrow_right` | `autoMirror = true` |
| `Icons.AutoMirrored.Outlined.DriveFileMove` | `drive_file_move` | `autoMirror = true` |
| `Icons.AutoMirrored.Outlined.List` | `list` | `autoMirror = true` |
| `Icons.AutoMirrored.Outlined.OpenInNew` | `open_in_new` | `autoMirror = true` |
| `Icons.AutoMirrored.Outlined.PlaylistAdd` | `playlist_add` | `autoMirror = true` |
| `Icons.AutoMirrored.Outlined.PlaylistPlay` | `playlist_play` | `autoMirror = true` |
| `Icons.AutoMirrored.Outlined.Sort` | `sort` | `autoMirror = true` |
| `Icons.AutoMirrored.Outlined.TextSnippet` | `text_snippet` | `autoMirror = true` |
| `Icons.AutoMirrored.Outlined.ViewList` | `view_list` | `autoMirror = true` |

(14 rows: 12 distinct base names; `ArrowBack` and `ArrowForward` are each used in two styles.)
Five of these names **also appear in non-mirrored call sites**: `ArrowForward` (`Icons.Outlined.ArrowForward`),
`OpenInNew`, `PlaylistAdd`, `PlaylistPlay`, and `Sort` [measured: each appears both as
`AutoMirrored/Outlined/...` and as `Outlined/...` in the call-site list]. Those five are therefore
generated **twice** — once with `autoMirror = true` for the mirrored call sites and once with the
default `false` — because `Icons.AutoMirrored.Outlined.Sort` and `Icons.Outlined.Sort` are different
`ImageVector`s with identical path data. The remaining seven (`ArrowBack`, `ArrowForwardIos`,
`ArrowRight`, `DriveFileMove`, `List`, `TextSnippet`, `ViewList`) are used only in their mirrored form
[measured] and get a single `autoMirror = true` vector; generating a second, mirrored copy of those
would be a bug.

### 6.5 Why this matters for the file set

The naming rule decides the *filename* and the *fetch URL*; the trap decides the *count*. A generator
that applies the rule and stops gets 178 files and 6 silent 404s [measured]. A generator that applies
the rule plus the alias table plus the byte-dedupe plus the FILL=1 split plus the mirrored duplicates
gets **194 SVG files → 199 generated vectors (192 distinct artworks) for 184 base names / 225 real
call sites** — the number `#12` should plan against.

---

## Appendix A — End-to-end proof: one real glyph, fetched and converted

**Fetch** [measured 2026-09-18]:

```
curl -sS -o content_cut.svg -w '%{http_code} %{size_download}\n' \
  https://raw.githubusercontent.com/google/material-design-icons/27e9ef1dbeedc13d682fece4a58e1eda4cb0961a/symbols/web/content_cut/materialsymbolsrounded/content_cut_24px.svg
→ 200 723
```

(The CDN alternative, for comparison: `https://fonts.gstatic.com/s/i/short-term/release/materialsymbolsrounded/content_cut/default/24px.svg`
→ 200, 758 bytes, same `viewBox`, same geometry written with explicit `Q`/`t` pairs instead of the
repo file's `q`/`T` forms.)

**Payload** (722 bytes + newline, exactly as fetched) is quoted in §1.3.

**Parse result**: 1 `<path>`, `viewBox = 0 -960 960 960`, **70 commands**, **182 numeric literals**, all
consumed (parser invariant), command letters `M m L l q t T Z`.

**Conversion** (`bun /tmp/svg2compose.js content_cut.svg "Rounded.ContentCut"`). The full output is
**4,291 bytes** and was produced by the script, not by hand; abridged here at the middle commands:

```kotlin
    ImageVector.Builder(
            name = "Rounded.ContentCut",
            defaultWidth = 24.dp,
            defaultHeight = 24.dp,
            viewportWidth = 960.0f,
            viewportHeight = 960.0f,
        )
        .apply {
        group(translationX = 0.0f, translationY = 960.0f) {
            path(
                fill = SolidColor(Color.Black),
                fillAlpha = 1.0f,
                stroke = null,
                strokeLineWidth = 0.0f,
                strokeLineCap = Butt,
                strokeLineJoin = Miter,
                strokeLineMiter = 4.0f,
                pathFillType = NonZero,
            ) {
                moveToRelative(480.0f, -400.0f)
                lineToRelative(-94.0f, 94.0f)
                quadToRelative(8.0f, 15.0f, 11.0f, 32.0f)
                reflectiveQuadToRelative(3.0f, 34.0f)
                quadToRelative(0.0f, 66.0f, -47.0f, 113.0f)
                reflectiveQuadTo(240.0f, -80.0f)
                …
                quadToRelative(0.0f, 8.0f, 6.0f, 14.0f)
                reflectiveQuadToRelative(14.0f, 6.0f)
                close()
                moveTo(240.0f, -160.0f)
                quadToRelative(33.0f, 0.0f, 56.5f, -23.5f)
                reflectiveQuadTo(320.0f, -240.0f)
                …
                reflectiveQuadTo(240.0f, -320.0f)
                quadToRelative(-33.0f, 0.0f, -56.5f, 23.5f)
                reflectiveQuadTo(160.0f, -240.0f)
                quadToRelative(0.0f, 33.0f, 23.5f, 56.5f)
                reflectiveQuadTo(240.0f, -160.0f)
                close()
            }
        }
        }
        .build()
```

**Verification of this glyph** [measured]: inverse round trip through the Kotlin text matches the
upstream commands exactly (`m l q t q T q T … Z` in the same order with the same numbers); the
round-tripped SVG renders pixel-identical to the original in Chromium at 96 × 96 (0 differing pixels,
0 max delta); the name `content_cut` is present in the rounded `.codepoints` dictionary; the
`viewBox` is the 960-unit grid.

## Appendix B — The converter (as actually run)

`/tmp/svg2compose.js`, Bun/Node, zero dependencies, 186 lines. The essential body:

```js
const ARITY = { M: 2, L: 2, H: 1, V: 1, C: 6, S: 4, Q: 4, T: 2, A: 7, Z: 0 };
const TOKEN = /([MmLlHhVvCcSsQqTtAaZz])|([-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?)/g;

function parsePath(d) {                       // implicit repeats expanded; total-consumption asserted
  const toks = []; let m; TOKEN.lastIndex = 0;
  while ((m = TOKEN.exec(d)) !== null) toks.push(m[1] ?? Number(m[2]));
  const cmds = []; let i = 0, prev = null, total = 0;
  while (i < toks.length) {
    let cmd = toks[i];
    if (typeof cmd === "string") i++;
    else if (prev) cmd = prev === "M" ? "L" : prev === "m" ? "l" : prev;
    else throw new Error("path data does not start with a command");
    const n = ARITY[cmd.toUpperCase()];
    const args = toks.slice(i, i + n);
    if (args.length < n || args.some((a) => typeof a !== "number")) throw new Error("truncated");
    i += n; total += args.length; cmds.push({ cmd, args }); prev = cmd;
  }
  const numbersInD = toks.filter((t) => typeof t === "number").length;
  if (total !== numbersInD) throw new Error(`consumed ${total} of ${numbersInD} numbers`);
  return cmds;
}

const f = (x) => { let s = String(x); return `${s.includes(".") ? s : s + ".0"}f`; };

function emitPath(cmds) {                     // the whole SVG → Compose table
  return cmds.map(({ cmd, args: a }) => {
    const r = cmd === cmd.toLowerCase() && /[a-z]/.test(cmd) ? "Relative" : "";
    switch (cmd.toUpperCase()) {
      case "M": return `moveTo${r}(${f(a[0])}, ${f(a[1])})`;
      case "L": return `lineTo${r}(${f(a[0])}, ${f(a[1])})`;
      case "H": return `horizontalLineTo${r}(${f(a[0])})`;
      case "V": return `verticalLineTo${r}(${f(a[0])})`;
      case "C": return `curveTo${r}(${a.slice(0, 6).map(f).join(", ")})`;
      case "S": return `reflectiveCurveTo${r}(${a.slice(0, 4).map(f).join(", ")})`;
      case "Q": return `quadTo${r}(${a.slice(0, 4).map(f).join(", ")})`;
      case "T": return `reflectiveQuadTo${r}(${a.slice(0, 2).map(f).join(", ")})`;
      case "A":                                              // SVG flags → Compose booleans
        return `arcTo${r}(${f(a[0])}, ${f(a[1])}, ${f(a[2])}, ${a[3] !== 0}, ${a[4] !== 0}, ${f(a[5])}, ${f(a[6])})`;
      case "Z": return "close()";
    }
  });
}

function parseSvg(svg) {
  const vb = /viewBox="([^"]+)"/.exec(svg);
  const w = /width="([^"]+)"/.exec(svg);
  const h = /height="([^"]+)"/.exec(svg);
  const viewport = vb
    ? vb[1].split(/[\s,]+/).map(Number)                        // 960-unit dialect
    : w && h ? [0, 0, Number(w[1]), Number(h[1])] : null;      // 24-unit dialect
  const paths = [...svg.matchAll(/<path\b([^>]*)\/?>/g)].map((m) => ({
    d: /d="([^"]*)"/.exec(m[1])?.[1] ?? "",
    fill: /fill="([^"]*)"/.exec(m[1])?.[1] ?? null,
    fillRule: /fill-rule="([^"]*)"/.exec(m[1])?.[1] ?? null,
  }));
  return { viewBox: viewport, paths };
}
```

plus the Kotlin writer: `ImageVector.Builder(name, 24.dp, 24.dp, viewportWidth, viewportHeight)` with
`.apply { … }`, one `path(fill = SolidColor(Color.Black), fillAlpha = 1.0f, stroke = null,
strokeLineWidth = 0.0f, strokeLineCap = Butt, strokeLineJoin = Miter, strokeLineMiter = 4.0f,
pathFillType = NonZero|EvenOdd) { … }` per `<path>`, wrapped in
`group(translationX = -viewBoxX, translationY = -viewBoxY)` whenever the viewBox origin is not
`0 0`, then `.build()`. `autoMirror` is passed as a builder argument when the manifest marks the
glyph as auto-mirrored.

## Appendix C — Reproduction

```bash
# 1. Pin the upstream revision
gh api repos/google/material-design-icons/commits/master --jq '.sha, .commit.committer.date'

# 2. Prove the licence and the layout
curl -sS -o /dev/null -w '%{http_code} %{size_download}\n' \
  https://raw.githubusercontent.com/google/material-design-icons/master/LICENSE     # 200 11357
gh api repos/google/material-design-icons/contents/ --jq '.[].name'
gh api repos/google/material-design-icons/contents/symbols/web/content_cut/materialsymbolsrounded --jq '.[].name'

# 3. Fetch one glyph, rounded and outlined, from both routes
SHA=27e9ef1dbeedc13d682fece4a58e1eda4cb0961a
curl -sS -o rc.svg -w 'repo  %{http_code} %{size_download}\n' \
  "https://raw.githubusercontent.com/google/material-design-icons/$SHA/symbols/web/content_cut/materialsymbolsrounded/content_cut_24px.svg"
curl -sS -o cc.svg -w 'cdn   %{http_code} %{size_download}\n' \
  "https://fonts.gstatic.com/s/i/short-term/release/materialsymbolsrounded/content_cut/default/24px.svg"

# 4. Convert, then verify the round trip (script in /tmp/svg2compose.js, page in /tmp/rt/)
bun /tmp/svg2compose.js rc.svg "Rounded.ContentCut"

# 5. Name dictionary and alias check
curl -sS -o rounded.codepoints -w '%{http_code} %{size_download}\n' \
  "https://raw.githubusercontent.com/google/material-design-icons/master/variablefont/MaterialSymbolsRounded%5BFILL%2CGRAD%2Copsz%2Cwght%5D.codepoints"   # 200 79029, 4284 names

# 6. Deleted-dependency size (version from the BOM, then the artifact)
curl -sS -o bom.pom https://dl.google.com/dl/android/maven2/androidx/compose/compose-bom/2026.05.01/compose-bom-2026.05.01.pom
curl -sS -L -D - -o /dev/null \
  https://dl.google.com/dl/android/maven2/androidx/compose/material/material-icons-extended-android/1.7.8/material-icons-extended-android-1.7.8.aar | grep -i content-length
curl -sS -o mie.aar https://dl.google.com/dl/android/maven2/androidx/compose/material/material-icons-extended-android/1.7.8/material-icons-extended-android-1.7.8.aar
unzip -o -q mie.aar -d mie-aar classes.jar
unzip -l mie-aar/classes.jar | awk '$4 ~ /^androidx\/compose\/material\/icons\// {n++; s+=$1} END {print n, s}'

# 7. Regenerate the call-site → symbol table
#    scan (regex Icons\.(AutoMirrored\.)?(Default|Outlined|Rounded|Sharp|Filled|TwoTone)\.([A-Za-z0-9_]+)
#    over app/src/main/java), apply the §6.1 rule, intersect with rounded.codepoints, resolve aliases
#    by codepoint + CDN byte equality, and emit /tmp/sealplus-glyph-mapping.tsv (226 rows).
```

## Conclusion

**Pipeline.**

1. **Source** — `google/material-design-icons` (Apache-2.0, `master`), per glyph:
   `symbols/web/<glyph>/materialsymbolsrounded/<glyph>_{24px,fill1_24px}.svg`, pinned at revision
   `27e9ef1dbeedc13d682fece4a58e1eda4cb0961a`; `fonts.gstatic.com` is an acceptable convenience mirror
   but is unversioned, and 6 of the app's names resolve only through the alias table. Names come from
   `variablefont/MaterialSymbolsRounded[FILL,GRAD,opsz,wght].codepoints` (4,284 names).
2. **Tooling** — a ~190-line in-repo script (`tools/svg2compose.js`, Appendix B) that reads `viewBox`
   with a `width`/`height` fallback, maps 13–19 SVG commands to `PathBuilder` calls 1:1 (verified
   against `PathBuilder.kt` and Google's own `vector/PathNode.kt`), keeps upstream coordinates and
   wraps the 960-unit grid in `group(translationY = 960f)`, and emits
   `ImageVector.Builder(name, 24.dp, 24.dp, viewportWidth, viewportHeight, autoMirror)`, one
   `path(fill = SolidColor(Color.Black), …)` per layer. No external converter, no
   `material-icons-core` dependency: the ~35-line `materialIcon`/`materialPath` helper is optional and
   has Google's own precedent in material3's internal `Icons.kt`.
3. **Output location** — `app/src/main/java/com/junkfood/seal/ui/svg/symbols/`, one committed Kotlin
   file per glyph, plus `object SealSymbols { object Rounded { … } }`, with
   `tools/material-symbols.manifest.tsv` recording glyph, variant, codepoint, `auto_mirror` and the
   upstream URL per file. Generated, then treated as source.
4. **Naming rule** — `camelCase → snake_case` with digit-aware boundaries (§6.1); verified 183/184
   names against the rounded dictionary with 1 non-call-site miss; plus the four rules that the naive
   rule does not cover: `Default` ≡ `Filled`, Material-Icons artwork ≠ Material-Symbols artwork,
   `autoMirror` as a builder flag (no `_mirrored` names upstream), and the 6-name alias table.

**Glyph count.** Enumeration: `Icons\.(AutoMirrored\.)?(Default|Outlined|Rounded|Sharp|Filled|TwoTone)\.([A-Za-z0-9_]+)`
over the 165 `.kt` files under `app/src/main/java` → **78 files**, 226 call-site names, 184 base names,
**225 real call sites** (one KDoc false positive at `GradientDarkExample.kt:199`). What the migration
commits under Plan A: **194 SVG files → 199 generated vectors (192 distinct artworks) for 184 base
names** — 178 FILL=0 files, 16 additional distinct FILL=1 files, and 5 mirrored duplicates; or 178
files / 183 vectors if `#12` prefers a single fill variant (§3.3). Cost, measured as source: 382,032 B
with a local helper (1,920 B/vector); estimated as compiled ≈1.46 MiB uncompressed class `[estimate]`.
The deleted dependency, measured: 35,720,998 B AAR, 11,117 icon classes, 85,390,331 B uncompressed,
frozen at 1.7.8 while the rest of Compose in the same BOM is 1.11.2. The APK delta is small because
R8 already strips unreferenced icons today (`app/build.gradle.kts:97-98`) `[INFERENCE, unmeasured]`;
the real win is build cost and dependency hygiene, not APK size.

**Verification step.** Three gates, all cheap and two already run here: (i) the script must fail on a
missing glyph file and check dictionary membership + `viewBox` grid; (ii) exact path-data equality —
inverse round trip through the generated Kotlin, **194/194 SVG files exact** (the 5 mirrored duplicates
reuse verified path data and differ only in the flag); (iii) rendered pixel comparison —
**194/194 glyphs pixel-identical in Chromium at 96 × 96, 0 blank**; then in-app, extend
`ui/svg/VectorPreviews.kt` with a grid preview at 24 dp to compare against the Material Symbols tiles,
and a `@Preview(locale = "ar")` for the `autoMirror` vectors. AndroidX's own equivalent
(`ExtendedIconComparisonTest`) is the precedent for the screenshot level.

**Maintenance cost.** Adding a glyph: ~5 minutes, one manifest row plus one script run plus a ~1.9 KB
diff. Upstream updates: invisible by default — there is no dependency to bump — so the pinned SHA and
a `--check` diff mode are the only way the app notices; a full re-export is up to 194 files /
382,032 B of review. A renamed or removed glyph upstream fails loudly on the 404 and resolves through
the alias table (the measured instance: 6 names today). Four things must stay in the manifest or they
drift: the alias table, the `autoMirror` set (12 names → 17 vectors), the 27 FILL=1 choices, and the
pinned revision.
