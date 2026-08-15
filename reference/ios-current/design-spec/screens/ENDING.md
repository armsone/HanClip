# 엔딩 · 여행 기록 · 5종 정보 카드

## 역할/경로

- 편집의 음악 아래 `엔딩` 행 또는 퀵 설정 그룹에서 full-screen. 영화 마지막에 촬영기간과 도시 이동을 독립 카드로 1~10초 삽입.
- 자막과 분리되어 자막 text가 없어도 사용 가능. 위치 데이터가 현재 없어도 설정을 미리 켤 수 있다.
- 소스 `WatermarkSettings.swift:205-255,315-540`; `EditorView.swift:1007-1035,11952-12373`; renderer `EditorViewModel.swift:2160-2580`.

## 위→아래 UI

1. 공통 header/닫기.
2. top control: 사용/안함, 표시시간 `− n.n초 +`, theme tabs 순서 `자막·보물지도·여행일정·랜드마크·오피스`.
3. 현재 output aspect ratio 그대로의 실제 render preview.
4. caption theme일 때 자막 font preset/color/shadow/size/line-spacing controls.

## 카드 공통 데이터 규칙

- heading는 `여행 기록`.
- 기간: 첫 media date→마지막 date. 같은 날이면 한 날짜만.
- 위치는 media 순서. 바로 이전과 같은 위치는 중복 생략; 날짜가 바뀌면 같은 도시도 새 일정.
- 대한민국은 도시명만. 해외는 첫 stop과 국가 변경 때 국가명을 표시하고 이후 중복 국가 생략.
- 국가 이동=`airplane`, 지역 이동=`car`. 이동 icon+지역명은 한 덩어리. 도시 이름은 줄바꿈하지 않으며 공간 부족 시 font 축소.

## 5종 테마

| 테마 | 배치/표면 | icon/font 규칙 | 재선택 |
|---|---|---|---|
| 자막 | 현재 자막 preview와 같은 glass/색/배경, 날짜+route text | 현재 자막 font/color/shadow/line spacing | 일반 선택 |
| 보물지도 | parchment/고전 지도, 한 도시→점선→다음 도시, compass/X 장식 | 옛 지도 계열 font; dotted curved route | 선택된 theme 재탭 시 variation 증가해 새 경로 |
| 여행일정 | 실제 촬영 날짜별 itinerary path; DAY 번호 금지 | 날짜 badge, route/activity icons | 일반 |
| 랜드마크 | 지역별 landmark/emoji를 route 순서로 다수 배치 | iPhone 기본 emoji와 등록 landmark, unknown fallback travel icon | 일반 |
| 오피스 | document number, 촬영기간, 날짜·지역·이동수단 table의 정형 보고서 | 동일 크기/weight, 지역명 한 줄 | 일반 |

## 치수/타이포/표면

- control은 preview 위쪽. preview는 output aspect ratio에 맞춰 width를 계산하며 실제 renderer image를 표시.
- display time step .5s, min1/max10; button hit target은 48 이상. theme item text와 icon은 1줄/selected radio.
- caption text wrapping은 단어 중간 분할 금지. 지역명 내부 공백도 non-breaking unit. 안 맞으면 minimum font.
- 정확 renderer 좌표/색은 `endingInfoPreviewImage`와 theme switch가 기준이며 Android canvas에 같은 normalized 위치로 이식한다.

## 상태

- disabled/off, enabled but data unavailable(설정 유지/preview placeholder), loading geocode/render, preview ready, render failure.
- reverse geocode 결과가 없으면 raw location 표시 여부는 소스 서비스 결과에 따르며 임의 도시 추측 금지.

## 접근성/반응형

- theme label+selected state; stepper label/value; preview는 기간과 stops를 합친 description.
- portrait/landscape/1:1 등 모든 output ratio에서 도시명 한 줄 보장. landmarks가 많으면 중요도를 낮춘 장식부터 생략.

## 컨트롤 기본값/수명

- [CONTROL_DEFAULTS.md](../CONTROL_DEFAULTS.md#엔딩). 기본 off/2s/caption/variation0. 여행 preset은 theme treasureMap으로 설정하지만 enabled까지 true로 바꾸지 않는 현재 소스 차이가 있어 Android도 제품 확인 전 임의 자동 활성화 금지.

## Android 차이

- iOS emoji/landmark glyph 폭이 Android와 달라 line measurement를 Android font로 다시 하되 의미·순서 유지. geocoder locale은 한국 내 ko, 해외 en을 사용한다.
