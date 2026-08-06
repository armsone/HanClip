# HanClip iOS 분석 및 Android 이식 문서

작성일: 2026-08-05

## 1. 전체 화면과 화면 이동 구조

iOS 앱은 `HanClipApp`에서 `EditorView`를 루트로 띄우는 단일 화면 중심 구조다. `EditorView` 내부에서 `model.isProjectOpen` 값에 따라 홈 화면과 편집 화면을 전환하고, SwiftUI `fullScreenCover`, `sheet`, `fileExporter`, `alert`로 보조 화면을 띄운다.

주요 화면은 홈, 클립 편집, 사진 선택, 달력 선택, 파일 선택, AiShot 카메라, 테마 선택 팝업, 자막 설정, 저작권/로고 설정, 배경음악 설정, 온라인 음악 브라우저, 영상 미리보기, 전체 화면 플레이어, 저장 옵션, 진행 오버레이로 구성된다.

Android에서는 `MainActivity` + Compose Navigation으로 `Home`, `Editor`, `Preview`, `AiShot`, `Settings/TextOverlay`, `Settings/Music`, `Picker` 계열 route를 나누되, 사용자 흐름은 iOS처럼 홈과 편집을 가장 큰 두 상태로 유지한다.

## 2. 각 화면의 기능과 사용자 흐름

홈은 새 영화, AiShot, 여행, 골프 프리셋을 시작하고 저장된 프로젝트를 불러온다. 공유 인박스에 대기 중인 항목이 있으면 배너로 새 프로젝트 또는 기존 프로젝트 가져오기를 제공한다. Android AiShot은 CameraX 화면으로 진입해 카메라/마이크 권한, 감도, 샷 길이, 수동 클립 저장을 제공하고 저장된 클립을 AiShot 편집 화면으로 전달한다.

편집 화면은 클립 목록, 전체 기본 시간, 일괄 전체 구간 선택, 화면비, 자막, 배경음악, 순서 변경, 영상 만들기 버튼을 제공한다. 개별 클립 행에서는 썸네일, 구간, Live Photo 모드, 단일/다중 세그먼트, 삭제와 미리보기를 다룬다.

미리보기 화면은 내보낸 MP4를 재생하고 공유, 다시 편집, 홈 이동, `개봉하기` 저장 옵션 흐름을 제공한다. Android `개봉하기`는 사진 앱 저장과 파일 저장을 하단 팝업으로 선택하게 한다.

## 3. 영상 불러오기 및 권한 처리 방식

사진 보관함은 `PHPhotoLibrary.authorizationStatus(for: .readWrite)`와 `PHPhotoLibrary.requestAuthorization(for: .readWrite)`로 `.authorized` 또는 `.limited`일 때 허용한다. 사진/영상 썸네일은 `PHImageManager`, 영상 파일은 `PHAssetResourceManager` 또는 파일 복사 흐름을 사용한다.

파일 가져오기는 보안 범위 리소스 접근(`startAccessingSecurityScopedResource`) 후 임시 경로에 복사한다. 공유 확장은 `SharedInbox`에 파일 기록을 쌓고 앱 활성화 또는 신규 프로젝트 진입 시 가져온다.

Android 대체는 Android 13 이상에서 `READ_MEDIA_IMAGES`, `READ_MEDIA_VIDEO`, Android 12 이하에서 `READ_EXTERNAL_STORAGE`, Android 10 이상 저장은 MediaStore scoped storage, 파일 선택은 Storage Access Framework 또는 Photo Picker를 사용한다.

## 4. 자동 타격점 탐지 알고리즘

자동 타격점은 영상 프레임 분석이 아니라 오디오 분석이다. `AudioAnalysisService.analyze`가 오디오 트랙을 16-bit PCM으로 읽고 기본 192개 버킷으로 나눈 뒤 각 버킷의 RMS 에너지를 계산한다.

정규화 후 각 버킷에서 직전 최대 5개 버킷 평균을 baseline으로 삼고, `rise + value * 0.25`를 점수로 사용한다. 상승량이 0.04를 넘거나 주변보다 큰 local maximum이면 후보가 된다. 여기에 전체 에너지 후보(`value * 0.55`)를 추가하고, 최소 간격 약 0.45초를 만족하는 상위 후보를 최대 12개 선택한다.

대표 피크는 선택 후보의 첫 번째이고, 다중 클립 분할은 선택 후보 목록을 사용한다.

