# Android 5단계 보고서: 자동 타격점 탐지 로직 이식

## 구현한 기능

- Android `MediaExtractor`와 `MediaCodec`으로 영상의 오디오 트랙을 PCM으로 디코딩합니다.
- RMS 에너지 버킷을 계산하고 정규화한 뒤, 피크 점수와 최소 간격 조건으로 타격 후보 시간을 찾습니다.
- 영상 가져오기 시 분석 결과를 `ClipItem.audioWaveform`, `audioPeakTimeSeconds`, `audioPeakTimesSeconds`에 저장합니다.
- 첫 번째 피크를 중심으로 클립 시작 시간이 자동 보정됩니다.

## 추가하거나 수정한 파일

- `/Users/armsone/git/HanClip/android/app/src/main/java/com/hanclip/android/core/media/AudioAnalysisService.kt`
- `/Users/armsone/git/HanClip/android/app/src/main/java/com/hanclip/android/core/media/MediaImportReader.kt`

## 실행 및 테스트 방법

```bash
cd /Users/armsone/git/HanClip/android
JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ./gradlew :app:assembleDebug
```

Android Emulator에서 실제 MP4를 Photo Picker로 선택해 클립이 생성되는 것을 확인했습니다.

## 남아 있는 문제

- iOS와 완전히 같은 민감도인지 확인하려면 같은 골프 샘플 여러 개로 수치 비교가 더 필요합니다.

## 다음 단계 작업

- 전체/개별 클립 시간 조절 기능을 Android UI에 연결합니다.
