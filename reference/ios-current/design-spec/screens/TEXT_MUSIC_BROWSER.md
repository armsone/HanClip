# 자막 · 음악 · 외부음악 브라우저/즐겨찾기/다운로드

## 역할/경로

- 자막/음악은 편집 설정 행 또는 퀵 설정 그룹에서 full-screen 진입. 설정 변경은 model binding에 즉시 반영하고 닫으면 호출 화면으로 복귀.
- 음악 파일은 audio file importer, 외부음악은 embedded browser. i 버튼 long press도 browser로 직접 진입.
- 소스 `EditorView.swift:934-1006, 9437-11906, 12696-15020`.

## 자막 UI 계층

1. 공통 top header: 로고/닫기, X, 저장/확인 동작.
2. title/status (`사용/안함`).
3. 실제 비율 preview의 multiline text editor; 오늘 날짜/촬영기간 삽입 button은 font preset 위.
4. font preset strip/grid; 같은 preset 재탭은 읽기 어려울 때 배경색 random variation.
5. 위치 5×5, 크기, 행간, 색, shadow; advanced font panel; installed/file font picker.

## 자막 치수/타이포

- preview/editor는 selected output ratio를 보존. 기본 입력 높이는 고정 최소값 후 텍스트가 화면 높이를 넘을 때만 증가하며 keyboard 위 가용 높이를 넘으면 내부 scroll.
- 삽입 buttons는 작은 keyboard-theme capsule: `오늘 날짜 삽입 | 촬영 기간 삽입`.
- 기본 text: `yy. M. d. (EEE)` ko_KR. 촬영 기간은 같은 날 1회, 다른 날 `빠른 날 ~ 최근 날`; 줄바꿈 시 `~`와 뒤 날짜를 함께 유지.
- 위치 이름은 내부 공백이 있어도 한 의미 단위, 이동 icon까지 함께 줄바꿈; 안 맞으면 font 축소.

## 자막 상태/동작

- text가 비어도 `사용` 선택 가능(엔딩만 사용 가능). 기본 text를 사용자가 수정하지 않았으면 날짜 삽입은 replace; 수정했으면 cursor 위치 insert.
- 25-position selection, font/size/color/shadow/line spacing 즉시 preview. cancel 시 session snapshot 복원 여부는 `TextOverlaySettingsSheet.SessionState` 경로를 따른다.
- font picker는 설치 서체와 파일 서체를 별도 full-screen cover.

## 음악 UI 계층

1. header/title + 사용 toggle.
2. 현재 파일/샘플 summary와 play state.
3. sample list:
   - `햇살 한 컷 / 잔잔한 생활 이야기`
   - `여행의 설렘 / 밝은 피아노와 퍼커션 여행`
   - `광고 클래식 드라마 / 오스티나토와 텐션`
   - `골프치러 가자 / 경쾌한 출발과 기대감`
   - `지우에게 첫눈이란 / 첫눈을 본 5살 아이의 감정`
   - `베이비 워킹 / 작고 경쾌한 첫걸음`
4. 파일/브라우저 import.
5. music volume/original audio sliders, 반복/fade in/fade out toggles.

## 브라우저 UI/상태

- NavigationStack + WebView. URL/favorite/download controls는 theme glass/capsule. favorites는 full-width floating panel이고 항목 수에 따라 아래로 성장, 화면을 채우면 내부 scroll.
- favorite favicon tap=삭제, long press=첫 homepage 지정. editor에서 reorder/edit/export; `.hanclip` favorite file import 시 같은 URL은 덮어쓰고 새 URL 추가.
- 공식 entry는 Pixabay Music/Mixkit Music. HanClip은 외부 음원을 내장하지 않는다.
- detected media에서 download 시작 시 고가시성 `browserDownloadPanelFill`, 진행바/%, cancel/minimize. 완료 시 audio는 background music, video는 media/shared inbox. 로딩/탐지 없음/진행/완료/취소/실패 상태를 구분.

## 아이콘/표면

- 자막 `captions.bubble.fill`, font `textformat`, 위치 grid; 음악 `music.note`, play/pause, repeat, fade; browser `globe`, star/bookmark, download, xmark.
- 공통 gradient/theme 토큰. download panel은 일반 panelFill의 두 배 계열인 `browserDownloadPanelFill` 사용.

## 반응형/접근성

- preview 비율을 보존하고 scroll. 긴 제목/지역명은 잘림보다 font 축소. sliders는 값(%), toggles는 상태를 읽는다.
- WebView control은 웹 컨텐츠와 앱 toolbar accessibility 순서를 분리.

## 컨트롤 기본값/수명

- [CONTROL_DEFAULTS.md](../CONTROL_DEFAULTS.md#자막), [음악](../CONTROL_DEFAULTS.md#음악). 자막·음악은 프로젝트 저장/복원. browser favorites/homepage는 앱 저장; 순간 play/download는 세션/task 상태.

## Swift 근거/Android

- `TextOverlaySettingsSheet:9437-11369`, `BackgroundMusicSettingsSheet:12696-13259`, `OnlineMusicBrowserView:13331-14098`, favorites editor `14099-14366`.
- Android WebView download는 DownloadManager/foreground notification을 사용하되 앱 내 progress/cancel 의미를 동일하게 유지.
