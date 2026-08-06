# Android 11단계 보고서: 실제 Android 기기 테스트

## 구현한 기능

- 디버그 APK를 사용자의 Android 폰에 ADB로 직접 설치했습니다.
- 실제 기기에서 영상 가져오기, 자동 분석, 내보내기, 저장, 공유까지 확인했습니다.
- iOS `AudioImpactClassifier` 흐름을 참고해 Android 자동 타격점 분석을 RMS 중심에서 peak, crossing rate, baseline 상승, crest factor 기반 랭킹으로 보강했습니다.
- iOS AiShot 실시간 감지 흐름을 참고해 Android AiShot 자동 녹화 트리거도 RMS, peak, crossing rate, baseline 상승, crest factor 기반 confidence 판정으로 보강했습니다.
- iOS 도움말/화면의 Ai 버전 표시를 참고해 Android AiShot 하단 패널에 `Ai 0.2.1 · 798 영상 보정 Ai` 안내를 추가했습니다.
- iOS AiShot 길이 프리셋을 참고해 Android의 `짧게`/`일반`/`길게` 선택을 앞/뒤 시간 기준 모델과 설명으로 보강했습니다.
- Android AiShot 자동 감지 저장 시간을 iOS의 뒤 구간(`afterShot`) 기준으로 분리하고, 수동 저장은 전체 프리셋 길이를 유지하도록 조정했습니다.
- iOS `@AppStorage` 흐름을 참고해 Android AiShot 감도와 샷 길이 선택도 다음 실행에 유지되도록 저장했습니다.
- iOS AiShot 줌 컨트롤을 참고해 Android AiShot에 CameraX 줌 프리셋 `1x`/`2x`/`4x` 선택과 저장을 추가했습니다.
- iOS 카메라 선택 저장 흐름을 참고해 Android AiShot 전면/후면 카메라 선택도 다음 실행에 유지되도록 저장했습니다.
- iOS 워터마크 모델의 `copyrightIconColorMode`와 `copyrightIconColorHex` 흐름을 참고해 Android HanClip 로고 색상 모드도 프로젝트 저장과 내보내기에 반영했습니다.
- iOS `SELECT THEME` 팝업과 `hanClipThemeMode` 흐름을 참고해 Android 홈 화면에도 테마 선택, 팔레트 미리보기, 선택값 저장을 추가했습니다.
- Android 테마 모델을 공용화하고 선택한 테마가 편집 화면의 배경, 헤더, 요약 패널, 프리셋 상태 패널, 가져오기 버튼에도 반영되도록 확장했습니다.
- 선택한 테마가 자막, 음악, 사진 시간, 영상 구간 선택 하단 시트의 표면, 헤더, 주요 실행 버튼, 타격점 패널에도 반영되도록 확장했습니다.
- 선택한 테마가 시사회 화면, 개봉 옵션 시트, 저장 중 다이얼로그에도 반영되도록 확장했습니다.
- 선택한 테마가 편집 알림/초기화/나가기 확인 팝업, 진행 오버레이, 자막/음악/순서/비율 칩, 전체 영상 시간 패널, 하단 영화 만들기 바에도 반영되도록 확장했습니다.
- 선택한 테마가 클립 카드, 썸네일 대체 화면, 개별 클립 조작 버튼에도 반영되도록 확장했습니다.
- iOS 최신 `SleepPreventionMode` 흐름을 참고해 Android에도 `항상켜짐`/`끔`/`오토` 화면 꺼짐 방지 선택과 실제 Activity 화면 유지 플래그를 연결했습니다.
- iOS `ImportantInfoSheet` 흐름을 참고해 Android 홈 화면에도 `i` 버튼, 주요 기능 안내 팝업, 화면 꺼짐 방지 빠른 설정을 추가했습니다.
- iOS 미디어 추가 메뉴의 `파일` 항목을 참고해 Android 편집 화면에도 파일 앱에서 사진/영상을 직접 선택하는 버튼을 추가했습니다.
- iOS 저장 영화 목록의 핀 고정 버튼을 참고해 Android 저장 영화 목록에도 핀 고정/해제와 핀 항목 상단 정렬을 추가했습니다.
- iOS 저장 영화 목록의 메모 편집 흐름을 참고해 Android 저장 영화 목록에도 메모 추가/편집/표시 기능을 추가했습니다.
- iOS 홈 저장 영화 목록의 작은 조작 아이콘 밀도를 참고해 Android 저장 영화 행의 썸네일, 메모, 핀, 삭제 버튼 크기와 간격을 조정했습니다.
- 이후 추가 마감으로 기본 갤러리 직접 호출, 사진 길이 조절, 자막 합성 경로, 배경 음악 선택, Android 공유 받기를 구현했습니다.
- 추가 실기기 검증으로 자동 분할 3개, 자막, 골프 배경음악을 함께 넣은 12초 영상을 실제 MP4로 내보내고 갤러리에 저장했습니다.
- CameraX 기반 AiShot 화면을 추가하고 카메라/마이크 권한, 수동 클립 저장, 저장 개수 표시, 편집 화면 전달을 실제 폰에서 확인했습니다.
- 시사회 화면의 전체화면 미리보기를 추가하고 실제 폰에서 검은 배경 전체화면 플레이어 표시를 확인했습니다.
- 자막 설정에 `HanClip` 로고 워터마크 스위치와 위치 선택을 추가하고 최종 영상 합성 경로에 연결했습니다.
- 자막 설정에 `HanClip` 로고 색상 선택을 추가하고 미리보기, 프로젝트 저장, 최종 영상 합성 경로에 연결했습니다.
- 자막 설정에 `HanClip` 로고 그림자 색상과 진하기 조절을 추가하고 미리보기, 프로젝트 저장, 최종 영상 합성 경로에 연결했습니다.
- 자막 설정에 iOS와 같은 줄간격 선택과 세부 +/- 조절을 추가하고 최종 영상 합성 경로에 연결했습니다.
- iOS 앱 번들 한글 폰트 8종을 Android assets에 포함하고 자막 내보내기 렌더러에서 직접 사용하도록 연결했습니다.
- 골프/여행 프리셋의 기본 자막 스타일을 iOS 프리셋에 맞춰 폰트, 색상, 그림자, HanClip 로고가 자동 적용되도록 조정했습니다.
- 홈의 저장 영화 카드가 실제 MP4 첫 프레임을 썸네일로 표시하도록 개선했습니다.
- 홈 저장 영화 목록에서 최근 저장 항목을 모두 스크롤로 볼 수 있도록 표시 범위를 넓혔습니다.
- 홈 저장 영화 목록에서 실제 접근 가능한 영상만 표시하도록 보강했습니다.
- 저장 영화 썸네일이 갤러리 저장 후의 `content://` URI도 읽도록 보강했습니다.
- 홈 저장 영화 섹션의 보조 버튼을 `작업 열기`/`새 작업`으로 표시해 실제 동작과 맞췄습니다.
- 미디어 가져오기와 영화 만들기 중 실수 조작을 막는 전체 화면 진행 오버레이를 추가했습니다.
- 자막 설정에 iOS식 스타일 프리셋(`가독성`, `여행`, `시네마`, `그린골프`)을 추가했습니다.
- 시사회 `파일로 저장` 성공 시에도 저장 영화 히스토리가 갱신되도록 연결했습니다.
- AiShot 저장 중 남은 시간과 진행바를 표시하도록 개선했습니다.
- 공유 인박스 배너가 실제 공유 항목이 있을 때만 보이도록 정리했습니다.
- 공유 인박스 배너에 대기 파일 개수를 표시하도록 개선했습니다.
- 저장 영화 히스토리에서 0클립/0초 항목이 쌓이거나 표시되지 않도록 보강했습니다.
- Android 저장 화면/알림 문구를 기본 갤러리 흐름에 맞춰 `갤러리` 기준으로 정리했습니다.
- 저장 파일명을 `HanClip-yyyyMMdd-HHmmss.mp4` 형식으로 정리했습니다.
- 새로 저장되는 영화 히스토리에 프리셋 제목을 저장하고 홈 카드 제목으로 표시하도록 개선했습니다.
- 홈 저장 영화 목록에서 항목을 목록에서 제거하는 버튼과 확인 팝업을 추가했습니다.
- 편집 화면 상단에 프리셋별 자동 컷, 자막/로고, 음악, 비율 상태 패널을 추가했습니다.
- 작업 초기화 전 확인 팝업을 추가했습니다.
- 편집 중 홈/뒤로 이동 전 자동 저장 안내 확인 팝업을 추가했습니다.
- 자동 타격점 다중 분할 완료 시 원본/생성 클립 수 상태 패널을 표시하도록 추가했습니다.
- 시사회 화면을 작은 화면에서도 끝까지 볼 수 있도록 세로 스크롤 구조로 보강했습니다.
- 시사회 갤러리/파일 저장 중 진행 다이얼로그를 표시하고 저장 작업을 백그라운드로 처리하도록 보강했습니다.
- 사진 시간 조절 시트에 닫기 버튼과 설명 문구를 추가해 다른 편집 시트와 톤을 맞췄습니다.
- 선택/공유한 배경음악을 실제 파일명으로 표시하도록 개선했습니다.
- 선택/공유한 배경음악을 앱 내부 작업 파일로 복사해 내보내기 때 권한이 끊기지 않도록 보강했습니다.
- 음악 설정 시트를 작은 화면에서도 끝까지 볼 수 있도록 스크롤 구조로 보강했습니다.
- 일부 미디어를 가져오지 못한 경우 선택/성공/실패 개수를 안내하도록 보강했습니다.
- 공유/파일 선택에서 MIME 타입이 비어 있을 때 확장자로 사진/영상을 판별하도록 보강했습니다.
- 지원하지 않는 파일 형식은 가져오기 실패 개수로 안내되도록 필터링했습니다.
- 작업용 미디어와 임시 내보내기 캐시가 과도하게 쌓이지 않도록 오래된 파일 정리 로직을 추가했습니다.
- 갤러리 저장 후 저장 영화 목록이 임시 캐시 URI 대신 실제 저장 URI를 우선 사용하도록 히스토리 교체 로직을 보강했습니다.
- Android 8 호환성을 위해 미디어 메타데이터/썸네일 추출 리소스 해제 방식을 보수했습니다.
- Android 8/9에서도 갤러리 저장이 가능하도록 저장 권한 요청과 `Movies/HanClip` 경로 지정을 보강했습니다.
- Android lint에서 잡힌 권한 검사, API 26 호환성, Media3 opt-in, muxer sample flag 문제를 정리했습니다.
- Android 14 선택 사진 접근 권한과 Samsung Gallery 패키지 조회 선언을 manifest에 보강했습니다.
- 누적 기능 보강 후 Android 버전을 `0.6.0`(`versionCode=6`)으로 올렸습니다.

