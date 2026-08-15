# HanClip Android 정밀 이식 레시피

## 0. 문서의 지위

- 기준 앱: HanClip iOS `31e60ec5feb100b3dfcec78d47040e54e2d682ca`.
- 기준일: 2026-08-12 KST.
- 이 문서는 화면을 비슷하게 그리는 가이드가 아니라 Android에서 같은 제품 동작을 재현하기 위한 구현 순서와 완료 조건이다.
- 값과 동작이 충돌하면 `CONTROL_DEFAULTS.md` → 화면 문서 → 이 문서 순으로 더 구체적인 근거를 적용한다.
- SwiftUI/UIKit 구현 방식 자체는 복사하지 않는다. 사용자에게 보이는 의미, 상태 전이, 저장 수명, 실패 복구를 동일하게 만든다.
- Android 고유 권한, MediaStore, SAF, CameraX, Media3, 백 버튼, 폴더블·태블릿 대응은 플랫폼 관습을 따르되 기능 의미를 바꾸지 않는다.

## 1. 절대 보존 계약

1. 기존 Android 사용자 프로젝트, 컬렉션 영상, 가져온 글꼴, 테마, 핀 순서, 즐겨찾기를 마이그레이션 없이 폐기하지 않는다.
2. JSON/Preferences 필드 추가는 이전 데이터에 안전한 기본값을 둔다. 필드 이름 변경은 구버전 이름도 읽는 변환기를 먼저 둔다.
3. 원본 미디어를 수정하지 않는다. 앱 내부 복사본 교체도 새 파일 생성 → 검증 → 인덱스 저장 → 이전 파일 삭제 순서로 한다.
4. import/export/compression 취소 시 임시 파일과 반영 전 레코드만 제거하고 이전 정상 상태를 복원한다.
5. 화면 회전, 폴드 접힘/펼침, 프로세스 재생성으로 편집 선택이나 작업 중 데이터가 조용히 초기화되지 않게 한다.
6. iOS에 없는 기능을 동등성 달성을 이유로 임의 추가하지 않는다. Android 보완이 필요하면 `IOS_PARITY.md`에 이유와 사용자 영향을 기록한다.

## 2. 구현 순서와 게이트

아래 단계는 앞 단계의 검증이 끝난 뒤 진행한다. 기존 구현이 있으면 새로 만들지 말고 해당 게이트를 통과하는지 검사한다.

| 단계 | 구현 묶음 | 완료 게이트 |
|---:|---|---|
| 1 | 데이터 스키마와 저장소 | 구버전 fixture를 읽고 저장해도 항목·순서·원본 파일이 보존됨 |
| 2 | 루트 상태 머신과 내비게이션 | HOME/EDITOR/QUICK/AISHOT/PREVIEW가 백·취소·재진입에서 명세 상태로 복귀 |
| 3 | 미디어 선택과 import | 사진·모션포토·영상·파일·공유 입력이 중복/취소/권한 거절을 안전하게 처리 |
| 4 | 편집 모델 | 프리셋, 클립 시간, 분할, 묶음, 비율, 자막, 음악, 엔딩 상태가 저장·복원됨 |
| 5 | 영상 합성 | 같은 입력과 설정에서 길이·순서·비율·오디오·오버레이가 계약 범위 안에서 일치 |
| 6 | 시사회·저장·공유 | 다시 편집, 공유, 갤러리/파일 저장이 실패 후 재시도 가능 |
| 7 | 컬렉션 | 30개, 핀/정렬, 포스터 AI, 메타데이터, 압축, 플레이어 계약 통과 |
| 8 | AiShot | 권한, 회전, 감도, 앞뒤 버퍼, 연속 감지, 일괄 편집 전달 통과 |
| 9 | 적응형 UI·접근성 | 바형/폴드/태블릿/회전에서 상태 보존, 터치 48dp, 글자 확대와 TalkBack 확인 |
| 10 | 출시·운영 | release 빌드, 데이터 업그레이드, 성능, 개인정보·라이선스, 장애 로그 점검 |

각 단계는 `ACCEPTANCE_TESTS.md`의 대응 시나리오와 `:app:assembleDebug`, `:app:lintDebug`를 통과해야 한다.

## 3. Android 권장 구조

