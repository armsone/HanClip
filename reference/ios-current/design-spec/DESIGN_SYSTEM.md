# HanClip iOS 디자인 시스템 → Android 구현 명세

기준 소스: `HanClip/App/HanClipApp.swift`, `HanClip/Views/EditorView.swift`, `HanClip/Views/HanClipFullscreenVideoPlayer.swift`, `HanClip/Views/ClipRow.swift`, `HanClip/Services/PhotoPicker.swift`, `HanClip/Views/VideoTrimEditor.swift`, `HanClip/Services/AiShotCamera.swift` (commit `31e60ec5`, 2026-08-12). 이 문서는 화면 캡처가 아닌 실제 호출 소스를 기준으로 한다. iOS 소스는 이 조사에서 수정하지 않았다.

## 1. 단위와 플랫폼 대응

- SwiftUI의 수치는 pt다. Android의 기본 대응은 레이아웃 `dp`, 글자 `sp`이며 1 pt를 1 dp/sp로 시작한다. 기기별 밀도는 OS가 변환한다.
- iOS `safeAreaInset`/`safeAreaPadding`은 Android `WindowInsets.statusBars`, `navigationBars`, `displayCutout`으로 대응한다. 상태바나 홈 인디케이터 영역에 고정 좌표를 쓰지 않는다.
- iOS 동적 글자 크기 적용 여부는 대부분 `.system(size:)` 고정값이므로 Android도 고정 sp로 먼저 맞춘다. 접근성 글자 확대 시 `minimumScaleFactor`가 있는 요소는 축소보다 2행 또는 컨테이너 확장을 우선한다.
- iPhone 17 Pro 시뮬레이터 기준 캡처 해상도는 1206×2622 px이나, 구현 수치는 픽셀이 아니라 아래 pt 규칙을 따른다.
- 최소 터치 영역: 소스에 시각 크기 42~58 pt가 반복된다. Android는 모든 탭 대상의 실제 hit box를 최소 48×48 dp로 보장한다. 작은 아이콘/핀/필터도 투명 패딩으로 확장한다.

## 2. 테마 모드와 정확한 기본 색

모드는 `automatic`, `light`, `dark`, `blossomGlow`, `grayscalePlay`, `pixelPop` 여섯 개다. 이전 저장값 `readableComfort`는 `light`, `rosyBrown`/`electricCobalt`는 `automatic`으로 마이그레이션한다. 소스: `HanClipApp.swift:5-54, 56-620`.

| 모드 | Main / primary | Sub / secondary | Background | Background+Black | Text | 강제 색상 모드 |
|---|---|---|---|---|---|---|
| Automatic light | `#072931` rgba(7,41,49,1) | `#007E81` rgba(0,126,129,1) | `#FFFFFF` | `#F5F5F5` rgba(245,245,245,1) | `#1A1A1A` | 시스템 |
| Automatic dark | `#67E8F9` rgba(103,232,249,1) | `#527387` rgba(82,115,135,1) | `#373A36` rgba(55,58,54,1) | 약 `#353835` rgba(52.8,55.7,51.8,1) | `#FFFFFF` | 시스템 |
| Light Mode | `#002228` | `#005C60` | `#FAFEFD` | `#D2E7E5` | `#00070C` | light |
| Dark Mode | `#67E8F9` | `#527387` | `#0A0E12` | `#11181F` | `#E8EEF2` | dark |
| Blossom Glow | `#D65E7A` | `#8B6897` | `#FFF8FA` | `#F7EBF1` | `#2D1F28` | light |
| Grayscale Play | `#1C1C1E` | `#787880` | `#F7F7F8` | `#E2E2E5` | `#121214` | light |
| Pixel Pop | `#2652FF` | `#DC2F65` | `#F9FBFF` | `#E8EFFF` | `#0F1630` | light |

`onSecondary`는 Grayscale Play에서 `#F7F7F8`, 그 외에는 `#FFFFFF`다. 사용되지 않는 `golfPrimary #007644`, `golfSecondary #29AB87` 상수는 테마 선택 경로에 연결되지 않으므로 Android 전역 테마로 구현하지 않는다.

