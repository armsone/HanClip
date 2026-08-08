# HanClip Android

HanClip iOS 앱을 Android로 이식하기 위한 별도 Android Studio 프로젝트입니다.

## 현재 단계

11단계 기본 검증 완료: 실제 Android 폰 설치와 핵심 흐름 테스트

현재 Android 버전: `1.0.1` (`versionCode=380`)

- Kotlin
- Jetpack Compose
- MVVM 기본 구조
- Media3 ExoPlayer/Transformer 의존성 선언
- CameraX 기반 AiShot 카메라 화면
- iOS 앱 아이콘 기반 Android 런처 아이콘/adaptive icon 적용
- Android 8.0(API 26) 이상 지원
- iOS 프로젝트 파일은 수정하지 않고 `android/` 폴더 안에서 작업
- iOS 앱도 계속 변경되므로 Android 작업 중 하루에 한 번 최신 iOS 소스를 읽어 플랫폼 차이점 확인
- Android 개발 중에는 소스 수정 열 번마다 한 번 커밋하고 푸시
- Mac과 휴대폰이 `zangzip` 네트워크에 연결되어 있으면 무선 디버깅을 우선 사용하고, 연결할 수 없을 때만 USB 사용
- iOS 테마 선택 흐름을 참고한 홈 테마 선택 팝업과 선택값 저장
- iOS 최신 `Pixel Pop` 테마 팔레트를 Android 테마 선택지 색상과 동기화
- Android 홈과 테마 선택 팝업에서 `HanClip` 외 주요 영어 표시(`Automatic Mode`, `SELECT THEME`, `COLOR SYSTEM`)를 한글 중심 문구로 정리
- 테마 선택 팝업에서 미선택 테마명이 밝은 배경에서도 흐려지지 않도록 글자색 기준 보정
- iOS `비슷한 사진 묶음` 흐름을 참고해 Android도 연속 사진 유사도 분석, 대표 컷 기본 사용, 묶음 펼치기, 추가 사진 사용, 내보내기 대상 필터링 지원
- 선택한 테마를 홈과 편집 화면 주요 영역에 공통 적용
- 선택한 테마를 자막, 음악, 사진 시간, 영상 구간 선택 하단 시트 주요 영역에 적용
- 선택한 테마를 시사회 화면, 개봉 옵션 시트, 저장 중 다이얼로그에 적용
- 선택한 테마를 편집 확인 팝업, 진행 오버레이, 전체 영상 시간 패널, 하단 만들기 바에 적용
- 선택한 테마를 클립 카드, 썸네일 대체 화면, 개별 클립 조작 버튼에 적용
- iOS 최신 화면 꺼짐 방지 설정을 참고해 Android도 `항상켜짐`/`끔`/`오토` 선택 저장 및 실제 화면 유지 플래그 연결
- iOS `중요 안내` 흐름을 참고해 홈 화면 `i` 버튼, 기능 안내 팝업, 화면 꺼짐 방지 빠른 설정 추가
- iOS 최신 설정/카피라이터 흐름을 참고해 홈 상단을 설정 아이콘과 `설정` 팝업 흐름으로 정리
- iOS 최신 전체 화면 설정 흐름을 참고해 Android 자막/음악 설정을 하단 시트에서 전체 화면 설정으로 전환
- iOS 최신 개봉 위치 화면 흐름을 참고해 Android `개봉하기` 저장 위치 선택도 전체 화면으로 전환
- iOS 영상 생성 진행창 흐름을 참고해 Android 영화 만들기 진행 오버레이에 `제작 취소` 추가
- iOS 원본/클립 미리보기 흐름을 참고해 Android 클립 카드에 원본/선택 구간 전체 화면 미리보기 추가
- 사진 클립 시간 조절 화면에 실제 사진 미리보기 영역을 추가해 선택한 사진을 보면서 길이 조절 가능
- iOS 순서변경 상태를 참고해 Android 순서 모드에 가로 썸네일 조작 바, 완료 버튼, 빠른 이동/삭제 액션 추가
- 순서 변경 중에는 하단 `영화 만들기` 바를 숨겨 썸네일 이동/삭제 버튼이 겹치지 않도록 조정
- iOS 미디어 추가 메뉴의 `파일` 흐름을 참고해 Android 편집 화면에 사진/영상 파일 직접 선택 추가
- iOS 저장 영화 목록의 핀 고정 흐름을 참고해 Android 저장 영화 핀 고정/해제와 상단 정렬 추가
- iOS 저장 프로젝트의 핀 최대 5개 제한을 참고해 Android 저장 영화도 6번째 핀 고정 시 안내 팝업 표시
- iOS 저장 프로젝트 보관 정책을 참고해 Android 저장 영화 목록도 전체 10개, AiShot 2개 중심으로 유지
- iOS 영화 목록의 빈 프로젝트 슬롯을 참고해 Android 홈 일반 영화 목록에도 남은 저장 공간 자리 표시자 표시
- 홈 저장 영화 목록을 스크롤할 때 제목/카드가 Android 상태바와 겹치지 않도록 안전 영역 여백 보정
- iOS 영화 목록 행 정보 구성을 참고해 Android 일반 영화 행도 저장 시각, 클립 수, 길이, 파일 크기 중심으로 표시
- Android 작은 화면에서 파일 크기가 잘리지 않도록 일반 영화 행 세부 정보를 `개수 · 파일 크기`로 압축
- iOS 영화 목록의 최근 저장 표시를 참고해 Android 저장 영화/AiShot 카드에도 이번 실행에서 새로 만든 항목 `NEW` 배지 표시
- iOS 영화 목록의 클립 썸네일 스트립을 참고해 Android 일반 영화 행에도 저장된 MP4의 여러 프레임 미니 썸네일 표시
- iOS AiShot 카드의 보조 썸네일 흐름을 참고해 Android AiShot 카드에도 여러 클립일 때 미니 프레임 스트립 표시
- 홈 저장 영화 대표 썸네일과 미니 프레임 스트립에 메모리 캐시를 적용해 스크롤/재구성 시 같은 MP4 프레임 반복 디코딩 감소
- iOS 시간 표시 흐름을 참고해 Android 편집 요약 패널의 전체 길이를 1분 이상일 때 `n분 n초` 형태로 표시
- 편집 화면 빠른 가져오기 버튼을 2열 보조 버튼 배치로 조정해 `영상만`, `달력`, `파일`, `Ai컷` 글자 잘림 제거
- 편집 화면에서 아직 클립이 없을 때 하단 `영화 만들기` 바를 숨겨 사진/영상 선택 영역이 가려지지 않도록 보정
- 편집 요약 패널의 `클립/전체/기본/분할` 지표를 균등 폭으로 보정해 긴 전체 시간 표시가 다른 지표를 밀지 않도록 안정화
- iOS의 `Ai` 표기 톤에 맞춰 Android 편집 화면의 `AI컷` 버튼을 `Ai컷`으로 정리
- iOS 시사회 화면 흐름을 참고해 Android 시사회도 정사각형 큰 미리보기와 `다시 편집`/공유/`개봉하기` 한 줄 액션으로 정리
- iOS `AiShotIcon` PNG를 Android 리소스로 가져와 홈 AiShot 카드와 저장 영화 헤더 아이콘에 적용
- Android 9 이상 사진 가져오기에서 HEIC/최신 이미지 크기를 `ImageDecoder`로 읽어 원본 비율이 1:1로 잘못 잡히는 경우를 줄임
- 홈 AiShot 저장 목록 헤더의 iOS PNG 아이콘이 잘 보이도록 밝은 칩 배경과 얇은 테두리로 대비 보정
- 홈 설정/기능 안내 팝업에서 남아 있던 영어 항목 `Special Thanks`와 `Android 공유` 표현을 한글 중심 문구로 정리
- 시사회 개봉 옵션의 갤러리 저장 설명도 `기본 갤러리의 HanClip 폴더`로 한글 중심 문구로 정리
- 영화 만들기 실패 시 시스템 영어 오류 대신 사용자가 바로 이해할 수 있는 한글 재시도 안내를 표시
- 달력 미디어 선택에서 촬영일(`DATE_TAKEN`)이 없는 스크린샷/저장 영상도 추가일·수정일 기준으로 월별 목록에 보이도록 보강
- 실제 연결 폰에서 2026년 8월 달력의 8월 6일 미디어 28개와 썸네일 표시 확인
- 달력 날짜별 썸네일 표시와 가져오기 순서를 URI 문자열이 아니라 실제 촬영/저장 시각 최신순으로 안정화
- 실기기 화면 이동 후 최근 로그에서 HanClip `FATAL EXCEPTION` 없이 정상 확인
- 브라우저 화면의 상단 설명 문구를 작은 화면에서 잘리지 않도록 `무료 음악 찾기`로 압축
- iOS 저장 영화 목록의 메모 흐름을 참고해 Android 저장 영화 메모 추가/편집/표시와 새 저장 시 핀/메모 보존 추가
- iOS 저장 프로젝트 요약의 파일 크기 흐름을 참고해 Android 저장 영화 히스토리에도 내보낸 MP4 크기를 저장하고 홈 목록 세부 정보에 표시
- 기존 Android 저장 영화 항목도 홈 목록을 읽을 때 접근 가능한 URI에서 파일 크기를 자동 보강해 새 저장 전에도 크기 표시 가능
- 홈 저장 영화 세부 문구를 `클립 수 · 길이 · 파일 크기` 중심으로 압축해 작은 화면에서도 파일 크기가 보이도록 조정
- 홈 저장 영화 행에서 파일 크기가 있는 항목은 `클립 수 · 파일 크기`로 더 압축해 작은 화면에서도 크기가 잘리지 않도록 보정
- iOS 홈 목록의 작은 조작 아이콘 밀도를 참고해 Android 저장 영화 행 썸네일/메모/핀/삭제 버튼 크기와 간격 조정
- 홈 저장 영화 행과 AiShot 카드의 메모/핀/삭제 아이콘에 작은 배경 버튼을 적용해 실제 조작 버튼처럼 보이도록 정리
- iOS 외부 호출 주소 흐름을 참고해 Android도 `hanclip://open`, `hanclip://aishot`, `hanclip://photo`, `hanclip://calendar`, `hanclip://files`, `hanclip://search` 빠른 진입 연결
- iOS 달력 미디어 선택 흐름을 참고해 Android 편집 화면에 월별 달력, 날짜별 사진/영상 개수, 썸네일 다중 선택, `hanclip://calendar` 빠른 진입 추가
- iOS 온라인 음악 브라우저 흐름을 참고해 Android 앱 안 WebView 브라우저, Pixabay/Mixkit 바로가기, 주소/검색 이동, 음악 설정 `브라우저` 버튼 추가
- iOS 음악 설정 흐름을 참고해 Android 음악/원본 소리 볼륨 슬라이더, 초안 저장, Media3 Transformer 내보내기 gain 반영 추가
- iOS 음악 미리듣기 흐름을 참고해 Android 선택 음악/샘플 음악 재생·정지 버튼과 Media3 ExoPlayer 미리듣기 추가
- iOS 브라우저 즐겨찾기 패널을 참고해 Android 브라우저에 즐겨찾기 목록, 현재 주소 추가/해제, 삭제, 첫 페이지 지정과 저장 추가
- iOS `.hanclipfavorites` 포맷과 맞춰 Android 브라우저 즐겨찾기 공유/가져오기 지원
- Android 파일 앱에서 `.hanclipfavorites`를 직접 열어 브라우저 즐겨찾기로 가져오기 지원
- `.hanclipfavorites` 직접 열기에서 읽기 성공 시 병합하고, 직접 파일 경로 읽기 실패 시 안내 후 브라우저로 진입하도록 보강
- 홈, 편집, 미리보기 화면 흐름 구현
- 홈 저장 영화 카드에 실제 MP4 첫 프레임 썸네일 표시
- 홈 저장 영화 썸네일이 `file://`와 갤러리 `content://` URI 모두 처리
- 홈 저장 영화 목록에서 최근 저장 항목을 모두 스크롤로 표시
- 홈 저장 영화 목록을 iOS처럼 `AiShot`과 `일반 영화` 카테고리로 구분하고 개수 표시
- iOS 홈의 AiShot 프로젝트 영역을 참고해 Android 홈도 AiShot 저장 영화를 2열 카드형 그리드와 빈 슬롯으로 표시
- 홈 저장 영화 목록에서 실제 접근 가능한 영상만 표시
- 새로 저장되는 영화 히스토리에 프리셋 제목 저장 및 홈 카드 제목 표시
- 홈 저장 영화 섹션의 작업 버튼 문구를 실제 동작에 맞게 표시
- 미디어 가져오기/영화 만들기 중 전체 화면 진행 오버레이 표시
- 편집 화면 상단에 프리셋별 자동 컷, 자막/로고, 음악, 비율 상태 패널 표시
- 자동 타격점 다중 분할 완료 시 원본/생성 클립 수 상태 패널 표시
- 갤러리 저장 후 캐시 히스토리를 실제 저장 URI로 교체
- 갤러리 저장 실패 시 생성된 빈 MediaStore 항목 정리
- 저장 영화 히스토리에서 0클립/0초 항목 제외
- 홈 저장 영화 목록에서 항목을 목록에서 제거하는 버튼과 확인 팝업 추가
- 프리셋별 편집 화면 진입 구현
- 샘플 클립 기반 편집 UI 구현
- Samsung 기본 갤러리가 있는 기기에서는 기본 갤러리로 사진/영상 선택
- `사진+영상 선택`, `영상만`, `Ai컷` 모두 Samsung 기본 갤러리 우선 호출
- 실제 연결 폰에서 `사진+영상 선택` 버튼이 Google Photos가 아니라 Samsung 기본 갤러리 `항목 선택` 화면으로 열리는 것 확인
- `Ai컷` 버튼은 가져오기 전 자동 분할 모드를 켜도록 연결
- Android 11+ 패키지 조회 제한 대응을 위한 Samsung Gallery `queries` 선언
- Android 14 선택 사진 접근 권한 선언
- Samsung 기본 갤러리가 없는 기기에서는 Android 기본 선택 방식으로 사진/영상 선택
- 선택 미디어의 Uri, MIME 타입, 길이, 원본 크기 읽기
- 여러 사진/영상을 가져올 때 `미디어 n/N개를 불러오는 중...` 항목별 진행 문구 표시
- 공유/파일 선택에서 MIME 타입이 비어 있을 때 확장자로 사진/영상 판별
- 지원하지 않는 파일 형식은 가져오기 실패 개수로 안내되도록 필터링
- 일부 미디어를 가져오지 못한 경우 선택/성공/실패 개수 안내
- 작업용 미디어 파일이 과도하게 쌓이지 않도록 내부 캐시 정리
- Android 8 호환성을 고려한 안전한 미디어 메타데이터/썸네일 리소스 해제
- 실제 사진/영상 썸네일 표시
- 영상 클립 탭 시 구간 선택 시트 표시
- Media3 ExoPlayer 기반 실제 영상 재생 자리 구현
- 시작/길이 슬라이더로 `trimStartSeconds`, `durationSeconds` 업데이트
- MediaExtractor/MediaCodec 기반 오디오 RMS 자동 타격점 탐지
- iOS `AudioImpactClassifier` 흐름을 반영한 RMS, peak, crossing rate, baseline 상승, crest factor 기반 자동 타격점 랭킹
- 전체 클립 길이 일괄 적용 및 영상 원본 전체 선택
- 전체 클립 길이를 0.5초 단위로 빠르게 조절하고 1.5~6.0초 프리셋 선택
- iOS처럼 전체 클립 기본 길이와 출력 비율 선택을 다음 새 작업에도 기억
- 개별 클립 길이 +/- 0.5초 조절
- 클립 위/아래 순서 변경
- 자동 컷 원본/자식 클립 순서 변경 시 묶음 구조 유지
- 기본 길이 변경 후 원본 영상 자동 컷 재분할
- 작업 초기화 전 확인 팝업 표시
- 편집 중 홈/뒤로 이동 전 자동 저장 안내 확인 팝업 표시
- 자막 텍스트, 글꼴 크기, 글꼴 계열, 색상, 위치 설정 UI
- 자막 줄간격 `좁게`/`보통`/`넓게`와 세부 +/- 조절 UI
- iOS 번들 한글 폰트 8종을 Android assets에 포함
- 자막 텍스트를 Media3 `OverlayEffect`로 최종 영상에 합성
- 자막 줄간격을 Media3 `OverlayEffect` 텍스트 렌더링에 반영
- `HanClip` 로고 워터마크 스위치, 위치 설정, 최종 영상 합성
- `HanClip` 로고 색상 설정, 프로젝트 저장, 미리보기, 최종 영상 합성
- iOS 워터마크 모델처럼 `HanClip` 로고 색상 모드를 기본/회색/지정색으로 선택
- `HanClip` 로고 그림자 색상/진하기 설정, 프로젝트 저장, 미리보기, 최종 영상 합성
- 골프/여행 프리셋에서 iOS와 유사한 기본 자막 색상, 그림자, 폰트, HanClip 로고 자동 적용
- 자막 설정에 `가독성`, `여행`, `시네마`, `그린골프` 스타일 프리셋 추가
- 자막 그림자 색상과 진하기 조절 추가
- 자막 설정 미리보기에도 실제 내보내기와 유사한 그림자 색상/진하기 반영
- 자막 위치 그리드는 `T`, HanClip 로고 위치 그리드는 `H`로 구분
- 배경 음악 파일 선택 및 Media3 Composition 오디오 시퀀스 연결
- 선택/공유한 배경음악을 실제 파일명으로 표시
- 선택/공유한 배경음악을 앱 내부 작업 파일로 복사해 내보내기 권한 안정화
- 음악 설정 시트를 작은 화면에서도 끝까지 볼 수 있도록 스크롤 구조로 보강
- 사진 클립 탭 시 사진 표시 시간 조절 시트
- 사진 시간 조절 시트에 닫기 버튼과 설명 문구 추가
- Android 공유 받기(`ACTION_SEND`, `ACTION_SEND_MULTIPLE`) 연결
- 공유로 들어온 오디오 파일을 배경음악으로 적용
- 공유 인박스 배너는 실제 공유 항목이 있을 때만 표시
- 공유 인박스 배너에 대기 파일 개수 표시
- 실제 영상 1개 클립은 MediaExtractor/MediaMuxer로 빠르게 잘라내기
- 여러 클립/사진 조합은 Media3 Transformer Composition 경로로 내보내기
- 임시 내보내기 캐시가 과도하게 쌓이지 않도록 오래된 파일 정리
- 내보낸 MP4 미리보기, 갤러리 저장, Android 공유 시트 연결
- 공유 인텐트에 `ClipData` URI 권한을 함께 전달해 공유 대상 앱 호환성 보강
- 시사회 영상 전체화면 미리보기 다이얼로그
- 시사회 전체화면에서 반복 재생과 화면 채우기/맞추기 전환 지원
- 시사회 화면을 작은 화면에서도 끝까지 볼 수 있도록 세로 스크롤 구조로 보강
- 시사회 `개봉하기` 팝업에서 갤러리 저장과 파일 저장 선택
- 시사회 갤러리/파일 저장 중 진행 다이얼로그 표시 및 백그라운드 저장 처리
- Android 저장 화면/알림 문구를 `갤러리` 기준으로 정리
- 저장 파일명을 `HanClip-yyyyMMdd-HHmmss.mp4` 형식으로 정리
- 시사회 `파일로 저장` 성공 후 저장 영화 히스토리 갱신
- AiShot 카메라/마이크 권한, 감도 선택, 샷 길이 선택, 수동 클립 저장, 저장 중 남은 시간/진행바, 여러 클립 저장 후 편집 이동
- AiShot 샷 길이 프리셋을 iOS처럼 `짧게` 앞 1.5초/뒤 1.5초, `일반` 앞 2초/뒤 3초, `길게` 앞 5초/뒤 5초 기준으로 표시
- AiShot 자동 감지 저장은 iOS 프리셋의 뒤 구간(`afterShot`)만큼 저장하고, 수동 저장은 전체 프리셋 길이만큼 저장
- AiShot 감도와 샷 길이 선택을 iOS처럼 다음 실행에도 유지
- AiShot 샷 시간 버튼을 iOS처럼 `일반`을 중심으로 `길게`/`짧게`를 번갈아 선택하는 방식으로 변경하고 다음 선택 방향도 저장
- AiShot 촬영 화면에 iOS식 기본 줌 프리셋 `1x`/`2x`/`4x` 선택과 다음 실행 유지 추가
- AiShot 전면/후면 카메라 선택을 다음 실행에도 유지
- AiShot 실시간 타격음 감지를 iOS처럼 RMS, peak, crossing rate, baseline 상승, crest factor 기반 confidence 판정으로 보강
- AiShot 화면에 iOS와 동일한 현재 Ai 버전 `0.2.1`과 `798 영상 보정 Ai` 안내 표시
- iOS AiShot 촬영 화면을 참고해 Android도 샷 길이 변경 시 중앙 안내 패널로 `앞/뒤 시간`, 전체 길이, 현재 선택 상태를 즉시 표시
- iOS AiShot 촬영 화면처럼 Android도 줌, 샷 시간, 수동 촬영, 카메라 전환을 카메라 위에 떠 있는 조작군으로 분리하고 하단 패널은 감도/Ai 안내 중심으로 정리
- AiShot 샷 시간 중앙 안내 패널의 배경 불투명도를 높여 줌 조작 텍스트가 비쳐 보이지 않도록 가독성 보정
- 실제 Android 폰 `SM_F968N`에서 설치/실행/가져오기/내보내기/저장/공유 확인
- 실제 Android 폰 설치 버전 `1.0.60`, `lastUpdateTime=2026-08-06 12:34:45` 확인
- 실제 Android 폰 브라우저 화면에서 상단 설명 `무료 음악 찾기`가 말줄임 없이 표시되는 것 확인
- 실제 Android 폰 홈 화면에서 `HanClip` 표기, 한글 프리셋 카드, 저장 영화 목록, AiShot 아이콘 표시 확인
- 실제 Android 폰 설정 팝업에서 `화면 꺼짐 방지` 오토 상태와 한글 기능 안내 카드 표시 확인
- 실제 Android 폰 빈 편집 화면에서 `사진+영상 선택`, `영상만`, `달력`, `파일`, `Ai컷` 버튼 글자 잘림 없이 표시 확인
- 연결 폰의 충전 중 화면 유지 설정 `stay_on_while_plugged_in=3` 유지 확인
- Samsung Gallery 우선 `ACTION_GET_CONTENT` 다중 선택 흐름과 Android 14 사진/영상 권한 선언 재확인
- 홈/설정/편집 화면 이동 후 최근 로그에서 HanClip `FATAL EXCEPTION` 없이 정상 확인
- 브라우저 다운로드 감지 시 외부 앱 호출 대신 Android 기본 다운로드 관리자로 `Downloads/HanClip` 저장 시작 안내 표시
- 브라우저 다운로드 관리자 요청에 WebView 쿠키를 함께 전달해 쿠키가 필요한 음원 사이트 다운로드 호환성 보강
- 음악 설정 화면에 브라우저 다운로드 후 `Downloads/HanClip` 폴더에서 다시 선택하라는 안내 문구 추가
- 실제 Android 폰 1.0.56 음악 설정 화면에서 다운로드 위치 안내 문구가 겹침 없이 표시되는 것 확인
- 실제 Android 폰 1.0.56 `사진+영상` 선택에서 Google Photos가 아니라 기본 갤러리 스타일의 `항목 선택` 화면 진입 재확인
- Android 앱 이름 리소스와 홈 표기 모두 `HanClip` 유지 확인
- 바탕화면 APK 내부 메타데이터 확인: `com.hanclip.android`, `versionName=1.0.60`, `versionCode=106`, `minSdk=26`, 앱 라벨 `HanClip`
- 실제 Android 폰 1.0.56 `hanclip://photo` 딥링크 호출이 기본 갤러리 `항목 선택` 화면으로 연결되는 것 확인
- 실제 Android 폰 1.0.56 `hanclip://calendar` 딥링크 호출이 달력 미디어 선택 시트로 연결되는 것 확인
- 홈 첫 화면 `HanClip` 제목 왼쪽에 iOS `LogoMark` 기반 로고 이미지 추가
- Android 앱 실행 아이콘 foreground와 legacy mipmap 아이콘을 투명/흰 배경 캔버스 안 80% 크기 로고로 다시 생성해 여백 보강
- 실제 Android 폰 1.0.60 홈 화면에서 참고 이미지처럼 캡슐 안 `HanClip` 로고가 겹침 없이 표시되는 것 확인
- 바탕화면 APK, 테스트 APK 사본, debug APK SHA-256 `42989630e428d443314eb71fe870f532402e6b9f1feac9fc397c41fe07cb0e04` 동일 확인
- 첨부 로고 참고 이미지에 맞춰 홈 상단을 옅은 배경 캡슐, 얇은 둥근 테두리, 짙은 청록 `HanClip`, 왼쪽 로고마크 구성으로 변경
- 홈 상단 `HanClip` 서체를 앱 내 `Pretendard Bold` 기반의 두꺼운 산세리프 톤으로 맞춤
- 홈 상단 캡슐 안 로고마크도 참고 이미지에 맞춰 짙은 청록 단색으로 표시
- 실제 Android 폰 1.0.60 홈 로고 확인 후 최근 로그에서 HanClip `FATAL EXCEPTION` 없이 정상 확인
- 실제 Android 폰 1.0.54 브라우저 화면 진입과 상단 컨트롤 표시 재확인