```text
UI(Route/Screen/Dialog)
  → ViewModel: 사용자 의도와 화면 상태 전이
    → Use case/service: import, 분석, 합성, 압축
      → Repository/store: 프로젝트·컬렉션·환경설정 영속화
        → Android adapters: MediaStore, SAF, CameraX, Media3, Work/Foreground service
```

- Composable에서 파일 복사, JSON 쓰기, 영상 분석을 직접 수행하지 않는다.
- ViewModel은 URI를 화면 문자열로 직렬화하지 말고 도메인 식별자와 영속 권한 상태를 관리한다.
- 장시간 작업은 단일 `Job` 소유자를 정하고 진행률, 취소, 오류, 재시도 상태를 하나의 불변 UI state로 노출한다.
- export/import/compression을 동시에 시작하지 못하게 하되 플레이어와 편집 상태는 보존한다.
- `Activity`의 `configChanges`에 의존해 상태 보존을 끝냈다고 판단하지 않는다. SavedState와 저장소 복원을 별도로 검증한다.

## 4. 루트 상태 머신 레시피

핵심 상태는 다음과 같이 상호 배타적으로 관리한다.

```text
HOME
 ├ preset(new/travel/life/golf) → EDITOR
 ├ preset(quick) → MEDIA_SELECTION → QUICK_DURATION
 ├ preset(aishot) → AISHOT → EDITOR
 ├ saved project → LOADING → EDITOR/AISHOT
 └ collection movie → COLLECTION_PLAYER

EDITOR
 ├ settings → TEXT/MUSIC/ENDING
 ├ media add → MEDIA_SELECTION/AISHOT
 ├ create → GENERATING → PREVIEW
 └ exit → HOME | SAVE | SAVE_AND_HOME

PREVIEW
 ├ edit again → EDITOR 또는 QUICK_DURATION
 ├ share → system share
 └ release → MEDIASTORE 또는 SAF
```

- Dialog/Sheet 여부와 별개로 구조 상태를 구분한다. 예: PHOTO와 CALENDAR는 같은 선택 세션을 공유하지만 서로 다른 필터 UI state다.
- 시스템 Back은 가장 위 overlay → 설정 화면 → 현재 flow 취소 순서다. 진행 중 작업은 즉시 화면을 닫지 말고 취소 확인/취소 완료를 거친다.
- `홈`은 편집 시작 스냅샷으로 되돌리고, `저장`은 현재 화면에 남으며 새 취소 기준점을 만든다. `저장 후 홈`은 저장 완료 후 HOME으로 이동한다.
- 새 프로젝트에서 `홈`을 선택하면 자동 생성된 빈 프로젝트를 제거한다. 기존 프로젝트의 핀, 메모, 저장 시각은 편집 취소로 되돌리지 않는다.

## 5. 화면 레이아웃 레시피

### 5.1 공통

- phone compact: 한 열, 전체 사용 가능 폭, 좌우 기본 여백 14~18dp.
- 600dp 이상: 의미 있는 밀도 개선만 적용한다. 단순 확대 금지.
- iOS regular-width의 읽기 폭 상한은 920pt다. Android 편집 핵심 콘텐츠도 920dp를 상한 후보로 사용하되 실제 600/840dp 기기에서 검증한다.
- 테마 패널 상한 620dp, 확인 패널 760dp, 공유/인박스 패널 720dp를 기준으로 한다.
- 시스템 바, 힌지, display cutout, IME inset을 포함한 safe drawing 영역 안에 닫기와 주 조작을 둔다.

### 5.2 넓은 화면

- phone: 저장 일반 영화 1열, 컬렉션 2열, 편집 클립 1열.
- 600dp 이상: 일반 영화 2열, 컬렉션 3열 고정, 편집 클립 2열. 헤더와 전역 설정은 한 화면 전체 읽기 폭을 유지한다.
- 840dp 이상 미디어 그리드와 AI 후보는 더 많은 열을 허용하되 카드 안 정보가 2줄 이상 잘리지 않아야 한다.
- 폴드 접힘/펼침 때 같은 프로젝트·선택 목록·스크롤의 의미적 위치를 보존한다.

### 5.3 입력과 접근성

