# HanClip iOS Current Design Spec Manifest

## 목적/기준

- Android 개발자가 스크린샷 없이 최신 iOS UI와 상태 수명을 재현하기 위한 source-of-truth 문서.
- 기준 작업 트리: `/Users/armsone/git/HanClip`, commit `31e60ec5feb100b3dfcec78d47040e54e2d682ca`, 2026-08-12 KST.
- 조사 중 iOS Swift/asset/project 파일은 수정하지 않았다. `reference/ios-current/design-spec` 문서만 추가했다.
- 추가 스크린샷 촬영은 위임 지시에 따라 중단했다. 이전에 확보된 4개 PNG는 `reference/ios-current/home/`에 보존되어 있으나 구현 기준은 이 문서다.

## 문서 목록

| 파일 | 범위 | 상태 |
|---|---|---|
| [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md) | 색/gradient/spacing/type/components/icons/motion/a11y/pt→dp | 완료 |
| [SCREEN_MAP.md](SCREEN_MAP.md) | 실제 호출 화면·overlay·전환·상태 matrix/미사용 구분 | 완료 |
| [CONTROL_DEFAULTS.md](CONTROL_DEFAULTS.md) | 모든 핵심 control 초기값, preset 차이, 상태 수명/저장/복원 | 완료(확인 필요 표시 포함) |
| [ANDROID_PORTING_RECIPE.md](ANDROID_PORTING_RECIPE.md) | Android 구현 순서, 보호 계약, 플랫폼 매핑, 단계별 완료 게이트 | 완료 |
| [DATA_CONTRACTS.md](DATA_CONTRACTS.md) | 프로젝트·클립·자막·음악·엔딩·컬렉션·AiShot 데이터와 마이그레이션 계약 | 완료 |
| [ACCEPTANCE_TESTS.md](ACCEPTANCE_TESTS.md) | P0/P1/P2 수용 테스트, 기기 매트릭스, 출시 판정 | 완료 |
| [HANDOFF.md](HANDOFF.md) | Android 현행 감사, 수정 계획, CCMB 주간 사용량 산정 지시 | 완료 |
| [screens/HOME.md](screens/HOME.md) | home/presets/integrated projects/collection/media menu | 완료 |
| [screens/MEDIA_SELECTION.md](screens/MEDIA_SELECTION.md) | photos/calendar/filter/sort/gesture/preview/import | 완료 |
| [screens/EDITOR.md](screens/EDITOR.md) | editor/clip settings/add/reorder/clip preview | 완료 |
| [screens/TEXT_MUSIC_BROWSER.md](screens/TEXT_MUSIC_BROWSER.md) | caption/music/browser/favorites/download | 완료 |
| [screens/ENDING.md](screens/ENDING.md) | ending and five themes | 완료 |
| [screens/EXPORT_PREVIEW.md](screens/EXPORT_PREVIEW.md) | preparation/composition/cancel/error/preview/release | 완료 |
| [screens/COLLECTION.md](screens/COLLECTION.md) | shelf/poster/pin/AI/compress/player | 완료 |
| [screens/AISHOT.md](screens/AISHOT.md) | camera/control/capture states | 완료 |
| [screens/SYSTEM_PANELS.md](screens/SYSTEM_PANELS.md) | theme/copyright/licenses/permissions/errors | 완료 |

## 보존된 참고 PNG(새 촬영 중단)

| 파일 | 내용 | 기준 기기 |
|---|---|---|
| `../home/home-empty-top.png` | project0/collection0 home | iPhone 17 Pro simulator, iOS 26.5, 1206×2622 px |
| `../home/home-media-add-menu.png` | media menu | 동일 |
| `../home/home-theme-short-tap.png` | logo short-tap theme change representative | 동일 |
| `../home/copyright-top.png` | copyright top | 동일 |

## 확인 필요/플랫폼 의사결정

1. iPad/tablet 전용 max-width/breakpoint가 iOS source에 명시되지 않았다. 문서 제안값은 Android design review 필요.
2. 여행 preset은 보물지도 theme를 설정하지만 `includesEndingInfoCard=true`를 명시하지 않는다. 제품 요구와 source가 충돌할 수 있으므로 Android에서 임의로 자동 활성화하지 말고 확인한다.
3. 사진 `추가순`은 iOS `PHAsset.modificationDate` 우선이다. Android MediaStore의 정확 대응(`DATE_ADDED`/`DATE_MODIFIED`)을 검증한다.
4. 일부 UIKit font/cell spacing 및 collection poster metadata font의 정확 line-level 값은 해당 파일 상수에서 구현 시 재확인한다. 확인하지 않은 값은 문서에 추측값을 넣지 않았다.
5. `golfPrimary/golfSecondary`는 선언됐지만 active theme switch에서 사용되지 않는다. Android global theme에 포함하지 않는다.
6. quick action enum의 calendar/files/search와 실제 launcher shortcut 노출 구성은 별도 확인한다.

## 2026-08-11 이후 기준 증분

- iPad는 모든 방향을 지원하고 regular-width의 루트/헤더/하단 핵심 콘텐츠 폭을 최대 920pt로 제한한다. 테마 패널 620pt, 확인 패널 760pt, 공유 inbox 720pt 상한을 둔다.
- iPhone 전체화면 재생은 방향 정책을 전환·복원하지만 iPad는 현재 window 방향을 사용한다.
- AiShot은 preview와 capture의 horizon-level rotation을 별도로 적용하고 렌즈 전환/녹화 시작 때 다시 반영한다.
- 시사회와 컬렉션 재생은 `HanClipFullscreenVideoPlayer` 공통 구현을 사용한다. Android도 공통 player 상태/gesture를 우선 감사한다.
- 이 증분은 이전 2026-08-10 화면 문서의 넓은 화면 “제안”을 일부 확정된 구현값으로 대체한다.

## 변경 반영 규칙

- iOS UI 변경 시 `SCREEN_MAP`에서 호출 경로와 구조 state를 먼저 갱신한다.
- control의 초기값/저장 위치/복원 규칙이 바뀌면 `CONTROL_DEFAULTS`를 같은 commit에서 갱신한다.
- 공통 token 변경은 `DESIGN_SYSTEM`; 화면 전용 치수/문구/gesture는 해당 `screens/*.md`.
- 구조가 같은 단순 값 변화는 문서 수치만 갱신한다. 빈/데이터/패널/진행/오류처럼 구조가 달라질 때만 향후 필요 시 screenshot을 증분 추가한다.
- Android 사용자 문구에서 Live Photo는 항상 `모션포토`.

## 소스 조사 주요 범위

- `HanClip/App/HanClipApp.swift`
- `HanClip/Views/EditorView.swift`
- `HanClip/Views/ClipRow.swift`
- `HanClip/Views/VideoTrimEditor.swift`
- `HanClip/Services/PhotoPicker.swift`
- `HanClip/Services/AiShotCamera.swift`
- `HanClip/ViewModels/EditorViewModel.swift`
- `HanClip/Models/ClipItem.swift`, `WatermarkSettings.swift`
- `HanClip/Services/ProjectStore.swift`, `MovieCollectionStore.swift`, `VideoComposer.swift`