## 테스트 기기

- 모델: `SM_F968N`
- 연결 방식: USB ADB
- 앱 패키지: `com.hanclip.android`
- 설치 APK: `/Users/armsone/git/HanClip/android/app/build/outputs/apk/debug/app-debug.apk`

## 실행 및 테스트 방법

```bash
/Users/armsone/Library/Android/sdk/platform-tools/adb devices -l
/Users/armsone/Library/Android/sdk/platform-tools/adb -s R3KYB061JTZ install -r /Users/armsone/git/HanClip/android/app/build/outputs/apk/debug/app-debug.apk
/Users/armsone/Library/Android/sdk/platform-tools/adb -s R3KYB061JTZ shell am start -n com.hanclip.android/.MainActivity
```

## 확인한 흐름

- 앱 설치 성공
- 앱 실행 성공
- 테스트 MP4를 폰의 `Movies` 폴더로 전송
- Samsung 기본 갤러리에서 11초 테스트 영상 선택 성공
- 앱 편집 화면으로 영상 가져오기 성공
- 사진 클립 시간 조절 시트 표시 성공
- 자동 분석 후 기본 클립 생성 성공
- `영화 만들기` 실행 성공
- 미리보기 화면에서 내보낸 MP4 재생 준비 성공
- 미리보기 화면 전체화면 버튼 표시 및 전체화면 다이얼로그 재생 화면 표시 성공
- `갤러리에 저장` 실행 성공
- Android 공유 시트 표시 성공
- Android 공유 받기 인텐트 필터 빌드 성공
- 자막 합성용 Media3 `OverlayEffect` 빌드 성공
- `HanClip` 로고 워터마크 UI 표시 및 Media3 `OverlayEffect` 빌드 성공
- 프리텐다드, 고운바탕, 고운돋움, 나눔고딕, 도현, 검은고딕, 마루부리 폰트 assets 포함 빌드 성공
- 골프 프리셋 자막 설정에서 자막과 `HanClip 로고` 기본 켜짐 상태 확인
- 홈 저장 영화 카드에서 실제 골프 MP4 프레임 썸네일 표시 확인
- 갤러리 저장 히스토리 교체 로직 빌드 성공
- `MediaMetadataRetriever.release()` 기반 Android 8 호환성 보수 빌드 성공
- Android 8/9 갤러리 저장 권한과 `Movies/HanClip` 경로 보강 빌드 성공
- `./gradlew :app:lintDebug` 성공
- `./gradlew :app:testDebugUnitTest` 성공(`NO-SOURCE`)
- Android 14 선택 사진 접근 및 Samsung Gallery 조회 manifest 보강 후 `lintDebug` 재성공
- 홈 저장 영화 섹션 버튼 문구 개선 후 `lintDebug` 성공
- 홈 저장 영화 썸네일 `content://` URI 대응 후 `lintDebug` 성공
- 진행 오버레이 추가 후 `./gradlew :app:lintDebug :app:assembleDebug` 성공
- 실제 폰 설치 버전 `0.5.0`, `lastUpdateTime=2026-08-06 04:14:34` 확인
- 자막 설정 시트에서 스타일 프리셋 표시와 골프 프리셋 `그린골프` 선택 상태 확인
- 자막 스타일 프리셋 추가 후 `./gradlew :app:lintDebug :app:assembleDebug` 성공, 실제 폰 설치 `lastUpdateTime=2026-08-06 04:16:15` 확인
- 파일 저장 히스토리 반영 후 `./gradlew :app:lintDebug :app:assembleDebug` 성공, 실제 폰 설치 `lastUpdateTime=2026-08-06 04:18:34` 확인
- AiShot 수동 저장 중 `클립 저장 중`, 남은 초, 진행바, `저장 중지` 버튼 표시 확인
- AiShot 저장 완료 후 `저장 완료 · 1개`, 자동 감지 설명, `편집으로` 버튼 표시 확인
- AiShot 저장 진행 표시 추가 후 `./gradlew :app:lintDebug :app:assembleDebug` 성공, 실제 폰 설치 `lastUpdateTime=2026-08-06 04:20:30` 확인
- 평상시 홈에서 공유 인박스 배너가 숨겨지는 것 확인
- 공유 인박스 배너 표시 조건 정리 후 `./gradlew :app:lintDebug :app:assembleDebug` 성공, 실제 폰 설치 `lastUpdateTime=2026-08-06 04:23:06` 확인
- 홈 저장 영화 목록에서 0클립 항목이 숨겨지고 정상 영화만 표시되는 것 확인
- 저장 영화 히스토리 0클립 정리 후 `./gradlew :app:lintDebug :app:assembleDebug` 성공, 실제 폰 설치 `lastUpdateTime=2026-08-06 04:24:49` 확인
- 저장 영화 프리셋 제목 반영 후 `./gradlew :app:lintDebug :app:assembleDebug` 성공, 실제 폰 설치 `lastUpdateTime=2026-08-06 04:26:38` 확인
- 홈 저장 영화 목록 제거 버튼 표시 확인, 실제 폰 설치 `lastUpdateTime=2026-08-06 04:28:26` 확인
- 홈 저장 영화 목록 제거 확인 팝업 표시 확인, 실제 폰 설치 `lastUpdateTime=2026-08-06 04:45:24` 확인
- 편집 종료 확인 팝업 추가 후 `./gradlew :app:lintDebug :app:assembleDebug` 성공, 실제 폰 설치 `lastUpdateTime=2026-08-06 04:47:52` 확인
- 시사회 화면 스크롤 구조 보강 후 `./gradlew :app:lintDebug :app:assembleDebug` 성공, 실제 폰 설치 `lastUpdateTime=2026-08-06 04:49:25` 확인
- 시사회 저장 중 진행 다이얼로그 추가 후 `./gradlew :app:lintDebug :app:assembleDebug` 성공, 실제 폰 설치 `lastUpdateTime=2026-08-06 04:50:54` 확인
- 작업 미디어/내보내기 캐시 정리 로직 추가 후 `./gradlew :app:lintDebug :app:assembleDebug` 성공, 실제 폰 설치 `lastUpdateTime=2026-08-06 04:52:26` 확인
- 저장 파일명 개선 후 `./gradlew :app:lintDebug :app:assembleDebug` 성공, 실제 폰 설치 `lastUpdateTime=2026-08-06 04:53:41` 확인
- 홈 저장 영화 전체 표시 후 `./gradlew :app:lintDebug :app:assembleDebug` 성공, 실제 폰 설치 `lastUpdateTime=2026-08-06 04:55:48` 확인
- MIME 타입 누락 미디어 확장자 판별 보강 후 `./gradlew :app:lintDebug :app:assembleDebug` 성공, 실제 폰 설치 `lastUpdateTime=2026-08-06 04:57:04` 확인
- 사진 시간 조절 시트 디자인 보강 후 `./gradlew :app:lintDebug :app:assembleDebug` 성공, 실제 폰 설치 `lastUpdateTime=2026-08-06 04:59:08` 확인
- 저장 영화 목록 접근 가능 항목 필터 추가 후 `./gradlew :app:lintDebug :app:assembleDebug` 성공, 실제 폰 설치 `lastUpdateTime=2026-08-06 05:00:36` 확인
- 배경음악 파일명 표시 개선 후 `./gradlew :app:lintDebug :app:assembleDebug` 성공, 실제 폰 설치 `lastUpdateTime=2026-08-06 05:02:37` 확인
- 배경음악 내부 복사 안정화 후 `./gradlew :app:lintDebug :app:assembleDebug` 성공, 실제 폰 설치 `lastUpdateTime=2026-08-06 05:03:57` 확인
- 지원하지 않는 미디어 형식 필터 추가 후 `./gradlew :app:lintDebug :app:assembleDebug` 성공, 실제 폰 설치 `lastUpdateTime=2026-08-06 05:05:45` 확인
- 음악 설정 시트 스크롤 보강 후 `./gradlew :app:lintDebug :app:assembleDebug` 성공, 실제 폰 설치 `lastUpdateTime=2026-08-06 05:07:12` 확인
- 공유파일 자동 처리 후 홈 대기 배너 카운트 정리, `./gradlew :app:lintDebug :app:assembleDebug` 성공, 실제 폰 설치 `lastUpdateTime=2026-08-06 05:11:01` 확인
- 기존 저장 영화 제목 구분 표시 보강 후 `./gradlew :app:lintDebug :app:assembleDebug` 성공, 실제 폰 설치 `lastUpdateTime=2026-08-06 05:13:40` 확인
- 빈 편집 화면에서 불필요한 `클립` 제목 숨김 처리 후 `./gradlew :app:lintDebug :app:assembleDebug` 성공, 실제 폰 설치 `lastUpdateTime=2026-08-06 05:16:41` 확인
- Samsung/기본 갤러리 `GET_CONTENT` 조회와 마이크 기능 선택 선언 보강 후 `./gradlew :app:lintDebug :app:assembleDebug` 성공, 실제 폰 설치 `lastUpdateTime=2026-08-06 05:18:12` 확인
- 실제 폰에서 `사진+영상 선택` 버튼이 Samsung 기본 갤러리(`com.sec.android.gallery3d`) 선택 화면으로 열리는 것 재확인
- 자막 설정에 그림자 색상과 그림자 진하기 슬라이더 추가 후 `./gradlew :app:lintDebug :app:assembleDebug` 성공, 실제 폰 설치 `lastUpdateTime=2026-08-06 05:22:34` 확인
- 자막 시트에서 그림자 설정을 색상 바로 아래로 재배치 후 `./gradlew :app:lintDebug :app:assembleDebug` 성공, 실제 폰 설치 `lastUpdateTime=2026-08-06 05:27:46` 확인
- Android 버전 `0.6.1`(`versionCode=7`)로 갱신 후 `./gradlew :app:lintDebug :app:assembleDebug` 성공, 실제 폰 설치 `lastUpdateTime=2026-08-06 05:29:14` 확인
- 바탕화면 APK `/Users/armsone/Desktop/HanClip-Android-완성본.apk`를 `0.6.1` 최신 빌드로 갱신
- AiShot 수동 중지 후 재녹화 타이머 안정화와 deprecated API 경고 정리 후 `./gradlew :app:lintDebug :app:assembleDebug` 성공, 실제 폰 설치 `lastUpdateTime=2026-08-06 05:31:14` 확인
- 편집 화면 `AI컷` 버튼이 가져오기 전 자동 분할 모드를 켜도록 보강 후 `./gradlew :app:lintDebug :app:assembleDebug` 성공, 실제 폰 설치 `lastUpdateTime=2026-08-06 05:32:58` 확인
- `영상만`/`AI컷` 선택을 다중 선택 가능한 `GET_CONTENT` 기반 Samsung Gallery 우선 호출로 변경 후 `./gradlew :app:lintDebug :app:assembleDebug` 성공, 실제 폰 설치 `lastUpdateTime=2026-08-06 05:34:17` 확인
- 실제 폰에서 `영상만` 버튼이 Samsung 기본 갤러리(`com.sec.android.gallery3d`) 선택 화면으로 열리는 것 재확인
- 공유 인텐트에 `ClipData` URI 권한 전달을 추가해 공유 대상 앱 호환성 보강 후 `./gradlew :app:lintDebug :app:assembleDebug` 성공, 실제 폰 설치 `lastUpdateTime=2026-08-06 05:37:26` 확인
- 자막 위치 그리드는 `T`, HanClip 로고 위치 그리드는 `H`로 표시하도록 구분 후 `./gradlew :app:lintDebug :app:assembleDebug` 성공, 실제 폰 설치 `lastUpdateTime=2026-08-06 05:39:11` 확인
- 갤러리 저장/파일 저장 원본 스트림 fallback을 공통화해 `content://`와 `file://` 저장 안정성 보강 후 `./gradlew :app:lintDebug :app:assembleDebug` 성공, 실제 폰 설치 `lastUpdateTime=2026-08-06 05:40:45` 확인
- 누적 변경 후 `./gradlew :app:testDebugUnitTest` 성공(`NO-SOURCE`)
- 바탕화면 APK, 테스트 APK 사본, debug APK가 모두 37MB 최신 빌드로 갱신된 것 확인
- 편집 화면 프리셋 상태 패널 추가 후 `./gradlew :app:lintDebug :app:assembleDebug` 성공, 실제 폰 설치 `lastUpdateTime=2026-08-06 04:32:40` 확인
- 작업 초기화 확인 팝업 추가 후 `./gradlew :app:lintDebug :app:assembleDebug` 성공, 실제 폰 설치 `lastUpdateTime=2026-08-06 04:35:43` 확인
- 자동 분할 완료 상태 패널 추가 후 `./gradlew :app:lintDebug :app:assembleDebug` 성공, 실제 폰 설치 `lastUpdateTime=2026-08-06 04:37:10` 확인
- 미디어 가져오기 성공/실패 개수 안내 보강 후 `./gradlew :app:lintDebug :app:assembleDebug` 성공, 실제 폰 설치 `lastUpdateTime=2026-08-06 04:38:16` 확인
- Android 버전 `0.6.0`(`versionCode=6`) 갱신 후 `./gradlew :app:lintDebug :app:assembleDebug` 성공, 실제 폰 설치 `lastUpdateTime=2026-08-06 04:39:28` 확인
- 공유 인박스 개수 표시 후 `./gradlew :app:lintDebug :app:assembleDebug` 성공, 실제 폰 설치 `lastUpdateTime=2026-08-06 04:41:06` 확인
- 갤러리 저장 문구 정리 후 `./gradlew :app:lintDebug :app:assembleDebug` 성공, 실제 폰 설치 `lastUpdateTime=2026-08-06 04:43:32` 확인
- 실제 폰 설치 버전 `0.6.1`, `lastUpdateTime=2026-08-06 05:40:45` 확인
- 자동 컷 원본/자식 클립 순서 변경 시 묶음 구조가 깨지지 않도록 보강
- 전체 영상 시간 패널에 0.5초 단위 +/- 조절과 5.0초/6.0초 프리셋 추가
- Android 버전 `0.6.2`(`versionCode=8`) 갱신 후 `./gradlew :app:lintDebug :app:assembleDebug` 성공
- 실제 폰 설치 버전 `0.6.2`, `lastUpdateTime=2026-08-06 05:48:13` 확인
- 바탕화면 APK `/Users/armsone/Desktop/HanClip-Android-완성본.apk`와 테스트 APK 사본을 `0.6.2` 최신 빌드로 갱신
- 설치 후 홈 화면 실행 및 UI 계층 정상 표시 확인
- iOS 최신 소스의 자동 분할/초기화 흐름을 참고해 Android에 원본 영상 `재분할` 기능 추가
- Android 버전 `0.6.3`(`versionCode=9`) 갱신 후 `./gradlew :app:lintDebug :app:assembleDebug` 성공
- 실제 폰 설치 버전 `0.6.3`, `lastUpdateTime=2026-08-06 05:50:59` 확인
- 바탕화면 APK `/Users/armsone/Desktop/HanClip-Android-완성본.apk`와 테스트 APK 사본을 `0.6.3` 최신 빌드로 갱신
- 갤러리 저장 실패 시 생성된 빈 MediaStore 항목을 정리하도록 저장 경로 안정화
- Android 버전 `0.6.4`(`versionCode=10`) 갱신 후 `./gradlew :app:lintDebug :app:assembleDebug :app:testDebugUnitTest` 성공
- 실제 폰 설치 버전 `0.6.4`, `lastUpdateTime=2026-08-06 05:53:49` 확인
- 바탕화면 APK `/Users/armsone/Desktop/HanClip-Android-완성본.apk`와 테스트 APK 사본을 `0.6.4` 최신 빌드로 갱신
- iOS 저장 목록 구조를 참고해 Android 홈 저장 영화 목록을 `AiShot`과 `일반 영화` 카테고리로 구분하고 개수를 표시하도록 보강
- Android 버전 `0.6.5`(`versionCode=11`) 갱신 후 `./gradlew :app:lintDebug :app:assembleDebug :app:testDebugUnitTest` 성공
- 실제 폰 설치 버전 `0.6.5`, `lastUpdateTime=2026-08-06 05:58:11` 확인
- 바탕화면 APK `/Users/armsone/Desktop/HanClip-Android-완성본.apk`와 테스트 APK 사본을 `0.6.5` 최신 빌드로 갱신
- 실제 폰 홈 화면에서 `일반 영화` 카테고리와 개수 `7` 표시 확인
- iOS 기본 편집값 저장 흐름을 참고해 Android에도 전체 클립 기본 길이와 출력 비율 선택을 SharedPreferences에 저장하도록 보강
- Android 버전 `0.6.6`(`versionCode=12`) 갱신 후 `./gradlew :app:lintDebug :app:assembleDebug :app:testDebugUnitTest` 성공
- 실제 폰 설치 버전 `0.6.6`, `lastUpdateTime=2026-08-06 06:02:41` 확인
- 바탕화면 APK `/Users/armsone/Desktop/HanClip-Android-완성본.apk`와 테스트 APK 사본을 `0.6.6` 최신 빌드로 갱신
- iOS 로고/저작권 색상 설정 흐름을 참고해 Android에 `HanClip` 로고 색상 설정/저장/내보내기 반영
- Android 버전 `0.6.7`(`versionCode=13`) 갱신 후 `./gradlew :app:lintDebug :app:assembleDebug :app:testDebugUnitTest` 성공
- 실제 폰 설치 버전 `0.6.7`, `lastUpdateTime=2026-08-06 06:06:50` 확인
- 바탕화면 APK `/Users/armsone/Desktop/HanClip-Android-완성본.apk`와 테스트 APK 사본을 `0.6.7` 최신 빌드로 갱신
- iOS 자막 줄간격 설정 흐름을 참고해 Android에 줄간격 선택/세부 조절/저장/내보내기 반영
- Android 버전 `0.6.8`(`versionCode=14`) 갱신 후 `./gradlew :app:lintDebug :app:assembleDebug :app:testDebugUnitTest` 성공
- 실제 폰 설치 버전 `0.6.8`, `lastUpdateTime=2026-08-06 06:12:02` 확인
- 바탕화면 APK `/Users/armsone/Desktop/HanClip-Android-완성본.apk`와 테스트 APK 사본을 `0.6.8` 최신 빌드로 갱신
- iOS 로고/저작권 그림자 설정 흐름을 참고해 Android에 `HanClip` 로고 그림자 색상/진하기 설정/저장/내보내기 반영
- Android 버전 `0.6.9`(`versionCode=15`) 갱신 후 `./gradlew :app:lintDebug :app:assembleDebug :app:testDebugUnitTest` 성공
- 실제 폰 설치 버전 `0.6.9`, `lastUpdateTime=2026-08-06 06:14:38` 확인
- 바탕화면 APK `/Users/armsone/Desktop/HanClip-Android-완성본.apk`와 테스트 APK 사본을 `0.6.9` 최신 빌드로 갱신
- iOS `AudioImpactClassifier` 흐름을 참고해 Android 자동 타격점 분석을 RMS, peak, crossing rate, baseline 상승, crest factor 기반 랭킹으로 보강
- Android 버전 `0.7.0`(`versionCode=16`) 갱신 후 `./gradlew :app:lintDebug :app:assembleDebug :app:testDebugUnitTest` 성공
- 실제 폰 설치 버전 `0.7.0`, `lastUpdateTime=2026-08-06 06:18:40` 확인
- 바탕화면 APK `/Users/armsone/Desktop/HanClip-Android-완성본.apk`와 테스트 APK 사본을 `0.7.0` 최신 빌드로 갱신
- iOS AiShot 실시간 감지 흐름을 참고해 Android AiShot 자동 녹화 트리거를 RMS, peak, crossing rate, baseline 상승, crest factor 기반 confidence 판정으로 보강
- Android 버전 `0.7.1`(`versionCode=17`) 갱신 후 `./gradlew :app:lintDebug :app:assembleDebug :app:testDebugUnitTest` 성공
- 실제 폰 설치 버전 `0.7.1`, `lastUpdateTime=2026-08-06 06:22:08` 확인
- 바탕화면 APK `/Users/armsone/Desktop/HanClip-Android-완성본.apk`와 테스트 APK 사본을 `0.7.1` 최신 빌드로 갱신
- iOS Ai 버전 표시 흐름을 참고해 Android AiShot 하단 패널에 `Ai 0.2.1 · 798 영상 보정 Ai` 안내 추가
- Android 버전 `0.7.2`(`versionCode=18`) 갱신 후 `./gradlew :app:lintDebug :app:assembleDebug :app:testDebugUnitTest` 성공
- 실제 폰 설치 버전 `0.7.2`, `lastUpdateTime=2026-08-06 06:24:26` 확인
- 바탕화면 APK `/Users/armsone/Desktop/HanClip-Android-완성본.apk`와 테스트 APK 사본을 `0.7.2` 최신 빌드로 갱신
- iOS AiShot 길이 프리셋을 참고해 Android의 `짧게`/`일반`/`길게` 선택을 앞/뒤 시간 기준 모델과 설명으로 보강
- Android 버전 `0.7.3`(`versionCode=19`) 갱신 후 `./gradlew :app:lintDebug :app:assembleDebug :app:testDebugUnitTest` 성공
- 실제 폰 설치 버전 `0.7.3`, `lastUpdateTime=2026-08-06 06:27:27` 확인
- 바탕화면 APK `/Users/armsone/Desktop/HanClip-Android-완성본.apk`와 테스트 APK 사본을 `0.7.3` 최신 빌드로 갱신
- AiShot 자동 감지 저장은 iOS 프리셋의 뒤 구간(`afterShot`)만큼 저장하고 수동 저장은 전체 프리셋 길이만큼 저장하도록 분리
- Android 버전 `0.7.4`(`versionCode=20`) 갱신 후 `./gradlew :app:lintDebug :app:assembleDebug :app:testDebugUnitTest` 성공
- 실제 폰 설치 버전 `0.7.4`, `lastUpdateTime=2026-08-06 06:30:33` 확인
- 바탕화면 APK `/Users/armsone/Desktop/HanClip-Android-완성본.apk`와 테스트 APK 사본을 `0.7.4` 최신 빌드로 갱신
- iOS `@AppStorage` 흐름을 참고해 Android AiShot 감도와 샷 길이 선택을 다음 실행에도 유지하도록 저장
- Android 버전 `0.7.5`(`versionCode=21`) 갱신 후 `./gradlew :app:lintDebug :app:assembleDebug :app:testDebugUnitTest` 성공
- 실제 폰 설치 버전 `0.7.5`, `lastUpdateTime=2026-08-06 06:33:23` 확인
- 바탕화면 APK `/Users/armsone/Desktop/HanClip-Android-완성본.apk`와 테스트 APK 사본을 `0.7.5` 최신 빌드로 갱신
- iOS AiShot 줌 컨트롤을 참고해 Android AiShot에 CameraX 줌 프리셋 `1x`/`2x`/`4x` 선택과 저장을 추가
- Android 버전 `0.7.6`(`versionCode=22`) 갱신 후 `./gradlew :app:lintDebug :app:assembleDebug :app:testDebugUnitTest` 성공
- 실제 폰 설치 버전 `0.7.6`, `lastUpdateTime=2026-08-06 06:36:26` 확인
- 바탕화면 APK `/Users/armsone/Desktop/HanClip-Android-완성본.apk`와 테스트 APK 사본을 `0.7.6` 최신 빌드로 갱신
- iOS 카메라 선택 저장 흐름을 참고해 Android AiShot 전면/후면 카메라 선택도 다음 실행에 유지되도록 저장
- Android 버전 `0.7.7`(`versionCode=23`) 갱신 후 `./gradlew :app:lintDebug :app:assembleDebug :app:testDebugUnitTest` 성공
- 실제 폰 설치 버전 `0.7.7`, `lastUpdateTime=2026-08-06 06:40:08` 확인
- 바탕화면 APK `/Users/armsone/Desktop/HanClip-Android-완성본.apk`와 테스트 APK 사본을 `0.7.7` 최신 빌드로 갱신
- iOS 워터마크 모델의 `copyrightIconColorMode`/`copyrightIconColorHex` 흐름을 참고해 Android HanClip 로고 색상 모드와 프로젝트 저장/내보내기 반영
- Android 버전 `0.7.8`(`versionCode=24`) 갱신 후 `./gradlew :app:lintDebug :app:assembleDebug :app:testDebugUnitTest` 성공
- 실제 폰 설치 버전 `0.7.8`, `lastUpdateTime=2026-08-06 06:43:52` 확인
- 바탕화면 APK `/Users/armsone/Desktop/HanClip-Android-완성본.apk`와 테스트 APK 사본을 `0.7.8` 최신 빌드로 갱신
- iOS `SELECT THEME` 팝업과 `hanClipThemeMode` 흐름을 참고해 Android 홈 테마 선택/팔레트 미리보기/선택값 저장 추가
- Android 버전 `0.7.9`(`versionCode=25`) 갱신 후 `./gradlew :app:lintDebug :app:assembleDebug :app:testDebugUnitTest` 성공
- 실제 폰 설치 버전 `0.7.9`, `lastUpdateTime=2026-08-06 06:48:17` 확인
- 바탕화면 APK `/Users/armsone/Desktop/HanClip-Android-완성본.apk`와 테스트 APK 사본을 `0.7.9` 최신 빌드로 갱신
- 홈 전용 테마 모델을 공용 `HanClipThemeMode`/`HanClipThemeStore`로 분리하고 편집 화면 주요 영역까지 선택 테마 반영
- Android 버전 `0.8.0`(`versionCode=26`) 갱신 후 `./gradlew :app:lintDebug :app:assembleDebug :app:testDebugUnitTest` 성공
- 실제 폰 설치 버전 `0.8.0`, `lastUpdateTime=2026-08-06 06:52:34` 확인
- 바탕화면 APK `/Users/armsone/Desktop/HanClip-Android-완성본.apk`와 테스트 APK 사본을 `0.8.0` 최신 빌드로 갱신
- 편집 하단 시트 중 자막/음악/사진 시간/영상 구간 선택의 표면, 헤더, 주요 실행 버튼, 타격점 패널에 선택 테마 반영
- Android 버전 `0.8.1`(`versionCode=27`) 갱신 후 `./gradlew :app:lintDebug :app:assembleDebug :app:testDebugUnitTest` 성공
- 실제 폰 설치 버전 `0.8.1`, `lastUpdateTime=2026-08-06 06:56:11` 확인
- 바탕화면 APK `/Users/armsone/Desktop/HanClip-Android-완성본.apk`와 테스트 APK 사본을 `0.8.1` 최신 빌드로 갱신
- 시사회 화면 배경, 개봉 준비 카드, 다시 편집/공유/개봉/홈 버튼, 개봉 옵션 시트, 저장 중 다이얼로그에 선택 테마 반영
- Android 버전 `0.8.2`(`versionCode=28`) 갱신 후 `./gradlew :app:lintDebug :app:assembleDebug :app:testDebugUnitTest` 성공
- 실제 폰 설치 버전 `0.8.2`, `lastUpdateTime=2026-08-06 06:59:12` 확인
- 바탕화면 APK `/Users/armsone/Desktop/HanClip-Android-완성본.apk`와 테스트 APK 사본을 `0.8.2` 최신 빌드로 갱신
- 편집 알림/초기화/나가기 확인 팝업, 진행 오버레이, 자막/음악/순서/비율 칩, 전체 영상 시간 패널, 하단 영화 만들기 바에 선택 테마 반영
- Android 버전 `0.8.3`(`versionCode=29`) 갱신 후 `./gradlew :app:lintDebug :app:assembleDebug :app:testDebugUnitTest` 성공
- 실제 폰 설치 버전 `0.8.3`, `lastUpdateTime=2026-08-06 07:04:06` 확인
- 바탕화면 APK `/Users/armsone/Desktop/HanClip-Android-완성본.apk`와 테스트 APK 사본을 `0.8.3` 최신 빌드로 갱신
- 실제 폰 홈 화면 실행 및 `일반 영화` 카테고리 표시 유지 확인
- 배경 음악용 Media3 병렬 오디오 시퀀스 빌드 성공
- 골프 테스트 영상 11.2초에서 자동 클립 3개 생성 성공
- 자동 클립 3개 + 자막 + `골프치러 가자` 배경음악으로 내보내기 성공
- 시사회 `개봉하기` 팝업 표시 성공
- `갤러리로 개봉`으로 `/sdcard/Movies/HanClip` 저장 성공
- AiShot 권한 허용, 수동 4초 녹화, `저장 완료 · 1개` 표시, `편집으로` 버튼을 통한 AiShot 편집 화면 미디어 1개 전달 성공
- CCMB 기준 Codex 주간 사용량 20% 사용 확인