- 모든 주 버튼/아이콘 hit target 최소 48×48dp. 시각 크기가 작으면 투명 hit 영역을 확장한다.
- 색만으로 선택/오류/핀을 구분하지 않고 아이콘, 체크, 문구를 함께 쓴다.
- TalkBack 순서는 화면 제목 → 설명 → 주요 콘텐츠 → 주 행동 → 보조 행동이다.
- 동적 글자 확대 시 핵심 문구를 잘라 숨기지 않는다. 카드 높이 증가 또는 스크롤을 허용한다.

## 6. 미디어 선택과 import 레시피

1. 선택 세션을 만들고 기존 Photo/MediaStore 출처 식별자를 선선택한다.
2. 사진/달력 전환은 동일한 선택 순서 배열을 전달한다.
3. 필터 기본은 사진·모션포토·영상, 정렬은 촬영일 오름차순, 그리드는 5열이다.
4. 영상 길이 필터를 켜면 미디어 종류를 영상으로 임시 변경하고, 해제하면 이전 종류 선택을 복원한다.
5. 확인 시 기존 사진첩 출처만 새 선택으로 교체하고 파일/AiShot 출처는 유지한다.
6. 각 URI는 읽기 가능성, MIME, 길이/크기, 중복을 확인한 뒤 64KB 수준의 취소 가능한 스트림으로 앱 영역에 복사한다.
7. Samsung Motion Photo는 전체 파일을 스트리밍 검색해 embedded MP4를 찾는다. 전체 파일 메모리 적재 금지.
8. import 성공 전 프로젝트 인덱스에 완성 항목으로 노출하지 않는다. 부분 실패는 성공 항목/실패 항목을 명시하고 재시도 가능하게 한다.

Android 매핑:

- 사진 권한: API 수준에 맞는 Photo Picker/READ_MEDIA_* 정책.
- 파일: SAF와 persistable permission 또는 앱 내부 안전 복사.
- 촬영일: EXIF/MediaStore date taken 우선. 추가일 정렬은 MediaStore `DATE_ADDED` 의미를 iOS modificationDate와 비교해 `IOS_PARITY.md`에 고정한다.
- 위치: 권한으로 읽을 수 없는 HEIC/영상 메타데이터를 실패로 오인하지 말고, 권한 후 재시도 경로를 제공한다.

## 7. 편집과 합성 레시피

- 프리셋 적용은 한 번의 원자적 모델 변경으로 처리한다. 중간 recomposition이 일부 기본값을 다시 저장하지 않게 한다.
- 시간 값은 UI 표시 반올림과 내부 계산 단위를 분리한다. 기본시간 0.1~30초, 구간은 원본 길이를 넘지 않는다.
- `isVideoSegmentSelected=false`는 원본 행 삭제가 아니라 결과 제외다. 사용으로 되돌릴 수 있어야 한다.
- 묶음 대표 선택은 같은 입력/기준에서 결정적이어야 하며 그룹 펼침, 추가 사용, 순서가 저장된다.
- 출력 비율 `첫 사진`은 첫 유효 소스의 회전 보정 후 크기를 사용한다.
- 합성 전 입력 URI/내부 파일을 모두 검증하고 총 예상 길이를 계산한다. 합성 후 실제 duration이 허용 오차를 벗어나면 성공 처리하지 않는다.
- 음악 반복, 0.3초 fade-in, 1.0초 fade-out, 원본/음악 볼륨은 렌더와 미리보기에 동일하게 적용한다.
- 자막, 저작권 로고, 엔딩 카드는 미리보기와 최종 출력 좌표계가 같아야 한다.

## 8. 통합 전체화면 플레이어 계약

iOS 최신판은 시사회와 컬렉션 재생의 기반을 `HanClipFullscreenVideoPlayer`로 통합했다. Android도 공통 엔진/상태를 사용하고 화면별 configuration만 다르게 둔다.

공통 상태:

- autoplay, loop, fit/fill, title, share 가능 여부, mini progress, 시작 시각.
- single tap: controls 표시/숨김.
- double tap 좌/우: 10초 뒤/앞 이동.
- pinch: 확대/축소, 확대 상태 drag: pan, 축소 상태 vertical drag: 닫기.
- scrub: seek 중 controls auto-hide 중지, 종료 후 다시 예약.
- 재생 끝: loop면 0으로 seek 후 재생, 아니면 종료 상태와 controls 표시.
- 닫기: player pause/release, observer/job 제거, phone 방향 정책 복원.

