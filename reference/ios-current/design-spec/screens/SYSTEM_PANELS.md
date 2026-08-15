# 테마 패널 · i/카피라이터 · 저작권 · 권한/오류 팝업

## 테마 패널

- 진입: 홈 로고 0.6s long press. 홈 blur2 + black20% dim; panel width 92%, top aligned, move-from-top+opacity.
- 계층: `SELECT THEME` 18 semibold; `COLOR SYSTEM` summary(Main/Sub/BG/Text four chips); 6 radio rows(min height48); `확인` 44 capsule.
- rows: Automatic/Light/Dark/Blossom Glow/Grayscale Play/Pixel Pop. radio `largecircle.fill.circle`/`circle` 20 semibold. 색 swatch 26×26/radius6. custom 3종은 swatch drag로 순서 변경.
- 바깥 tap/확인=닫기. 선택은 panel을 닫지 않고 즉시 theme 변경(`dismissPanel:false`); 확인만 닫음.
- source `EditorView.swift:507-550,1221-1250,2656-2945`; colors `HanClipApp.swift`.

## i 버튼/카피라이터 계층

- i 44 circle tap→full-screen `ImportantInfoSheet`; long press 0.55s→browser.
- 화면: common top header/logo; 우측 X와 reset; `카피라이터 설정`; watermark collapsed/expanded + 구매/복원; screen sleep segmented; `Special Thanks`; feature documentation cards; `외부 호출 주소`; sample/external music; embedded-font copyright/size/license, 최하단까지 ScrollView.
- background gradient; content horizontal20, group spacing14, bottom28. exact card geometry는 `InfoRow`/`EmbeddedFontCopyrightRow`.

## 워터마크/IAP

- 사용/안함 segmented는 행 어느 곳 tap해도 switch. 미구매면 사용 불가/강제 off.
- platform icons: HanClip, Instagram/Facebook/YouTube/Blog/KakaoTalk/X/Telephone/Homepage/Custom assets. position 5×5. address, icon color(original만 현재 allCases에 노출), text/shadow colors/opacity.
- reset은 platform HanClip, default bottomTrailing/colors/opacity로 돌린다. purchase plans/StoreKit 상태는 `CopyrightPurchaseManager`/`HanClip.storekit` 기준.

## 화면 꺼짐 방지

- `항상켜짐`, `끔`, `오토`; detail은 각각 항상 유지/시스템 자동잠금/렌더·import·save 중만 유지.

## 저작권 문서

- 앱 내부 Feature docs는 `ImportantInfoSheet.items` 배열이 단일 원본. Android도 새 기능 명칭/설명을 계속 동기화한다.
- embedded font license는 각 font file/LICENSE를 함께 배포. 전체 원문을 UI에서 접거나 scroll 가능하게 보이되 삭제하지 않는다.

## 권한/오류 팝업

- 전역 alert title `HanClip`, body `model.alertMessage`, `확인` 1개.
- 사진: read/add 권한; 카메라/마이크; 파일 security scope; notification/network/browser; Photos save; StoreKit error를 구분.
- 권한 거부 시 해당 기능을 실행하지 않고 설정 앱 이동 안내가 필요한 경우 시스템 API 사용. 정확 문구가 소스에서 동적으로 생성되면 Android에서 추측하지 않고 동일 원인+해결 행동을 명시.
- progress와 error를 동시에 표시하지 않는다. task failure에서 busy state를 반드시 해제한 후 alert.

## 아이콘/접근성

- theme `paintpalette.fill`; info `info.circle.fill`; reset `arrow.counterclockwise`; close `xmark`; watermark `signature`; sleep icons는 설정 source.
- 모든 InfoRow는 title+detail. font license 장문은 heading rotor/semantic heading 제공.

## 반응형

- theme width92%이면서 최대 620pt, reset/exit 확인은 최대 760pt. copyright는 safe-area scroll이며 regular-width 루트 최대 920pt 안에서 읽기 폭을 유지한다.

## 컨트롤 기본값/수명

- [CONTROL_DEFAULTS.md](../CONTROL_DEFAULTS.md#홈테마컬렉션), [카피라이터](../CONTROL_DEFAULTS.md#카피라이터). theme/watermark/sleep는 UserDefaults로 앱 재실행 유지; feature docs는 read-only.

## Swift 근거/Android

- `ImportantInfoSheet:8325-9436`, common InfoRow `11426+`, purchase manager service.
- Android IAP는 Play Billing로 구현하되 상품 entitlement 의미를 맞추고 Apple StoreKit product ID는 복사하지 않는다.
