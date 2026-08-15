# HanClip Android 이식용 전수 기술서

## 0. 문서 지위와 기준

- 기준 시각: 2026-08-13 22:19:34 +0900
- iOS 저장소: /Users/armsone/git/HanClip
- Git branch: main
- Git HEAD: 31e60ec5feb100b3dfcec78d47040e54e2d682ca
- iOS 제품/최종 작업트리 빌드: 1.0.1 (3.11.44)
- 목적: Android 담당자가 Swift를 다시 추론하지 않고 2026-08-13 iPhone 앱의 화면, 상태, 데이터 수명, 오류 처리와 오늘 변경을 구현하도록 하는 현재 기준 명세.
- 우선순위: 이 문서가 2026-08-12 작성 reference/ios-current/design-spec 문서와 충돌하면 이 문서가 우선이다. 충돌하지 않는 렌더러 좌표와 알고리즘은 기존 문서를 함께 사용한다.
- 조사 원칙: 현재 작업트리와 HEAD diff, 실제 Swift 최종 상태, 프로젝트 빌드 설정, 이 task 완료 기록을 교차검증했다. 2026-08-13 당일 Git commit은 없다.
- 변경 제한: 이 조사에서 앱 Swift 소스와 Xcode 프로젝트 설정은 수정하지 않았다. 이 Markdown만 추가한다.

### 0.1 현재 작업트리

| 상태 | 경로 | 분류 |
|---|---|---|
| M | HanClip.xcodeproj/project.pbxproj | 빌드 3.9.24 → 3.11.44 |
| M | HanClip/.DS_Store | 사용자/환경 파일, Android 제외 |
| M | HanClip/App/HanClipApp.swift | 테마 대비, 타이포 토큰, 최소 탭 영역 |
| M | HanClip/Models/ClipItem.swift | Live Photo 표시명 |
| M | HanClip/Services/AiShotCamera.swift | 글자 체계, hit target, 안내 패널 |
| M | HanClip/Services/PhotoPicker.swift | Dynamic Type, 셀 접근성, 닫기 hit target |
| M | HanClip/Views/ClipRow.swift | 편집 행, 세그먼트/stepper, 묶음 버튼 |
| M | HanClip/Views/EditorView.swift | 홈·편집·설정·브라우저·달력·퀵·삭제 |
| M | HanClip/Views/HanClipFullscreenVideoPlayer.swift | 제목/시간 타이포 |
| M | HanClip/Views/VideoTrimEditor.swift | 용어·타이포·hit target |
| M | PROJECT_RULES.md | 개발 규칙, 제품 기능 제외 |
| ?? | reference/ | iOS 명세와 이 문서 |

작업트리 diff는 앱/규칙 파일 11개, +1167/-645이며 .DS_Store 바이너리가 별도다. reference는 HEAD에 없는 untracked 자료이므로 Android 저장소로 옮길 때 명시적으로 추적해야 한다.

### 0.2 근거와 한계

| 근거 | 직접 확인 | 한계 |
|---|---|---|
| task 완료 기록 | 빌드 3.11.42, .43, .44의 수정·빌드·설치 | 3.9.25~3.11.41의 상세 changelog 없음 |
| git status/diff/log | dirty 파일, HEAD 대비 미커밋 변경, 최근 commit | 오늘 변경은 commit 경계가 없어 완전한 시간순 분할 불가 |
| Swift 최종 소스 | 실제 호출, 수치, 문구, binding/state | 모든 화면 실기기 재조작은 안 함 |
| Xcode 프로젝트 | 모든 app/share/widget config가 3.11.44, marketing 1.0.1 | App Store 배포 미확인 |
| 실제 기기 기록 | .42/.43/.44 설치와 devicectl 버전 조회 | 마지막 빌드의 모든 시각·제스처는 사용자 검증 |

### 0.3 빌드 번호별 확인 기록

| 빌드 | 확인 상태 | 변경 |
|---|---|---|
| 1.0.1 (3.9.24) | HEAD 원래 값, task 초기에 사용자 기기 설치 사용자 보고 | 2026-08-13 작업 전 기준 |
| 3.9.25~3.11.41 | 미검증 | commit/changelog가 없어 추정 금지 |
| 1.0.1 (3.11.42) | 실제 기기 설치·조회 기록 | 전역 타이포, 가독성/터치, 편집 설정 재배치, 홈/브라우저/달력/PhotoPicker 1차 정리. 미커밋 diff라 line별 빌드 경계 일부 미검증 |
| 1.0.1 (3.11.43) | 실제 기기 설치·조회 | 묶음사진 편집·초기화 30 시각/44 hit, 컨테이너 66→96; Photo duration 닫기 38 시각/44 hit |
| 1.0.1 (3.11.44) | 실제 기기 빌드·서명·설치·조회 | 엔딩 초기화/취소/저장 세션, 자막 진입 자동 사용, 하단 비율 첫 사진 10pt 2줄 |