Android 세부:

- Media3 Player 인스턴스, gesture state, system bar 정책을 공통 Composable/Controller로 격리한다.
- phone은 전체화면 재생 중 센서 방향을 따라 보이되 종료 후 앱 기준 방향을 복원한다.
- 태블릿/폴드 펼침은 Activity 전체를 억지로 90도 회전시키지 않고 현재 window orientation을 따른다.
- lifecycle stop에서 player를 해제하거나 중지하되 재진입 시 position/loop/fit 상태의 제품 요구를 지킨다.

## 9. 컬렉션 레시피

- 최대 30개. 0~29개는 ADD A FILM 카드, 30개는 숨김.
- pinned 우선, pinned 내부 사용자 순서, 나머지는 최신순. unpinned drag 금지.
- 포스터 롱터치: 제목/메모, 핀, AI 재선택, 용량 줄이기, 삭제 등 실제 제공 동작을 한 곳에 모은다.
- AI 후보는 device 8 + HanClip 8, 후보 번호/핀/제목/위치/재생시간/파일 크기를 실제 카드와 같은 문맥으로 보여준다.
- 압축 옵션: 1080p 8.5Mbps, 720p 5Mbps, 540p 2.5Mbps 상한. 회전 메타데이터 적용 후 long/short edge로 이미 목표 이하인지 판단한다.
- 일괄 압축은 720p/540p만 노출하고 이미 목표 이하인 영상은 건너뛴다.
- 결과가 원본보다 작을 때만 안전 교체한다. 메타데이터 JSON, poster, title, pin, created/captured/location은 보존한다.

## 10. AiShot 레시피

- 권한: 카메라+마이크. 거절, 다시 묻지 않음, 설정 복귀를 별도 상태로 처리한다.
- 감도 자동/시끄러움/일반/조용함은 앱 수명, 샷 시간 짧게/일반/길게는 프로젝트별 수명이다.
- 카메라 준비 직후 임시 영상을 연속 녹화하고 타격 기준 앞/뒤 구간만 절단한다.
- 짧게 1.5+1.5초, 일반 2+3초, 길게 5+5초. 저장 뒤 다음 감지 녹화를 자동 재시작한다.
- 미리보기와 저장 영상의 horizon 회전을 각각 적용한다. 렌즈 전환과 새 녹화 시작 때 capture rotation을 다시 적용한다.
- 저장 URI는 세션 순서를 유지해 모으고 편집 진입 때 한 번에 넘긴다. 비동기 import 완료 순서로 재정렬하지 않는다.
- 저장 중 감지 중복을 차단하고, 취소/앱 background/카메라 interruption에서 임시 녹화를 정리한 뒤 복구 가능한 상태를 표시한다.

## 11. 오류·관측·운영

- 사용자 오류는 대상과 다음 행동을 포함한다: 무엇을 못했는지, 원본이 보존됐는지, 재시도/설정 이동/문제 항목 제거 중 무엇이 가능한지.
- 로그에는 URI의 민감한 전체 경로, 주소록/위치 원문, 사용자 자막, 토큰을 남기지 않는다.
- import/export/compression/AiShot에는 작업 ID, 단계, 소요 시간, 취소/성공/실패 종류 정도만 남긴다.
- ANR 위험 작업은 main thread에서 실행하지 않는다. bitmap은 표시 크기에 맞춰 decode하고 큰 파일 전체 `ByteArray` 적재를 금지한다.
- release 후보는 debug와 별도로 jank, PSS/RSS, 긴 영상, 저장 공간 부족, background 복귀를 검사한다.

## 12. 완료의 정의

“화면이 존재함”은 완료가 아니다. 다음을 모두 만족해야 한다.

1. `ACCEPTANCE_TESTS.md`의 P0 전부와 해당 기능 P1 통과.
2. 기존 데이터 fixture 업그레이드 및 재실행 보존.
3. phone compact, 폴드 cover, 폴드 펼침 또는 600dp+, 회전에서 핵심 흐름 검증.
4. debug assemble/lint 통과, release 후보 설치·콜드 스타트·내보내기 성공.
5. iOS와 다른 점을 `IOS_PARITY.md`에 근거·영향·후속 조건과 함께 기록.
6. 기능 사전 문구와 실제 UI/동작이 일치.
