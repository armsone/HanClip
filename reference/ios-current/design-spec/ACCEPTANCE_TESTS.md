# HanClip Android 수용 테스트

## 1. 판정 규칙

- P0: 출시 차단. 데이터 손실, 핵심 흐름, 잘못된 영상, crash/ANR, 권한/취소 복구.
- P1: 동등성 차단. 세부 동작, 상태 수명, 주요 레이아웃·접근성.
- P2: 개선. 극단 기기/성능 튜닝과 시각 미세 차이.
- 모든 실패는 재현 기기/폭, 앱 빌드, 입력 자산, 기대/실제, 로그 또는 캡처를 남긴다.
- 시각 비교는 OS 상태바/폰트 raster 차이를 제외하되 정보 위계, 수치, 정렬, 조작 위치와 상태는 같아야 한다.

## 2. 기준 기기 매트릭스

| 클래스 | 필수 상태 |
|---|---|
| phone compact | 세로, 가로 전체화면, dark/light, font 1.0/1.3 |
| fold cover | 세로, 좁은 폭, cutout |
| fold unfolded 또는 600dp+ | 세로/가로, 접힘 왕복 |
| tablet 800dp+ | 세로/가로, 3열 컬렉션, 2열 일반 영화/편집 |
| API 경계 | minSdk(API 26) + 최신 target API 기기/에뮬레이터 |

## 3. P0 핵심 시나리오

### AT-001 기존 데이터 업그레이드

준비: 이전 배포 빌드에서 프로젝트 3개, pinned 컬렉션 5개, 가져온 글꼴, 사용자 로고, 브라우저 즐겨찾기 생성.

절차: 새 APK를 `adb install -r`로 설치 → 앱 cold start → 각 프로젝트 열기 → 하나 저장 → process kill/restart.

기대: 항목 수·순서·pin·clip 시간·자막/음악/엔딩·파일이 유지되고 silent reset/전체 삭제가 없다.

### AT-002 새 영화 왕복

사진 2 + 영상 1 선택 → 편집에서 순서, 사진시간, trim, 자막, 음악, 엔딩 변경 → 저장 → 홈 → 다시 열기.

기대: 화면과 최종 렌더 설정이 동일하며 입력 순서와 duration이 유지된다.

### AT-003 편집 종료 3종

기존 프로젝트를 열고 변경한다.

- 홈: 이번 세션 변경을 되돌리고 홈 이동.
- 저장: 변경 저장, 편집 유지, 이후 홈의 취소 기준은 새 저장점.
- 저장 후 홈: 변경 저장 후 홈.

핀·메모·기존 저장 시각 정책은 명세대로 보존한다.

### AT-004 import 취소·부분 실패

대용량 영상 여러 개 import 중 취소. 다음에는 하나의 읽기 권한을 제거해 부분 실패 유도.

기대: 취소 항목 temp/record가 남지 않고 기존 project는 정상. 실패 대상과 재시도 방법이 표시된다.

### AT-005 export 정확성

서로 다른 비율 사진/회전 영상/원본 오디오/음악/자막/로고/엔딩을 포함해 6개 비율을 각각 export.

기대: 해상도, 회전, 순서, 길이(프레임/컨테이너 허용 오차), 음악 반복/fade, 오버레이 위치가 계약과 일치하며 결과가 재생된다.

### AT-006 저장 공간 부족

import/export/compression에서 공간 부족을 유도.

기대: 원본과 이전 index를 보존하고 temp를 정리하며 앱 재시작 후 정상 사용 가능.

### AT-007 컬렉션 압축 안전성

1080p보다 큰 영상, 이미 720p 이하 영상, 매우 짧은 영상, 회전 영상으로 단건/일괄 압축.

기대: 목표 이하 skip, 작은 결과만 교체, 취소/실패는 원본 유지, title/pin/poster/metadata 유지.

### AT-008 AiShot 연속 세션

일반 2+3초로 3회 연속 타격을 감지/수동 저장하고 편집으로 이동.

기대: 3개가 탐지 순서로 전달되고 각 길이가 목표 주변이며 미리보기/파일 회전이 정상. 다음 녹화가 자동 재시작된다.

### AT-009 프로세스·회전 복구

편집 중 접힘/펼침, 세로/가로, background/foreground 후 시스템이 process를 제거하도록 유도.

기대: 저장된 프로젝트와 사용자 선택을 손상하지 않는다. 진행 중 작업은 성공으로 위장하지 않고 안전한 재시도 상태다.

### AT-010 권한 거절과 설정 복귀

사진/카메라/마이크 권한을 최초 거절, 영구 거절, 설정에서 허용으로 각각 시험.

기대: 무한 요청/빈 화면/crash가 없고 필요한 이유와 설정 이동을 제공하며 허용 후 flow를 재개한다.

## 4. 화면·기능 P1 체크리스트

### 홈

