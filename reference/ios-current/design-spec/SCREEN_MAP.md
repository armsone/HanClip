# HanClip 실제 화면·상태·전환 지도

기준일 2026-08-12, iOS commit `31e60ec5`. `EditorView.presentationConfiguredView`와 각 ViewModel의 open/close 메서드에서 실제 연결된 경로만 “호출됨”으로 분류했다. 스크린샷 촬영은 중단했으며 이 문서는 최신 소스 호출 관계가 기준이다.

## A. 루트 상태 머신

```text
App/딥링크/퀵액션
  └─ EditorView
      ├─ model.isProjectOpen == false → HOME
      │   ├─ 프리셋 → EDITOR 또는 QUICK_DURATION / AISHOT
      │   ├─ 저장 영화 → LOAD_PROGRESS → EDITOR 또는 AISHOT
      │   ├─ 컬렉션 포스터 → COLLECTION_PLAYER
      │   ├─ 미디어 추가 → PHOTO / CALENDAR / FILE / AISHOT
      │   ├─ 로고 탭/롱터치 → THEME_NOTICE / THEME_PANEL
      │   └─ i 탭/롱터치 → COPYRIGHT / ONLINE_BROWSER
      └─ model.isProjectOpen == true → EDITOR
          ├─ 미디어 추가 → PHOTO / CALENDAR / FILE / AISHOT
          ├─ 클립 탭 → CLIP_TRIM_PREVIEW
          ├─ 자막/음악/엔딩 → SETTINGS
          ├─ 만들기 → GENERATION_PROGRESS → PREVIEW
          └─ 저장·홈/홈 → SAVE_PROGRESS 또는 CONFIRMATION → HOME
```

루트 위에 구조적으로 다른 overlay가 겹친다: 공유 inbox banner, import/busy progress, 테마 선택, 홈 이동 확인, 비율 선택, 클립 리셋 확인, 전역 오류 alert. 소스: `EditorView.swift:280-615`.

## B. 실제 호출 화면 목록

| ID | 화면/패널 | 호출됨 | 진입 | 종료/다음 | 구조적 상태 |
|---|---|---:|---|---|---|
| HOME | 홈 | 예 | 앱 시작, 편집 저장/취소 | 프리셋·목록·컬렉션·미디어 메뉴 | 프로젝트 0/있음, 컬렉션 0/있음, 공유파일 배너, 테마 notice |
| MEDIA_MENU | 미디어 추가 메뉴 | 예 | 홈/편집 우측 `photo.badge.plus` | AiShot/사진/달력/파일 | 메뉴 열림/닫힘 |
| PHOTO | 사진 선택 | 예 | MEDIA_MENU, 퀵모드, 컬렉션 | 확인→가져오기, 달력 전환, 취소 | 권한, 로딩, 필터, 정렬, 선택, 미리보기, auto-scroll |
| CALENDAR | 달력 선택 | 예 | MEDIA_MENU, PHOTO | 확인→가져오기, 사진 전환, 취소 | 월 이동, 날짜 선택, 썸네일, 미리보기 |
| IMPORT | 미디어 가져오기 진행 | 예 | PHOTO/CALENDAR/FILE/공유 inbox | EDITOR/QUICK_DURATION 또는 취소 | 준비, %, 완료, 취소, rollback, 실패 |
| QUICK_DURATION | 퀵모드 영상 길이 | 예 | 퀵 프리셋 + 미디어 선택 | 만들기→GENERATION; 사진/파일/설정; 취소→HOME | 추천/최소/고정시간, 매체수 제한, 비율/자막/음악/엔딩 |
| EDITOR | 영화 제작 | 예 | 프리셋, 저장 영화, 시사회 다시 편집 | 만들기/저장/홈 | clip settings 접힘/펼침, 목록/순서변경, 묶음/자클립 |
| CLIP_TRIM | 개별 클립 편집/미리보기 | 예 | EDITOR 클립 탭 | 닫기, 이전/다음, 삭제, 시사회 | 사진/영상, 자동진행, trim, 확대 |
| TEXT | 자막 설정 | 예 | EDITOR 자막행, QUICK_DURATION | 저장/취소, 폰트 picker | 사용/안함, 기본/사용자텍스트, 프리셋, 고급 폰트 |
| MUSIC | 음악 설정 | 예 | EDITOR 음악행, QUICK_DURATION | 저장/취소, 파일, 브라우저 | 없음/샘플/파일, 재생, 볼륨, 반복, fade |
| BROWSER | 외부음악 브라우저 | 예 | MUSIC/ i 롱터치 | 다운로드→미디어/공유 inbox, 닫기 | favorites panel/editor, 탐지, 다운로드 progress/완료/실패 |
| ENDING | 엔딩 설정 | 예 | EDITOR 음악 아래 엔딩행, QUICK_DURATION | 저장/취소 | 사용, 시간 1~10s/0.5s, 5 테마, preview/재생성 |
| GENERATION | 영상 제작 진행 | 예 | 만들기/퀵 만들기 | PREVIEW 또는 취소/오류 | 준비, 합성 진행, 현재 thumbnail, 시간, 취소, decode 오류 |
| PREVIEW | 시사회 | 예 | GENERATION 성공 | 다시 편집, 공유, 개봉, fullscreen | 재생/일시정지, 진행바, 전체화면, 저장 옵션 |
| RELEASE | 개봉/저장 | 예 | PREVIEW `개봉하기` | 사진 앱/파일 앱/취소 | 앨범명, 저장 진행/완료/실패 |
| COLLECTION | 컬렉션 홈 섹션 | 예 | HOME 내부 | import/player/context menu/compress | 0/있음, 2열, 핀, progress, bulk 접힘/펼침 |
| COLLECTION_PLAYER | 컬렉션 플레이어 | 예 | 포스터 탭 | 아래 swipe/닫기 | portrait/landscape, controls auto-hide, scrub, zoom/pan/reset |
| COLLECTION_POSTER_AI | 썸네일 AI 재선택 | 예 | 포스터 context menu | 후보 선택/재생성/닫기 | device AI 8 + HanClip AI 8, loading/error |
| COLLECTION_COMPRESS | 파일 용량 줄이기 | 예 | context menu 또는 bulk | 작업→HOME | current info, 1080/720/540 estimate, 진행/취소 |
| AISHOT | AiShot 카메라 | 예 | 프리셋/MEDIA_MENU/quick action | 저장→EDITOR/HOME, 닫기 | 권한, 촬영대기/촬영/저장, zoom/sensitivity/camera, progress/error |
| THEME | 테마 패널/notice | 예 | 로고 0.6s 롱터치/탭 | 선택/확인/외부탭 | 6 mode, custom reorder, 4-color summary |
| COPYRIGHT | i 버튼/카피라이터 | 예 | i 탭 | X/로고 | watermark collapsed/expanded, IAP, sleep, docs, licenses |
| PERMISSION_ALERT | 권한·오류 | 예 | 각 서비스 | 확인/설정 앱 | 사진/카메라/마이크/저장/파일/네트워크 오류 |

