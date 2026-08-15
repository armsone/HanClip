# 컨트롤 기본값과 상태 수명

화면 표시를 보고 추정하지 않고 초기화·저장·복원 코드를 따라 정리했다. `세션`은 현재 View 인스턴스가 살아 있는 동안, `프로젝트`는 ProjectStore에 저장된 영화 단위, `앱`은 UserDefaults/컬렉션 디스크 저장을 뜻한다. 서로 충돌하는 경로는 별도 표기한다.

## 홈·테마·컬렉션

| 컨트롤/위치 | 선택지·문구 | 최초/새 진입 기본 | 변경 후 수명·복원 | 비활성/연동 | 실제 상태/근거 |
|---|---|---|---|---|---|
| 로고 테마 | Automatic, Light, Dark, Blossom Glow, Grayscale Play, Pixel Pop | `automatic` | 탭/패널 선택 즉시 UserDefaults; 앱 재실행 유지. 프로젝트와 무관 | custom 3종만 drag reorder | `@AppStorage hanClipThemeMode`, `hanClipCustomThemeOrder`; `EditorView.swift:156-239, 2656-2945` |
| 컬렉션 pin | 고정/해제 | import 시 unpinned | 컬렉션 저장소에 유지, 앱 재실행 복원. pinned만 drag 순서 저장 | unpinned는 drag 불가 | `CollectedMovie.isPinned`, `MovieCollectionStore`; `EditorView.swift:3570-3825` |
| bulk 압축 펼침 | 닫힘/열림 | 화면 인스턴스 생성 시 닫힘 | 홈 View 세션 동안 유지, 앱 재실행/새 root는 초기화 | collection 0이면 disabled, 닫힘 값 유지 | `@State isCollectionBulkCompressionExpanded=false`, `EditorView.swift:143,3579+` |
| bulk 해상도 | 720p/540p | 선택 전 없음 | 버튼 즉시 작업, 선택 값 자체 저장 안 함 | 이미 목표 이하 영상은 skip | `beginCollectionBulkCompression` |

## 사진·달력·가져오기

| 컨트롤 | 선택지 | 기본 | 수명·복원 | 비활성/연동 | 상태/근거 |
|---|---|---|---|---|---|
| media filter | 전체; 사진/Live/영상 복수 | 일반 `[photo,livePhoto,video]`; 컬렉션 videoOnly `[video]` | picker controller 재생성 시 초기화. 사진↔달력은 selection만 공유하며 filter는 공유 안 함 | 최소 1종 유지. duration filter 시 강제로 video | `selectedMediaFilters`; `PhotoPicker.swift:429-437, 966-1055` |
| duration filter | 이상/이하 + ≥1초 | 없음, comparison `.atLeast` | picker 세션. 해제 시 이전 media filters 복원 | 켜면 mediaFiltersBeforeDurationFilter 저장 후 `[video]`; 끄면 복원 | `durationFilterSeconds`, `durationFilterComparison`; `1120-1138` |
| sort | 날짜순/추가순 + ↑/↓ | 날짜순, 오름차순 | picker 세션만. 같은 mode 재탭 방향 반전; 다른 mode 선택 시 기존 방향 유지 | 없음 | `mediaSortMode=.captureDate`, `isMediaSortAscending=true`; `438-440,1027-1073` |
| grid columns | 1/3/5/8 | 5 | picker 세션만 | pinch boundary에서 더 이상 이동 불가 | `columnCount=5`; `PhotoPicker.swift:444,1510+` |
| selection | asset multi-select | 호출 시 `initialSelectionIdentifiers`; 아니면 빈 배열 | 사진↔달력/같은 project 재진입 복원. 확인하면 Photo Library 출처를 교체; file 출처 유지. project save에는 clip source로 복원 | 0개면 `추가/확인/해제` disabled | `mediaPickerSelectionIdentifiers`; `EditorViewModel.swift:159+`; `PhotoPicker.swift:1616-1632` |
| 오늘 2단계 | 이동/오늘 visible 선택 | armed=false | filter/sort 변경 시 reset, picker 종료 시 소멸 | 첫 tap 후 같은 상태에서 두 번째 tap selection | `isTodayButtonArmedForSelection`; `PhotoPicker.swift:451` |

## 영화 제작·클립 설정