## 3. 파생 토큰

- `backgroundGradient`: `backgroundWithBlack`(top) → `background`(bottom), 수직 linear gradient.
- `primaryText`: Text × opacity 0.88, Dark만 0.92.
- `secondaryText`: Text × 0.58, Dark만 0.66.
- `mutedIcon`: Text × 0.46, Dark만 0.52.
- `panelFill`: Light Sub 18%; Dark white 6%; Blossom Sub 10%; Grayscale Sub 12%; Pixel Sub 8.5%; Automatic light Sub 8%, dark white 6%에 해당한다.
- `browserDownloadPanelFill`: Light Sub 36%; Dark white 12%; Blossom Sub 20%; Grayscale Sub 24%; Pixel Sub 17%; Automatic light Sub 16%, dark white 12%.
- `panelStroke`: Light Main 36%; Dark Main 30%; Blossom Main 20%; Grayscale/Pixel Main 24%; Automatic light Main 18%, dark Main 26%.
- `groupFill`: Light Sub 28%; Dark white 8%; Blossom/Grayscale Sub 18%; Pixel Sub 15%; Automatic light Sub 16%, dark white 8%.
- `childFill`: Light Sub 12%; Dark white 4.5%; Blossom Sub 6.5%; Grayscale Sub 7.5%; Pixel Main 5.5%; Automatic light Sub 4.5%, dark white 4.5%.
- `separator`: Light Main 34%; Dark Main 22%; Blossom Main 16%; Grayscale Main 20%; Pixel Main 18%; Automatic light Sub 14%, dark Sub 22%.
- 브라우저 다운로드/즐겨찾기처럼 가독성이 중요한 떠 있는 패널은 일반 `panelFill`이 아니라 `browserDownloadPanelFill`을 쓴다.

## 4. 공통 배치

- 화면 최상단: `HanClipTopHeader` 또는 루트 `rootTopHeader`. 높이 58 pt, top 6, horizontal 14. 좌측 로고 pill, 우측 action cluster.
- `HanClipHeaderPill`: horizontal padding 10, vertical 7, Capsule, ultraThinMaterial + panelFill 72%, panelStroke 62% 1 pt, shadow Sub 8% radius 12/y 5.
- `HanClipLogoLabel`: 커스텀 `LogoMarkV2` 35.2×35.2, 간격 6, “HanClip” system semibold 26, 전체 폭 154, Main 색.
- `HanClipHeaderActionCluster`: 내부 HStack spacing 14, symbol 25 semibold, 높이 58, horizontal 16, 같은 capsule/material/stroke/shadow.
- 작은 제목줄 `HanClipTitleLine`: 우측 정렬 HStack spacing 7, 기본 좌우 18, 아이콘 10 black을 18×18 안에 배치, radius 5, Sub 10% 배경; 텍스트 12 black, primaryText 76%.
- 홈 본문은 세로 ScrollView, indicator 숨김. 주요 horizontal inset는 14 또는 18. 섹션 간격 8~12. 하단 안전 공간과 i 플로팅 버튼을 위해 24 pt 이상 둔다.
- 화면 최대 너비: compact는 safe area 전체 폭. regular horizontal size class에서 홈/편집 루트·헤더·하단 핵심 콘텐츠 최대 920pt. 테마 패널은 화면 92%이면서 최대 620pt, reset/exit 확인은 최대 760pt, 공유 inbox는 최대 720pt. 사진 선택 그리드는 기기 폭과 열 수에 따라 확장한다.
- Android는 폭 600dp 이상에서 넓은 화면 구성을 시작하되 단순 확대하지 않는다. phone 일반 영화/컬렉션/편집 클립 1/2/1열, 600dp 이상 2/3/2열을 기준으로 하고 핵심 읽기 폭은 920dp를 넘기지 않는다.

## 5. 패널·카드·버튼

