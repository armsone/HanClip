# HanClip

여러 사진과 영상을 선택해 원하는 길이의 하나의 영상으로 만드는 iPhone 앱입니다.

기본 출력은 첫 번째로 선택한 사진의 원본 비율을 따릅니다. 영상을 만들기 직전에
1:1, 3:4, 4:3, 9:16, 16:9 화면 비율로 변경할 수 있습니다.

영상 생성이 끝나면 저장 전에 재생 가능한 미리보기가 표시됩니다. 미리보기에서
다시 편집하거나, 저장을 선택한 뒤 사진 앱 또는 파일 앱 위치를 정할 수 있습니다.

## 프로젝트 구성

- `HanClip.xcodeproj`, `HanClip/`: iOS 앱 Xcode 프로젝트와 소스
- `HanClipShare/`, `HanClipWidget/`: 공유 확장과 위젯
- `Shared/`, `docs/`: 공통 리소스와 개발 문서

## iOS 실행

### 개발 환경

- Xcode 16 이상
- iOS 17 이상 SDK 및 시뮬레이터
- 저장소에 공유된 `HanClip` 스킴과 Swift 5 언어 모드 사용

1. `HanClip.xcodeproj`를 Xcode로 엽니다.
2. HanClip 스킴과 iPhone 시뮬레이터를 선택합니다.
3. 실행 버튼을 누릅니다.

처음 클론한 환경에서는 Xcode의 사용자별 설정을 가져오지 않아도 저장소에
공유된 스킴과 Debug 빌드 설정으로 바로 빌드할 수 있습니다.

실제 iPhone에서 실행하려면 HanClip 및 HanClipShare 타깃의 Signing & Capabilities에서
본인의 Apple Developer Team과 고유한 Bundle Identifier/App Group을 설정해야 합니다.

## Android 소스 백업

분리 전 Android 소스와 관련 문서는
`HanClip-Android-source-backup-2026-08-10.tar.gz`에 압축 보관되어 있습니다.
