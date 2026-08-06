# HanClip Android 2단계 보고

작성일: 2026-08-06

## 구현한 기능

- iOS 한클립 흐름에 맞춘 홈 화면 구성
  - 한클립 헤더
  - 공유 파일 대기 배너
  - 새 영화, AiShot, 여행, 골프 프리셋 카드
  - 저장된 영화 섹션
- 프리셋별 편집 화면 진입
  - `새 영화`, `AiShot`, `여행`, `골프` route 값을 Android Navigation에 연결
  - 프리셋에 따라 기본 클립 시간과 단일/다중 분할 모드 설정
- 편집 화면 구성
  - 상단 닫기/홈 이동
  - 클립 수, 전체 시간, 기본 시간, 분할 모드 요약
  - 사진, 파일, AiShot 가져오기 액션 자리
  - 자막, 음악, 순서 설정 액션 자리
  - 화면비 선택 자리
  - 샘플 클립 목록과 위/아래 순서 변경 버튼
  - 전체 기본 시간 선택과 전체 적용 버튼
  - 하단 영화 만들기 버튼
- 미리보기 화면 구성
  - 영상 플레이어 자리
  - 사진 앱 저장, 공유, 다시 편집, 홈으로 이동 액션 자리

## 추가하거나 수정한 파일

- `android/app/src/main/java/com/hanclip/android/HanClipApp.kt`
- `android/app/src/main/java/com/hanclip/android/core/model/MoviePreset.kt`
- `android/app/src/main/java/com/hanclip/android/feature/home/HomeRoute.kt`
- `android/app/src/main/java/com/hanclip/android/feature/editor/EditorRoute.kt`
- `android/app/src/main/java/com/hanclip/android/feature/editor/EditorViewModel.kt`
- `android/app/src/main/java/com/hanclip/android/feature/preview/PreviewRoute.kt`
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
- 홈 화면 표시 확인
- AiShot 카드 선택 후 편집 화면 이동 확인
- 영화 만들기 선택 후 미리보기 화면 이동 확인

## 남아 있는 문제

- 아직 실제 영상 선택, 썸네일 로딩, 재생, 편집, 내보내기는 구현 전이다.
- 저장된 영화와 공유 대기 파일은 샘플 UI만 있다.
- 자막, 음악, 순서, 화면비 버튼은 화면 자리만 있고 세부 설정 화면은 다음 단계 이후 구현한다.
- UI는 iOS 흐름에 맞춘 1차 Android 초안이며, 실제 기능이 붙으면서 세부 디자인을 더 다듬어야 한다.

## 다음 단계 작업

3단계: 영상 선택 및 썸네일 표시

- Android Photo Picker 연결
- 선택한 영상/사진 Uri를 앱 상태에 추가
- MediaMetadataRetriever 또는 Media3 기반 썸네일 추출
- 선택 항목을 편집 화면 클립 목록에 실제 데이터로 표시
