# Material 3 Expressive API surface at the pinned Compose BOM (2026.05.01)

**Method (one line).** Every claim below comes from the artifact bytes of the resolved
Google Maven artifacts (AAR `classes.jar`, AndroidManifest, Gradle `.module`, `-sources.jar`)
and from first-party release notes; no repository file was modified and no build was run.

Pinned by `gradle/libs.versions.toml`: `androidxComposeBom = "2026.05.01"`, `kotlin = "2.3.21"`,
`androidGradlePlugin = "9.2.1"`, `graphics = "1.1.0"` (`androidx.graphics:graphics-shapes`,
declared but imported by nothing), app `compileSdk`/`targetSdk` 37, `minSdk` 24.
Artifacts were unpacked under a transient `/tmp` directory, so the paths in the commands
below are placeholders; every command is re-runnable as written. The two durable artifacts
are this report and `research/evidence/material3-1.4.0-optin-dump.txt`.

---

## 1. BOM resolution

Command (exact):

```
curl -fsSL https://dl.google.com/dl/android/maven2/androidx/compose/compose-bom/2026.05.01/compose-bom-2026.05.01.pom
```

| Coordinate the BOM pins | Version | App already declares it? |
|---|---|---|
| `androidx.compose.material3:material3` / `-android` | **1.4.0** | yes (`libs.androidx.compose.material3`, in `androidxCompose` bundle) |
| `androidx.compose.material3:material3-window-size-class` / `-android` | 1.4.0 | yes (catalog; used by `MainActivity`, `QuickDownloadActivity`) |
| `androidx.compose.material3:material3-adaptive-navigation-suite` / `-android` | 1.4.0 | **no** |
| `androidx.compose.material3.adaptive:adaptive` / `-android` | 1.2.0 | **no** |
| `androidx.compose.material3.adaptive:adaptive-layout` / `-android` | 1.2.0 | **no** |
| `androidx.compose.material3.adaptive:adaptive-navigation` / `-android` | 1.2.0 | **no** |
| `androidx.compose.foundation:foundation` / `-android` | 1.11.2 | yes (bundle) |
| `androidx.compose.ui:ui` / `-android` | 1.11.2 | yes (bundle) |
| `androidx.compose.runtime:runtime` | 1.11.2 | yes (bundle) |
| `androidx.compose.material:material-icons-extended` / `-android` | 1.7.8 | yes (bundle) |
| `androidx.compose.material:material-icons-core` / `-android` | 1.7.8 | no (material3 1.4.0 no longer depends on it) |
| `androidx.graphics:graphics-shapes` | **not pinned at all** | catalog declares it at 1.1.0, unused |
| any `androidx.window:*` | not pinned | comes transitively from the adaptive artifacts |

Cross-check that no `androidx.graphics` entry hides in the BOM:

```
curl -fsSL .../compose-bom-2026.05.01.pom | tr '\n' ' ' | sed 's|</dependency>|\n|g' |
  sed 's/<[^>]*>/ /g' | tr -s ' ' | awk '$2=="androidx.graphics"'   # -> no output
```

**Answer to question 1:** the BOM pins `material3 1.4.0`, and that artifact does **not** carry
the expressive component APIs. 1.4.0 is the release in which they were deliberately removed
(see §6); they live on the 1.5.0-alpha line. There is no lockfile in the repository and none
was needed: the BOM POM plus the artifact metadata are the resolution.

---

## 2. The listed APIs at `material3-android 1.4.0` (and `material3-adaptive-navigation-suite-android 1.4.0`)

Artifacts fetched with:

```
curl -fsSL -O https://dl.google.com/dl/android/maven2/androidx/compose/material3/material3-android/1.4.0/material3-android-1.4.0.aar
unzip -o -q material3-android-1.4.0.aar classes.jar -d m3
javap -v -p -cp m3/classes.jar androidx.compose.material3.<Class>
```

