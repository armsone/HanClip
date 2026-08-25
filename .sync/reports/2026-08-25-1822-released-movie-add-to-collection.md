# 개봉영화에서 컬렉션에 추가 동기화 보고서

- 시작: 2026-08-25 18:00:43 KST
- 종료: 2026-08-25 18:22:59 KST
- 경과: 22분 16초
- 동기화 그룹: `hanclip` — HanClip(Apple), HanClip-Android, NasFinder.com(공개 정보)
- 범위: 개봉영화 항목의 길게 누르기 패널에 `컬렉션에 추가`를 `개봉영화에서 제거` 바로 위에 배치하고, 원본을 유지한 비파괴 컬렉션 추가를 Apple·Android에 구현

## 실제 동기화 표

| 기능/변화 | 기준 | Apple 상태 | Android 상태 | 기술·런타임 근거 | Matchup 근거 | 최종 판정 |
|---|---|---|---|---|---|---|
| 길게 누르기 패널의 `컬렉션에 추가` 순서 | 사용자 직접 지시 | `EditorView.swift`에 지정 순서로 구현, 시뮬레이터 빌드 통과 | `HomeRoute.kt`에 지정 순서로 구현, `assembleDebug` 통과 | 양 플랫폼 컴파일 성공 | 대응 실행 화면 캡처 없음 | source-only |
| 개봉영화 유지 + 컬렉션 추가 | HC-COLL-001 | 별도 컬렉션 메타데이터를 추가하고 같은 영상 파일을 참조 | 동일한 `Collection` 항목을 추가하고 같은 영상 파일을 참조 | Apple 빌드, Android 정책 단위시험 통과 | 기기 동작 추적 없음 | source-only |
| 반복 추가 방지와 최대 30개 | HC-COLL-001 | 파일명 기준 멱등 처리 후 용량 검사 | 파일명/해시 기준 멱등 처리 후 용량 검사 | Android `MovieCollectionPolicyTest` 통과, Apple 소스·빌드 확인 | 해당 없음 | source-only |
| 공유 영상·포스터 삭제 및 압축 안전성 | 데이터 보존 우선 | 다른 항목이 참조하면 삭제하지 않으며 압축 원본도 보존 | 제거·압축 전 남은 참조를 확인 | Android 관련 정책 시험 통과, 양 플랫폼 빌드 통과 | 해당 없음 | source-only |
| 카피라이터 기능 사전 | 프로젝트 규칙 | `개봉영화` 설명 갱신 | `개봉영화` 설명 갱신 | 양 플랫폼 빌드 통과 | 실행 화면 미확인 | source-only |
| 홈페이지 공개 설명 | NasFinder.com 계약 | Apple 지원 사실 포함 | Android 지원 사실 포함 | 사이트 감사 0 오류, 빌드 및 28개 테스트 통과 | 공개 HTML에서 새 문구 확인 | synchronized |

## 프로젝트별 검증

- Apple: `xcodebuild -project HanClip.xcodeproj -scheme HanClip -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/HanClip-CollectionAdd-DerivedData build` → 성공. 기존 deprecation 경고만 존재.
- Android: `./gradlew :app:testDebugUnitTest --tests com.hanclip.android.core.project.MovieCollectionPolicyTest` → 성공. `./gradlew :app:assembleDebug` → 성공.
- 제품 계약: Ruby YAML 로드 성공, `git diff --check` 성공.
- Android parity ledger: JSON 문법은 정상. 기존 ledger 전체가 현행 스키마와 맞지 않아 gate는 exit 2(구조 오류 226개). 이번에 추가한 두 행은 `implemented_source_only`로 유지.
- 홈페이지: NasFinder 감사 스크립트 0 오류(기존 4개 미디어 경고), `npm test` 28/28 통과, Sites version 194 운영 게시 성공. `https://nasfinder.com/apps/hanclip`과 Sites 운영 URL에서 `컬렉션에도 바로 추가` 문구 확인.

## Matchup / ledger gate

- 메뉴와 동작은 양 플랫폼 소스에 구현됐으나, 같은 fixture로 만든 Apple·Android 대응 화면 캡처와 실제 입력→저장→재실행 동작 추적을 수행하지 않았다.
- 따라서 시각·동작 동기화 완료를 주장하지 않는다.
- ledger gate는 이번 기능과 무관한 기존 226개 구조 오류 때문에 실행 단계에서 차단됐다. 기존 오류 수는 이번 행 추가 전후 동일하다.

