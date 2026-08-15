# HanClip iOS Matchup Reference Audit

## Evidence decision

- Source of truth: current dirty iOS working tree at `HEAD 31e60ec5`, app `1.0.1 (3.11.47)`.
- Stable paired-ready captures: `HOME.empty.dark`, `COPYRIGHT.collapsed.dark`, `COPYRIGHT.expanded.dark`.
- Partial captures: `HOME.empty.automatic-light` and `MEDIA_MENU.open.automatic-light`. Their content, colors, card dimensions, and menu anatomy are usable, but their page vertical geometry is excluded because the initial automatic-light content is displaced about `111pt` relative to the same source after a dark-theme refresh.
- Partial captures: both `BROWSER` captures. The app-owned chrome/panel is valid evidence, but the embedded web page is network-owned and unstable.
- Not captured in this pass: theme notice/panel, populated fixtures, media permission/selection, editor and downstream production flows. The pass stopped when another task booted the shared CoreSimulator device; no parity-complete claim is allowed.
- Exact source values may be used for tokens and geometry. Screenshot-only visual estimates must not replace source values.
- The PNGs were captured before one accessibility-only correction: the theme hint is now attached only to `HanClipHeaderPill`, not the entire `rootTopHeader`. This has no visual-pixel impact, so the PNGs remain valid for visual comparison. A final build and runtime accessibility trace are still required before calling that semantic fix verified.

## Primary paired profile correction

The fresh iOS state is **theme mode `automatic` under system light**, not the explicit `Light Mode` theme.

- Automatic/system-light: primary `#072931`, secondary `#007E81`, light system background.
- Explicit Light Mode is a separate theme state: primary `#002228`, secondary `#005C60`, background `#FAFEFD`.
- Android must keep these states separate when creating paired captures.

## Current HOME exact source contract

| Item | iOS current value |
|---|---|
| Grid | 3 columns at default Dynamic Type; 2 at `xxxLarge`; 1 at accessibility sizes |
| Grid spacing | horizontal `8pt`, vertical `10pt`, outer horizontal inset `14pt` |
| Card height | `74 + scaled(72 relativeTo: body)`; default `146pt` |
| Card padding | horizontal `5pt`, vertical `12pt` |
| Vertical layout | icon, title, subtitle occupy three equal flexible zones |
| Icon surface | `40×40pt`, radius `8pt`; SF Symbol `19pt bold`; AiShot asset `25×25pt` |
| Title | system subheadline, semibold, default `15pt`, max 2 lines |
| Subtitle | scaled footnote baseline `10.4pt`, max 2 lines, centered |
| Card chrome | radius `8pt`, stroke `1pt`, shadow radius `7pt`, y `4pt` |
| Touch/semantics | entire card button; accessibility label is title, hint is subtitle |

Header semantics after the post-capture correction: the HanClip logo alone exposes the theme-change hint. The information button and media-add button must keep their own independent labels, hints, and actions; Android must not inherit the logo hint onto the full header container.

Source: `HanClip/Views/EditorView.swift` (`homeMoviePresetGrid`, `homePresetColumnCount`, `homePresetCardHeight`, `homeQuickStartButton`) and `HanClip/App/HanClipApp.swift` (`HanClipTheme`, `HanClipTypography`).

## Atomic paired matrix — captured states