Two visibility traps apply to every "present" row. First, a Kotlin `internal` declaration is
still a **public JVM symbol** in `javap` output; it is not callable from app code. Second,
`javap` cannot show the opt-in marker for an `internal` declaration, because the marker itself
(`ExperimentalMaterial3ExpressiveApi`) is `internal annotation class` in 1.4.0
(`commonMain/.../ExperimentalMaterial3ExpressiveApi.kt:24`). On that artifact, **no class in
the whole `classes.jar` references that marker** (scan below), while the positive control on
`material3-android-1.4.0-alpha18` finds it in 54 classes:

```
cd m3c && awk 'FNR==1{ if (hit) c++; hit=0 } index($0,"ExperimentalMaterial3ExpressiveApi")>0 {hit=1}
  END{ if(hit) c++; print c+0 }' $(find . -name '*.class')      # 1.4.0 -> 1 ; its own marker class only
                                                               # alpha18 -> 54 (positive control)
```

| API | Owning artifact and version | Present? | Opt-in marker required | Min API | Evidence |
|---|---|---|---|---|---|
| `MaterialExpressiveTheme` | `androidx.compose.material3:material3-android:1.4.0` | **present, but `internal`** — not callable | n/a (internal) | 24 (app floor) | `javap -p -cp m3/classes.jar androidx.compose.material3.MaterialThemeKt` prints `public static final void MaterialExpressiveTheme(ColorScheme, MotionScheme, Shapes, Typography, content)`; the matching source is `internal fun MaterialExpressiveTheme` — `unzip -p material3-android-1.4.0-sources.jar commonMain/androidx/compose/material3/MaterialTheme.kt` line 185. Absent from the public API file (below). |
| `MaterialTheme.motionScheme` | `material3-android:1.4.0` | **present, but `internal`** — not callable | n/a (internal) | 24 | `javap -p -cp m3/classes.jar androidx.compose.material3.MaterialTheme` prints `public final MotionScheme getMotionScheme(Composer,int)`; source says `internal val motionScheme` (`MaterialTheme.kt:141`). The composition local is internal too (`internal val LocalMotionScheme`, same file line 155), which is why its accessor is name-mangled: `getLocalMotionScheme$material3()`. Note that lack of mangling does not prove visibility: `getMotionScheme` is unmangled while the declaration is `internal`. |
| `MotionScheme` (type, `standard()`, `expressive()`) | `material3-android:1.4.0` | **present, but `internal`** — not callable | n/a (internal) | 24 | `javap -p -cp m3/classes.jar androidx.compose.material3.MotionScheme` = `public interface MotionScheme`; source `MotionScheme.kt:42` = `internal interface MotionScheme`. Factories are mangled: `javap -p -cp m3/classes.jar 'androidx.compose.material3.MotionScheme$Companion'` → `standard$material3()`, `expressive$material3()`. |
| expressive typography styles (`displayLargeEmphasized` …) | `material3-android:1.4.0` | **present, but `internal`** — not callable | n/a (internal) | 24 | `javap -p -cp m3/classes.jar androidx.compose.material3.Typography` prints mangled getters `getDisplayLargeEmphasized$material3()` …; the 30-parameter constructor is `internal constructor` (`Typography.kt:87-88`). A **public** constructor and `copy(...)` that take all 30 styles do exist (`Typography.kt:220`, `:337`, both carrying an internal `@OptIn`), so a caller may supply its own emphasized styles — it just cannot read the library defaults. The 15-parameter `Typography(...)` and `copy(...)` **are public and stable**. |
| `ButtonGroup` | — (no owner at this version) | **absent** | n/a | n/a | `unzip -l m3/classes.jar \| grep -i buttongroup` → only `androidx/compose/material3/tokens/ButtonGroupSmallTokens.class` and `tokens/ConnectedButtonGroupSmallTokens.class` (private token objects). No `ButtonGroupKt`. No `ButtonGroupKt.kt` in `material3-android-1.4.0-sources.jar`. |
| `SplitButton` | — | **absent** | n/a | n/a | `unzip -l m3/classes.jar \| grep -i splitbutton` → only `tokens/SplitButton{Small,Medium,Large,XLarge,XSmall}Tokens.class`. No `SplitButtonKt`. |
| `FloatingActionButtonMenu` | — | **absent** | n/a | n/a | `unzip -l m3/classes.jar \| grep -i floatingactionbutton` → `FloatingActionButtonKt` with `FloatingActionButton`, `Small/Large/ExtendedFloatingActionButton` only; no `FloatingActionButtonMenuKt` or `…Scope`. |
| `LoadingIndicator` | — | **absent** as a component | n/a | n/a | `unzip -l m3/classes.jar \| grep -i loadingindicator` → only `tokens/LoadingIndicatorTokens.class`. The only public name collision is the pull-to-refresh metric `PullToRefreshDefaults.getLoadingIndicatorElevation-D9Ej5fM()` (`javap -p -cp m3/classes.jar androidx.compose.material3.pulltorefresh.PullToRefreshDefaults`). No `LoadingIndicatorKt`, no `LoadingIndicatorDefaults`. |
| `HorizontalFloatingToolbar` | — | **absent** | n/a | n/a | `unzip -l m3/classes.jar \| grep -i horizontalfloating` → no output. Only `tokens/FloatingToolbarTokens.class` and `tokens/DockedToolbarTokens.class`. `FlexibleBottomAppBar` is built from the docked-toolbar tokens (`AppBar.kt:2169`). |
| `ShortNavigationBar` | `material3-android:1.4.0` | **present, public, stable** | none — `stable` | 24 (app floor; AAR manifest says 21) | `javap -p -cp m3/classes.jar androidx.compose.material3.ShortNavigationBarKt` → `ShortNavigationBar-kQ6Tpik`, `ShortNavigationBarItem-6ZDA4I0`; `-v` shows only `@Composable` / `@ComposableInferredTarget`. Source `ShortNavigationBar.kt:94-95` = plain `fun ShortNavigationBar(`. Also public: `ShortNavigationBarDefaults`, `ShortNavigationBarItemDefaults`, `ShortNavigationBarArrangement`. In the published API file both methods carry no opt-in tag. |
| `FlexibleBottomAppBar` | `material3-android:1.4.0` | **present, but `internal`** — not callable | n/a (internal) | 24 | `javap -p -cp m3/classes.jar androidx.compose.material3.AppBarKt` prints `public static final void FlexibleBottomAppBar-wBhsO_E(...)`, but the source is `internal fun FlexibleBottomAppBar(` (`AppBar.kt:1286-1287`). The public `BottomAppBar` overloads exist: two are `@ExperimentalMaterial3Api`, two are stable (`javap -v … AppBarKt`). |
| `WideNavigationRail` | `material3-android:1.4.0` | **present, public, stable** | none — `stable` | 24 (AAR manifest says 21) | `javap -v -p -cp m3/classes.jar androidx.compose.material3.WideNavigationRailKt` → `WideNavigationRail`, `ModalWideNavigationRail-k3FuEkE`, `WideNavigationRailItem-pli-t6k`, all with only `@Composable`; `rememberWideNavigationRailState` in `WideNavigationRailStateKt`. No `ExperimentalMaterial3Api` anywhere in that class dump. |
| `ToggleButton` | — | **absent** | n/a | n/a | `unzip -l m3/classes.jar \| grep -i togglebutton` → `DatePickerKt$DisplayModeToggleButton$1`, `IconButtonKt$SurfaceIconToggleButton$2`, `IconToggleButtonColors` only. No `ToggleButtonKt`, no `ToggleButtonDefaults`. Nearest public equivalent present and stable: the `IconToggleButton` family in `IconButtonKt` (`IconToggleButton`, `FilledIconToggleButton`, `FilledTonalIconToggleButton`, `OutlinedIconToggleButton`) plus `IconButtonDefaults.*ToggleButton*` colors. |
| new `Slider` overloads | `material3-android:1.4.0` | **present** — stateless: stable; state-based and thumb/track-slot: opt-in | stateless `stable`; `Slider(state: SliderState, …)`, `Slider(value, …, thumb, track, …)`, `rememberSliderState`, `VerticalSlider` → `androidx.compose.material3.ExperimentalMaterial3Api` | 24 | `javap -v -p -cp m3/classes.jar androidx.compose.material3.SliderKt`; source `Slider.kt:181-182` (stable), `:271-273` (`@ExperimentalMaterial3Api`), `:354-356` (`@ExperimentalMaterial3Api`), `:414-415` (`internal fun VerticalSlider`). API file marks the same overloads. |
| new `RangeSlider` overloads | `material3-android:1.4.0` | **present** — stateless: stable; state-based and start/end-thumb slots: opt-in | stateless `stable`; `RangeSlider(state: RangeSliderState, …)`, `RangeSlider(value, …, startThumb, endThumb, track)`, `rememberRangeSliderState` → `ExperimentalMaterial3Api` | 24 | `javap -v -p -cp m3/classes.jar androidx.compose.material3.SliderKt`; source `Slider.kt:489-490` (stable), `:591-593` and `:697-699` (`@ExperimentalMaterial3Api`). API file marks the same overloads. |
| `MaterialShapes` | — | **absent** | n/a | n/a | `unzip -l m3/classes.jar \| grep -i materialshapes` → no output; no `MaterialShapes.kt` in the sources jar. Present only in `material3-android-1.4.0-alpha18` and `-beta01` (5 class files each), gone from `-beta02`, `-rc01` and `1.4.0`. It is **not** in `androidx.graphics:graphics-shapes:1.1.0` either (`unzip -l gs/classes.jar \| grep -i materialshapes` → no output; that AAR has `Morph`, `RoundedPolygon`, `RoundedPolygonKt` only). |