- 기본 카드: `panelFill` 또는 `background` 혼합 linear gradient, RoundedRectangle. 홈 프리셋 radius 8, 정보/설정 카드 12~24, 큰 모달 카드 24~30.
- 1차 액션: Main → Sub(보통 82~92%) 대각선 gradient, 흰색 bold, Capsule, 높이 44~56, Main 18~22% shadow radius 8~14/y 4~7.
- 2차 액션: background/ultraThinMaterial + Sub 10%, primaryText 또는 secondaryText, 1 pt Sub/Main stroke.
- 비활성: opacity를 낮추고 hit testing/disabled를 함께 적용한다. 단순 회색만 바꾸지 않는다.
- 세그먼트: 행 전체를 탭해 상태 전환할 수 있도록 구현된 공용 컨트롤이 있다. 선택 pill은 Main 계열, 미선택은 group/panel 계열. Android는 SegmentedButtonRow 대신 전체 행 pointer input도 동일하게 처리한다.
- 컬렉션 포스터: 2열, horizontal 18, column gap 10, row gap 12, aspect ratio width:height = 1:1.38, radius 12.
- 홈 프리셋: 3열, gap x=8/y=10, horizontal 14, 카드 높이 108/radius 8. 아이콘 tile 40×40/radius 8.
- 떠 있는 i 버튼: 시각 44×44 circle, serif bold 18, panelFill 72%, interactive glass(iOS 26) 또는 material, stroke 1, shadow radius 10/y 4, bottom 8. Android는 blur 사용 가능 시 `RenderEffect`, 아니면 반투명 panel fill.

## 6. 타이포그래피

- UI 기본은 SF system. Android는 `Roboto` 또는 시스템 sans로 대응하되 weight/크기를 우선한다.
- 헤더 로고: 26 semibold. 큰 패널 제목: 18 semibold/bold. 섹션 제목: 12 black. 본문 기본 14~16 medium/semibold. 보조 정보 9~12 medium/semibold. 진행률/숫자: rounded design + monospaced digits 대응.
- 프리셋: 제목 12 bold 1줄, scale min 0.76; 부제 9 semibold 1줄, min 0.68.
- 컬렉션 추가 포스터: `HANCLIP` system serif 9 bold tracking 3; `ADD A FILM` `MaruBuri-Regular` 15 tracking 1.2; `COLLECTION` serif 8 semibold tracking 2.4.
- 자막 선택 글꼴은 앱 UI와 별도다: Kakao Big Sans, Nanum Gothic, Pretendard, MaruBuri, Puradak Gentle Gothic, Tenada, Cafe24 Ssurround, Ddulgi Mayo, Gowun Dodum/Batang, Black Han Sans, Do Hyeon, Paperlogy, NEXON Lv.1 Gothic, Poppins. Android 번들 시 동일 파일 및 라이선스 고지를 포함한다.
- `lineLimit(1)`+`minimumScaleFactor`가 빈번하다. Android는 `maxLines=1`, `overflow=Ellipsis`, 필요 시 `TextAutoSize`를 사용한다. 지역명은 의미 단위 전체를 한 줄로 유지하고, 이동 아이콘까지 함께 다음 줄로 옮기는 별도 규칙이 있다.

## 7. 아이콘 체계

