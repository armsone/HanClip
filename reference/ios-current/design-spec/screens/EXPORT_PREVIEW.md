# 제작 준비 · 합성 · 취소/오류 · 시사회 · 개봉/저장

## 역할/경로

- EDITOR/QUICK 만들기 → generation overlay → `VideoPreviewView`; 시사회에서 편집/공유/개봉.
- 소스 `EditorView.swift` progress/preview presentation, `HanClipFullscreenVideoPlayer.swift` 공통 전체화면 player, ViewModel export/save methods.

## 제작 진행 UI

- root를 blur2하고 zIndex100 overlay로 입력 차단.
- 중앙 panel: current preview thumbnail(실제 output ratio, max dimension260, radius16), progress message, ProgressView, %, 처리시간/예상시간. 영상 preview rendering이면 header X=`제작 취소`.
- thumbnail은 전체 opacity50% 위에 진행률만큼 원본 opacity mask를 좌→우로 덮는다. white38% stroke, shadow Sub10% radius10/y5.
- 상태: 준비/소스 불러오기/분석/합성/마무리, 완료, 취소 중, 실패. `progressMessage`를 단일 진실로 사용.
- 실패 alert title `HanClip`, button `확인`; decoder 오류는 `Cannot Decode`와 media 범위를 ViewModel/Composer가 제공한 그대로 표시.

## 시사회 UI

1. 공통 header/title.
2. preview player: horizontal18, max width, 1:1 outer frame, radius26, white38% stroke, shadow Sub10% radius16/y8. 실제 영상은 aspect fit/fill surface.
3. 우상단 fullscreen 42 circle: `arrow.up.left.and.arrow.down.right` 15 black.
4. persistent progress bar.
5. bottom HStack gap12/horizontal18: `다시 편집` flexible height48; share 54×48 circle; `개봉하기` flexible height48 Main→Sub gradient.
- onAppear audio playback session activate, seek zero, autoplay. surface tap play/pause.

## 전체화면 시사회

- black background, system overlays hidden. autoplay/loop, fit·fill 구성, tap controls, 좌/우 double tap ±10초, scrub, pinch zoom/pan, 아래 swipe close를 공통 player가 처리한다.
- phone은 orientation observer와 방향 정책을 사용하고 종료 시 portrait 정책을 복원한다. iPad/large window는 현재 window orientation을 존중한다. close/share/title은 safe-area 아래에 둔다.

## 개봉 UI

- 시사회 위 full-screen overlay. top header + `개봉` title.
- central material card radius30/padding22: primary `사진 앱으로 개봉` height56 + `앨범`/앨범명 field; secondary `파일 앱으로 개봉` height50. 하단 `취소` 146×48.
- 아래 drag >60 pt 또는 X/취소=시사회 복귀 및 재생. 저장 선택은 overlay를 animation 없이 즉시 숨긴 뒤 Photos/file exporter.

## 저장 상태

- 사진 저장은 album name(기본값은 View local 값 확인 필요), 권한/진행/완료/실패. 파일은 `HanClip-yyyyMMdd-HHmm.mp4`.
- 성공 message: files `선택한 위치에 개봉했습니다.`; Photos message는 ViewModel 구현 기준.
- 시사회 share/fullscreen dismiss 후 audio session 재활성화 및 play.

## 타이포/아이콘/접근성

- actions 15~17 semibold/bold. progress values rounded monospaced. icons: `chevron.backward`, `square.and.arrow.up`, `square.and.arrow.down`, `photo.on.rectangle`, `folder`, `xmark`.
- player surface label `시사회 재생 또는 일시정지`; fullscreen/share/개봉 버튼 contentDescription.

## 반응형

- preview frame는 phone portrait에서 square container. fullscreen은 orientation별. Android landscape gesture axis/close direction은 physical orientation에 맞춰 변환.

## 컨트롤 기본값/수명

- [CONTROL_DEFAULTS.md](../CONTROL_DEFAULTS.md#재생반복정렬). 시사회는 매 진입 autoplay from zero; fullscreen loop/aspectFill on, controls hidden. 이러한 player state는 프로젝트 저장 대상 아님.

## Android

- 장시간 export는 foreground service+notification 병행. UI cancel은 같은 task token을 취소. MediaStore/SAF 저장 차이만 플랫폼화하고 HanClip `개봉` 용어/상태 흐름은 동일.