Second, independent route for two rows (required cross-check): the first-party API-surface file
for the 1.4.0 line, `compose/material3/material3/api/1.4.0-beta01.txt` of `androidx/androidx`.

```
curl -fsSL https://raw.githubusercontent.com/androidx/androidx/androidx-main/compose/material3/material3/api/1.4.0-beta01.txt
```

* `ShortNavigationBarKt` / `WideNavigationRailKt` are present there as
  `method @androidx.compose.runtime.Composable public static void ShortNavigationBar(…)` /
  `… WideNavigationRail(…)` — **no** opt-in tag, matching `javap`.
* `SliderKt` shows both: `method @androidx.compose.runtime.Composable public static void Slider(float value, …)`
  and `method @SuppressCompatibility @androidx.compose.material3.ExperimentalMaterial3Api @androidx.compose.runtime.Composable public static void Slider(androidx.compose.material3.SliderState state, …)`.
* `MaterialExpressiveTheme`, `MotionScheme`, `FlexibleBottomAppBar`, `MaterialShapes`,
  `SplitButton`, `ButtonGroup`, `FloatingActionButtonMenu` have **zero** hits in that file, which
  is the public surface; the fourth backstop, the generated reference page, dates them later:
  `…/reference/kotlin/androidx/compose/material3/MaterialExpressiveTheme.composable` and
  `…/MotionScheme` both print `Added in 1.5.0-alpha28`.

