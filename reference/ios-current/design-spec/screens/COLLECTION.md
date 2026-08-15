# 컬렉션 · 포스터 · AI 썸네일 · 용량 줄이기 · 플레이어

## 역할/경로

- 홈의 비디오가게 선반. 완성 영상을 사진(공용 사진/달력 UI, videoOnly) 또는 파일(.movie multi)에서 가져온다.
- poster tap→full-screen player; long press→context menu; compress sheet/AI 후보 full-screen.
- 소스 `EditorView.swift` collection presentation/context/progress; `MovieCollectionStore.swift`; 공통 player `HanClipFullscreenVideoPlayer.swift`.

## 목록/포스터

- title row `n/30 … 컬렉션`, 2열(horizontal18/gap10/row12). poster ratio1:1.38 radius12. add poster는 마지막에 배치; 30개면 숨김.
- poster title은 가운데보다 약간 아래, poster typography. metadata: 위치를 최상단, 파일크기는 영상시간 위; 제작일과 촬영일이 같으면 제작일만. 제목 long edit는 multiline, keyboard 위를 넘으면 내부 scroll.
- pin: pinned `CollectionPin` 51×51 in 64 hit, offset y -26; 목 절반이 poster 상단에 걸침. unpinned는 바늘 위치 중심의 18×18 검정 paper hole in 44 hit, y12.
- poster 전체 위에 clear button을 하나 두고 card는 hit testing false로 해 좌/우 오선택을 막는다.

## 동작

- poster tap=정확 해당 movie player. pin button은 poster tap과 별도.
- context: `핀 고정/핀 해제`, `제목 수정`, `썸네일 AI 재선택`, `파일 용량 줄이기`, `공유`, `컬렉션에서 제거`.
- pinned만 draggable. 다른 pinned 위 drop으로 pinned order 변경.
- import 중 progress `컬렉션으로 가져오는 중 completed/total`; AI auto poster `AI가 컬렉션의 최고 순간을 고르는 중 completed/total`.

## AI 썸네일 후보

- full-screen, 실제 컬렉션 poster 크기/overlay(title/pin/metadata)를 후보마다 합성해 보여준다.
- `디바이스 AI` 8개(왼쪽), `한클립 AI` 8개(오른쪽), 총16. 재생성은 이전과 다른 frame/결 후보를 요청. 선택 시 poster 저장.
- 후보 생성의 “AI”는 source frame scoring/feature 분석이며 외부 생성형 이미지로 추측하지 않는다. 실제 알고리즘은 `MovieCollectionStore` candidate generation 경로.

## 용량 줄이기

- context sheet title `파일 용량 줄이기`, 현재 `<width>×<height> · duration · size`; options 1080/720/540(각 title/detail/예상 약 size), 결과가 원본보다 크면 원본 유지.
- 홈 bulk는 접힘 28pt capsule. 펼침: 720p/540p, 이미 이하 해상도 skip.
- 진행: `<title> 용량 줄이는 중`, %, cancel, progress bar.

## 플레이어

- full-screen black. safe title/close/share, video center, 약 3초 auto-hide controls. portrait/landscape 모두 지원.
- 최신 공통 player는 좌/우 double tap ±10초 seek, progress scrub, 아래 swipe close를 제공한다. orientation별 축을 물리 화면 기준으로 변환한다.
- pinch zoom portrait/landscape; zoom>1에서 one-finger pan. 확대 중 pan이 scrub/close보다 우선한다.
- controls는 일정 시간 후 숨김; tap 재표시. system overlays hidden.

## 상태

- empty/data/max30; import/loading/failure; black first frame 방지 thumbnail search; pin/unpin/reorder; AI loading/candidates/retry/error; compress info loading/progress/cancel/failure; player portrait/landscape/zoom/control hidden.

## 타이포/표면/아이콘

- poster title/metadata는 theme text + poster contrast layer. metadata font는 초기 디자인보다 1.5배 확대된 현재 소스 값을 기준으로 직접 추출 필요.
- icons `books.vertical.fill`, `plus`, `archivebox`, `sparkles`, `arrow.down.right.and.arrow.up.left`, `square.and.arrow.up`, `trash`, `pin/pin.slash`; `CollectionPin` custom.

## 접근성/반응형

- poster label에 title/location/date/duration/size/pin. context actions destructive 표시. zoom scale와 player time 읽기.
- phone 2열, 600dp 이상 Android tablet/폴드 펼침은 3열 고정. player는 모든 orientation. iPad/large window는 현재 window orientation을 사용하고 phone만 센서 방향 정책을 전환한다.

## 컨트롤 기본값/수명

- [CONTROL_DEFAULTS.md](../CONTROL_DEFAULTS.md#홈테마컬렉션), [재생](../CONTROL_DEFAULTS.md#재생반복정렬). movie/pin/order/title/poster/compressed file은 collection store 영속; bulk 펼침과 player zoom/control은 세션.

## Android

- videoOnly picker, 30 limit, metadata rules, candidate count/overlay를 동일. ML Kit/MediaMetadataRetriever 차이가 있어도 두 후보군 명칭과 HanClip scoring 의미를 보존.