## C. 홈 세부 전환

- 프리셋 3×2: 새 영화→`.newMovie`, 퀵모드→`.quick`, AiShot→`openAiShot`, 여행 영화→`.travel`, 인생 영화→`.life`, 골프 영화→`.golf` (`EditorView.swift:3128-3200`).
- 저장 프로젝트는 AiShot과 일반을 별도 목록으로 나누지 않고 `model.savedProjects` 한 배열로 렌더링한다. 프로젝트 종류 아이콘을 시간 앞에 넣는다. 최대 10 (`ProjectStore.swift:39`).
- 컬렉션은 별도 화면이 아니라 홈 아래 2열 선반이다. 최대 30 (`MovieCollectionStore.swift:140`). 포스터 탭은 player, 롱터치 context menu, pin 된 항목만 drag reorder.
- 로고 탭은 `visibleThemeModes`의 다음 모드로 순환하고 2초 notice. 롱터치는 패널. 패널 내부 custom 세 모드만 drag reorder 가능.
- i 탭은 COPYRIGHT, 0.55초 롱터치는 BROWSER.

## D. 사진·달력 공유 선택 상태

- 둘은 동일 `model.mediaPickerSelectionIdentifiers`를 주고받는다. 전환은 0.11초 crossfade이며 full-screen cover는 유지한다 (`EditorView.swift:653-681`).
- PHOTO→CALENDAR는 현재 identifier 배열을 전달. CALENDAR→PHOTO도 동일 배열을 전달한다.
- 영화 제작/퀵모드에서 사진을 다시 열면 기존 사진 보관함 선택을 복원하고, 새 확인 결과로 Photo Library 출처만 교체한다. 파일로 가져온 클립은 유지한다.
- 컬렉션용 사진 선택도 같은 PhotoPicker/Calendar 계열을 쓰지만 mediaType을 video로 제한한다. Android는 컬렉션 import에서 영상만 허용한다.

## E. 편집→제작→시사회

```text
EDITOR 만들기
 → 입력/소스 준비(isLoading/importing)
 → 영상 합성(isExporting/isPreviewRendering)
 → 성공: model.exportedURL + showPreview
 → PREVIEW
    ├ 다시 편집 → 저장 프로젝트/퀵 시작 모드에 따라 EDITOR 또는 QUICK_DURATION
    ├ 공유 → system share
    └ 개봉하기 → RELEASE → Photos album 또는 Files exporter
```

