# HanClip Android Current Build Summary

## 현재 설치 파일

- 바탕화면 APK: `/Users/armsone/Desktop/HanClip-Android-완성본.apk`
- 테스트 APK 사본: `/Users/armsone/git/HanClip/android/HanClip-android-debug-tested.apk`
- 빌드 APK: `/Users/armsone/git/HanClip/android/app/build/outputs/apk/debug/app-debug.apk`

## 현재 설치 버전

- 패키지: `com.hanclip.android`
- 버전: `0.9.0`
- versionCode: `36`
- 최소 지원: Android 8.0, API 26
- 실제 폰 설치 시각: `2026-08-06 07:29:11`

## 핵심 반영 사항

- 앱 이름과 화면 표기는 `HanClip`로 유지
- iOS 테마 선택 흐름을 참고한 홈 테마 선택 팝업, 팔레트 미리보기, 선택값 저장
- 선택한 테마를 홈과 편집 화면 주요 영역에 공통 적용
- 선택한 테마를 자막/음악/사진 시간/영상 구간 선택 하단 시트 주요 영역에 적용
- 선택한 테마를 시사회 화면, 개봉 옵션 시트, 저장 중 다이얼로그에 적용
- 선택한 테마를 편집 확인 팝업, 진행 오버레이, 전체 영상 시간 패널, 하단 만들기 바에 적용
- 선택한 테마를 클립 카드, 썸네일 대체 화면, 개별 클립 조작 버튼에 적용
- iOS 최신 화면 꺼짐 방지 설정을 참고해 Android도 `항상켜짐`/`끔`/`오토` 선택 저장 및 실제 화면 유지 플래그 연결
- iOS `중요 안내` 흐름을 참고해 홈 화면 `i` 버튼, 기능 안내 팝업, 화면 꺼짐 방지 빠른 설정 추가
- iOS 미디어 추가 메뉴의 `파일` 흐름을 참고해 Android 편집 화면에 사진/영상 파일 직접 선택 추가
- iOS 저장 영화 목록의 핀 고정 흐름을 참고해 Android 저장 영화 핀 고정/해제와 상단 정렬 추가
- iOS 저장 영화 목록의 메모 흐름을 참고해 Android 저장 영화 메모 추가/편집/표시와 새 저장 시 핀/메모 보존 추가
- iOS 홈 목록의 작은 조작 아이콘 밀도를 참고해 Android 저장 영화 행 썸네일/메모/핀/삭제 버튼 크기와 간격 조정
- Samsung 기본 갤러리 우선으로 사진+영상, 영상만, AI컷 선택
- 사진과 영상 다중 선택 후 클립 생성
- 골프 프리셋 자동 컷 모드와 기본 자막/로고/배경음악
- 자동 타격점 후보 기반 영상 분할
- iOS `AudioImpactClassifier`를 참고한 peak/crossing/baseline 상승 기반 자동 타격점 랭킹
- 전체 클립 시간 0.5초 단위 조절, 1.5~6.0초 프리셋, 개별 사진/영상 시간 조절
- 기본 클립 길이와 출력 비율 선택을 다음 새 작업에도 유지
- 자동 컷 묶음 구조를 유지하는 클립 순서 변경, 기본 길이 변경 후 재분할, 삭제, 프로젝트 초기화 확인
- 자막 텍스트, 폰트, 글자 색상, 그림자 색상/진하기, 줄간격, 위치 설정
- HanClip 로고 위치, 색상, 그림자 색상/진하기 설정
- HanClip 로고 색상 모드 기본/회색/지정색 선택, 프로젝트 저장, 내보내기 반영
- 여러 클립 연결, MP4 내보내기, 갤러리 저장, 파일 저장, 공유
- 갤러리 저장 실패 시 빈 저장 항목 정리
- AiShot 카메라, 자동 감지, 수동 저장, 녹화 중 진행 표시
- AiShot 길이 프리셋을 iOS와 같은 앞/뒤 시간 기준 설명으로 표시
- AiShot 자동 감지 저장 시간을 iOS의 뒤 구간 기준으로 분리하고 수동 저장은 전체 프리셋 길이 유지
- AiShot 감도와 샷 길이 선택을 SharedPreferences에 저장해 다음 실행에도 유지
- AiShot 촬영 화면에 CameraX 줌 프리셋 `1x`/`2x`/`4x` 선택과 저장 반영
- AiShot 전면/후면 카메라 선택을 SharedPreferences에 저장해 다음 실행에도 유지
- AiShot 실시간 타격음 감지에 iOS식 peak/crossing/baseline 상승 confidence 판정 반영
- AiShot 화면에 현재 Ai 버전 `0.2.1`과 `798 영상 보정 Ai` 설명 표시
- 공유 받은 사진/영상/음악 처리
- 홈 저장 영화 목록, 썸네일, 제거 확인 팝업
- 홈 저장 영화 목록의 `AiShot`/`일반 영화` 카테고리와 개수 표시

## 마지막 검증