| 의미/위치 | iOS | 크기/weight | Android 대응 |
|---|---|---|---|
| 미디어 추가 | `photo.badge.plus` | header 25 semibold | Material `add_photo_alternate`; 배지 결합 필요 |
| 닫기/취소 | `xmark` | 18~25 bold/semibold | `close` |
| 영화 프리셋 | `square.grid.2x2.fill` | 10 black | `grid_view` |
| 새 영화 | `film.stack.fill` | 19 bold | 커스텀/`video_library` |
| 퀵모드 | `bolt.fill` | 19 bold | `bolt` |
| AiShot | asset `AiShotIcon` | 25×25 | 동일 에셋 |
| 여행 | `airplane` | 19 bold | `flight` |
| 인생 | `heart.fill` | 19 bold | `favorite` |
| 골프 | `figure.golf` | 19 bold | Material 부재, custom vector 필요 |
| 영화 목록 | `rectangle.stack.fill` | 10 black | `video_library` |
| 컬렉션 | `books.vertical.fill` | 10 black | `collections_bookmark` |
| 용량 줄이기 | `archivebox` + chevron | 10 bold | `inventory_2` + expand icon |
| 컬렉션 핀 | asset `CollectionPin` | 51×51 in 64 hit box | 동일 PNG/vector 권장 |
| 사진/달력/파일 | `photo.on.rectangle` / `calendar` / `folder` | 메뉴 기본 | `photo_library` / `calendar_month` / `folder` |
| 자막/음악/엔딩 | `captions.bubble.fill` / `music.note` / `map.fill` | 화면별 11~20 | `closed_caption` / `music_note` / `map` |
| 공유/저장 | `square.and.arrow.up` / `square.and.arrow.down` | 18 semibold | `share` / `download` |
| 진행 | `progress.indicator`, `hourglass`, `sparkles` | 10~31 | `progress_activity`, `hourglass`, `auto_awesome` |

SF Symbol이 Material과 시각적으로 다르면 의미보다 HanClip 실루엣을 우선해 custom vector를 만든다. 에셋명은 대소문자를 그대로 유지한다.

## 8. 모션·전환

- 기본 상태 전환은 SwiftUI `.snappy`; Android는 180~260 ms spring(낮은 bounce)로 대응.
- blur/overlay 값 변화는 `.easeInOut(0.20s)`.
- 사진↔달력 전환은 opacity `.easeInOut(0.11s)`; slide가 아니라 같은 자리 crossfade.
- 테마/확인 팝업: 검정 20% dim, 홈을 blur 2 pt. 테마는 top에서 move+fade; 저장 확인은 bottom에서 move+fade.
- busy overlay와 공유 배너: root blur 2 pt, 0.20s. 진행창은 zIndex 100, 사용자 입력 차단.
- 테마 변경 notice: 상단 70 pt 위치 capsule, 2초 후 fade out.
- Android reduced motion 설정 시 move/scale을 opacity로 축소한다.

## 9. 상태와 접근성 공통 규칙

- 모든 icon-only 버튼은 contentDescription을 둔다. 소스의 accessibilityLabel/Hint를 화면 문서에 보존한다.
- 현재 선택은 색상만으로 알리지 않고 radio/check glyph와 “선택됨” state description을 함께 제공한다.
- 로고: 홈에서 짧은 탭=다음 테마, 0.6초 롱터치=테마 패널. i 버튼: 탭=카피라이터, 0.55초 롱터치=브라우저.
- 진행 상태는 제목, completed/total 또는 %, ProgressBar, 취소 가능 여부를 함께 표시한다.
- 오류는 전역 제목 `HanClip`, 본문 `model.alertMessage`, 확인 버튼 1개. 기능별 구체 문구는 런타임 오류에서 오므로 문서에 없는 문자열을 추측하지 않는다.
- Live Photo의 Android 표기는 모든 사용자 노출 문구에서 **모션포토**로 바꾼다. 기능 의미는 정지 프레임 또는 짧은 동영상으로 사용하는 선택이다.

## 10. 소스 근거와 주의

- 전역 테마/공통 glass modifier: `HanClip/App/HanClipApp.swift:5-620, 650-730`.
- 공통 헤더/제목줄: `HanClip/Views/EditorView.swift:7957-8150`.
- 홈/프리셋/목록/컬렉션: `EditorView.swift:3015-4010`.
- 공용 사진 선택 UIKit: `HanClip/Services/PhotoPicker.swift:100-330, 341-3200`.
- 편집 행: `HanClip/Views/ClipRow.swift` 전체.
- 화면 방향 및 플레이어: `HanClip/Views/HanClipFullscreenVideoPlayer.swift` 전체, 호출 구성은 `EditorView.swift`.
- 코드에 선언만 있고 실제 presentation 경로에 연결되지 않은 값은 SCREEN_MAP에서 “미사용/확인 필요”로 분리한다.