---

## 3. Artifact map — what must be added to the version catalog besides `material3`

| Artifact | Version | Why |
|---|---|---|
| `androidx.compose.material3:material3` | BOM → 1.4.0 | already declared; owns every *usable* row in §2 |
| `androidx.compose.material3:material3-window-size-class` | BOM → 1.4.0 | already declared and used; keep |
| `androidx.compose.material3:material3-adaptive-navigation-suite` | BOM → 1.4.0 | **new** — the only owner of `NavigationSuiteScaffold` |
| `androidx.compose.material3.adaptive:adaptive` | BOM → 1.2.0 | **new** — `WindowAdaptiveInfo`, `currentWindowAdaptiveInfo()` |
| `androidx.compose.material3.adaptive:adaptive-layout` | BOM → 1.2.0 | **new** — `ListDetailPaneScaffold`, `SupportingPaneScaffold` |
| `androidx.compose.material3.adaptive:adaptive-navigation` | BOM → 1.2.0 | **new** — `rememberListDetailPaneScaffoldNavigator`, `rememberSupportingPaneScaffoldNavigator` |
| `androidx.graphics:graphics-shapes` | 1.1.0 (catalog entry, no BOM pin) | **not needed** — imported by no source file; material3 1.4.0 does not depend on it (removed in 1.4.0-beta02); and it contains no `MaterialShapes` |