- `./gradlew :app:lintDebug :app:assembleDebug` 성공
- `./gradlew :app:testDebugUnitTest` 성공, 현재 테스트 소스 없음(`NO-SOURCE`)
- 실제 폰 `SM_F968N` 설치 성공
- 설치된 버전 `0.9.0`, `versionCode=36`, `lastUpdateTime=2026-08-06 07:29:11` 확인
- `사진+영상 선택` 버튼이 Samsung 기본 갤러리로 열림 확인
- `영상만` 버튼이 Samsung 기본 갤러리로 열림 확인
- 설치 후 홈 화면 실행 및 UI 계층 정상 표시 확인
- iOS 최신 소스를 읽어 자동 컷 재분할 흐름 차이 반영
- iOS 저장 목록 구분을 참고해 Android 홈에서 `일반 영화` 카테고리와 개수 표시 확인
- iOS 기본 편집값 저장 흐름을 참고해 Android에 기본 길이/출력 비율 저장 추가
- iOS 로고/저작권 색상 설정 흐름을 참고해 Android에 HanClip 로고 색상 설정, 저장, 미리보기, 내보내기 반영
- iOS 자막 줄간격 설정 흐름을 참고해 Android에 줄간격 선택, 세부 조절, 저장, 내보내기 반영
- iOS 로고/저작권 그림자 설정 흐름을 참고해 Android에 HanClip 로고 그림자 색상/진하기 설정, 저장, 미리보기, 내보내기 반영
- iOS `AudioImpactClassifier` 흐름을 참고해 Android 자동 타격점 후보 랭킹을 RMS, peak, crossing rate, baseline 상승, crest factor 기반으로 보강
- iOS AiShot 실시간 감지 흐름을 참고해 Android AiShot 자동 녹화 트리거를 confidence 판정 기반으로 보강
- iOS Ai 버전 표시 흐름을 참고해 Android AiShot 하단 패널에 현재 Ai 모델 안내 표시
- iOS AiShot 길이 프리셋을 참고해 Android AiShot 길이 선택을 앞/뒤 시간 기준 모델과 설명으로 보강
- Android CameraX 현재 구조에서 자동 감지 저장 시간을 iOS의 뒤 구간 기준으로 맞추고, 수동 저장은 전체 프리셋 길이 유지
- iOS `@AppStorage` 흐름을 참고해 AiShot 감도와 샷 길이 선택을 다음 실행에도 유지
- iOS AiShot 줌 컨트롤을 참고해 Android AiShot에 CameraX 줌 프리셋과 선택 저장 반영
- iOS 카메라 선택 저장 흐름을 참고해 Android AiShot 전면/후면 카메라 선택 저장 반영
- iOS 워터마크 모델의 `copyrightIconColorMode`/`copyrightIconColorHex` 흐름을 참고해 Android HanClip 로고 색상 모드 저장과 내보내기 반영
- iOS `SELECT THEME` 팝업과 `hanClipThemeMode` 흐름을 참고해 Android 홈 테마 선택/저장 반영
- Android 테마 모델을 공용화하고 편집 화면 배경/헤더/상태/가져오기 버튼까지 선택 테마 반영
- 편집 하단 시트 중 자막/음악/사진 시간/영상 구간 선택의 표면, 헤더, 주요 버튼, 타격점 패널까지 선택 테마 반영
- 시사회 화면, 개봉 옵션 시트, 저장 중 다이얼로그까지 선택 테마 반영
- 편집 알림/초기화/나가기 확인 팝업, 진행 오버레이, 자막/음악/순서/비율 칩, 전체 영상 시간 패널, 하단 영화 만들기 바까지 선택 테마 반영
- 클립 카드, 썸네일 대체 화면, 개별 클립 조작 버튼까지 선택 테마 반영
- iOS `SleepPreventionMode` 흐름을 참고해 Android 편집 화면의 화면 꺼짐 방지 선택과 Activity 화면 유지 플래그를 연결
- iOS `ImportantInfoSheet` 흐름을 참고해 Android 홈에 `중요 안내` 팝업과 주요 기능 설명, 화면 꺼짐 방지 빠른 설정 반영
- iOS 미디어 추가 메뉴의 `파일` 항목을 참고해 Android 편집 화면에 Android 파일 앱 기반 사진/영상 선택 버튼 반영
- iOS 저장 영화 목록의 핀 버튼을 참고해 Android 저장 영화 히스토리에 `isPinned` 저장, 핀 우선 정렬, 홈 행 핀 버튼 반영
- iOS 저장 영화 목록의 메모 편집을 참고해 Android 저장 영화 히스토리에 `memo` 저장, 메모 편집 팝업, 홈 행 메모 표시 반영
- Android 홈 저장 영화 행의 제목 영역이 좁아지지 않도록 썸네일과 메모/핀/삭제 아이콘 버튼을 컴팩트 크기로 조정
- 폰 화면 켜짐 유지: `stay_on_while_plugged_in=3`
- 폰 배터리: USB 연결, 100%

## 남은 리스크

- 현재 APK는 디버그 APK입니다. Play Store 또는 외부 배포용 릴리스 APK/AAB는 서명 키가 필요합니다.
- AiShot 자동 감지 민감도는 실제 골프장 소리 샘플로 추가 보정하면 더 좋아집니다.
- 긴 영상 여러 개와 긴 음악 조합은 실제 사용자 샘플로 추가 성능 테스트가 필요합니다.
