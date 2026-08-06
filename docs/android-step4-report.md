# HanClip Android 4단계 보고

작성일: 2026-08-06

## 구현한 기능

- 영상 클립 구간 선택 화면
  - 편집 화면에서 영상 클립 행을 누르면 `구간 선택` Bottom Sheet가 열린다.
  - 원본 길이, 시작 시간, 선택 길이, 선택 구간을 표시한다.
- Media3 ExoPlayer 재생 자리
  - 실제 영상 Uri가 있는 클립은 `ExoPlayer` + `PlayerView`로 재생한다.
  - 샘플 영상 클립은 재생 자리와 안내 문구를 표시한다.
  - 시작 시간이 바뀌면 플레이어가 해당 지점으로 seek한다.
- 구간 조절
  - 시작 슬라이더로 `trimStartSeconds` 후보 값을 조절한다.
  - 길이 슬라이더로 `durationSeconds` 후보 값을 조절한다.
  - 길이는 최소 0.5초, 최대 원본 길이로 제한한다.
  - 시작 + 길이가 원본 길이를 넘지 않도록 clamp한다.
- 편집 상태 반영
  - 적용 버튼을 누르면 `EditorViewModel.updateVideoTrim()`이 클립 상태를 갱신한다.
  - 편집 화면 클립 행의 시작/길이 텍스트가 즉시 갱신된다.
  - 전체 영상 시간도 즉시 다시 계산된다.

## 추가하거나 수정한 파일

- `android/app/src/main/java/com/hanclip/android/feature/editor/VideoTrimSheet.kt`
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
- 홈에서 `AiShot` 진입
- 첫 번째 영상 클립 탭
- `구간 선택` Bottom Sheet 표시 확인
- 시작/길이 슬라이더 표시 확인
- 길이 슬라이더 조절 후 `적용`
- 첫 번째 클립 길이가 `4.0초`에서 `5.6초`로 변경되고 전체 시간이 `16.0초`에서 `17.6초`로 변경되는 것 확인

## 남아 있는 문제

- 실제 영상 Uri가 있는 경우 ExoPlayer로 재생하도록 구현했지만, 이번 검증은 샘플 영상 클립으로 UI와 상태 변경을 확인했다.
- 실제 영상 파일을 에뮬레이터에 넣어 재생/seek 동작을 검증하는 테스트가 추가로 필요하다.
- 현재는 Bottom Sheet 안에서 단일 시작/길이 슬라이더를 쓴다. iOS와 같은 더 정교한 waveform/thumbnail 기반 트리머는 후속 단계에서 다듬어야 한다.
- 사진 클립은 아직 사진 길이 조절 UI로 연결하지 않았다. 6단계 전체/개별 시간 조절에서 처리한다.

## 다음 단계 작업

5단계: 자동 타격점 탐지 로직 이식

- Android에서 영상 오디오 PCM을 추출한다.
- iOS `AudioAnalysisService`의 RMS bucket/피크 점수 알고리즘을 Kotlin으로 이식한다.
- 분석 결과를 `audioWaveform`, `audioPeakTimeSeconds`, `audioPeakTimesSeconds`에 저장한다.
- 다중 클립 분할 후보 계산을 Android 모델에 연결한다.
