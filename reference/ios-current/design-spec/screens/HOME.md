# 홈 · 영화 프리셋 · 통합 영화 목록 · 미디어 메뉴

## 역할과 경로

- 진입: 앱 시작, 편집에서 저장 후 홈/저장하지 않고 홈, `hanclip://open`.
- 종료: 프리셋/저장 프로젝트/컬렉션/미디어 메뉴를 통해 전환. 홈은 navigation bar가 숨겨진 root다.
- 호출: `EditorView.activeRootContent`, `emptyState`, `rootTopHeader`, `mediaImportMenu` (`EditorView.swift:280-340, 1221-1350, 2074-2115, 3015-4010`).

## 위→아래 UI 계층과 치수

1. safe-area header: height 58, top 6, horizontal 14. 좌측 HanClip logo pill(폭 154), 우측 media-add pill.
2. ScrollView top 22: 우측 정렬 `영화 프리셋` title line, 아래 8.
3. 3×2 preset grid: horizontal 14, column 8/row 10; card height 108/radius 8. 아이콘 tile 40×40/radius 8.
4. `n/10` + `영화 목록`, horizontal 18. 저장 rows; 프로젝트가 2개 미만이면 합계 2행이 되도록 silhouette.
5. top 10의 `n/30` + `컬렉션`; 2열 poster(horizontal18, gap10, row12), 1:1.38/radius12.
6. shelf edge, bulk compression control, build 2행, bottom 24. bottom safe inset에 44×44 i button(bottom8).

## 표면·타이포그래피

- 전체 background gradient. preset card는 Background97%→PanelFill84%→accent7%(퀵 12%), 1 pt accent30%/panelStroke72%, shadow Text6% radius7/y4.
- icon tile accent→secondaryAccent, onSecondary glyph, white22% stroke, accent16% shadow radius5/y3.
- preset title 12 bold 1줄(min scale .76), subtitle 9 semibold 1줄(.68). count 12 semibold. build 11 bold monospaced.
- shelf edge Main76%→Sub50%→Main70%, height9; black16% top line 2; shadow black22% radius5/y4.

## 텍스트·아이콘·에셋

- `새 영화 / 모든 것의 시작` (`film.stack.fill`)
- `퀵모드 / 고르면 바로 영화로` (`bolt.fill`)
- `AiShot / 스마트한 레코딩` (`AiShotIcon` 25×25)
- `여행 영화 / 여행을 추억으로` (`airplane`)
- `인생 영화 / 삶의 순간을 한 편으로` (`heart.fill`)
- `골프 영화 / 공도 넣고 기억도 넣고` (`figure.golf`, Android custom vector)
- section: `square.grid.2x2.fill`, `rectangle.stack.fill`, `books.vertical.fill`.
- collection add: `HANCLIP`, `ADD A FILM`/`IMPORTING`, `COLLECTION`; pin asset `CollectionPin`.
- bulk: `컬렉션 용량 줄이기`, `720p 일괄 변환`, `540p 일괄 변환`, `선택한 해상도 이하인 영상은 그대로 둡니다.`
- media menu: `AiShot`, `사진`, `달력`, `파일`; icons `AiShotIcon`, `photo.on.rectangle`, `calendar`, `folder`.

## 동작

- 로고 tap=다음 테마; 0.6s long press=테마 패널. media-add tap=anchored menu.
- preset tap=해당 preset. saved row tap=load. AiShot도 통합 목록이며 종류 icon으로 구분.
- poster tap=player; long press=context menu; pin tap=toggle; pinned만 long-drag reorder.
- i tap=카피라이터; 0.55s long press=외부음악 브라우저.

## 상태

- project 0/1/2+: silhouette 2/1/0. 최대 10.
- collection 0: add만+bulk disabled; 1~29: posters+add; 30:add 숨김.
- progress: collection import/compress/AI poster panel. 공유 inbox는 root blur2 위 50% 높이(min360/max455) banner.
- 접근성: logo `HanClip`; preset label=title/hint=subtitle; i=`카피라이터`; pin=`컬렉션 핀 고정/해제`.

## 반응형

- iPhone preset 3열, collection 2열. 좁은 폭은 minimumScaleFactor. iPad regular-width는 루트 최대 920pt 안에서 표시된다. Android는 600dp 이상에서 일반 영화 2열·컬렉션 3열을 사용한다.

## 컨트롤 기본값과 상태 수명

- 상세 기준은 [CONTROL_DEFAULTS.md](../CONTROL_DEFAULTS.md#홈테마컬렉션)를 따른다. 홈에서 영속적인 값은 theme(UserDefaults), saved projects/collection(디스크)이며 media menu 자체 선택은 영속하지 않는다.

## Android 동일 의미

- 통합 영화 목록, limits(10/30), 3×2/2열, pin 상태/순서를 유지. iOS `Menu`는 anchored dropdown. Live Photo는 `모션포토`.