Everything else already resolves through the BOM. There is **no** separate "expressive"
artifact to add: `androidx/compose/material3/group-index.xml` has no `material3-expressive`
coordinate, and the BOM lists none. Dependency facts, from the Gradle metadata (not the lossy POM):

```
curl -fsSL https://dl.google.com/dl/android/maven2/androidx/compose/material3/material3-android/1.4.0/material3-android-1.4.0.module
```

`androidRuntimeElements-published` requires: `androidx.activity:activity-compose:1.8.2`,
`androidx.annotation:annotation:1.8.1`, `androidx.compose.animation:animation-core:1.8.1`,
`androidx.compose.foundation:foundation:1.8.1`, `foundation-layout:1.8.1`,
`androidx.compose.material:material-ripple:1.8.1`, `androidx.compose.runtime:runtime:1.9.0`,
`androidx.compose.ui:ui:1.8.2`, `ui-text:1.8.1`, `ui-util:1.8.1`,
`androidx.lifecycle:lifecycle-common-java8:2.6.1`, `androidx.collection:collection:1.4.5`.
No `androidx.graphics` entry and no `material-icons-core` entry — both removals are announced
in the release notes (§6).

---

## 4. The adaptive answer

Same columns, for the BOM-resolved adaptive artifacts
(`adaptive-android-1.2.0.aar`, `adaptive-layout-android-1.2.0.aar`,
`adaptive-navigation-android-1.2.0.aar`, `material3-adaptive-navigation-suite-android-1.4.0.aar`;
`javap -v -p -cp <dir>/classes.jar <class>`).

| API | Owning artifact and version | Present? | Opt-in marker required | Min API | Evidence |
|---|---|---|---|---|---|
| `NavigationSuiteScaffold` | `material3-adaptive-navigation-suite-android:1.4.0` | present, public, **stable** | none — `stable` | 24 (AAR manifest says 21) | `javap -v -p -cp navsuite/classes.jar androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffoldKt` → `NavigationSuiteScaffold-*`, `NavigationSuiteScaffoldLayout-*`, `NavigationSuiteItem-*`, `rememberNavigationSuiteScaffoldState`, `NavigationSuite` with only `@Composable`; `grep ExperimentalMaterial3AdaptiveNavigationSuiteApi` over the whole `classes.jar` hits **only the marker's own class file**. The navsuite API file marks no member with it. |
| `ListDetailPaneScaffold` | `adaptive-layout-android:1.2.0` | present, public | `androidx.compose.material3.adaptive.ExperimentalMaterial3AdaptiveApi` | 24 (AAR manifest says 23) | `javap -v -p -cp adaptl/classes.jar androidx.compose.material3.adaptive.layout.ListDetailPaneScaffoldKt` → `RuntimeInvisibleAnnotations: androidx.compose.material3.adaptive.ExperimentalMaterial3AdaptiveApi`. |
| `SupportingPaneScaffold` | `adaptive-layout-android:1.2.0` | present, public | `ExperimentalMaterial3AdaptiveApi` | 24 | `javap -v -p -cp adaptl/classes.jar androidx.compose.material3.adaptive.layout.SupportingPaneScaffoldKt` — same annotation on both overloads. |
| `AdaptiveInfo` | — | **the name does not exist** | n/a | n/a | `unzip -l` over all five `classes.jar`s for `/AdaptiveInfo.class` → no match. The type is `androidx.compose.material3.adaptive.WindowAdaptiveInfo` (`adapt/classes.jar`), read via `currentWindowAdaptiveInfo(boolean, Composer, int, int)` — that function is **stable** (`javap -v` shows only `@Composable`) — and `currentWindowDpSize(Composer,int)`, which is `@ExperimentalMaterial3AdaptiveApi`. (`adaptive 1.0.0` and `1.2.0` both ship `WindowAdaptiveInfo`, never `AdaptiveInfo`.) |
| `rememberListDetailPaneScaffoldNavigator`, `rememberSupportingPaneScaffoldNavigator` | `adaptive-navigation-android:1.2.0` | present, public | `ExperimentalMaterial3AdaptiveApi` | 24 | `javap -v -p -cp adaptn/classes.jar androidx.compose.material3.adaptive.navigation.ThreePaneScaffoldNavigatorKt` — both carry the annotation; `ThreePaneScaffoldNavigator` and `ThreePaneScaffoldPredictiveBackHandler` come from the same artifact. |