## 1. Android 절대 구현 원칙

| iOS 최종 동작 | Android 구현 요구사항 |
|---|---|
| SwiftUI/UIKit point | layout dp, text sp. 1pt→1dp/sp로 시작하고 Android font metrics로 검증 |
| iPhone compact, iPad regular 핵심 폭 최대920 | WindowSizeClass, phone/fold/tablet, 핵심 읽기 폭 최대920dp 후보 |
| safeArea/full-screen cover | status/navigation/cutout/hinge/IME inset 반영 |
| 화면/앱/project/collection/registry 상태 분리 | rememberSaveable/SavedStateHandle, DataStore, versioned JSON/index/registry 분리 |
| 새 파일 검증 후 index 교체와 이전 파일 삭제 | import/export/compress transaction과 rollback. 원본 선삭제 금지 |
| Live Photo는 정지/모션 의미 | Android 사용자 표기는 모션포토, 내부 still/motion |
| SF Symbols/custom assets | Material 의미가 다르면 custom vector; AiShotIcon/CollectionPin 보존 |
| iOS material/glass | Android blur 가능 시 사용, 아니면 대비 보존 surface. iOS API 복사 제외 |

## 2. 최종 디자인 시스템

### 2.1 색상

| 모드 | iOS 최종 | Android 요구 |
|---|---|---|
| Automatic light | Main #072931, Sub #007E81, BG #FFFFFF, Text #1A1A1A | 동일 sRGB |
| Automatic dark | Main #67E8F9, Sub #527387, BG #373A36, Text #FFFFFF | 동일 |
| Light | Main #002228, Sub #005C60, BG #FAFEFD, Text #00070C | 동일 |
| Dark | Main #67E8F9, Sub #527387, BG #0A0E12, Text #E8EEF2 | 동일 |
| Blossom Glow | Main **#B23E5D**(178,62,93), Sub #8B6897, BG #FFF8FA, Text #2D1F28 | 구형 #D65E7A 금지. white CTA 대비 개선값 사용 |
| Grayscale Play | Main #1C1C1E, Sub #787880, BG #F7F7F8, Text #121214 | 동일 |
| Pixel Pop | Main #2652FF, Sub #DC2F65, BG #F9FBFF, Text #0F1630 | 동일 |

- background는 backgroundWithBlack→background 수직 gradient.
- panelFill/panelStroke/groupFill/childFill/separator의 모드별 opacity는 기존 DESIGN_SYSTEM.md를 유지하되 Blossom Main만 갱신한다.
- radius는 작은 카드 8~14, 설정14, 큰 모달24~30. 이유 없는 elevation 추가 금지.

### 2.2 타이포그래피

| 토큰 | iOS 최종 | Android 요구 |
|---|---|---|
| screenTitle | title3 semibold, 약20 | 20sp semibold, 1~2줄 |
| modalTitle | headline semibold, 약17 | 17sp semibold |
| sectionTitle | subheadline semibold, 약15 | 15sp semibold |
| body | body regular, 약17 | 17sp |
| denseBody | callout regular, 약16 | 16sp |
| rowTitle | callout semibold, 약16 | 16sp semibold |
| secondary | subheadline regular, 약15 | 15sp |
| metadata | footnote regular, 약13 | 13sp |
| metadataEmphasis | footnote medium | 13sp medium |
| caption | caption medium, 약12 | 12sp, 기능 정보 하한 |
| badge | caption semibold | 12sp semibold |
| primaryNumber | title2 rounded semibold, tabular, 약22 | 22sp tabular |
| compactNumber | footnote monospaced medium, 약13 | 13sp tabular |
| primaryCTA | headline semibold | 17sp semibold |

- 홈 preset: 기본3열, xxxLarge 이상2열, 접근성 크기1열.
- 핵심 문구는 6~9pt 축소 대신 2줄/ellipsis/height 증가.
- PhotoPicker header는 17 semibold headline metrics max24, 하단은 13 semibold footnote metrics max18.
- Android는 fontScale 1.0/1.3/1.6/2.0, Bold Text 상당 설정을 검증한다.

### 2.3 터치·접근성

| iOS 최종 | Android 요구 |
|---|---|
| 공통 최소 hit 44×44pt, 작은 visual과 분리 가능 | 모든 interactive target 48×48dp 이상 |
| segment visual 24~30, hit44 | visual 유지 가능, 각 target48, 중첩 금지 |
| icon-only label/hint/custom action | contentDescription/stateDescription/custom action |
| 색+surface+selected trait | 색만으로 상태 구분 금지 |