## 설치 파일

디버그 APK:

```text
app/build/outputs/apk/debug/app-debug.apk
```

APK와 빌드 산출물은 저장소에서 추적하지 않습니다.

## Android Studio에서 열기

Android Studio에서 `File > Open...`을 누른 뒤 저장소의 `android/` 폴더를 선택합니다.

```text
android/
```

## 패키지 구조

```text
com.hanclip.android
com.hanclip.android.core.model
com.hanclip.android.core.media
com.hanclip.android.core.permissions
com.hanclip.android.core.theme
com.hanclip.android.feature.aishot
com.hanclip.android.feature.home
com.hanclip.android.feature.editor
com.hanclip.android.feature.preview
```

## 테스트 완료

- `./gradlew :app:lintDebug :app:assembleDebug` 성공
- `./gradlew :app:testDebugUnitTest` 성공(`NO-SOURCE`)
- Android Studio Emulator `StarterApp_API_37`에 APK 설치 성공
- Samsung 기본 갤러리로 실제 MP4 선택 성공
- 영상 썸네일 표시 성공
- 자동 타격점 분석 후 2초 기본 클립 생성 성공
- 단일 영상 클립 MP4 내보내기 성공
- 미리보기 화면에서 내보낸 MP4 로드 성공
- 시사회 화면의 전체화면 버튼으로 검은 배경 전체화면 플레이어 표시 성공
- `/sdcard/Movies/HanClip` 갤러리 저장 성공
- Android 8/9용 `WRITE_EXTERNAL_STORAGE` 권한 및 `Movies/HanClip` 저장 경로 보강
- Android 공유 시트 표시 성공
- 실제 Android 폰 `SM_F968N`에 APK 설치 성공
- 실제 Android 폰에서 MP4 가져오기, 내보내기, 저장, 공유 성공
- 실제 Android 폰에서 `사진+영상 선택`과 `영상만`은 Samsung 기본 갤러리, `파일`은 Android 파일 앱 경로로 분리
- 사진 클립 시간 조절 시트 표시 확인
- 자막/음악/공유 받기 코드 빌드 확인
- 자막 설정 시트에서 `HanClip 로고` 스위치 표시 확인
- 골프 프리셋 진입 후 자막 설정에서 자막과 `HanClip 로고`가 기본으로 켜지는 것 확인
- 홈 저장 영화 카드에서 실제 골프 MP4 프레임 썸네일 표시 확인
- 갤러리 저장 시 저장 히스토리에서 임시 캐시 항목을 제거하고 실제 저장 항목으로 교체하도록 빌드 확인
- Android 8 호환성 보수를 위해 `MediaMetadataRetriever.release()` 경로 빌드 확인
- Android 8/9 갤러리 저장 권한 요청과 `MediaStore.DATA` 저장 경로 빌드 확인
- Android lint 오류 정리 후 `lintDebug` 통과
- Android 14 선택 사진 접근 및 Samsung Gallery 조회 manifest 보강 후 `lintDebug` 통과
- 홈 저장 영화 섹션 버튼 문구 개선 후 `lintDebug` 통과
- 홈 저장 영화 썸네일 `content://` URI 대응 후 `lintDebug` 통과
- 진행 오버레이 추가 후 `lintDebug`와 `assembleDebug` 통과
- 실제 폰 설치 버전 `0.5.0`, `lastUpdateTime=2026-08-06 04:14:34` 확인
- 자막 설정 시트에서 스타일 프리셋 표시와 골프 프리셋 `그린골프` 선택 상태 확인
- 자막 스타일 프리셋 추가 후 `lintDebug`와 `assembleDebug` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 04:16:15`
- 파일 저장 히스토리 반영 후 `lintDebug`와 `assembleDebug` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 04:18:34`
- AiShot 수동 저장 중 `클립 저장 중`, 남은 초, 진행바, `저장 중지` 버튼 표시 확인
- AiShot 저장 완료 후 `저장 완료 · 1개`, 자동 감지 설명, `편집으로` 버튼 표시 확인
- AiShot 저장 진행 표시 추가 후 `lintDebug`와 `assembleDebug` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 04:20:30`
- 평상시 홈에서 공유 인박스 배너가 숨겨지는 것 확인
- 공유 인박스 배너 표시 조건 정리 후 `lintDebug`와 `assembleDebug` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 04:23:06`
- 홈 저장 영화 목록에서 0클립 항목이 숨겨지고 정상 영화만 표시되는 것 확인
- 저장 영화 히스토리 0클립 정리 후 `lintDebug`와 `assembleDebug` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 04:24:49`
- 저장 영화 프리셋 제목 반영 후 `lintDebug`와 `assembleDebug` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 04:26:38`
- 홈 저장 영화 목록 제거 버튼 표시 확인, 실제 폰 설치 `lastUpdateTime=2026-08-06 04:28:26`
- 홈 저장 영화 목록 제거 확인 팝업 표시 확인, 실제 폰 설치 `lastUpdateTime=2026-08-06 04:45:24`
- 편집 종료 확인 팝업 추가 후 `lintDebug`와 `assembleDebug` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 04:47:52`
- 시사회 화면 스크롤 구조 보강 후 `lintDebug`와 `assembleDebug` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 04:49:25`
- 시사회 저장 중 진행 다이얼로그 추가 후 `lintDebug`와 `assembleDebug` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 04:50:54`
- 작업 미디어/내보내기 캐시 정리 로직 추가 후 `lintDebug`와 `assembleDebug` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 04:52:26`
- 저장 파일명 개선 후 `lintDebug`와 `assembleDebug` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 04:53:41`
- `HanClip-android-debug-tested.apk` 테스트 완료 사본을 최신 빌드로 갱신
- 홈 저장 영화 전체 표시 후 `lintDebug`와 `assembleDebug` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 04:55:48`
- MIME 타입 누락 미디어 확장자 판별 보강 후 `lintDebug`와 `assembleDebug` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 04:57:04`
- 사진 시간 조절 시트 디자인 보강 후 `lintDebug`와 `assembleDebug` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 04:59:08`
- 저장 영화 목록 접근 가능 항목 필터 추가 후 `lintDebug`와 `assembleDebug` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 05:00:36`
- 배경음악 파일명 표시 개선 후 `lintDebug`와 `assembleDebug` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 05:02:37`
- 배경음악 내부 복사 안정화 후 `lintDebug`와 `assembleDebug` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 05:03:57`
- 지원하지 않는 미디어 형식 필터 추가 후 `lintDebug`와 `assembleDebug` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 05:05:45`
- 음악 설정 시트 스크롤 보강 후 `lintDebug`와 `assembleDebug` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 05:07:12`
- 공유파일 자동 처리 후 홈 대기 배너 카운트 정리, `lintDebug`와 `assembleDebug` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 05:11:01`
- 기존 저장 영화 제목 구분 표시 보강 후 `lintDebug`와 `assembleDebug` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 05:13:40`
- 빈 편집 화면에서 불필요한 `클립` 제목 숨김 처리 후 `lintDebug`와 `assembleDebug` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 05:16:41`
- Samsung/기본 갤러리 `GET_CONTENT` 조회와 마이크 기능 선택 선언 보강 후 `lintDebug`와 `assembleDebug` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 05:18:12`
- 실제 폰에서 `사진+영상 선택` 버튼이 Samsung 기본 갤러리(`com.sec.android.gallery3d`) 선택 화면으로 열리는 것 재확인
- 자막 설정에 그림자 색상과 그림자 진하기 슬라이더 추가 후 `lintDebug`와 `assembleDebug` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 05:22:34`
- 자막 시트에서 그림자 설정을 색상 바로 아래로 재배치 후 `lintDebug`와 `assembleDebug` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 05:27:46`
- Android 버전 `0.6.1`(`versionCode=7`)로 갱신 후 `lintDebug`와 `assembleDebug` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 05:29:14`
- 별도 배포용 APK 사본을 `0.6.1` 최신 빌드로 갱신
- AiShot 수동 중지 후 재녹화 타이머 안정화와 deprecated API 경고 정리 후 `lintDebug`와 `assembleDebug` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 05:31:14`
- 편집 화면 `Ai컷` 버튼이 가져오기 전 자동 분할 모드를 켜도록 보강 후 `lintDebug`와 `assembleDebug` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 05:32:58`
- `영상만`/`Ai컷` 선택을 다중 선택 가능한 `GET_CONTENT` 기반 Samsung Gallery 우선 호출로 변경 후 `lintDebug`와 `assembleDebug` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 05:34:17`
- 실제 폰에서 `영상만` 버튼이 Samsung 기본 갤러리(`com.sec.android.gallery3d`) 선택 화면으로 열리는 것 재확인
- 공유 인텐트에 `ClipData` URI 권한 전달을 추가해 공유 대상 앱 호환성 보강 후 `lintDebug`와 `assembleDebug` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 05:37:26`
- 자막 위치 그리드는 `T`, HanClip 로고 위치 그리드는 `H`로 표시하도록 구분 후 `lintDebug`와 `assembleDebug` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 05:39:11`
- 갤러리 저장/파일 저장 원본 스트림 fallback을 공통화해 `content://`와 `file://` 저장 안정성 보강 후 `lintDebug`와 `assembleDebug` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 05:40:45`
- 자동 컷 클립 순서 변경 묶음 안정화와 전체 시간 +/- 조절 보강 후 `lintDebug`와 `assembleDebug` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 05:48:13`
- 원본 영상 `재분할` 기능 추가 후 `lintDebug`와 `assembleDebug` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 05:50:59`
- 갤러리 저장 실패 시 빈 항목 정리 보강 후 `lintDebug`, `assembleDebug`, `testDebugUnitTest` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 05:53:49`
- iOS 저장 목록 구조를 참고해 홈 저장 영화 카테고리/개수 표시 추가 후 `lintDebug`, `assembleDebug`, `testDebugUnitTest` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 05:58:11`
- iOS 기본 편집값 저장 흐름을 참고해 기본 길이/출력 비율 저장 추가 후 `lintDebug`, `assembleDebug`, `testDebugUnitTest` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 06:02:41`
- iOS 로고/저작권 색상 설정 흐름을 참고해 `HanClip` 로고 색상 설정/저장/내보내기 추가 후 `lintDebug`, `assembleDebug`, `testDebugUnitTest` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 06:06:50`
- iOS 자막 줄간격 설정 흐름을 참고해 Android에 줄간격 선택/세부 조절/저장/내보내기 추가 후 `lintDebug`, `assembleDebug`, `testDebugUnitTest` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 06:12:02`
- iOS 로고/저작권 그림자 설정 흐름을 참고해 `HanClip` 로고 그림자 색상/진하기 설정/저장/내보내기 추가 후 `lintDebug`, `assembleDebug`, `testDebugUnitTest` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 06:14:38`
- iOS `AudioImpactClassifier` 흐름을 참고해 자동 타격점 분석을 RMS, peak, crossing rate, baseline 상승, crest factor 기반 랭킹으로 보강 후 `lintDebug`, `assembleDebug`, `testDebugUnitTest` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 06:18:40`
- iOS AiShot 실시간 감지 흐름을 참고해 자동 녹화 트리거를 RMS, peak, crossing rate, baseline 상승, crest factor 기반 confidence 판정으로 보강 후 `lintDebug`, `assembleDebug`, `testDebugUnitTest` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 06:22:08`
- iOS Ai 버전 표시 흐름을 참고해 AiShot 하단 패널에 `Ai 0.2.1 · 798 영상 보정 Ai` 안내 추가 후 `lintDebug`, `assembleDebug`, `testDebugUnitTest` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 06:24:26`
- iOS AiShot 길이 프리셋을 참고해 `짧게`/`일반`/`길게` 선택을 앞/뒤 시간 기준 모델과 설명으로 보강 후 `lintDebug`, `assembleDebug`, `testDebugUnitTest` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 06:27:27`
- AiShot 자동 감지 저장은 iOS 프리셋의 뒤 구간(`afterShot`)만큼 저장하고 수동 저장은 전체 프리셋 길이만큼 저장하도록 분리 후 `lintDebug`, `assembleDebug`, `testDebugUnitTest` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 06:30:33`
- iOS `@AppStorage` 흐름을 참고해 AiShot 감도와 샷 길이 선택을 다음 실행에도 유지하도록 저장 후 `lintDebug`, `assembleDebug`, `testDebugUnitTest` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 06:33:23`
- iOS AiShot 줌 컨트롤을 참고해 CameraX 줌 프리셋 `1x`/`2x`/`4x` 선택과 다음 실행 유지 추가 후 `lintDebug`, `assembleDebug`, `testDebugUnitTest` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 06:36:26`
- iOS 카메라 선택 저장 흐름을 참고해 AiShot 전면/후면 카메라 선택을 다음 실행에도 유지하도록 추가 후 `lintDebug`, `assembleDebug`, `testDebugUnitTest` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 06:40:08`
- iOS 워터마크 모델의 `copyrightIconColorMode`/`copyrightIconColorHex` 흐름을 참고해 Android `HanClip` 로고 색상 모드와 프로젝트 저장/내보내기 반영 후 `lintDebug`, `assembleDebug`, `testDebugUnitTest` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 06:43:52`
- iOS `SELECT THEME` 팝업과 `hanClipThemeMode` 흐름을 참고해 Android 홈 테마 선택/팔레트 미리보기/선택값 저장을 추가 후 `lintDebug`, `assembleDebug`, `testDebugUnitTest` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 06:48:17`
- 홈 전용 테마 모델을 공용 `HanClipThemeMode`/`HanClipThemeStore`로 분리하고 편집 화면 배경, 헤더, 요약 패널, 프리셋 상태 패널, 가져오기 버튼에 선택 테마 반영 후 `lintDebug`, `assembleDebug`, `testDebugUnitTest` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 06:52:34`
- 편집 하단 시트 중 자막/음악/사진 시간/영상 구간 선택의 표면, 헤더, 주요 실행 버튼, 타격점 패널에 선택 테마 반영 후 `lintDebug`, `assembleDebug`, `testDebugUnitTest` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 06:56:11`
- 시사회 화면 배경, 개봉 준비 카드, 다시 편집/공유/개봉/홈 버튼, 개봉 옵션 시트, 저장 중 다이얼로그에 선택 테마 반영 후 `lintDebug`, `assembleDebug`, `testDebugUnitTest` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 06:59:12`
- 편집 알림/초기화/나가기 확인 팝업, 진행 오버레이, 자막/음악/순서/비율 칩, 전체 영상 시간 패널, 하단 영화 만들기 바에 선택 테마 반영 후 `lintDebug`, `assembleDebug`, `testDebugUnitTest` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 07:04:06`
- 누적 변경 후 `./gradlew :app:testDebugUnitTest` 성공(`NO-SOURCE`)
- 바탕화면 APK, 테스트 APK 사본, debug APK가 모두 37MB 최신 빌드로 갱신된 것 확인
- iOS 외부 호출 주소를 참고해 Android Manifest 딥링크와 Compose 빠른 진입 연결 추가 후 `lintDebug`, `assembleDebug`, `testDebugUnitTest` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 07:34:56`
- 실제 폰에서 `hanclip://open` 홈 진입, `hanclip://aishot` AiShot 진입, `hanclip://photo` Samsung 기본 갤러리 선택, `hanclip://files` Android 파일 선택기 진입 확인
- iOS 달력 미디어 선택 흐름을 참고해 Android 편집 화면 `달력` 버튼, MediaStore 월별 날짜 그리드, 날짜별 썸네일 다중 선택, 가져오기 연결 추가 후 `lintDebug`, `assembleDebug`, `testDebugUnitTest` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 07:45:46`
- 실제 폰에서 `hanclip://calendar` 호출, 사진/동영상 권한 요청, 월별 달력 표시, 날짜별 미디어 개수 표시, 썸네일 선택, `가져오기 1개`, 편집 클립 추가까지 확인
- iOS 온라인 음악 브라우저 흐름을 참고해 Android WebView 브라우저 화면, Pixabay/Mixkit 바로가기, 주소/검색 입력, 음악 설정 `브라우저` 버튼, `hanclip://search` 브라우저 진입 추가 후 `lintDebug`, `assembleDebug`, `testDebugUnitTest` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 07:51:30`
- 실제 폰에서 `hanclip://search` 호출 후 앱 안 브라우저 화면, Pixabay/Mixkit 바로가기, 주소 입력, 이동 버튼, 다운로드 후 파일 선택 안내 표시 확인
- iOS 브라우저 즐겨찾기 패널을 참고해 Android 브라우저 즐겨찾기 목록, 현재 주소 추가/해제, 즐겨찾기 삭제, 첫 페이지 지정, SharedPreferences 저장 추가 후 `lintDebug`, `assembleDebug`, `testDebugUnitTest` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 07:55:25`
- 실제 폰에서 `hanclip://search` 호출 후 브라우저 화면, 첫 페이지, 즐겨찾기 패널, 현재 주소 추가/해제, 홈/삭제 버튼 표시 확인
- iOS 최신 `Pixel Pop` 테마 색상(`#2652FF`, `#DC2F65`, `#F9FBFF`, `#E8EFFF`, `#0F1630`)을 Android 테마 팔레트에 동기화 후 `lintDebug`, `assembleDebug`, `testDebugUnitTest` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 07:59:58`
- 실제 폰 홈 화면에서 `SELECT THEME` 팝업과 `Pixel Pop` 선택지 표시 확인
- iOS `비슷한 사진 묶음` 흐름을 참고해 Android 사진 8x8 밝기 지문, 연속 사진 유사도 그룹, 대표 컷 기본 렌더링, 묶음 펼치기/접기, `사용` 버튼, 초안 저장/복원 추가 후 `lintDebug`, `assembleDebug`, `testDebugUnitTest` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 08:10:38`
- 실제 폰에서 HanClip 홈 화면 실행, 테마/주요 진입 버튼과 저장 영화 목록 표시 확인
- 시사회 전체화면 플레이어에 iOS 흐름을 참고한 반복 재생 토글과 화면 채우기/맞추기 전환 버튼 추가 후 `lintDebug`, `assembleDebug`, `testDebugUnitTest` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 08:15:18`
- 실제 폰에서 HanClip 홈 화면 실행 확인
- iOS `BrowserFavoritesArchive`와 같은 `.hanclipfavorites` JSON 포맷으로 Android 브라우저 즐겨찾기 공유/가져오기, 중복 주소 병합, 가져온 뒤 브라우저 진입 추가 후 `lintDebug`, `assembleDebug`, `testDebugUnitTest` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 08:23:57`
- 실제 폰에서 `hanclip://search` 브라우저 진입, 첫 페이지/즐겨찾기/즐겨찾기 해제/공유 버튼 표시 확인
- Android 파일 앱에서 `.hanclipfavorites`를 직접 열 때도 iOS 즐겨찾기 JSON을 병합하고 브라우저로 진입하도록 `ACTION_VIEW` 문서 열기 경로 추가 후 `lintDebug`, `assembleDebug`, `testDebugUnitTest` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 08:26:59`
- 실제 폰 패키지 덤프에서 `ACTION_VIEW`, `application/vnd.hanclip.browser-favorites+json`, `application/json` 문서 열기 필터 등록 확인
- `.hanclipfavorites` 직접 열기 검증 중 외부 저장소 `file://` 입력은 Android 샌드박스에서 읽기 제한될 수 있어 실패 안내와 브라우저 진입 fallback 추가 후 `lintDebug`, `assembleDebug`, `testDebugUnitTest` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 08:35:11`, 실제 폰 브라우저 진입 확인
- iOS 최신 설정/카피라이터 흐름을 참고해 Android 홈 상단 `i` 버튼을 설정 버튼으로 정리하고 설정 팝업 제목/설명/Special Thanks 항목 보강 후 `lintDebug`, `assembleDebug`, `testDebugUnitTest` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 08:38:08`, 실제 폰 설정 팝업 표시 확인
- 편집 화면 프리셋 상태 패널 추가 후 `lintDebug`와 `assembleDebug` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 04:32:40`
- 작업 초기화 확인 팝업 추가 후 `lintDebug`와 `assembleDebug` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 04:35:43`
- 자동 분할 완료 상태 패널 추가 후 `lintDebug`와 `assembleDebug` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 04:37:10`
- 미디어 가져오기 성공/실패 개수 안내 보강 후 `lintDebug`와 `assembleDebug` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 04:38:16`
- Android 버전 `0.6.0`(`versionCode=6`)으로 갱신 후 `lintDebug`와 `assembleDebug` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 04:39:28`
- 공유 인박스 개수 표시 후 `lintDebug`와 `assembleDebug` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 04:41:06`
- 갤러리 저장 문구 정리 후 `lintDebug`와 `assembleDebug` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 04:43:32`
- 프리텐다드, 고운바탕, 고운돋움, 나눔고딕, 도현, 검은고딕, 마루부리 Android assets 포함 빌드 성공
- iOS 내장 자막 서체와 맞춰 Kakao Big Sans, Cafe24 Ssurround, Puradak Gentle Gothic, Tenada, Ddulgi Mayo를 Android assets/UI/내보내기 매핑에 추가 후 `lintDebug`, `assembleDebug`, `testDebugUnitTest` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 08:41:02`, 실제 폰 자막 설정 폰트 목록 표시 확인
- iOS 최신 전체 화면 설정 흐름을 참고해 Android 자막/음악 설정을 하단 시트에서 전체 화면 Dialog로 전환 후 `lintDebug`, `assembleDebug`, `testDebugUnitTest` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 08:46:05`, 실제 폰 자막/음악 전체 화면 표시 확인
- iOS 최신 개봉 위치 화면 흐름을 참고해 Android `개봉하기` 저장 위치 선택을 전체 화면 Dialog로 전환하고 상태바 영역까지 배경을 덮도록 보정 후 `lintDebug`, `assembleDebug`, `testDebugUnitTest` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 08:55:42`, 실제 폰 저장 위치 전체 화면 표시 확인
- iOS 영상 생성 진행창 흐름을 참고해 Android 영화 만들기 진행 오버레이에 `제작 취소` 버튼과 Transformer 작업 취소 연결 추가 후 `lintDebug`, `assembleDebug`, `testDebugUnitTest` 통과, 실제 폰 설치 `lastUpdateTime=2026-08-06 08:58:35`
- 골프 영상 11.2초 샘플에서 자동 분할 3개 생성 확인
- 자동 분할 3개 + 자막 + 골프 배경음악 조합으로 MP4 내보내기 성공
- 시사회 `개봉하기` 팝업에서 `/sdcard/Movies/HanClip` 저장 성공
- AiShot 권한 허용 후 수동 4초 클립 저장, 저장 개수 표시, `편집으로` 버튼을 통한 AiShot 편집 화면 전달 확인
- Android 런처 아이콘 리소스 빌드 성공
- Android 공유 인텐트에서 `audio/*` 수신 빌드 성공
- CCMB 로그 기준 Codex 주간 사용량 20% 사용 확인

## 남은 검증

- 현재는 디버그 APK입니다. 외부 배포용 릴리스 APK/AAB를 만들려면 서명 키가 필요합니다.
- AiShot 자동 타격음 감지 민감도는 실제 골프장 소리 샘플에서 추가 보정하면 됩니다.
- 여러 사용자 영상 연결, 자막 합성, 배경 음악 믹싱, 장시간 영상 성능은 추가 실사용 샘플에서 더 확인하면 됩니다.