| 컨트롤 | 선택지·문구 | 최초/프리셋 기본 | 수명·복원 | 비활성/연동 | 상태/근거 |
|---|---|---|---|---|---|
| 기본시간 stepper | 0.1~0.9:0.1; 1~10:0.5; 11+:1.0, 전체 0.1~30 | 앱 최초 fallback 3.0. preset: 새2, 퀵1, AiShot4, 골프4, 여행1, 인생2 | `hanClipDefaultDuration` UserDefaults에 매 변경 저장; preset 진입은 덮어씀. 프로젝트 save/load는 project 값 복원 | min/max에서 button disabled; 적용 시 clips 갱신 | `defaultDuration`, storage key; `EditorViewModel.swift:106-118,230-246,750-790` |
| 영상 분할 | 표시 `한컷/분할`; model `.single/.multiple` (`all`은 묶음용 의미) | 모든 현 preset `.multiple`=분할 | project 저장/복원. 새 project는 preset 적용 | peak 없음 시 single로 자동 reset 가능 | `defaultVideoSegmentMode`; `EditorViewModel.swift:120,750-790,1841,4632+` |
| 모션포토 방식 | iOS `사진/영상`; model `.still/.motion` | import한 Live Photo는 `.motion`; bulk UI state `.motion` | clip별 project 저장/복원. bulk state 자체는 View 세션 | 모션 데이터 없으면 영상 선택 실효 없음 | `ClipItem.livePhotoMode`; `PhotoPicker.swift:2964`; `EditorView.swift:121,6235+` |
| 묶음 사용 방식 | 자동/수동/전체 → model single/multiple/all 매핑 | bulk state `.single`=자동. import grouping 기준으로 group에 설정 | group/clip project 저장/복원 | group이 없으면 행 없음 | `bulkSimilarPhotoGroupMode=.single`, `similarPhotoGroup videoSegmentMode`; `EditorView.swift:122,6300+` |
| 대표 간격 stepper | `1/n`, n=1…20 | 앱 최초 6. 여행 6, 인생 3; 그 외 저장된 UserDefaults 유지(프리셋이 명시한 경우 덮어씀) | UserDefaults + project 결과 재계산. 저장 영화 load 후 current criteria 재적용 | min/max disable; 변경 시 grouping representative 재선택 | `similarPhotoRepresentativeInterval`, key; `EditorViewModel.swift:108,121,267-282,778-787` |
| 영상 길이 범위 | `선택구간/전체영상` | clip trim 값에 따라 선택구간 | clip/project 저장 | 사진에는 미노출 | `VideoRangeSegmentedControl`, trimStart/duration |
| 화면비율 | `첫 사진`, 1:1,3:4,4:3,9:16,16:9 | UserDefaults 미설정=`첫 사진`/nil | UserDefaults 기본 + project 저장/복원. project import 첫 media 시 stored default 다시 적용 | clips 없는 editor에서는 출력 source 자동값 | `outputAspectRatio`, `hanClipDefaultAspectRatio`; `EditorViewModel.swift:122-124,248-264` |
| clip settings 펼침 | 닫힘/열림 | 닫힘 | EditorView 세션, project 저장 안 함 | 없음 | 해당 `@State`/section gesture; `EditorView.swift:5900-6510` |

## 프리셋 초기값

| 프리셋 | 기본시간 | 영상 | 대표간격 | 자막 | 음악 | 엔딩 | 비율 |
|---|---:|---|---:|---|---|---|---|
| 새 영화 | 2s | 분할 | 저장값 | 사용, 오늘 날짜, Poppins/노랑/보라 그림자 | 없음 (`.empty`) | 안함, 자막,2s | 저장 기본 |
| 퀵모드 | 1s(길이 선택에서 재계산 가능) | 분할 | 저장값 | 사용, 빈 텍스트 | `햇살 한 컷`, 사용 | 안함, 자막,2s | 저장 기본 |
| AiShot | 4s | 분할 | 저장값 | 사용, 오늘 날짜, green golf preset | 없음 | 안함 | 저장 기본 |
| 골프 | 4s | 분할 | 저장값 | 사용, 오늘 날짜 | `골프치러 가자` | 안함 | 저장 기본 |
| 여행 | 1s | 분할 | 6 | 사용, 촬영기간+지역으로 import 후 refresh, travel font/color | `여행의 설렘` | **주의:** theme만 보물지도이며 `includesEndingInfoCard`는 projectDefault false에서 바꾸지 않음. 즉 화면 요구와 달리 자동 사용 여부는 확인 필요 | 저장 기본 |
| 인생 | 2s | 분할 | 3 | 사용, 오늘 날짜 | 없음 | 안함 | 저장 기본 |