## 3. 루트 상태와 전환

HOME → preset/editor/quick/AiShot/saved project/collection/media.
EDITOR → text/music/ending/media/clip trim/generation/home-save.
GENERATION → PREVIEW → RELEASE.
i tap → COPYRIGHT, i 0.55s long press → BROWSER.

| iOS 최종 | Android 요구 |
|---|---|
| overlay 우선: busy/share/theme/exit/aspect/reset/alert | Back은 최상위 overlay부터, task 취소 완료 후 전환 |
| PHOTO↔CALENDAR 같은 cover와 ordered selection, 0.11s crossfade | 같은 ViewModel session, route 변화에서 순서 보존 |
| QUICK 설정 진입 시 quick cover를 닫고 설정 후 복귀 | 중복 destination 없이 SavedState 복귀 |
| regular root/header/bottom max920 | tablet/fold max920dp 후보 |

## 4. 화면별 전수 명세

### 4.1 HOME · 프리셋 · 영화 · 컬렉션 · 미디어 메뉴

| 항목 | iOS 최종 동작 | Android 구현 요구사항 |
|---|---|---|
| header | 높이58, top6, horizontal14. logo icon30/text22/width126. 우측 i 44 circle + photo.badge.plus, gap8 | 같은 hierarchy. compact 폭 겹침 금지 |
| i | 하단이 아닌 상단. tap=카피라이터, 0.55s long=브라우저, custom action 브라우저 열기 | 상단 유지, TalkBack custom action 또는 overflow. 하단 i 금지 |
| logo | tap=다음 theme+2초 notice, 0.6s long=theme panel | click/long-click 경합 분리 |
| preset 문구 | 새 영화/모든 것의 시작; 퀵모드/고르면 바로 영화로; AiShot/스마트한 레코딩; 여행 영화/여행을 추억으로; 인생 영화/삶의 순간을 한 편으로; 골프 영화/공도 넣고 기억도 넣고 | 문구/순서 동일. golf/AiShot custom asset |
| preset grid | horizontal14, x8/y10, radius8, icon40, minHeight120. title15 최대2줄, subtitle13 최대2줄 | 구형 108/12/9 폐기. 3→2→1열 adaptive |
| 영화 | 일반/AiShot kind별 section, 같은 store와 총 limit10. kind icon/date/time/meta/memo/pin | limit/kind/stable project 유지 |
| 삭제 | swipe는 72 red trash reveal만. minDistance24, horizontal ratio1.35, threshold -82. trash/accessibility action 뒤 alert: 이 영화를 삭제할까요? / 삭제한 영화는 복구할 수 없습니다. | P0: reveal→explicit delete→confirm. TalkBack도 confirm. 영구 삭제 직결 금지 |
| 컬렉션 | max30. 0~29 add, 30 hide. phone2열, poster1:1.38/radius12, pin/order/context/compress/AI | 기존 contract. 600dp+ 3열은 parity 기록 |
| build caption | metadata13 tabular, HanClip 1.0.1 Build 3.11.44 / Ai model | debug/about 대응; 노출 차이는 parity |
| media menu | AiShot, 사진, 달력, 파일 | CameraX/Photo Picker/MediaStore/SAF |
| 상태 | project0/data, collection0~30, shared inbox, progress, busy, theme notice | 구조 상태별 test |
| 제외 | StoreKit, iOS glass, UIApplication shortcut API | Play Billing/Android shortcuts |

### 4.2 PHOTO · CALENDAR · IMPORT

| 항목 | iOS 최종 동작 | Android 구현 요구사항 |
|---|---|---|
| Photo header | safe top+14, 좌/중/우 각88×40: 취소 / 사진 / n개 추가. 17 semibold scaled max24 | fontScale에서 action 숨김 금지; 필요 시 adaptive app bar |
| bottom | horizontal18, bottom16, 필터·전날·오늘·해제·추가 각54×54. 13 semibold max18 | min48. compact에서 2행이면 parity 기록 |
| filter | 전체, 사진, 라이브, 영상 복수; duration 이상/이하; 날짜순/추가순 ↑/↓ | 라이브→모션포토. 최소1종, duration 해제 시 이전 filter 복구 |
| grid | 기본5열, pinch1/3/5/8, capture date ascending, bottom inset92 | 단계/순서 보존 |
| cell | radius8, kind badge20×18, check18, selected scale0.86 | 동일 상태 |
| cell a11y | label 날짜·시간+종류, value 선택 안 됨 또는 선택됨 n번째, selected trait, double tap hint | TalkBack label/state/order |
| duration X | visual38, hit44 | hit48 |
| 권한 거절 | 최종 iOS는 header를 권한 필요로 바꾸고 빈 grid. 설정/재시도 empty state 없음 | iOS 결함 복제 금지. P1 설명+설정 이동+재시도, 플랫폼 개선 기록 |
| loading/empty | 최초 fetch와 진짜 empty를 나누는 전용 UI 확인 안 됨 | P1 loading/library empty/filter empty/cloud delay 분리 |
| Calendar | 실제4~6주, row=max(44,base), grid=row×count. 공휴일 caption 최대2줄, media 없음 disabled | day target48, 6주도 축소 금지 |
| day a11y | n일, 공휴일, 미디어 n개/없음; value selected/unselected | TalkBack state, disabled 전달 |
| selection | Photo↔Calendar ordered identifiers. confirm은 Photo Library source만 교체, file/AiShot 유지 | stable MediaStore key |
| import | cancellable progress, 성공 전 완성 clip 노출 금지, rollback | transaction/foreground-safe coroutine |

