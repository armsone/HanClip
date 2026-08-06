# Android 6단계 보고서: 전체·개별 클립 시간 조절

## 구현한 기능

- 전체 클립 기본 길이 선택값을 모든 클립에 적용합니다.
- 영상 원본 전체 선택 버튼으로 영상 클립의 길이를 원본 길이에 맞춥니다.
- 개별 클립마다 `-0.5`, `+0.5` 버튼으로 길이를 조절합니다.
- 시간 변경 시 전체 길이 요약이 즉시 갱신됩니다.

## 추가하거나 수정한 파일

- `/Users/armsone/git/HanClip/android/app/src/main/java/com/hanclip/android/feature/editor/EditorViewModel.kt`
- `/Users/armsone/git/HanClip/android/app/src/main/java/com/hanclip/android/feature/editor/EditorRoute.kt`

## 실행 및 테스트 방법

```bash
cd /Users/armsone/git/HanClip/android
JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ./gradlew :app:assembleDebug
```

에뮬레이터 편집 화면에서 전체 시간 패널과 개별 클립 버튼을 눌러 길이 표시가 바뀌는 것을 확인했습니다.

## 남아 있는 문제

- 아주 긴 원본 영상의 전체 선택 후 내보내기 성능은 실제 폰에서 추가 확인이 필요합니다.

## 다음 단계 작업

- 클립 순서 변경 기능을 정리하고 자막 UI를 구현합니다.