근거 `EditorViewModel.applyMoviePreset:748-800`, `WatermarkSettings.projectDefault/dateCaptionPreset/travelPreset:662-755`, `BackgroundMusicSettings` `ClipItem.swift:1-120`.

## 퀵모드 길이

| 컨트롤 | 선택지 | 기본/수명 | 연동/저장 | 근거 |
|---|---|---|---|---|
| selected duration | stepper ±5s, 30s/45s/1m/2m/3m/5m/추천시간/최소시간 | 진입 시 추천=`max(1, mediaCount×1s)`, `usesRecommended=true`. Quick picker 재생성 시 다시 추천; 설정/미디어 round-trip은 model 값으로 cover 재생성되어 확인 필요 | 고정 선택은 min `max(0.2, mediaCount×0.2)`. 만들기 때 target/mediaCount로 defaultDuration, 최소0.2. 추천은 nil 전달→기본 1s 유지 | `QuickMovieDurationPicker.init`, `minimumSelectableDuration`; `EditorView.swift:15849-16354`; `confirmQuickMovieDuration` |
| ratio | 첫 사진+5개 | stored default/project 값 | 즉시 model 변경, 프로젝트 저장 | 위 표 |
| 자막/음악/엔딩 toggles | 사용/안함 | quick preset 값 | binding으로 model 즉시 변경; 설정 화면 닫아도 유지; 저장/불러오기 복원 | `EditorView.swift:682-708,15900+` |

## 자막

| 컨트롤 | 선택지/기본 | 수명 | 조건/연동 | 상태/근거 |
|---|---|---|---|---|
| 사용 | 사용/안함 | projectDefault false지만 모든 movie preset은 true. project 저장/복원 | 텍스트가 비어도 사용 가능; 실제 render text는 비어 있으면 없음, 엔딩은 독립 | `WatermarkSettings.isEnabled`, `EditorView.swift:9437+` |
| 위치 | 5×5, `가로 n, 세로 n` | topLeading | project 저장/복원 | preview tap 선택 | `WatermarkPosition` |
| 서체 | bundled/imported presets | Poppins; travel/golf preset 차이 | project 저장/복원; imported font registry는 앱 저장 | `fontName`, FontRegistry |
| 크기 | 작게11/기본14/크게21/더크게26 | 더크게 | project 저장/복원 | preset travel=large, golf=extraLarge | `WatermarkFontSize` |
| 행간 | 좁게/보통/넓게 + multiplier 0.5…2 step.2 | normal/1.0 | project 저장/복원 | line spacing preset+fine value 연동 | `WatermarkLineSpacing` |
| 그림자 | on/off, opacity/color | on, .75, #642BFF | project 저장/복원 | opacity 0이면 shadowEnabled false로 normalize | `WatermarkSettings` |

## 음악

| 컨트롤 | 선택지/기본 | 수명 | 조건/연동 | 근거 |
|---|---|---|---|---|
| 사용 | 사용/안함 | `projectDefault`는 첫 bundled sample `햇살 한 컷` 사용. 단 새/AI/golf/life preset은 `.empty` 또는 지정곡으로 덮어씀 | project 저장/복원. 파일 없으면 shouldRender=false | `BackgroundMusicSettings.projectDefault/empty`, preset switch |
| sample | 6곡(정확 목록은 TEXT_MUSIC_BROWSER) | preset 지정 또는 선택 없음 | 선택 즉시 fileURL/displayName/isEnabled true | `sampleTracks`, `useSampleBackgroundMusic` |
| music volume | slider | .35 | project 저장/복원 | 없음 | `defaultMusicVolume` |
| original audio | slider | 1.0 | project 저장/복원 | 없음 | `defaultOriginalAudioVolume` |
| repeat/fade in/fade out | bool | 모두 true | project 저장/복원 | 음악 파일 없으면 controls disabled 여부는 화면 소스 확인 필요 | `BackgroundMusicSettings.empty/decoder` |

## 엔딩