### 4.3 QUICK_DURATION

| 항목 | iOS 최종 | Android 요구 |
|---|---|---|
| 구조 | header + ScrollView + sticky CTA | 작은 phone/fontScale 모두 도달 |
| header | X / 퀵모드 영상 길이 최대2줄 / media add | 동일 |
| selected | ±5초, caption+primaryNumber22, buttons width72/minHeight56 | target48, min/max disable |
| choices | 30/45초,1/2/3/5분,추천,최소. 2열, gap8/12, minHeight58 | 추천=max(1,count×1), 최소=max(.2,count×.2), max3600 |
| settings | editor 공용 자막/음악/엔딩 summary + ratio | 공용 component/state |
| CTA | 이 시간으로 만들기, height93, sticky | nav inset 포함 |
| ratio | first+5종, visual/hit32, drag min4 | Android target48와 의도 임계 보강. iOS 잔여 P1 |
| round trip | setting/media 후 quick 복귀 | 선택시간을 ViewModel에 보존 |

### 4.4 EDITOR · 설정 패널

| 행 | iOS 최종 | Android 요구 |
|---|---|---|
| panel | radius14, gradient/panelFill, stroke1.15, 기본 row min56 | text에 따라 grow |
| 영상 길이 | arrow.left.and.right, 선택구간/전체영상, visual112×24/hit112×44 | 각 target48 |
| 기본시간 | label width52 한 줄. − 2.0초 + outer128×44, visual24, value min48 한 줄. 적용 outer76×44 visual26 | 단위 포함 한 줄. range0.1~30; step 0.1/0.5/1.0; apply all |
| 라이브 | 사진/영상, visual112×24/hit44 | 사진/모션, target48 |
| 영상 | 한컷/분할, visual112×24/hit44 | single/multiple |
| 묶음 1행 | 묶음사진 + − 1/n + outer118×44, visual24, n1~20 | 대표 간격 저장/재계산 |
| 묶음 2행 | icon spacer24 + 선택 방식 + 자동/수동/전체 width144 visual26/hit44 | 반드시 2행, 각48 |
| 자막 summary | min82. T24 + 자막 + toggle; 문구15; 크기·위치·그림자13 최대2줄 | 같은 위계 |
| 음악 summary | min82. note24 + 음악 + toggle; 곡명; 음악/원본/반복/페이드 | 파일 없으면 disabled |
| 엔딩 summary | min88. map24 + 엔딩 + toggle; theme + duration outer128×44 | 같은 위계 |
| status | visual104×30, actual112×44, 사용/안함, 전체 tap toggle | visual/48 hit 분리 |
| reuse | editor와 quick이 같은 structs | 공용 Compose component |

### 4.5 EDITOR · ClipRow

| 항목 | iOS 최종 | Android 요구 |
|---|---|---|
| list header | 클립 n개, 순서 변경112×34 | action target48 |
| row | position/thumbnail/time/mode/stepper, min 약58 | fontScale에서72~88 grow |
| position | compactNumber13, width32 | 1~999 판독 |
| segments | 사진/영상, 자동/수동/전체, 한컷/분할 visual24~26, outer44 | each48 |
| duration | visual68×20, outer88×44, −/+ each44 | pointer48, visual 유지 가능 |
| parent actions | edit/reset visual30, outer44 each, parent area96 | 48+gap+48 |
| edit | rectangle.stack.fill+pencil, visual y-8만 이동, hit centered | hit offset 금지 |
| reset | arrow.counterclockwise, same | parent/child state regression |
| child | 사용/제외 caption12+icon+selected | stateDescription |
| delete | 공용 reveal→alert. 이 클립을 삭제할까요? / 현재 영화에서 제거됩니다. | project delete와 구분 |
| reorder | group 단위, child는 parent editor | stable ID/relations |

### 4.6 하단 만들기·비율