Release-note anchor for the adaptive line: the 1.2.0 entry (October 22, 2025) on
https://developer.android.com/jetpack/androidx/releases/compose-material3-adaptive lists
`PaneScaffoldScope.preferredHeight`, the reflow/levitate strategies and
"Make `currentWindowAdaptiveInfo()` function support large and extra-large window width size
classes". Version pairing for this BOM: adaptive **1.2.0**, adaptive-navigation-suite **1.4.0**
(the latter's own metadata requires `material3:1.4.0` and `adaptive:1.1.0`, and the BOM lifts
`adaptive` to 1.2.0).

---

## 5. Platform constraints

| Constraint | Resolved value | Source |
|---|---|---|
| AAR `minSdkVersion` — `material3-android:1.4.0`, `material3-adaptive-navigation-suite-android:1.4.0`, `material3-window-size-class-android:1.4.0` | 21 | `unzip -p <aar> AndroidManifest.xml` |
| AAR `minSdkVersion` — `adaptive`, `adaptive-layout`, `adaptive-navigation` 1.2.0, and `graphics-shapes` 1.1.0 | 23 | same |
| Per-API floor above the app's `minSdk 24` | **none for any listed API** | No `@RequiresApi` / `@RequiresExtension` on any listed symbol. Only **8** class files in the whole `material3-android-1.4.0` artifact mention `RequiresApi`/`RequiresExtension` (dynamic-color 31/34, `DatePicker.jvm.kt` helpers 26, `Locale24` 24, `CalendarModelImpl` 26, `ModalWideNavigationRail` API 33/34 impls, `Listener$Api33Impl` 33); the three adaptive artifacts have **0**. Scan: `awk 'index($0,"RequiresApi")>0||index($0,"RequiresExtension")>0'` per class file. |
| `compileSdk` floor | `minCompileSdk=35` for all five material3 artifacts (`minCompileSdk=34` for `graphics-shapes`) — satisfied by `compileSdk = 37` | `unzip -p <aar> META-INF/com/android/build/gradle/aar-metadata.properties` |
| AGP floor | `minAndroidGradlePluginVersion=8.6.0` (`8.1.1` for `graphics-shapes`) — satisfied by AGP 9.2.1 | same file |
| Java level | Class files are major version **52** (Java 8) in `material3 1.4.0`, `material3-adaptive-navigation-suite 1.4.0` and `adaptive-layout 1.2.0` — no Java 21 floor; the app's Java 21 toolchain is fine | `javap -v … \| grep 'major version'` |
| Kotlin / Compose compiler | The app uses the Compose Compiler Gradle plugin (`org.jetbrains.kotlin.plugin.compose`, version = `kotlin` = 2.3.21). The compatibility map states the plugin is for Kotlin **2.0.0+** — https://developer.android.com/jetpack/androidx/releases/compose-kotlin. The library's Kotlin metadata is `mv=[2,0,0]`. | reference page above; `kotlin.Metadata` in the class files |

---

## 6. Known breakage and changes at the resolved version

All quotes are first-party release notes:
https://developer.android.com/jetpack/androidx/releases/compose-material3