- 전역 busy overlay 조건: export, project load, photo import, shared import, calendar load/import (`EditorView.swift`의 `isBusyOverlayVisible`).
- 취소 가능 조건은 작업별 메서드가 있을 때만 버튼을 보인다. 취소는 task cancel + 가능한 경우 import rollback.
- Cannot Decode 등 exporter 오류는 `alertMessage`로 전역 alert. 특정 media 범위가 있으면 본문에 포함되는 것은 ViewModel/Composer 경로이며 고정 문구를 Android에서 임의 생성하지 않는다.

## F. 컬렉션 상태 매트릭스

| 상태 | 표시 |
|---|---|
| 0개 | `0/30`, ADD A FILM 포스터 1개, 선반, 비활성 `컬렉션 용량 줄이기` |
| 1~29개 | 2열 포스터 + 마지막 ADD A FILM, pin/hole, metadata, bulk control |
| 30개 | 포스터만, add card 숨김 |
| import | `컬렉션으로 가져오는 중`, completed/total, progress bar |
| AI poster | `AI가 컬렉션의 최고 순간을 고르는 중`, completed/total |
| compression | `<title> 용량 줄이는 중`, %, 취소, progress |
| bulk collapsed | archivebox + label + chevron down, 높이 28 |
| bulk expanded | 720p/540p 두 버튼 + “선택한 해상도 이하인 영상은 그대로 둡니다.” |
| pinned | `CollectionPin` 이미지가 포스터 상단에 걸침, drag/drop 가능 |
| unpinned | 작은 검정 종이 구멍 표시, drag reorder 불가 |

## G. 화면 방향/반응형

- iPhone 루트 홈·편집은 portrait 정책이며 전체화면 플레이어 진입/종료 때 방향 정책을 전환·복원한다. iPad는 모든 방향을 지원한다.
- regular horizontal size class에서 루트, 헤더, 하단 핵심 콘텐츠는 최대 920pt다. 테마 패널 620pt, 확인 패널 760pt, 공유 inbox 720pt 상한이다.
- 시사회와 컬렉션은 최신 공통 `HanClipFullscreenVideoPlayer`를 사용한다. iPhone은 센서 방향과 gesture 축을 보정하고 iPad는 현재 window 방향을 사용해 수동 이중 회전을 피한다.
- 사진 선택은 UIKit collection view 열 수가 pinch로 1/3/5/8로 바뀐다. 날짜 separator는 가운데 정렬. 상하 edge auto-scroll 속도는 edge 접근량에 비례한다.
- Android는 landscape에서 닫기 swipe가 물리 화면의 아래 방향이 되도록 orientation 변환 후 gesture translation을 해석한다. iOS 축을 그대로 복사하지 않는다.

## H. 딥링크/퀵액션

- `hanclip://aishot`, `hanclip://quick`, `hanclip://files`, `hanclip://calendar`, `hanclip://photo`, `hanclip://search`, `hanclip://open`.
- 현재 quick action switch에는 `.open`, `.aiShot`, `.photo`, `.quick`, `.calendar`, `.files`, `.search`가 모두 남아 있다. 홈 아이콘 노출 목록과 외부 URL 처리 목록은 별개다.

## I. 미사용 또는 호출 여부 확인 필요

- 전역 색상 `golfPrimary/golfSecondary`는 현재 `HanClipTheme.primaryUIColor/secondaryUIColor` 선택 switch에서 참조되지 않는다. 골프 프리셋 accent는 Main/Sub 토큰을 사용한다.
- `HanClipQuickAction.calendar/files/search` 케이스는 라우터에 존재하고 처리되지만 현재 앱 아이콘 quick action 노출 구성은 Info.plist/등록 코드 별도 확인 필요. Android shortcut 노출은 제품 요구와 맞춰 다시 확인한다.
- 소스에 존재하는 helper View라도 `presentationConfiguredView`, `activeRootContent`, 설정 화면 body 또는 context menu에서 역참조되지 않으면 Android 구현 범위에서 제외한다. 개별 문서에 “호출 근거”가 없는 helper는 미사용으로 간주한다.
- iPad regular-width 루트/헤더/하단 최대 920pt와 주요 패널 상한은 확정됐다. 화면별 열 수처럼 별도 분기가 없는 영역은 iOS가 가용 폭 안에서 기존 grid/layout을 확장하므로 Android 고유 600/840dp 분기는 실제 기기 검증 후 `IOS_PARITY.md`에 기록한다.

## J. 상세 문서 연결

- [홈·미디어 메뉴](screens/HOME.md)
- [사진·달력·가져오기](screens/MEDIA_SELECTION.md)
- [영화 제작·클립 설정·순서 변경](screens/EDITOR.md)
- [자막·음악·외부 브라우저](screens/TEXT_MUSIC_BROWSER.md)
- [엔딩·5종 카드](screens/ENDING.md)
- [제작 진행·시사회·개봉](screens/EXPORT_PREVIEW.md)
- [컬렉션·플레이어](screens/COLLECTION.md)
- [AiShot](screens/AISHOT.md)
- [테마·카피라이터·권한/오류](screens/SYSTEM_PANELS.md)