| iOS 최종 | Android 요구 |
|---|---|
| close52 + ratio52 + wand/총시간/만들기 height52 | sticky, nav inset, 한손 |
| nil ratio는 첫/사진 고정10 semibold, 2줄, fixed vertical, inner34, outer52 | 최대 fontScale에서도 ellipsis 금지. 10sp 고정 예외+TalkBack 첫 사진 |
| fixed ratio icon32, picker hit44 | target48 |
| nil은 첫 유효 source의 회전 보정 비율 | enum/null 저장, 문자열 역파싱 금지 |

### 4.7 CLIP_TRIM

| iOS 최종 | Android 요구 |
|---|---|
| Photo/Live 대신 사진/라이브 | 사진/모션 |
| corner38+hit44, delete32+44, play40+44, loop34+44 | 모두48 |
| header44, playback44, rowTitle/compactNumber | fontScale/landscape clipping 금지 |
| 좌우20% invisible prev/next 유지 | 명시 affordance를 P1로 추가하거나 parity 기록 |
| trim/waveform/play/loop/auto-next/delete confirm | 기존 상태 계약 유지 |

### 4.8 TEXT

| 항목 | iOS 최종 | Android 요구 |
|---|---|---|
| 자동 사용 | onAppear에서 normalize와 session snapshot 후 off면 on | 진입 즉시 on, unsaved change로 save/cancel 노출 |
| header | leading reset. unchanged=X. changed=X 저장 없이 나가기 + floppy 저장 후 닫기 | Cancel/Save 표현 가능, 의미 동일 |
| cancel | snapshot enabled/text/position/font/color/shadow/spacing/size/ending 연관 필드 복구 | immutable snapshot 전체 복구 |
| save | current binding 유지 후 dismiss | project dirty |
| reset | original session 또는 project default | change 표시 |
| content | 자막, toggle, editor, 날짜/기간, font preset, appearance,5×5 | 기존 상세 유지 |
| empty | enabled 가능, text render 없음, ending 독립 | empty를 off로 강제 금지 |
| bug 원인 | 자동 활성화 로직 부재 | cancel restores off, save keeps on test |

### 4.9 MUSIC

| iOS 최종 | Android 요구 |
|---|---|
| 파일 없으면 bundled sample normalize, original enabled 유지 후 snapshot. original off면 화면에서 임시 on | content-first local session |
| off→임시 on만이며 content 동일이면 change 아님; unchanged dismiss에서 off 복구 | commit/rollback 명시 |
| reset + conditional cancel/save/close | TEXT/ENDING과 동일 문법 |
| sample/file/browser, preview, music35%, original100%, loop/fades true | stableTrackId, 0..1 |
| summary min82 | 공용 |
| 6 sample과 라이선스/preview cleanup unchanged | 기존 명세 유지 |

### 4.10 ENDING

| 항목 | iOS 최종 | Android 요구 |
|---|---|---|
| header | reset. unchanged close X. changed cancel X + floppy save | TEXT/MUSIC와 동일 |
| snapshot | enabled,duration,theme,variation,font,textColor,shadow enabled/opacity/color,size,line spacing/scale | cancel에서 전부 복구 |
| reset | projectDefault off,2s,caption,variation0+기본 appearance | preview refresh |
| save | current binding 유지 | project persist |
| UI | 엔딩, toggle, 5 themes, duration44, preview, caption preset | theme target48 |
| themes | 자막/보물지도/여행일정/랜드마크/오피스 | stable enum; treasure reselect variation++ |
| duration | 1~10, step.5, default2 | clamp/step |
| unavailable | sample preview fallback, export data 없음 안전 처리 | crash/corrupt 금지 |
| bug 원인 | 기존 sheet에 X만 있고 snapshot/change/save가 없음 | change/save icon/cancel/save regression |

### 4.11 BROWSER

| iOS 최종 | Android 요구 |
|---|---|
| 음악 또는 상단 i long | long-click+TalkBack action/overflow |
| toolbar visual32, hit44 | target48; 좁으면 overflow |
| favicon tap delete 폐기. favicon long만 homepage | 구형 문서 tap-delete 금지 |
| row 별 trash44→즐겨찾기를 삭제할까요? confirmation | explicit delete+confirm |
| bookmark/back/close/homepage custom actions | TalkBack actions |
| editor reorder/edit/export/all delete confirm | SAF |
| detected video 다운로드/보기/닫기, progress/cancel | DownloadManager/foreground |

### 4.12 GENERATION · PREVIEW · RELEASE · PLAYER

