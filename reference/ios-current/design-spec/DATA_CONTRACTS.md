# HanClip 데이터·상태 계약

## 1. 계약 원칙

- 이 문서는 Swift 타입의 바이트 호환을 요구하지 않는다. iOS와 Android가 같은 사용자 개념, 기본값, 상태 수명, 마이그레이션 안전성을 갖도록 한다.
- Android JSON 키는 이미 배포된 키를 우선 보존한다. 아래 논리 필드와 매핑표를 코드 가까이에 둔다.
- 모든 persistent model에는 schema version을 두고, 미지 필드는 무시하되 알려진 사용자 데이터를 손실시키는 전체 초기화 fallback은 금지한다.

## 2. 수명 계층

| 계층 | 포함 상태 | Android 저장 후보 |
|---|---|---|
| 화면 세션 | 패널 펼침, 현재 재생/zoom, picker filter/sort/columns | rememberSaveable/SavedStateHandle; 영구 저장 불필요 |
| 앱 환경설정 | 테마, 테마 순서, 기본시간, 기본 비율, 대표 간격, AiShot 감도, 화면 유지, 카피라이터 | DataStore 또는 기존 SharedPreferences |
| 프로젝트 | clips, 순서, 선택/trim, preset, caption/music/ending, 비율, 기본시간 | 프로젝트별 versioned JSON + 내부 미디어 |
| 컬렉션 | 영상, poster, title, pin/order, 위치/기간/제작일, poster version | collection index JSON + 내부 영상/poster |
| registry | 가져온 글꼴, 브라우저 즐겨찾기 | versioned registry + 내부 파일 |

## 3. Project 계약

필수 논리 필드:

| 필드 | 의미 | 기본/복구 |
|---|---|---|
| projectId | 안정적인 프로젝트 식별자 | 누락 시 한 번 생성 후 저장 |
| schemaVersion | 마이그레이션 버전 | 기존 데이터는 v1로 간주 |
| preset | new/quick/aiShot/travel/life/golf | 알 수 없으면 new, 원문은 로그에만 익명 기록 |
| createdAt/updatedAt | 생성/저장 시각 | 파일 시각 fallback, 역전 시 교정 |
| clips | 사용자 순서의 clip 배열 | 누락 시 빈 배열, 손상 항목만 격리 |
| defaultDuration | 사진 기본시간 | 0.1~30초 clamp |
| defaultVideoSegmentMode | single/multiple/all | multiple |
| outputAspectRatio | first/1:1/3:4/4:3/9:16/16:9 | first |
| caption | WatermarkSettings 논리 모델 | projectDefault 뒤 preset 적용 |
| backgroundMusic | 음악 설정 | empty 또는 preset 값 |
| ending | enabled/duration/theme/variation | false/2초/caption/0 |
| similarPhotoCriteria | 대표간격과 분석 기준 | 앱 기본, 기존 결과는 보존 |
| memo/pin/pinnedAt | 홈 관리 메타데이터 | null/false/null |

저장 규칙:

1. 새 JSON을 같은 디렉터리 임시 파일에 쓴다.
2. flush/fsync 가능한 범위에서 완료한다.
3. decode 재검증 후 기존 index를 원자 교체한다.
4. 백업 index는 새 index 검증 후 갱신한다.
5. 미디어 삭제는 새 index가 해당 파일을 참조하지 않게 된 뒤 수행한다.

## 4. Clip 계약

| 필드 | 의미/불변식 |
|---|---|
| id | 재정렬·편집 중 유지되는 안정 ID |
| sourceKind | photo/livePhoto/video/file/aiShot/shared |
| internalFilename 또는 persistedUri | 재실행 후 읽을 수 있어야 함 |
| sourceIdentifier | 사진 선택 재진입 선선택용; 없다고 clip 삭제 금지 |
| sourceWidth/sourceHeight | 회전 보정 전후 기준을 구현에서 하나로 고정 |
| sourceDuration | 영상/모션 원본 길이, 사진은 null/0 허용 |
| displayDuration | 사진 또는 선택 결과 길이, 0보다 큼 |
| trimStart/trimDuration | 0 이상, start+duration ≤ sourceDuration+오차 |
| livePhotoMode | still/motion; motion 파일 없으면 still fallback과 안내 |
| videoSegmentMode | single/multiple/all |
| isVideoSegmentSelected | false는 결과 제외, 원본 clip 행 유지 |
| waveform/impactPoints | 원본 또는 분석 버전과 함께 invalidate 가능 |
| similarGroupId/groupSelection | 묶음과 대표·추가 사용 상태 |
| captureDate/location | 원본 metadata, 권한 부재 시 null |