- [ ] 프리셋 3×2와 정확한 제목/설명/아이콘.
- [ ] 로고 탭 순환, 롱터치 테마 패널, custom 3종 순서 저장.
- [ ] 일반 영화/AiShot 제한과 핀·메모·정렬.
- [ ] 컬렉션 0/1/29/30 상태와 ADD A FILM 노출.
- [ ] 600dp+ 일반 2열/컬렉션 3열, phone 1열/2열.

### 미디어 선택

- [ ] 사진/모션포토/영상 복수 필터 최소 1개 유지.
- [ ] 촬영일/추가일, 오름/내림, duration filter 복원.
- [ ] pinch 열 수 1/3/5/8 또는 Android 동등 조작과 상태 보존.
- [ ] 사진↔달력 선택 순서 공유, 오늘 2단계 동작.
- [ ] 기존 photo 선택 교체 시 file/AiShot clip 보존.

### 편집

- [ ] 프리셋별 기본값을 `CONTROL_DEFAULTS.md` 표와 대조.
- [ ] 기본시간 경계와 가변 step.
- [ ] video trim, impact split, 사용/제외 복구.
- [ ] 유사 사진 묶음 대표/펼침/추가 사용/저장.
- [ ] reorder 후 번호, thumbnail, duration, 결과 순서 일치.
- [ ] reset/undo/delete 확인과 데이터 범위가 정확.

### 자막·음악·엔딩

- [ ] 5×5 위치, font, size, line spacing, shadow와 실제 렌더 일치.
- [ ] imported TTF/OTF 30개 제한과 파일 누락 fallback.
- [ ] 6개 샘플 제목/파일, 외부 파일, 브라우저 download/favorite.
- [ ] music/original volume, loop, fade 동작.
- [ ] 엔딩 5종, 1~10초 0.5 step, variation, 위치 없는 fallback.

### 통합 전체화면 플레이어

- [ ] single tap controls, 좌/우 double tap ±10초.
- [ ] play/pause, loop, fit/fill, title/share configuration.
- [ ] scrub 중 auto-hide 중지, 약 3초 후 controls hide.
- [ ] pinch zoom, zoom pan, 축소 상태 아래 swipe close.
- [ ] phone 방향 전환 후 닫기 시 앱 방향 복원.
- [ ] tablet에서는 수동 90도 이중 회전이 없음.
- [ ] 닫기/reopen 반복 후 player/observer/job 누수 없음.

### 컬렉션

- [ ] pin만 drag reorder, 한 칸/열 단위 이동과 저장.
- [ ] device/HanClip AI 각 8개 후보와 재생성.
- [ ] poster metadata 순서와 같은 날짜 중복 숨김.
- [ ] player loop/fit-fill/seek/zoom/pan/닫기.
- [ ] 단건 1080/720/540, 일괄 720/540와 진행/취소.

### AiShot

- [ ] 감도 4종, 상태 점·감지/저장 문구, 한 줄 버튼.
- [ ] 샷 시간 3종과 프로젝트별 복원.
- [ ] lens/zoom/전후면 전환, preview/capture 회전.
- [ ] sound + visual 보조 판정과 말소리 억제.
- [ ] background/interruption/저장 실패 복구.

## 5. 접근성·현지화 P1

- [ ] TalkBack label이 아이콘 모양이 아니라 행동을 설명.
- [ ] 선택/비활성/진행 상태를 TalkBack이 읽음.
- [ ] 48dp hit target과 keyboard/스위치 접근.
- [ ] 글자 1.3배에서 닫기/저장/만들기와 오류 문구가 잘리지 않음.
- [ ] 밝은/어두운/custom 테마에서 WCAG에 준하는 가독성 검토.
- [ ] 사용자 표기는 `모션포토`, Android 시스템 저장 대상은 기기 용어에 맞춤.

## 6. 성능·안정성 P1/P2

- [ ] 홈 120Hz 반복 스크롤 jank 회귀가 기존 releaseQa 기준에서 유의하게 악화되지 않음.
- [ ] 30개 컬렉션과 긴 목록에서 bitmap 업로드/메모리 급증 없음.
- [ ] 4K/긴 영상 import·trim·export 시 main-thread I/O와 ANR 없음.
- [ ] 10회 player open/close, 10회 설정 open/close 후 player/camera/observer 수가 누적되지 않음.
- [ ] 앱 background 5분 후 복귀, 화면 잠금/해제, 전화/오디오 focus interruption 복구.
- [ ] 비행기 모드에서 브라우저 외 로컬 편집/렌더 기능 정상.

## 7. 출시 판정 기록 양식

```text
Build/commit:
기준 iOS commit:
시험 기기/API/window width:
P0: 통과 __ / 실패 __
P1: 통과 __ / 실패 __ / 미검증 __
기존 데이터 upgrade:
assemble/lint/release:
실기기 import/export/AiShot:
알려진 차이(IOS_PARITY 링크):
출시 판정: GO / CONDITIONAL / NO-GO
```