| 컨트롤 | 선택지/기본 | 수명 | 조건/연동 | 근거 |
|---|---|---|---|---|
| 사용 | 사용/안함 | false | project 저장/복원. 위치정보 없어도 선택 가능 | 결과 생성 시 data 없으면 실제 card 생성 불가 | `includesEndingInfoCard` |
| 시간 stepper | 1…10s, .5s step | 2s | project 저장/복원 | min/max disable | `normalizedEndingInfoCardDuration`, EndingInfo sheet |
| theme tabs | 자막/보물지도/여행일정/랜드마크/오피스 | 자막; travel는 보물지도 | project 저장/복원 | 보물지도 재탭 시 variation 증가/재생성 | `EndingInfoCardTheme`, `endingInfoCardVariation` |
| 자막 테마 font/color/shadow | 자막 설정과 동일 | current caption values | project 저장/복원 | theme=caption일 때 결과에 사용 | WatermarkSettings |

## 재생·반복·정렬

| 화면/컨트롤 | 기본 | 수명/복원 | 근거 |
|---|---|---|---|
| clip preview 자동진행 | off | EditorView 세션; project 저장 안 함 | `isAutoAdvancingPreview=false` |
| clip preview loop auto advance | off | EditorView 세션 | `isLoopingPreviewAutoAdvance=false` |
| 시사회 | 나타날 때 seek zero + play | 화면 재진입마다; project 무관 | `VideoPreviewView.onAppear` |
| fullscreen preview loop | on; aspectFill on; controls hidden | 화면 인스턴스 | `FullscreenVideoPreview` states |
| collection player | play on appear; controls auto-hide; zoom=1; configuration상 loop/fit-fill 제공 | 화면 인스턴스, 닫으면 reset | `HanClipFullscreenVideoPlayer` + collection 호출 configuration |

## AiShot

| 컨트롤 | 선택지/기본 | 수명 | 조건/연동 | 근거 |
|---|---|---|---|---|
| 감도 | 시끄러움/일반/조용함/자동 | 자동 | global `@AppStorage hanClipAiShotSensitivity`, 앱 재실행 유지, project와 무관 | controller sensitivity 즉시 변경 | `AiShotCamera.swift:6-40,127,271` |
| 샷 시간 | 짧게(1.5+1.5), 일반(2+3), 길게(5+5) | project별 최초 일반; 다음 edge long | projectID가 있으면 UserDefaults project-scoped key로 유지 | 일반→이전 edge 방향, short/long→normal 순환 | `AiShotDurationPreset`, init/store `AiShotCamera.swift:70-115,141-170,940-1010` |
| camera | 전면/후면 | 후면 | camera view/controller 세션; 저장 여부 확인 필요(현재 controller state) | 사용 가능한 device에 따라 disable/fallback | `cameraPosition=.back` |
| zoom | lens factors + precision dial | 1× 또는 camera min clamp | camera session; 앱 재실행 저장 안 함 | camera 전환 시 지원 범위 clamp | `zoomFactor=1`, controller setters |
| phase | 감지 중/감지 됨/저장 중 | detecting | capture state machine | saving 중 진행바; 설정 controls는 계속 조작 가능하도록 UI 요구 | `AiShotPhase` |

## 카피라이터

| 컨트롤 | 기본/선택지 | 수명 | 조건 | 근거 |
|---|---|---|---|---|
| 워터마크 사용 | 사용/안함 | 최초 logo watermark true(UserDefaults 키 부재 시), copyright 구매 상태에 따라 사용 가능 | UserDefaults 앱 영속; 프로젝트 caption과 별도 | 미구매 시 off+panel collapse | `WatermarkSettings.stored`, `ImportantInfoSheet` |
| sleep prevention | 항상켜짐/끔/오토 | `automatic` | `@AppStorage hanClipSleepPreventionMode`; 앱 영속 | auto는 render/import/save 동안만 idle timer disable | `EditorView.swift:33-60,214` |
| platform/address/position/colors | HanClip 및 SNS/사용자 아이콘, 5×5 위치 등 | platform HanClip, address empty, bottomTrailing, original color | UserDefaults 앱 영속 | platform 변경 시 주소/color defaults 연동 | WatermarkSettings keys + ImportantInfoSheet |

## 저장 수명 요약

- UserDefaults: 테마/테마순서, global 기본시간/비율/대표간격, AiShot 감도, project-scoped AiShot 시간, 카피라이터/화면꺼짐 방지.
- ProjectStore: clips와 clip별 선택, defaultDuration, video mode, aspect ratio, automatic source size, caption/ending, music, initial preset.
- View 세션만: panel 펼침, preview 재생/loop/zoom, photo filters/sort/columns, quick picker local choice.
- 컬렉션 저장소: movies, title/metadata/poster/pin/order/compression result.