| Route/state ID | Element/anatomy | Dimension/action | Fixture/profile | iOS exact reference | Android observed | Difference | Required action | Evidence/confidence | Status/exception proof |
|---|---|---|---|---|---|---|---|---|---|
| HOME.empty.automatic-light | page/background | theme/color | fresh-empty-v1, automatic/system-light, font 1.0 | `home_empty_default.png`; automatic token path | Android r03 automatic/system-light | token pass | keep automatic distinct from explicit Light Mode | source+PNG / High | pass; iOS initial vertical offset excluded |
| HOME.empty.automatic-light | header/logo | bounds/placement | same | LogoMarkV2 + `HanClip`, leading; i and media-add trailing | Android r03 | shared bounds pass | OS glyph raster may differ | PNG / High | pass; media-add glyph is P2 exception |
| HOME.empty.automatic-light | preset grid | geometry | same | 3×2, inset 14, gaps 8/10, card 146 high | Android r03 exact tokens | none in shared geometry | retain source-exact Compose geometry | source+PNG / High | pass; iOS initial page offset excluded |
| HOME.empty.automatic-light | preset card/icon | artwork | same | 40 square/r8; SF 19 bold or AiShot asset25 | Android r03 custom film/golf vectors | platform path approximation only | retain verified custom vectors | source+PNG / High | pass |
| HOME.empty.automatic-light | preset card/title | typography/content | same | exact 6 titles, subheadline semibold 15, max2 | Android r03 | OS font raster only | retain exact Unicode/weight/line count | source+PNG / High | pass |
| HOME.empty.automatic-light | preset card/supporting text | typography/content | same | exact 6 subtitles, scaled 10.4, max2 | Android r03 | OS font raster only | retain exact text/line count | source+PNG / High | pass |
| HOME.empty.automatic-light | movie list empty | hierarchy/state | same | `0/10`, `영화 목록`, two skeleton rows | Android r03 | none material | retain | PNG / High | pass |
| HOME.empty.automatic-light | collection empty | hierarchy/state | same | `0/30`, `컬렉션`, ADD A FILM follows below fold | Android r03 | none material | retain | PNG / High | pass |
| MEDIA_MENU.open.automatic-light | menu container | shape/placement | fresh-empty-v1 | trailing popup under media-add | Android r03 `250dp`, four `44dp` rows, r34 | OS menu chrome/raster only | retain | PNG / High | pass; iOS page vertical offset excluded |
| MEDIA_MENU.open.automatic-light | menu actions | content/icon/action | same | `AiShot`, `사진`, `달력`, `파일` in that order | Android r03 same order/actions | none material | retain | AX+PNG / High | pass |
| HOME.empty.dark | full HOME | theme/color | fresh-empty-v1, dark | `home_empty_dark.png`; Night Slate tokens | Android r03; inset draw layer removed | OS status/navigation bar only | retain | source+PNG / High | pass |
| COPYRIGHT.collapsed.dark | header | controls/content | fresh-empty-v1, dark | HanClip logo, `카피라이터 설정`, close/reset controls | Android r03 shared geometry | OS glyph raster only | retain | AX+PNG / High | pass |
| COPYRIGHT.collapsed.dark | watermark section | collapsed state | same | `워터마크`, `구매 옵션`, collapsed chevron | Android Play test-period control | product policy differs | do not copy StoreKit purchase UI | source+PNG / High | forced platform exception |
| COPYRIGHT.collapsed.dark | sleep setting | content/state | same | `화면 꺼짐 방지`, three-state control, helper text | Android r03 same text/policy | none material | retain `AiShot || mode-policy` | source+tests / High | pass |
| COPYRIGHT.expanded.dark | purchase panel | expanded state/content | same | permanent/year/month cards and exact prices shown by StoreKit fixture | Android Play free-test platform/position editor | store policy and product state | keep platform-native policy; share geometry/tokens only | source+PNG / High | forced platform exception |
| BROWSER.default.dark | browser chrome | geometry/action | fresh-empty-v1, dark | close, URL, go, reload, bookmark toolbar | pending | pending | compare app-owned toolbar only | source+PNG / High | 확인 필요 |
| BROWSER.default.dark | web body | external content | network-dependent | blank/loading then remote page | pending | variable | exclude only exact embedded web rect with documented mask | runtime / Low | 확인 필요; not yet a forced exception |
| BROWSER.favorites.dark | favorites panel | anatomy/content | built-in favorites | title/edit + 3 default rows + trash buttons | pending | pending | exact title, URL, favicon, home and delete affordances | AX+PNG / High | 확인 필요 |
| BROWSER.favorites.dark | external page/cookie UI | external content | network-dependent | remote Pixabay content | pending | variable | mask exact web-owned region, not app panel | runtime / Low | 확인 필요; mask unmeasured |

## Android paired pass — 2026-08-15

Android supplied five `1206×2622` captures at `480dpi` (`402×874dp`), `ko-KR`, `Asia/Seoul`, font scale `1.0`. The original PNGs were visually inspected here. During the audit, the canonical HOME-light and MEDIA files were overwritten by a newer Android run, so their originally supplied hashes cannot be treated as immutable independently verified evidence. Final proof must use revisioned filenames.

| State | Android SHA-256 | Current verdict | Required action / exception |
|---|---|---|---|
| `HOME.empty.automatic-light` | originally supplied `ed903…`; canonical at audit end `425050…` | fail / P1 visual; immutable proof pending | remove the extra opaque inner card rectangle; reduce card stroke/shadow to the iOS source tokens; replace non-equivalent home/section glyphs |
| `MEDIA_MENU.open.automatic-light` | originally supplied `23882…`; canonical at audit end `5bd5a5…` | fail / P1 geometry; immutable proof pending | align the menu to the iOS app-owned container (approximately `250×146pt`, trailing `14pt`, top approximately `53pt`, four approximately `44pt` rows); use regular body-weight labels |
| `HOME.empty.dark` | `b5932c1d3b85f1f3fa542e495bceca045f1e52d0b68df2d4e3eab46ac953ebaa` | fail / P1 visual | same inner-layer and glyph corrections; Android dark card fill is flatter and more rectangular than iOS |
| `COPYRIGHT.collapsed.dark` | `ea478e261d617fe9f3ac2fecd570ff722d87665d401ee11855c5613c2673adb9` | conditional fail / P1 hierarchy | match iOS title and container metrics; do not copy StoreKit products. Android's Play test-period policy is a recorded platform exception |
| `COPYRIGHT.expanded.dark` | `ff5cafea21f85855f061d42f8859491cf11758b86b7813b761e1d6e8bcce3dd3` | conditional / platform exception | the Android free-test platform and 5×5 position editor are valid Android product-state differences; shared typography, spacing, corner, and color tokens still require parity |