시간 단위는 저장소 전체에서 초(Double) 또는 밀리초(Long) 중 하나를 공식 단위로 정하고 변환 함수만 사용한다. UI 문자열을 역파싱해 저장하지 않는다.

## 5. 자막·카피라이터 계약

프로젝트 자막과 앱 전역 카피라이터 로고는 별개다.

- 프로젝트 자막: enabled, text, 5×5 position, fontId, size preset, line spacing, textColor, shadow enabled/color/opacity.
- 앱 카피라이터: enabled, platform, address, 5×5 position, original/custom color, user image reference.
- imported font는 displayName과 내부 파일명/해시를 분리한다. 이름 충돌로 기존 프로젝트가 다른 폰트를 가리키지 않게 stable ID를 쓴다.
- 사용자 이미지/폰트 파일이 사라졌으면 프로젝트를 열 수 없게 하지 말고 기본 자산 fallback과 복구 안내를 제공한다.

## 6. 음악 계약

| 필드 | 범위/기본 |
|---|---|
| enabled | 파일이 유효할 때만 render true |
| source | none/bundled/imported/downloaded |
| stableTrackId/file | 재실행 가능한 내부 참조 |
| displayName | UI용, 경로로 사용 금지 |
| musicVolume | 0...1, 기본 0.35 |
| originalAudioVolume | 0...1, 기본 1.0 |
| loop | 기본 true |
| fadeIn/fadeOut | 기본 true; 0.3초/1.0초 |

내장 샘플은 버전 업그레이드로 파일명이 바뀌어도 stableTrackId로 복원한다.

## 7. 엔딩 계약

- enabled 기본 false, duration 1...10초/0.5초 step, 기본 2초.
- theme: caption, treasureMap, itinerary, landmark, office.
- variation은 같은 테마 재생성의 결정적 seed 또는 index로 저장한다.
- 장소/기간이 없을 때 앱이 crash하거나 빈 파일을 만들지 않는다. theme별 명시된 fallback copy/layout을 사용한다.
- travel preset의 엔딩 자동 활성화는 현재 Swift 경로에 모순이 있으므로 Android가 새로 추측하지 않는다. 현 Android 정책과 제품 결정을 `IOS_PARITY.md`에 기록한다.

## 8. 컬렉션 계약

| 필드 | 의미/보존 조건 |
|---|---|
| id | 영상 교체/압축 후에도 유지 |
| videoFilename | 앱 내부 실제 파일; 안전 교체 대상 |
| posterFilename | 영상 교체로 불필요하게 초기화하지 않음 |
| title/memo | 사용자 편집값 보존 |
| duration/file size | 파일에서 재계산 가능, index 값은 cache |
| createdAt/captureRange/location | 압축 후 보존 |
| isPinned/pinnedAt/order | pinned 사용자 순서 보존 |
| posterSelectionVersion | 구버전 자동 AI 재선정 여부 |
| metadataVersion | 새 metadata parser의 재분석 판단 |

압축 transaction:

```text
source read → temp output → output playable/duration/size 검증
 → compressedBytes < originalBytes 확인
 → record.videoFilename 교체 + index save
 → 이전 source 삭제
```

어느 단계든 실패하면 temp만 삭제하고 원본 record/file을 유지한다.

## 9. AiShot 계약

- 감도는 앱 전역 stable enum으로 저장한다.
- duration preset은 projectId 범위 키로 저장한다.
- session captures는 탐지 순서의 ordered list다.
- 각 capture는 trigger monotonic time, requested pre/post, actual duration, internal URI/file을 가진다.
- wall clock 변경은 buffer 계산에 영향을 주지 않도록 monotonic clock을 사용한다.
- 세션 종료 전 저장 중인 항목은 완료/실패를 확정하고, orphan temp는 다음 안전한 시작에서 정리한다.

## 10. 마이그레이션·손상 복구 시험 fixture

Android 저장소에는 최소 다음 fixture를 둔다.

1. 가장 오래 지원하는 프로젝트 JSON.
2. `isVideoSegmentSelected`가 없는 프로젝트.
3. imported font와 사용자 워터마크 이미지가 있는 프로젝트.
4. 사진+영상+모션포토+묶음이 섞인 프로젝트.
5. pinned 순서와 사용자 title이 있는 30개 컬렉션.
6. 압축 도중 중단되어 temp가 남은 컬렉션.
7. index 1차 파일이 손상되고 backup이 정상인 경우.

각 fixture는 load → 의미 비교 → save → process restart → 재load를 자동 검사한다. 단순 decode 성공이 아니라 clip 수/순서, 선택, 시간, 핀, 파일 존재와 hash 보존을 확인한다.