## 5. 클립 시작·종료 시간 계산 방식

비디오 클립의 선택 길이는 `min(defaultDuration, sourceDuration)`이고 최소 0.5초를 보장한다. 시작 시간은 피크가 클립 중앙에 오도록 `peak - selectedDuration / 2`로 잡은 뒤 `0...sourceDuration-selectedDuration` 범위로 clamp한다.

종료 시간은 `trimStart + duration`이며 `ClipItem.trimEnd`에서 원본 길이를 넘지 않도록 `min(sourceDuration, trimStart + duration)`으로 계산한다.

## 6. 전체 영상 시간 일괄 조절 기능

`defaultDuration`은 UserDefaults에 저장되고 `0.5...30`초로 정규화된다. `applyDefaultDurationToAll()`은 모든 클립을 순회한다.

사진은 `duration`과 `photoDuration`을 기본 시간으로 설정한다. 영상은 기존 클립 중심점(`trimStart + duration / 2`)을 유지하면서 새 길이로 바꾸고 시작 시간을 clamp한다. Live Photo 정지 모드는 사진처럼, 모션 모드는 원본 길이 중앙 기준으로 재계산한다.

## 7. 개별 영상 시간 조절 기능

`updateVideoTrim(id:start:duration:)`은 영상 클립에 대해 길이를 최소 0.5초, 최대 원본 길이로 제한하고 시작 시간을 `0...sourceDuration-safeDuration`에 맞춘다. 다중 세그먼트 자식도 동일한 `ClipItem` 모델을 사용하므로 개별 구간 조정 방식은 같다.

## 8. 영상 순서 변경 기능

일반 클립 순서 변경은 SwiftUI drag/drop 기반으로 top-level unit을 이동한다. 다중 세그먼트 부모는 부모와 자식 묶음을 하나의 단위로 다루며, 세그먼트 자식끼리는 같은 부모 안에서 `moveVideoSegmentChild`로 순서를 바꾼다.

Android에서는 Compose drag/drop 또는 reorderable LazyColumn/LazyVerticalGrid 패턴을 적용하고, 데이터 계층에서는 `List<ClipItem>` 순서를 변경하는 순수 함수를 둔다.

## 9. 여러 영상의 연결 및 내보내기 방식

`VideoComposer.compose`가 `AVMutableComposition`에 각 클립을 순서대로 삽입한다. 영상/Live Photo 모션은 `trimStart`와 `duration`으로 지정한 원본 구간을 삽입한다. 사진은 렌더 크기에 맞는 임시 동영상으로 변환한 뒤 필요한 길이만큼 반복 삽입한다.

각 클립에는 aspect fill 변환을 적용하고, 전체 composition에 배경음악 믹스와 자막/로고 워터마크 렌더링을 추가한다. 최종 파일은 임시 MP4를 프로젝트 저장소로 복사한다.

Android에서는 Media3 Transformer의 `Composition`, `EditedMediaItem`, `Effects`, `ExportResult` 흐름으로 대체한다. Transformer만으로 세밀한 자막/로고 합성이 부족한 부분은 Media3 effect 또는 커스텀 OpenGL/bitmap overlay effect를 별도 구현 대상으로 둔다.

## 10. 해상도, 프레임레이트, 코덱 및 저장 형식

iOS 출력 프레임레이트는 30fps다. 파일 형식은 `.mp4`, `AVAssetExportPresetHighestQuality`를 사용한다. 사진을 동영상으로 바꾸는 중간 렌더는 H.264, 평균 비트레이트 6 Mbps, High profile, MP4를 사용한다.

화면비 프리셋은 1:1 1080x1080, 3:4 1080x1440, 4:3 1440x1080, 9:16 1080x1920, 16:9 1920x1080이다. 자동 화면비는 원본 비율에 따라 긴 변을 1920 또는 짧은 변을 1080 근처로 맞추고 4의 배수 픽셀로 보정한다.

Android 1차 목표도 MP4/H.264/30fps/동일 렌더 크기를 기본값으로 둔다. Media3 최신 안정 버전은 Android Developers 문서 기준 2026-07-22 업데이트의 1.10.1이다.

## 11. 자막, 폰트, 색상, 위치 처리 방식

자막 설정은 `WatermarkSettings`가 관리한다. 텍스트, 주소, 플랫폼, 위치, 폰트, 색상, 그림자, 줄 간격, 글자 크기, 저작권 로고 위치와 색상 옵션이 있다.