| iOS 최종 | Android 요구 |
|---|---|
| generation blur/dim, thumbnail, title/%/time/cancel | foreground service+cancellable job, validate output |
| preview autoplay zero, 편집/share/개봉/fullscreen | Media3 |
| common player tap, double±10, scrub, pinch/pan, vertical close, loop/fit | 한 controller/component |
| title modal17 line1 tail, time compact13 | ellipsis/tabular |
| phone sensor then portrait restore, iPad current window | phone/tablet/fold 분리 |
| 사진 앱/파일 앱 개봉 | MediaStore/SAF, Photos API 제외 |

### 4.13 COLLECTION

| iOS 최종 | Android 요구 |
|---|---|
| max30/add/2열/pin/order/context/title/memo/AI/compress | 기존 contract, 600dp+ 3열 |
| title15~17, metadata12~13, scrim | 6~9sp 축소 금지 |
| AI device8 + HanClip8 | 두 그룹/수 보존 |
| compression1080/720/540, 더 작을 때만 atomic replace | temp→playable/duration/size→index→old delete |
| common fullscreen player | 별도 gesture 금지 |

### 4.14 AISHOT

| iOS 최종 | Android 요구 |
|---|---|
| 4:3, detecting/detected/saving, sensitivity/duration/zoom/camera/manual | CameraX+AudioRecord/analysis |
| 감도 4종 app persistent, label13, hit44 | hit48+haptic/state |
| close visual40/hit44 | hit48 |
| notice minWidth280/max340,minHeight116,grow | available-32, grow |
| focal label 11 | min11sp |
| short1.5+1.5, normal2+3, long5+5 project scoped | monotonic/ordered |
| preview/capture rotation separate, lens/record reapply | saved MP4 별도 검증 |
| detection algorithm/file cleanup unchanged | 플랫폼 API 치환 |

### 4.15 THEME · COPYRIGHT · SYSTEM

| iOS 최종 | Android 요구 |
|---|---|
| 테마 선택, 색상 구성, 확인. 구형 영문 제거 | 한국어 동일 |
| 6 modes, custom3 reorder | DataStore migration |
| 상단 i tap full copyright: watermark/IAP/sleep/docs/licenses | Play Billing/Android screen flags |
| i long browser 복구+accessibility action | 명시 action |
| global alert title HanClip, dynamic message | 원인+다음 행동 |
| camera/mic/photo/file/save/network/store permissions | Android 권한/설정 이동 |

## 5. 기본값·데이터·영속화

### 5.1 상태 수명

| 계층 | iOS 최종 | Android 요구 |
|---|---|---|
| 화면 | panel/reorder/player zoom/Photo filter-sort-columns/setting snapshot | rememberSaveable/SavedStateHandle |
| 앱 | theme/order, global duration/ratio/similar interval, AiShot sensitivity, sleep, copyright, favorites | DataStore/기존 preference migration |
| project | clips/order/source/duration/trim/modes/ratio/caption/music/ending/preset/memo/pin | versioned JSON+internal media |
| collection | movie/poster/title/memo/pin/order/meta/compressed file | versioned index+transaction |
| registry | imported fonts/files, browser favorites/homepage | stable ID+internal file/URI |

### 5.2 Project 계약

필수 논리 필드:

- projectId, schemaVersion, preset, createdAt, updatedAt.
- ordered clips.
- defaultDuration 0.1…30.
- defaultVideoSegmentMode 기본 multiple.
- outputAspectRatio null/first, 1:1, 3:4, 4:3, 9:16, 16:9.
- caption, backgroundMusic, ending.
- similar-photo criteria와 representative interval.
- memo, pin, pinnedAt.

저장은 temp write→flush→decode verify→atomic replace→backup 순서다. 새 index가 파일을 참조한 뒤에만 이전 파일을 삭제한다.

### 5.3 Clip 계약

- stable id, sourceKind, persistent internal filename/URI, source identifier.
- source width/height/duration, displayDuration, trimStart/trimDuration.
- livePhotoMode still/motion.
- videoSegmentMode와 selected/excluded flag.
- similar group ID, representative/additional selection, parent/child relation.
- capture date/location, optional waveform/impact analysis version.

불변식:

- UI 문자열을 역파싱해 저장하지 않는다.
- source permission/file이 사라져도 프로젝트 전체 초기화 금지.
- isVideoSegmentSelected=false는 삭제가 아니라 결과 제외.
- group ID/order는 재구성 후에도 안정적.

### 5.4 프리셋과 control 기본값