The automatic-light HOME and MEDIA captures place the section heading at approximately `y=257pt`, while the same iOS source in the dark HOME capture places it near `y=146pt`. A theme-only transition must not move the main content by roughly `111pt`; the light-state gap is therefore an iOS initial-layout/runtime audit item, not a shared layout token. Android must not reproduce that large gap. Its current heading near `y=108dp` may still need a much smaller approximately `38dp` adjustment after the iOS defect is reproduced and corrected.

### Immutable Android r02 verdict

The Android task then supplied revisioned r02 files. All five SHA-256 values below were independently recalculated and matched.

| State | Immutable Android file / SHA-256 | Verdict |
|---|---|---|
| HOME automatic-light | `home_empty_default_r02.png` / `80fe662c526bac439e4ea314cf5ab71c15468d3dd8f20e3a94a0c269a264f722` | geometry/card size/light shadow pass; new-movie and golf glyph paths still fail |
| MEDIA_MENU | `media_menu_open_r02.png` / `8630fc372890122c3a0f2b385f436869ce8af7d68b99f120e100537cd3b90eea` | shared container/row geometry pass; platform font rendering accepted |
| HOME dark | `home_empty_dark_r02.png` / `7d4a67562ae3ee7079a5a5eb06244dcb1a00edff38873daafa6a3b9eb2eeb759` | fail / P1: an approximately `8dp` inset rectangular tonal layer remains visible inside all six cards; glyph path failures also remain |
| COPYRIGHT collapsed dark | `copyright_collapsed_dark_r02.png` / `fa789347b4dbd750a4adf5d202cc05b2549d46eae1f891f80658658a00a0e9e6` | shared geometry pass; Play test-period content is a platform exception |
| COPYRIGHT expanded dark | `copyright_expanded_dark_r02.png` / `5c1c7767409f08401b9e4d5f25e1161d55f468644d82035c05eda28317ef1923` | shared geometry pass; Play platform and position editor are a platform exception |

Behavioral P1 found during this pass: iOS keeps the screen awake in AiShot regardless of the selected sleep-prevention mode, then applies the mode only to other work. Android r02 applies AiShot only inside Automatic and therefore allows `AlwaysOff` to disable it. Android must evaluate `AiShot || mode-policy`, and its Automatic helper must use the iOS wording `렌더링, 사진/파일 가져오기, 저장 중에만 유지합니다.`. The supplied APK hash was not independently checked because no immutable APK path was provided.

### Immutable Android r03 final verdict for this slice

The three r02 P1 items were corrected. The five PNG hashes and the debug APK hash were independently recalculated from their immutable paths.

| State/artifact | SHA-256 | Final slice verdict |
|---|---|---|
| `home_empty_default_r03.png` | `5b7f58eaf9a9f5f06e918212c48523dd7da19aa5e1110f2b75658cd288ec3ff8` | pass |
| `home_empty_dark_r03.png` | `2bb9e557ea0056a564cf659bbeeb81f4d348016d49ef5f73da6d1a9b7dccec6d` | pass; dark inset rectangle removed |
| `media_menu_open_r03.png` | `e6261a9e8858f88e0cca1bfc3c2c74cba5d922c02f566c798dd566aa81958d8d` | pass |
| `copyright_collapsed_dark_r03.png` | `a61dde0d587a2c0e82383e009f8ec498406d417d1db9032df1c26d3b823840e3` | pass with recorded Play policy exception |
| `copyright_expanded_dark_r03.png` | `69b3528b23c2e65daa220a2f89e44acd7d96bb5c8ac4c54820d1753e3c16de46` | pass with recorded Play policy exception |
| `app/build/outputs/apk/debug/app-debug.apk` | `42685346a0b3cbbea9e410a4ccb4b1e2e7a121f349c591a879d0ee76cd18b39b` | artifact identity verified; installation is owned by the Android task |

