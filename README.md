# HanClip

사진과 영상을 고르면 하나의 영화로 만들어 주는 간결한 영상 편집 앱입니다. iPhone과 iPad에서 사용할 수 있고, Apple Silicon Mac에서도 iPad 앱으로 실행합니다.

## 주요 기능

- 사진·Live Photo·영상을 선택 순서대로 하나의 영화로 제작
- 개별 클립 길이, 사진/영상 모드, 묶음사진과 분할 편집
- 자막, 배경 음악, 엔딩과 출력 비율 설정
- 1:1, 3:4, 4:3, 9:16, 16:9 및 첫 사진 원본 비율 지원
- 저장 전 전체화면 미리보기와 사진 앱·파일 앱 내보내기
- 컬렉션, 프로젝트 저장·복원, AiShot 촬영 지원
- Dynamic Type, VoiceOver, 44pt 이상 핵심 터치 영역을 고려한 접근성

기본 출력은 첫 번째로 선택한 사진의 원본 비율을 따릅니다. 영상 생성이 끝나면 저장 전에 재생 가능한 미리보기가 표시되며, 다시 편집하거나 저장 위치를 선택할 수 있습니다.

## 지원 플랫폼

| 플랫폼 | 지원 범위 |
|---|---|
| iPhone | iOS 17 이상 |
| iPad | iPadOS 17 이상, 가로·세로 화면 |
| Mac | Apple Silicon Mac, macOS에서 iPad 앱으로 실행 |

Mac에서는 키보드·트랙패드 클릭이 터치 조작으로 연결됩니다. 사진 보관함, 파일 선택, 영상 미리보기와 내보내기는 macOS가 제공하는 iPad 앱 호환 환경을 사용합니다. Intel Mac은 지원하지 않습니다.

## 프로젝트 구성

- `HanClip.xcodeproj`, `HanClip/`: iPhone·iPad·Apple Silicon Mac 앱 Xcode 프로젝트와 소스
- `HanClipShare/`, `HanClipWidget/`: 공유 확장과 위젯
- `Shared/`, `docs/`: 공통 리소스와 개발 문서

## iPhone·iPad·Mac 실행

### 개발 환경

- Xcode 16 이상
- iOS 17 이상 SDK 및 시뮬레이터
- Mac 실행은 Apple Silicon Mac 필요
- 저장소에 공유된 `HanClip` 스킴과 Swift 5 언어 모드 사용

1. `HanClip.xcodeproj`를 Xcode로 엽니다.
2. HanClip 스킴과 iPhone, iPad 또는 `My Mac (Designed for iPad)`를 선택합니다.
3. 실행 버튼을 누릅니다.

처음 클론한 환경에서는 Xcode의 사용자별 설정을 가져오지 않아도 저장소에
공유된 스킴과 Debug 빌드 설정으로 바로 빌드할 수 있습니다.

실제 iPhone 또는 iPad에서 실행하려면 HanClip 및 HanClipShare 타깃의 Signing & Capabilities에서
본인의 Apple Developer Team과 고유한 Bundle Identifier/App Group을 설정해야 합니다.

## Android 소스 백업

분리 전 Android 소스와 관련 문서는
`HanClip-Android-source-backup-2026-08-10.tar.gz`에 압축 보관되어 있습니다.
