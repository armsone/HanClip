# Android 7단계 보고서: 영상 순서 변경

## 구현한 기능

- 각 클립 카드에 위/아래 이동 버튼을 배치했습니다.
- `EditorViewModel.moveClipUp`, `moveClipDown`으로 리스트 순서를 변경합니다.
- 순서 변경 후 클립 번호와 전체 요약이 다시 계산됩니다.

## 추가하거나 수정한 파일

- `/Users/armsone/git/HanClip/android/app/src/main/java/com/hanclip/android/feature/editor/EditorViewModel.kt`
- `/Users/armsone/git/HanClip/android/app/src/main/java/com/hanclip/android/feature/editor/EditorRoute.kt`

## 실행 및 테스트 방법

```bash
cd /Users/armsone/git/HanClip/android
JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ./gradlew :app:assembleDebug
```

편집 화면의 클립 카드 우측 위/아래 버튼으로 순서가 바뀌는 것을 확인했습니다.

## 남아 있는 문제

- 드래그 앤 드롭 정렬은 아직 없습니다. 현재는 명확한 버튼 방식입니다.

## 다음 단계 작업

- 자막과 폰트 설정 UI를 구현합니다.