| Item | Version | Consequence for this app |
|---|---|---|
| **"All public APIs tagged with `ExperimentalMaterial3ExpressiveApi` or `ExperimentalMaterial3ComponentOverrideApi` have been removed, please switch to `1.5.0-alpha` to continue enjoying these features."** | 1.4.0-beta01 (Jul 30, 2025) | The single most important fact. The expressive component set (`ButtonGroup`, `SplitButton`, `FloatingActionButtonMenu`, `LoadingIndicator`, `HorizontalFloatingToolbar`, `ToggleButton`, `MaterialShapes`) is not in 1.4.0 at all. |
| "Remove `graphics-shapes` dependency" ([b/436230765](https://issuetracker.google.com/issues/436230765)) | 1.4.0-beta02 (Aug 13, 2025) | `MaterialShapes` disappears with it (present in alpha18/beta01, absent from beta02 onward). Nothing in the app consumes `graphics-shapes`. |
| "This library no longer adds a dependency to `material-icons-core`" ([b/349894318](https://issuetracker.google.com/issues/349894318)) | 1.4.0 | The app declares `material-icons-extended` explicitly, so it is unaffected; do not rely on `material-icons-core` arriving transitively. |
| "`NavigationBarItem` and `NavigationRailItem`'s active label color change from `onSurface` to secondary" | 1.4.0 | Visual change in navigation bars/rails; revert recipe in the notes (`selectedTextColor = MaterialTheme.colorScheme.onSurface`). |
| "Material 3 components are now using the new `MotionScheme` to define their motion" and "Indeterminate circular Progress Indicator motion changes" | 1.4.0 | The app has 31 progress-indicator call sites (23 `CircularProgressIndicator`, 8 `LinearProgressIndicator`; counted over `app/src/main/java/**/*.kt`), so the indicator motion change is visible; `MotionScheme` itself is **not** reachable (internal, §2). |
| "Fixed wrong content padding of wide navigation rail. Bottom padding is now 0." | 1.5.0-alpha26 | `WideNavigationRail` at 1.4.0 has the wrong bottom content padding; the notes give the revert/pre-set value `contentPadding = PaddingValues(0.dp, 44.dp, 0.dp, 44.dp)` (and `WideNavigationRail.kt:1141` uses `NavigationRailCollapsedTokens.TopSpace` for both ends). |
| "Fixed `RangeSlider` and Slider keyboard navigation" / "[Slider] Fixed keyboard navigation for Slider" ([b/424845268](https://issuetracker.google.com/issues/424845268), [b/422942624](https://issuetracker.google.com/issues/422942624)) | 1.5.0-alpha02, -alpha06 | Confirms the 1.4.0 defect: in the 1.4.0 sources only the single-thumb `Slider` wires key events (`slideOnKeyEvents` appears once, `Slider.kt:796`); the `RangeSlider` thumbs get `.focusable(...)` with no key handling (`Slider.kt:999`, `:1015`). |
| "Deprecated stateless `Slider` and `RangeSlider` overloads in favor of their stateful versions" | 1.5.0-alpha28 | The *stable* overloads that 1.4.0 offers are already on a deprecation path; the stateful replacements are only in the alpha line and are `@ExperimentalMaterial3Api`. |
| "Promoted `BottomAppBar` and its associated methods to stable. These APIs no longer require the `@ExperimentalMaterial3Api` opt-in." | 1.5.0-alpha26 | At 1.4.0 two of the four `BottomAppBar` overloads still carry the marker. The app's call site (`VideoListPage.kt:377`) passes only `modifier` plus a trailing content lambda and no `scrollBehavior`, so it does not select the `scrollBehavior` overload that carries the marker; confirm at build time. |
| "Re-add `@ExperimentalMaterial3Api` annotation to `AppBarWithSearch` APIs"; `ExposedDropdownMenu` crash fixes; `ButtonGroup` compression-animation crash ([b/516743181](https://issuetracker.google.com/issues/516743181)) | 1.5.0-alpha22 … -alpha26 | Churn on the alpha line only; the `ButtonGroup` crash cannot affect 1.4.0 because the component is absent there. |

---

## 7. Avoid list — 14 things not to build on at these versions

1. `MaterialExpressiveTheme` — `internal` in 1.4.0; javap shows it only because Kotlin `internal` compiles to a public JVM symbol.
2. `MaterialTheme.motionScheme` — `internal val`; the composition local is name-mangled (`getLocalMotionScheme$material3`).
3. `MotionScheme` (the type and its `standard()` / `expressive()` factories) — `internal interface`, mangled factories; you cannot name the type at all.
4. Expressive typography styles (`displayLargeEmphasized` … `labelSmallEmphasized`) — `internal` getters; the 30-argument `Typography` constructor is `internal`. Use the 15-parameter `Typography(...)` / `copy(...)`, which are public and stable.
5. `FlexibleBottomAppBar` — `internal fun`, despite being listed as a component. Use the public `BottomAppBar` overloads (two of the four need `@ExperimentalMaterial3Api`).
6. `ButtonGroup` — absent; only private `tokens/ButtonGroupSmallTokens` and `tokens/ConnectedButtonGroupSmallTokens` remain.
7. `SplitButton` — absent; only private `tokens/SplitButton*Tokens` remain.
8. `FloatingActionButtonMenu` — absent; no facade class in the artifact.
9. `LoadingIndicator` — absent as a component; only `tokens/LoadingIndicatorTokens`, plus the unrelated `PullToRefreshDefaults.LoadingIndicatorElevation` metric.
10. `HorizontalFloatingToolbar` — absent; only `tokens/FloatingToolbarTokens` and `tokens/DockedToolbarTokens` remain.
11. `ToggleButton` — absent; there is no `ToggleButtonKt`. Use the stable `IconToggleButton` family or `SegmentedButton`.
12. `MaterialShapes` — absent at 1.4.0 (removed between `-beta01` and `-beta02` with the `graphics-shapes` dependency) and **also** not in `androidx.graphics:graphics-shapes:1.1.0`, so adding that catalog entry does not bring it back.
13. The **new state-based** `Slider` / `RangeSlider` overloads (`Slider(state = …)`, `RangeSlider(state = …)`, the `thumb`/`track` and `startThumb`/`endThumb` slot overloads, `rememberSliderState`, `rememberRangeSliderState`) — public but `@ExperimentalMaterial3Api`, and their stateless cousins are already deprecated on 1.5.0-alpha28. Prefer the stateless overloads and revisit after the API settles.
14. `ListDetailPaneScaffold`, `SupportingPaneScaffold` and the `remember*PaneScaffoldNavigator` functions — public but `@ExperimentalMaterial3AdaptiveApi`; for a screen-by-screen migration of the size contemplated, `NavigationSuiteScaffold` (stable) is the only adaptive API with no opt-in.

---

## 8. What this means for the migration (8 lines)

1. At BOM 2026.05.01, **12 of the 16 listed APIs cannot be used**: 7 are absent outright (`ButtonGroup`, `SplitButton`, `FloatingActionButtonMenu`, `LoadingIndicator`, `HorizontalFloatingToolbar`, `ToggleButton`, `MaterialShapes`) and 5 exist only as Kotlin `internal` (`MaterialExpressiveTheme`, `MaterialTheme.motionScheme`, `MotionScheme`, the emphasized typography styles, `FlexibleBottomAppBar`).
2. There is no "add the expressive artifact" fix; the removal is deliberate at 1.4.0-beta01, and the features live on `1.5.0-alpha`.
3. What *is* available now, with no opt-in: `ShortNavigationBar`, `WideNavigationRail` (+ `ModalWideNavigationRail`), the stateless `Slider`/`RangeSlider`, the `IconToggleButton` family, `SegmentedButton`, and `NavigationSuiteScaffold` from `material3-adaptive-navigation-suite:1.4.0`.
4. So Phase 1 can start today on layout, navigation and toggle surfaces, using only stable APIs and no new artifacts except the adaptive-navigation-suite coordinate.
5. Everything expressive — `MaterialExpressiveTheme` + `MotionScheme`, `SplitButton`, `ButtonGroup`, `LoadingIndicator`, `HorizontalFloatingToolbar`, `FloatingActionButtonMenu`, `ToggleButton`, `MaterialShapes` — needs a BOM bump to the 1.5.0-alpha line, which also brings the `material3-ripple` split and Compose 1.12/1.13-alpha dependencies.
6. Treat 1.4.0 as the "stable, no-expressive" baseline; treat 1.5.0-alpha as a separate, experimental track with its own opt-in markers and its own churn.
7. Budget for two known 1.4.0 defects if those components are used: `WideNavigationRail` bottom content padding, and `RangeSlider` keyboard navigation.
8. Do not add `androidx.graphics:graphics-shapes` to any bundle: nothing imports it and it does not contain `MaterialShapes`.

Raw `javap` annotation output for every "present" row above:
`research/evidence/material3-1.4.0-optin-dump.txt`.