## 의도적 차이

- 없음. Apple context menu와 Android dropdown menu는 플랫폼 기본 표시 수단이지만 앱 소유 라벨·순서·행동 의미는 동일하게 구현했다.

## 오류와 해결

| 단계 | 관찰된 오류 | 원인 | 수정/대응 | 결과 | 열림 여부 |
|---|---|---|---|---|---|
| Claude 위임 | Fable 호출이 5시간 세션 한도로 시작 전 거절 | Claude 5시간 남은 비율 0% | 파일 변경이 없음을 확인하고 Gemini가 승계 | 구현 진행 | 닫힘 |
| Gemini Apple | 5분 응답 대기 시간 초과 | Antigravity wrapper 응답 제한 | 생성된 diff를 직접 전수 검토하고 불필요한 확인창·실패 롤백·멱등 순서를 보정 | Apple 빌드 성공 | 닫힘 |
| Gemini Android | 5분 응답 대기 시간 초과 | Antigravity wrapper 응답 제한 | 생성된 diff를 직접 전수 검토하고 released-kind 검증을 추가 | 시험·빌드 성공 | 닫힘 |
| 홈페이지 감사 | 저장소의 `scripts/audit_site.py` 경로 없음 | 감사 스크립트는 스킬 디렉터리에 존재 | 실제 스킬 경로의 스크립트를 사이트 경로 인자와 함께 실행 | 0 오류 | 닫힘 |
| 계약 YAML 확인 | 시스템 Ruby가 `aliases:` 키워드를 지원하지 않음 | 구버전 Psych API | 지원되는 `YAML.load_file` 호출로 재검증 | 성공 | 닫힘 |
| parity ledger gate | 구조 오류 226개, exit 2 | 기존 ledger가 현행 atomic schema 이전 형식·상태·evidence를 포함 | 이번 행은 현행 형식으로 추가하고 기존 전체 재작성은 범위 밖으로 보존 | gate 차단 유지 | 열림 |

## 팀원 사용량 근거

- Claude Fable: 주간 남은 비율 73% → 73%(감소 0%p), Fable 남은 비율 48% → 48%(감소 0%p). Apple 구현 담당으로 배정했으나 세션 한도로 시작 전 종료.
- Gemini / Google AI Pro: 주간 남은 비율 63.627809% → 62.007606%(감소 1.620203%p), 5시간 남은 비율 98.347431% → 88.626230%(감소 9.721201%p). Claude 승계 Apple 구현과 Android 대응 구현을 수행. 호출별 분리 사용량은 제공되지 않아 공급자 전체 감소만 기록.

## 미완료 항목

1. Apple·Android 실제 동작 추적: 소스·빌드는 완료. 길게 누르기 → 추가 → 양쪽 목록 유지 → 재실행 유지 → 어느 한쪽 제거 뒤 남은 항목 재생을 실제 기기/시뮬레이터에서 확인해야 한다.
2. 대응 화면 캡처: 메뉴가 열린 같은 fixture의 iPhone·Android phone 캡처와 태블릿/TV 포커스 상태 근거가 없어 시각 동기화는 미검증이다.
3. parity ledger 정상화: 이번 기능 이전부터 존재한 226개 구조 오류를 별도 ledger 마이그레이션 작업에서 append-only 이력을 보존하며 현행 스키마로 바꿔야 gate를 실행할 수 있다.

## 저장·공개 상태

- HanClip Apple: 로컬 소스 변경만 존재, 커밋·푸시·설치·릴리스 없음.
- HanClip Android: 로컬 소스/시험 변경만 존재, 커밋·푸시·설치·릴리스 없음.
- NasFinder.com: 관련 두 파일만 커밋 `5bc9eb2`, 기본 GitHub 원격과 Sites 소스 원격 푸시 완료, 운영 게시 및 공개 문구 확인 완료.
- sync registry의 `last_verified_head`는 앱 저장소가 미커밋 상태이고 ledger gate가 차단되어 갱신하지 않았다.