## 결과 파일

실제 폰 저장 경로:

```text
/sdcard/Movies/HanClip/HanClip-1785945867444.mp4
/sdcard/Movies/HanClip/HanClip-1785954099302.mp4
```

검증 스크린샷:

```text
/private/tmp/hanclip-real-export.png
/private/tmp/hanclip-real-share.png
/private/tmp/hanclip-gallery-forced.png
/private/tmp/hanclip-photo-sheet.xml
/Users/armsone/git/HanClip/android/hanclip-preview-fullscreen-dialog.png
/Users/armsone/git/HanClip/android/hanclip-aishot-after-manual.png
/Users/armsone/git/HanClip/android/hanclip-aishot-editor.png
```

## 남아 있는 문제

- 현재는 디버그 APK입니다. Play Store 또는 외부 배포용 릴리스 APK/AAB를 만들려면 서명 키와 앱 아이콘/버전 정책 정리가 필요합니다.
- 여러 실제 사용자 영상을 이어 붙이는 Transformer 경로는 추가 기기/샘플에서 더 테스트하면 좋습니다.
- 배경 음악 믹싱과 자막 합성은 빌드 경로까지 구현했으며, 사용자의 실제 긴 영상/음악 조합으로 추가 품질 확인이 필요합니다.
- AiShot 자동 감지 민감도는 실제 골프장 타격음/주변 소음으로 추가 보정이 필요합니다.

## 다음 단계 작업

- 실제 사용자 영상 3개 이상으로 연결 내보내기 테스트
- AiShot 자동 감지 샘플 추가 수집 및 민감도 보정
- 릴리스 서명 설정과 배포용 APK/AAB 생성