| 기능 | 최종 기본 |
|---|---|
| 새 영화 | duration2s, video split, 오늘 날짜 자막 사용, 음악 없음, ending off/caption/2s |
| 퀵 | duration1s 또는 target/count, 자막 사용/빈 text, 햇살 한 컷 사용, ending off |
| AiShot | 4s, split, 오늘 날짜 green-golf 계열 자막, 음악 없음, ending off |
| 골프 | 4s, split, 오늘 날짜, 골프치러 가자, ending off |
| 여행 | 1s, 대표1/6, travel caption, 여행의 설렘, theme treasureMap. enabled 자동 true는 Swift에서 확인 안 됨 |
| 인생 | 2s, 대표1/3, 오늘 날짜, 음악 없음, ending off |
| 음악 | music .35, original1.0, loop/fade in/fade out true |
| 엔딩 | off,2s,caption,variation0 |
| Photo | photo/live/video, capture ascending,5 columns |
| ratio | stored 값 없으면 first/null |
| AiShot | sensitivity auto app-scope, duration normal project-scope, rear, zoom1 |

### 5.5 Migration fixture

- 가장 오래 지원하는 project.
- segment selected 필드 없는 project.
- imported font/custom watermark project.
- 사진+영상+모션포토+묶음 혼합 project.
- pin/order/title가 있는 collection30.
- compression temp가 남은 collection.
- primary index corrupt/backup 정상.
- off 자막/엔딩을 저장한 구버전 project.

load→semantic compare→save→process restart→reload에서 수/순서/시간/선택/pin/file/hash를 검증한다.

## 6. 오늘 수정된 결함과 원인

| 결함 | 원인 | iOS 최종 | Android 회귀 |
|---|---|---|---|
| 프로젝트 대각 swipe 영구 삭제 | predicted translation에서 즉시 removeItem, confirm/undo 없음 | 72 reveal+trash+alert만 delete | vertical/diagonal fling no delete; TalkBack confirm |
| favorite favicon 오삭제 | tap에 delete 의미 혼합 | long=homepage, 별도 trash+confirm | tap/long/trash 분리 |
| Blossom CTA 대비 | #D65E7A+white 약3.66:1 | #B23E5D | contrast 자동검사 |
| 고정 작은 글자 | fixed point/minScale/frame | token/Dynamic Type/2줄/grow | fontScale/bold/compact |
| 기본시간 2.0/초 2줄 | 좁은 frame+dynamic text | compactNumber, fixed, min48, outer128 | 0.1/2.0/10.0/30.0 한 줄 |
| 묶음 제목/선택 과밀 | 한 row에 title, stepper,3 segments | 대표간격/선택방식 min48 두 행 | compact/fontScale |
| 자막/음악/엔딩 답답함 | 정보와 조작 한 행 압축 | 82/82/88 top status+lower detail | long strings/on-off |
| segment 눌림 어려움 | visual24~26이 hit | outer44 | adjacent mis-tap |
| 묶음 edit/reset 작음 | 30×30, area66 | outer44, area96 | parent/child |
| Photo X 작음 | 38×38 | outer44 | close |
| 엔딩 save 없음 | snapshot/change/save toolbar 없음 | full SessionState+reset/cancel/save | cancel all/save retain |
| 자막 진입 off | auto activation 없음 | snapshot 후 off→on | cancel off/save on |
| 첫 사진 ellipsis | dynamic caption이 34×34 초과 | fixed10, line2 | max font size |
| i 이동 후 browser 상실 | gesture 복원 누락/경합 | exclusive short/long+custom action | short info/long browser |
| Calendar 6주 약31pt | fixed grid184 | row min44×row count | 4/5/6주 |
| Photo VO 정보 없음 | metadata/trait 없음 | date/kind/order/value/selected | TalkBack traversal |

## 7. 변경 파일·주요 심볼

| 파일 | 주요 심볼/영향 | Android 대응 |
|---|---|---|
| HanClip/App/HanClipApp.swift | blossomGlowPrimary, HanClipTypography, hanClipMinimumTapTarget | theme/type/touch tokens |
| HanClip/Models/ClipItem.swift | LivePhotoMode.displayTitle | still/motion label mapper |
| HanClip/Views/EditorView.swift | rootTopHeader, importantInfoButton, homeMoviePresetGrid, defaultDurationPanel, projectGlobalControls, summary rows, status/range segments, Text/Ending/Music sheets, Browser, SwipeToDeleteRow, QuickMovieDurationPicker, Calendar, bottom ratio | root/editor/settings/browser/calendar/quick |
| HanClip/Views/ClipRow.swift | parent edit/reset, VideoDurationStepper, CompactDurationStepper, Live/Similar/Video segments | clip controls |
| HanClip/Services/PhotoPicker.swift | PhotoDurationFilterEditor, header/bottom fonts, DragSelectionPhotoCell | media picker |
| HanClip/Services/AiShotCamera.swift | AiShotCameraView sensitivity/notice/focal | camera UI |
| HanClip/Views/VideoTrimEditor.swift | localized display, hit targets | trim |
| HanClip/Views/HanClipFullscreenVideoPlayer.swift | title/time typography | common player |
| HanClip.xcodeproj/project.pbxproj | build3.11.44 | Android versionCode 독립 증가 |
| PROJECT_RULES.md/.DS_Store | 규칙/환경 | 제품 제외 |