위치는 5x5 grid(`WatermarkPosition`)로 표현하고, 가로/세로 fraction은 각각 column/4, row/4다. 폰트 크기는 small 11pt, normal 14pt, large 21pt, extraLarge 26pt에 대응한다. 색상은 hex 문자열로 저장한다. 폰트는 `FontRegistry`가 번들 폰트와 사용자 추가 폰트를 관리한다.

Android에서는 동일한 5x5 grid 모델을 Kotlin enum으로 이식했다. 현재 폰트 UI는 Pretendard, 고운바탕, 나눔고딕, 도현 프리셋을 제공하며 최종 렌더에서는 Android `Typeface` 매핑으로 자막에 반영한다. iOS처럼 실제 번들 TTF 전체를 싣는 작업은 추가 품질 개선 항목이다.

## 12. 갤러리 저장 및 공유 기능

iOS 저장은 `PhotoLibraryService.saveVideo`가 Photos 권한을 사용해 사진 앱 또는 지정 앨범에 저장한다. 파일 저장은 SwiftUI `fileExporter`, 공유는 preview 화면의 share sheet를 사용한다.

Android는 MediaStore `Video.Media` insert 후 `RELATIVE_PATH`와 `IS_PENDING` 흐름을 사용한다. 공유는 `ACTION_SEND` + `FileProvider` 또는 MediaStore Uri를 쓴다.

## 13. iOS 전용 API와 플랫폼 독립적인 로직 구분

iOS 전용: SwiftUI, UIKit, Photos/PhotosUI, PHAsset/PHImageManager/PHPhotoLibrary, AVFoundation/AVKit, AVMutableComposition, AVAssetExportSession, CoreText, UniformTypeIdentifiers, WebKit/WKWebView, AppStorage/UserDefaults, Share Extension, UIApplication idle timer.

플랫폼 독립 로직: `ClipItem` 상태 모델, `VideoSegmentMode`, 기본 시간 정규화, 클립 중심 유지 시간 조정, 오디오 RMS 피크 선택 규칙, non-overlapping peak 선택, 5x5 워터마크 위치 모델, 화면비별 렌더 크기, 프로젝트 상태 흐름, 프리셋별 기본 시간/자막/음악 설정.

## 14. Android에서 대체해야 할 API 목록

| iOS API | Android 대체 |
| --- | --- |
| SwiftUI `NavigationStack`, `fullScreenCover` | Jetpack Compose Navigation, Dialog/ModalBottomSheet |
| `PHPhotoLibrary`, `PHAsset` | Android Photo Picker, MediaStore, scoped storage permissions |
| `PhotosPicker` | `ActivityResultContracts.PickMultipleVisualMedia` |
| `fileImporter`, security scoped resource | Storage Access Framework `OpenDocument` |
| `AVPlayer` | Media3 ExoPlayer |
| `AVAssetImageGenerator` | MediaMetadataRetriever 또는 Media3 thumbnail pipeline |
| `AVAssetReader` PCM 분석 | MediaExtractor + MediaCodec PCM decode 또는 FFmpeg 계열 검토 |
| `AVMutableComposition` | Media3 Transformer `Composition` |
| `AVAssetExportSession` | Media3 Transformer export |
| CoreGraphics/UIKit image drawing | Android Bitmap/Canvas 또는 Media3 Effect |
| CoreText/UIFont | Android Typeface, FontFamily |
| `PHPhotoLibrary.performChanges` | MediaStore insert/update |
| `UIActivityViewController` | Android Sharesheet Intent |
| `WKWebView` | Android WebView |
| Share Extension | Android share target intent-filter |
| `UIApplication.isIdleTimerDisabled` | `FLAG_KEEP_SCREEN_ON` |

## 단계별 Android 구현 계획

1단계는 Android 프로젝트 기본 구조 생성이다. 2단계부터 iOS와 동일한 화면과 내비게이션을 구현하고, 3단계 이후 영상 선택, 썸네일, 재생, 구간 선택, 오디오 피크 탐지, 시간 조절, 순서 변경, 자막/폰트, 연결 내보내기, 갤러리 저장/공유, 실기기 테스트 순서로 진행한다.

참고: AndroidX Media3 릴리스 정보는 Android Developers 공식 문서의 안정 버전 1.10.1 기준으로 잡았다. https://developer.android.com/jetpack/androidx/releases/media3
