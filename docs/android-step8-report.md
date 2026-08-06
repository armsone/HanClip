# Android 8단계 보고서: 자막과 폰트 적용

## 구현한 기능

- 자막 설정 시트를 추가했습니다.
- 자막 사용 여부, 문구, 글꼴 크기, 글꼴 계열, 색상, 위치를 조절할 수 있습니다.
- 설정값은 `WatermarkSettings` 모델로 관리하고 편집 화면 상태에 반영합니다.

## 추가하거나 수정한 파일

- `/Users/armsone/git/HanClip/android/app/src/main/java/com/hanclip/android/core/model/WatermarkSettings.kt`
- `/Users/armsone/git/HanClip/android/app/src/main/java/com/hanclip/android/feature/editor/TextOverlaySheet.kt`
- `/Users/armsone/git/HanClip/android/app/src/main/java/com/hanclip/android/feature/editor/EditorRoute.kt`
- `/Users/armsone/git/HanClip/android/app/src/main/java/com/hanclip/android/feature/editor/EditorViewModel.kt`

## 실행 및 테스트 방법

```bash
cd /Users/armsone/git/HanClip/android
JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ./gradlew :app:assembleDebug
```

편집 화면의 `자막` 버튼으로 설정 시트가 열리고 값이 변경되는 것을 확인했습니다.

## 남아 있는 문제

- 현재 자막 설정 UI와 상태 저장까지 구현되어 있습니다. 실제 영상 프레임 위 합성은 다음 고도화에서 필요합니다.

## 다음 단계 작업

- 여러 영상 연결 및 내보내기를 구현합니다.
