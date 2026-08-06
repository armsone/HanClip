# HanClip Android 3단계 보고

작성일: 2026-08-06

## 구현한 기능

- Android Photo Picker 연결
  - 편집 화면의 `사진` 버튼은 이미지/영상 선택 Picker를 연다.
  - 편집 화면의 `파일` 버튼은 영상 선택 Picker를 연다.
- 선택한 미디어를 실제 클립 목록에 반영
  - 선택된 Uri를 `ClipItem.sourceUri`와 `thumbnailUri`에 저장한다.
  - 처음 실제 미디어를 가져오면 2단계용 샘플 클립을 실제 미디어로 교체한다.
  - 이후 추가 선택은 기존 클립 뒤에 붙일 수 있게 했다.
- 미디어 메타데이터 읽기
  - ContentResolver MIME 타입으로 사진/영상 구분
  - 영상은 `MediaMetadataRetriever`로 길이, 폭, 높이를 읽는다.
  - 사진은 Bitmap bounds로 폭, 높이를 읽는다.
- 썸네일 표시
  - 사진은 `ImageDecoder`/`BitmapFactory`로 Bitmap 썸네일을 만든다.
  - 영상은 `MediaMetadataRetriever.getScaledFrameAtTime`으로 첫 프레임 썸네일을 만든다.
  - Compose `Image`로 클립 행 왼쪽에 실제 썸네일을 표시한다.
- 가져오기 상태와 완료 알림
  - 가져오는 동안 상태 문구를 표시한다.
  - 가져오기 성공/실패 알림을 표시한다.

## 추가하거나 수정한 파일

- `android/app/src/main/java/com/hanclip/android/core/media/MediaImportReader.kt`
- `android/app/src/main/java/com/hanclip/android/feature/editor/EditorRoute.kt`
- `android/app/src/main/java/com/hanclip/android/feature/editor/EditorViewModel.kt`
- `android/app/build.gradle.kts`
- `android/README.md`

## 실행 및 테스트 방법

```bash
cd /Users/armsone/git/HanClip/android
JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ./gradlew :app:assembleDebug
```

생성된 APK:

```text
/Users/armsone/git/HanClip/android/app/build/outputs/apk/debug/app-debug.apk
```

에뮬레이터 검증:

- `StarterApp_API_37` 에뮬레이터 실행
- APK 설치 성공
- 테스트 이미지를 `/sdcard/Pictures/`에 push 후 Media Scanner 실행
- 홈에서 `새 영화` 진입
- 편집 화면의 `사진` 버튼으로 Android Photo Picker 열림 확인
- 테스트 이미지 선택 후 한클립으로 복귀
- 클립 수가 1개로 바뀌고 실제 썸네일이 클립 목록에 표시되는 것 확인

## 남아 있는 문제

- 실제 영상 파일 선택 버튼은 연결되어 있지만, 이번 검증은 에뮬레이터에 준비한 이미지로 했다.
- 선택한 Uri는 아직 프로젝트 저장소에 영구 복사하지 않는다. 앱 재시작/장기 보관을 위해서는 다음 저장소 단계에서 앱 전용 파일로 복사해야 한다.
- 썸네일은 화면 표시용으로 즉석 생성한다. 많은 영상을 불러올 때 캐시가 필요하다.
- 영상 길이는 읽지만 아직 영상 재생/구간 선택 UI는 없다.

## 다음 단계 작업

4단계: 영상 재생 및 구간 선택

- Media3 ExoPlayer로 선택한 영상 재생
- 개별 클립 선택 화면 또는 시트 구성
- 시작/종료 슬라이더 구현
- `trimStartSeconds`, `durationSeconds`를 실제 UI 조작으로 업데이트
