# HanClip

여러 사진과 영상을 선택해 원하는 길이의 하나의 영상으로 만드는 iPhone·Android 앱입니다.

기본 출력은 첫 번째로 선택한 사진의 원본 비율을 따릅니다. 영상을 만들기 직전에
1:1, 3:4, 4:3, 9:16, 16:9 화면 비율로 변경할 수 있습니다.

영상 생성이 끝나면 저장 전에 재생 가능한 미리보기가 표시됩니다. 미리보기에서
다시 편집하거나, 저장을 선택한 뒤 사진 앱 또는 파일 앱 위치를 정할 수 있습니다.

## 프로젝트 구성

- `HanClip.xcodeproj`, `HanClip/`, `HanClipShare/`: iOS Xcode 프로젝트
- `android/`: Kotlin·Jetpack Compose 기반 Android Studio/Gradle 프로젝트
- `Shared/`, `docs/`: 공통 규칙과 개발 문서

두 앱은 같은 제품 저장소에서 관리하지만, 빌드 프로젝트와 플랫폼 소스는 서로 분리합니다.

## iOS 실행

1. `HanClip.xcodeproj`를 Xcode로 엽니다.
2. HanClip 스킴과 iPhone 시뮬레이터를 선택합니다.
3. 실행 버튼을 누릅니다.

실제 iPhone에서 실행하려면 HanClip 및 HanClipShare 타깃의 Signing & Capabilities에서
본인의 Apple Developer Team과 고유한 Bundle Identifier/App Group을 설정해야 합니다.

## Android 실행

1. Android Studio에서 `android/` 폴더를 엽니다.
2. JDK 17과 Android SDK 37을 사용해 Gradle 동기화를 진행합니다.
3. Android Studio에서 `app` 구성을 실행하거나 아래 명령으로 디버그 APK를 빌드합니다.

```bash
cd android
./gradlew :app:assembleDebug
```
