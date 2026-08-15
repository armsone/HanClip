# 영화 제작 · 클립 설정 · 추가 · 순서 변경 · 클립 미리보기

## 역할/경로

- 프리셋, 저장 영화 load, AiShot 결과, 시사회 `다시 편집`에서 진입. 저장/홈 또는 만들기로 종료.
- root는 `model.isProjectOpen`일 때 `clipEditor`. clip tap은 `VideoTrimEditor` full-screen cover.
- 근거 `EditorView.swift:4700-7950`; `ClipRow.swift`; `VideoTrimEditor.swift`.

## 위→아래 UI 계층

1. 공통 header: 로고/닫기 성격, 우측 media add.
2. 프로젝트 제목/메모/설정 header.
3. `클립 설정` title row: 어디든 tap하면 접힘/펼침. 오른쪽 끝 preset badge, 가운데 expand chevron.
4. 펼침 rows(모두 가장 두꺼운 행 높이에 통일): 영상 길이, 기본시간, 모션포토, 영상, 묶음사진, 자막, 음악, 엔딩.
5. `클립 n개` title row + 오른쪽 `순서 변경`.
6. clip rows 또는 reorder grid. 묶음 parent 아래 child photos/videos.
7. bottom make/aspect ratio/close actions.

## 치수/표면/텍스트

- 설정 외곽은 rounded panel, theme panelFill/stroke. 각 row divider는 separator. stepper center column은 기본시간·묶음·엔딩이 같은 x/폭을 사용.
- title row와 list title row의 색상은 동일 primaryText/section fill.
- 기본시간 stepper: `− <n.n초> +`와 우측 `적용`. 영상 길이 `선택구간/전체영상`.
- 모션포토 `사진/영상`; 영상 `한컷/분할`; 묶음 `− 1/n +` + `자동/수동/전체`.
- 자막: title/현재 문구 2행 + `사용/안함`; 음악: 선택곡/안내 + toggle; 엔딩은 음악 아래, `엔딩:` + 다음 행 동일 font/weight의 theme명, center stepper, toggle.
- preset badge는 `새 영화/퀵모드/AiShot/여행 영화/인생 영화/골프 영화/기존 영화`, icon은 `MoviePreset.systemImage`.

## 아이콘

- settings `slider.horizontal.3`, duration arrow/timer, Live Photo `livephoto`, video `film`, group `rectangle.stack`, caption `T`/`captions.bubble.fill`, music `music.note`, ending `map.fill`, reorder `square.grid.2x2` 또는 up/down.
- Android: Live Photo label/icon을 모션포토로 현지화; `figure.golf` custom.

## 입력 동작

- settings title row 전체 tap으로 expand/collapse; chevron은 행 수직 center.
- 모든 segmented row는 segment 어디를 눌러도 전환. stepper의 시각 버튼보다 hit area 확대.
- 기본시간 `적용`은 모든 대상 clip에 반영. 모션포토/영상/묶음 bulk control도 전체 적용.
- clip tap=preview/editor. 묶음 parent tap/수동 mode=children 확장; child는 사용/제외.
- reorder는 group을 하나의 tile로 drag. 영상 parent의 child 순서는 parent preview에서 drag/drop.
- aspect ratio bottom panel은 tap과 horizontal drag 모두 선택.

## 상태

- clips 0: list 0, make 없음, i 버튼. clips 있음: make button.
- settings collapsed/expanded; reorder normal/active; group auto/manual/all; child used/excluded; video single/multiple; load/save/import/render progress; 오류 alert.
- clip preview: 사진/모션포토/영상, 이전/다음/처음, trim, play/pause, loop/auto-next, delete confirm, waveform/peak. 영상 분할 peak가 없으면 한컷으로 자동 reset하고 notice.

## 타이포/접근성

- section title 12 black, primaryText76%; row main 14~16 bold/semibold, detail 10~12. time는 rounded/monospaced.
- 각 segmented control에 label/value. child 연결 세로선은 parent thumbnail 좌측에 붙여 parent 관계를 시각/접근성 description으로 전달.

## 반응형

- phone full width with horizontal 14~18. regular-width 핵심 콘텐츠는 최대 920pt. landscape에서도 의미적 rows와 선택을 유지한다. Android는 600dp 이상에서 clip 2열, header/전역 설정은 전체 읽기 폭을 유지한다.

## 컨트롤 기본값/상태 수명

- [CONTROL_DEFAULTS.md](../CONTROL_DEFAULTS.md#영화-제작클립-설정) 및 [프리셋 초기값](../CONTROL_DEFAULTS.md#프리셋-초기값). clip별 값과 설정은 프로젝트에 저장/복원되며 UI 펼침/reorder mode만 세션 상태다.

## Android 의미

- project criteria는 저장 영화 load 후 현재 grouping 기준을 재적용한다. UI만 복원하지 말고 `reapplyCurrentProjectCriteria()` 의미를 동일하게 구현.
- 모션포토 pair가 없으면 정지 fallback. 삭제와 제외는 구분한다.
