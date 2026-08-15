# 사진 · 달력 · 가져오기

## 역할과 경로

- 홈/편집/퀵/컬렉션에서 미디어 선택. 사진↔달력은 같은 full-screen cover에서 선택 identifier를 공유하고 0.11s crossfade.
- 확인/추가는 import task, 취소는 호출 문맥으로 복귀.
- 소스: `EditorView.swift:653-681, 1100-1210, 1340-1395, 18289-19650`; `PhotoPicker.swift`.

## 위→아래 UI

- PHOTO: safe header `취소 | 사진(달력 전환) | n개 추가`; filter/sort; centered 날짜; rounded thumbnail grid; bottom floating `필터·전날·오늘·해제·추가`.
- CALENDAR: `취소 | 달력(사진 전환) | 추가`; month/year controls; 날짜 grid; 선택 날짜 thumbnail/preview; bottom `전날·오늘·해제·확인`.
- preview: 누른 cell 주변(우선 위, 불가 시 아래)의 화면 약 25% floating panel. control은 위쪽; 바깥 tap 닫기. 선택 항목은 `제거`, 미선택은 `닫기`.
- IMPORT: origin blur/dim 위 progress title/value/bar/cancel.

## 치수·표면

- header는 공통 capsule/glass. 날짜 label centered rounded rectangle. thumbnails rounded; 선택 시 이미지+테두리를 안쪽으로 축소한다.
- 기본 5열; pinch 단계 1/3/5/8. 마지막 media가 bottom floating buttons 위로 올라오도록 content inset.
- selected check는 기존의 80%, Main, 우하단. 좌하단 media-kind badge는 theme background 80% 불투명.
- preview는 panelFill/material + panelStroke + shadow. bottom sheet 애니메이션 금지.
- UIKit의 정확 cell gap/font는 `PhotoPicker.swift` layout/UIFont 상수를 Android 구현 시 직접 매핑하며 확인되지 않은 수치를 추측하지 않는다.

## 텍스트·아이콘

- filters(복수): `전체`, `사진`, `라이브포토`, `영상`; Android는 `모션포토`.
- duration filter: `이상`/`이하`, 분/초. 적용 시 영상만 결과에 남김.
- sort: `날짜순`, `추가순` + up/down arrow; 같은 항목 재탭 시 방향 반전.
- preview: play/pause, scrubber, loop. Calendar preview는 동일 구성에 제거 동작.

## 제스처

- 좌우 drag로 selection 시작; 상하 이동으로 행을 넘겨 계속 선택. 상/하 edge 접근량에 비례해 auto-scroll 가속.
- long press 0.45s=고화질 사진/모션포토/영상 preview. control tap은 닫힘 gesture를 consume.
- pinch=1↔3↔5↔8열.
- `전날`: 선택 없음→어제, 선택 있음→선택 날짜 전날. `오늘`: 첫 tap 이동, 다시 tap visible 오늘 media 선택. `해제`: clear.

## 상태

- 사진 권한 미결정/거부/제한/허용, iCloud 원본 download, empty result, loading, selection, preview, import progress/cancel/failure.
- 취소 시 task cancel 및 이번 import ID rollback. 50개 이상도 batch/asynchronous, 개수 제한 없음.
- collection 경로는 영상만 보여준다.

## 반응형·접근성

- orientation/window 변화 시 grid를 재계산하고 선택 순서를 보존한다. landscape에서도 물리 상/하 edge auto-scroll. Android 600/840dp 열 수 차이는 플랫폼 대응값으로 실기기 검증한다.
- cell label은 종류/날짜/duration/selection 순번. filter는 selected state. preview control과 dismiss target 분리.

## 컨트롤 기본값과 상태 수명

- [CONTROL_DEFAULTS.md](../CONTROL_DEFAULTS.md#사진달력가져오기). 선택 identifier는 사진↔달력과 재진입에서 공유되며, 확인 시 Photo Library 출처를 새 선택으로 교체하고 file 출처는 유지한다.

## Swift 근거/Android

- duration editor `PhotoPicker.swift:100-330`; picker/gestures `341-3200`; long press `782-788, 1481+`; calendar `EditorView.swift:18289-19650`.
- Android는 MediaStore URI를 stable key로 사용. 추가순은 `DATE_ADDED`/`DATE_MODIFIED` 중 iOS modificationDate 대응 검증 필요.