Source inspection confirms the Android sleep policy now evaluates `isAiShotActive || mode-policy`, uses the exact Automatic helper text, and includes focused regression tests. The Android task also supplied a cold-relaunch accessibility trace showing the default logo enabled and an Instagram address persisted after platform switching and process restart; that trace is accepted for this slice. Remaining P0/P1 for these five states: none. Allowed P2/platform differences are the OS font raster, the header media-add glyph path, and Play test-period content. `theme_notice_r03.png` is not passed because no stable iOS theme-notice reference exists.

This verdict is deliberately limited to HOME automatic-light/dark, MEDIA_MENU, COPYRIGHT collapsed/expanded, sleep policy, and copyright persistence. It does not promote the uncaptured route inventory below to complete.

The Android finish-work pass later repackaged the same reported r03 UI/source as the release-QA candidate after changing only `versionCode` from 545 to 546. The final file at `/Users/armsone/git/HanClip-Android/app/build/outputs/apk/releaseQa/app-releaseQa.apk` has independently verified SHA-256 `83cdf966782f4b965a72815611c190f2acb4b7b2627e2493fcaaf3fe0e487816`. `aapt2 dump badging` independently reports package `com.hanclip.android`, `versionName=1.0.1`, `versionCode=546`, `minSdk=26`, and `targetSdk=37`. The Android task reports full JVM tests, debug AndroidTest APK compilation, `lintDebug`, and `assembleReleaseQa` passed; those commands were not rerun by the iOS task.

## Required route/state inventory — capture status

`captured` means an original 1206×2622 PNG and SHA-256 exist. It does not mean Android parity has passed.

| Group | Required states | Current iOS evidence |
|---|---|---|
| HOME | empty, populated, shared, busy | empty captured; others 확인 필요 |
| MEDIA_MENU | open | captured |
| THEME | automatic/light/dark/custom, notice, panel, reorder | automatic-light + dark HOME captured; notice/panel/reorder 확인 필요 |
| COPYRIGHT | collapsed, expanded, default-on/off/persisted | collapsed/expanded dark captured; on/off/persistence trace 확인 필요 |
| PHOTO | entry, selected, drag, reverse, loading, empty, filter | 확인 필요 |
| CALENDAR | month, today, selected | 확인 필요 |
| QUICK_DURATION | default, settings-return, font1.3 | 확인 필요 |
| EDITOR | empty, populated, expanded | 확인 필요 |
| CLIP_TRIM | photo, video, delete-confirm | 확인 필요 |
| TEXT | default, custom, font | 확인 필요 |
| MUSIC | none, sample, file | 확인 필요 |
| BROWSER | default, favorites, download, error | default/favorites partial; download/error 확인 필요 |
| ENDING | off, themes, duration | 확인 필요 |
| GENERATION | progress, cancel, error | 확인 필요 |
| PREVIEW | paused, playing, fullscreen | 확인 필요 |
| RELEASE | options, progress, error | 확인 필요 |
| COLLECTION | 0, 1, 29, 30, progress | HOME empty collection partially visible; distinct states 확인 필요 |
| COLLECTION_PLAYER | portrait, landscape, zoom | 확인 필요 |
| COLLECTION_POSTER_AI | loading, candidates, error | 확인 필요 |
| COLLECTION_COMPRESS | options, progress, cancel | 확인 필요 |
| AISHOT | permission, ready, capture, save | 확인 필요 |
| PERMISSION_ALERT | denied, permanent, recovered | 확인 필요 |

## Reproduction commands

The captured temporary device was intentionally deleted after use. The profile can be regenerated without touching a shared simulator:

```bash
xcrun simctl create HanClipMatchup-iPhone17Pro-YYYYMMDD \
  com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro \
  com.apple.CoreSimulator.SimRuntime.iOS-26-5

xcodebuild -project HanClip.xcodeproj -scheme HanClip \
  -configuration Debug -destination 'platform=iOS Simulator,id=<UDID>' \
  -derivedDataPath /private/tmp/hanclip-matchup-ios.<task> \
  CODE_SIGNING_ALLOWED=NO build

xcrun simctl install <UDID> \
  /private/tmp/hanclip-matchup-ios.<task>/Build/Products/Debug-iphonesimulator/HanClip.app
SIMCTL_CHILD_TZ=Asia/Seoul xcrun simctl launch <UDID> com.intosharp.hanclip
xcrun simctl io <UDID> screenshot --type=png <state-id>.png
shasum -a 256 <state-id>.png
```

The three stable captures and the non-vertical portions of the two partial light captures are suitable for immediate Android comparison. Full parity remains unverified until all inventory rows have stable pairs and behavioral traces.
