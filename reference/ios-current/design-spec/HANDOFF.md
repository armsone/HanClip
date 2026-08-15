# HanClip-Android 작업 인계서

## 1. 인계 목적

기존 Android 구현을 폐기하거나 처음부터 다시 만들지 않는다. 이 고정 명세를 기준으로 현재 Kotlin/Compose 구현을 감사해 필요한 최소 수정, 검증 순서, 예상 CCMB 주간 사용량을 산정한다.

## 2. 고정 입력

- iOS 기준 commit: `31e60ec5feb100b3dfcec78d47040e54e2d682ca`.
- 필수 문서: `MANIFEST`, `DESIGN_SYSTEM`, `SCREEN_MAP`, `CONTROL_DEFAULTS`, `ANDROID_PORTING_RECIPE`, `DATA_CONTRACTS`, `ACCEPTANCE_TESTS`, `screens/*`.
- Android 기준은 감사 시작 시 commit과 dirty state를 기록한다.
- iOS 저장소는 읽기 전용. Android 수정은 HanClip-Android 저장소 안에서만 한다.

## 3. Android 작업이 먼저 제출할 감사 결과

코드를 수정하기 전에 다음 표를 완성한다.

| ID | 기능/화면 | iOS 계약 | Android 근거 파일:줄 | 판정 | 사용자 영향 | 수정 후보 | 검증 | 예상 사용량 |
|---|---|---|---|---|---|---|---|---:|
| 예 | 통합 전체화면 플레이어 | ±10초/zoom/pan/close/orientation | PreviewRoute.kt:... | 부분 | 화면별 동작 불일치 | 공통 player 추출 | AT-... | 0.x% |

판정은 다음 다섯 개만 사용한다.

- `동일`: 코드 근거와 시험 근거가 모두 있음.
- `구현됨-미검증`: 코드 근거만 있음.
- `부분`: 일부 상태/경계/화면이 빠짐.
- `누락`: 호출 가능한 구현 없음.
- `플랫폼차이`: Android 고유 방식이 같은 사용자 결과를 제공하며 `IOS_PARITY.md`에 기록됨.

기존 `IOS_PARITY.md`의 “완료” 표기는 증거로 간주하지 않는다. 현재 코드, 저장 데이터, 빌드, 실기기 시험으로 재판정한다.

## 4. 우선 감사 영역

1. 2026-08-11 iOS 신규 변경
   - iPad regular-width 최대 920, 패널 620/720/760 상한.
   - phone/태블릿 방향 정책 분리.
   - AiShot preview/capture horizon rotation.
   - 통합 전체화면 플레이어 configuration과 gesture.
2. 데이터 안전성
   - 기존 project/collection JSON migration fixture.
   - 편집 종료 3종 스냅샷.
   - 압축 안전 교체와 취소.
3. “완료”였으나 세부 재검증이 필요한 영역
   - 롱터치/핀 drag/관리 메뉴.
   - 문구·아이콘·접힘 상태·상태 수명.
   - 실제 render와 preview 좌표·폰트·오디오.

## 5. 수정 계획 규칙

- 결함을 사용자 데이터 위험, 핵심 기능, 상태/회전, 시각 세부 순으로 정렬한다.
- 한 작업 묶음은 하나의 사용자 결과와 그 회귀 테스트로 제한한다.
- 기존 구현을 대체하기 전 호출자를 전부 찾고, 새 공통 컴포넌트로 점진 이전한다.
- 관련 없는 리팩터링, 패키지 이동, 이름 정리, 의존성 교체는 제외한다.
- dirty `PROJECT_RULES.md`는 사용자 변경으로 보존하고 이번 기능 수정에 섞지 않는다.

## 6. 사용량 산정 방식

CCMB 퍼센트포인트는 달력 시간이 아니라 실제 Codex 작업량 예산이다. Android 작업은 각 묶음을 아래처럼 산정한다.

| 난이도 | 예 | 예상 범위 |
|---|---|---:|
| S | 문구/아이콘/단일 spacing, 기존 테스트 갱신 | 0.2~0.5% |
| M | 한 화면 상태/gesture/저장 필드와 회귀 시험 | 0.5~1.2% |
| L | 공통 player, migration, import/압축 transaction | 1.2~2.5% |
| XL | export pipeline, AiShot 연속 녹화/회전, 광범위 실기기 검증 | 2.5~4.5% |

최종 보고는 최소/권장/상한 세 값으로 제시한다.

- 최소: P0 결함만 수정하고 필수 검증.
- 권장: P0+P1, phone+fold/tablet 실기기 검증.
- 상한: 발견된 구조 문제와 성능/장기 회귀까지 포함.

남은 주간 사용량보다 상한이 크면 기능을 잘라 임시 우회하지 말고 여러 주차로 나눈다. 각 주차 끝은 빌드 가능하고 데이터 호환 가능한 상태여야 한다.

## 7. 작업 시작 전 사용자에게 보고할 내용

1. 현재 Android commit과 dirty 파일.
2. 감사 결과 요약: 동일/미검증/부분/누락/플랫폼차이 개수.
3. 우선 수정 파일과 영향받을 기존 기능.
4. 회귀 위험과 보호용 기존/신규 테스트.
5. 최소/권장/상한 주간 사용량과 추천값.
6. 사용자가 `N%로 작업 시작해`라고 지시할 때까지 앱 소스 미수정.

## 8. 완료 보고 형식

```text
iOS 기준 / Android 시작·종료 commit
실제 변경 파일과 사용자 결과
데이터 migration/보존 결과
assembleDebug / lintDebug / releaseQa
실기기와 화면 폭별 시험
AT 통과/실패/미검증
IOS_PARITY에 남은 차이
CCMB 시작/종료/실제 증가
다음 주차 예상 사용량
commit/push/APK 상태
```