## 8. 검증과 미검증

### 8.1 직접 확인

- git diff --check 통과 기록.
- 3.11.42/.43/.44는 실제 iPhone destination xcodebuild 성공 기록.
- 각 빌드 devicectl install과 bundle com.intosharp.hanclip 버전 조회 성공 기록.
- 최종 조회: HanClip 1.0.1 / bundle version 3.11.44.
- 최종 빌드 새 compile error 없음. PhotoPicker 기존 deprecated UIKit warning은 남음.
- task 전후 XCTest clone directory가 비어 있었다는 기록.

### 8.2 미검증

- 최종 3.11.44에서 자막 auto on→cancel/off, save/on 실기기 조작.
- 엔딩 모든 theme/font/color/shadow/spacing cancel/save 실기기 조작.
- 최대 Dynamic Type에서 첫 사진 실제 두 줄 screenshot.
- compact320, 모든 Dynamic Type/VoiceOver/Bold/Contrast 조합.
- Photo denied/limited/iCloud delay/empty 실제 흐름.
- swipe delete 빠른 대각/멀티터치/복수 row reveal.
- Android 저장소 현재 code/dirty/IOS_PARITY. 이 문서는 Android audit를 하지 않음.
- App Store/TestFlight/release archive/long export/low storage.

### 8.3 알려진 잔여 위험

- Quick ratio visual/hit32와 drag min4.
- Photo 권한/로딩/empty recovery 미완성.
- row local reveal이라 여러 row 동시 reveal 가능.
- iOS 44pt를 Android 48dp로 별도 확대 필요.
- trim invisible navigation zone.
- travel treasureMap theme와 ending enabled 요구 모순.
- 기존 문서 line number는 미커밋 diff로 이동, symbol을 우선한다.

## 9. Android 전수 체크리스트

### P0 데이터·파괴 동작

- [ ] project swipe 즉시 delete 없음.
- [ ] reveal→trash→confirm만 repository delete.
- [ ] clip/project delete 문구와 범위 구분.
- [ ] favorite favicon tap delete 없음, trash+confirm.
- [ ] import/export/compress atomic replace.
- [ ] cancel/failure/process death에서 원본/index 보존.
- [ ] 구버전 project/collection/font/watermark fixture 보존.
- [ ] Text/Music/Ending cancel snapshot 전체 복구.

### P1 핵심 UX·접근성

- [ ] type token과 fontScale1.0/1.3/1.6/2.0.
- [ ] Blossom Main #B23E5D.
- [ ] 모든 interactive 48×48dp.
- [ ] home i 상단, short info/long browser.
- [ ] preset min120,15/13sp,3/2/1열.
- [ ] 기본시간 n.n초 한 줄, stepper/apply 의미.
- [ ] 묶음 대표간격/선택방식 두 행.
- [ ] summary 82/82/88 위계.
- [ ] Text 진입 off→on, cancel off, save on.
- [ ] Ending reset/cancel/save+full SessionState.
- [ ] 하단 첫 사진 완전 2줄.
- [ ] Photo cell 날짜/종류/선택순번 TalkBack.
- [ ] Calendar4~6주 target48/disabled.
- [ ] Quick scroll+sticky CTA+round-trip state.
- [ ] common fullscreen player/orientation.
- [ ] AiShot controls/notice 가독성과 target.
- [ ] Photo permission/loading/empty recovery.

### P2 시각·운영

- [ ] radius/elevation/type token 일관성.
- [ ] Android 사용자 용어 모션포토.
- [ ] theme/copyright 한국어.
- [ ] 긴 URL/title/location/holiday/999 selection wrap/ellipsis.
- [ ] reduced motion/dark/contrast/bold.
- [ ] phone/fold cover/fold open/tablet/split/landscape.
- [ ] release assemble/lint/migration/cold start/long export/low storage.
- [ ] intentional platform differences in IOS_PARITY.md.

## 10. Android 우선 구현 순서

1. P0 저장소/삭제/migration.
2. 공통 design/type/hit token.
3. EDITOR/ClipRow/TEXT/MUSIC/ENDING.
4. PHOTO/CALENDAR/IMPORT/QUICK.
5. HOME/BROWSER.
6. TRIM/PLAYER/COLLECTION/AISHOT.
7. 전 화면 회귀와 release gate.

각 묶음은 기존 Android 구현을 동일 / 구현됨-미검증 / 부분 / 누락 / 플랫폼차이로 먼저 판정한다. 기존 기능을 근거 없이 폐기하거나 Swift 구조를 그대로 복사하지 않는다.
