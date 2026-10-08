# 슈가캡 (SugarCap) — 리포 규칙

SSOT = `SPEC.md`. 세션 시작 시 SPEC §0·§8·§9부터 읽는다.

## 구조
- `tools/scrape/` — 카탈로그 수집 파이프라인(Python 3.13). 패키지 `sugarcap_scrape`, 브랜드 파서는 `brands/<id>.py`.
- `data/catalog.json` — 앱이 번들·원격 갱신하는 산출물. 손으로 고치지 않는다. 파이프라인으로만 생성.
- iOS 앱은 Phase 1에서 `SugarCap/` 아래 XcodeGen 프로젝트로 추가.

## 파이프라인 명령 (전부 `tools/scrape/`에서, venv는 리포 루트 `.venv`)
```
..\..\.venv\Scripts\python -m ruff format . && ..\..\.venv\Scripts\python -m ruff check .
..\..\.venv\Scripts\python -m mypy
..\..\.venv\Scripts\python -m pytest -q            # live 테스트 포함(실사이트 호출)
..\..\.venv\Scripts\python -m sugarcap_scrape.build --out ..\..\data\catalog.json --kfind .raw\kfind_20260828.xlsx
..\..\.venv\Scripts\python -m sugarcap_scrape.build --country us --out ..\..\data\catalog-us.json
..\..\.venv\Scripts\python -m sugarcap_scrape.build --country tw --out ..\..\data\catalog-tw.json
```
게이트: ruff·mypy 0 에러 + pytest 통과 전에 "완료" 금지.

## 데이터 규칙 (SPEC §2, 스키마 계약은 `data/SCHEMA.md`)
- 브랜드가 공개한 값만 기록한다. **ml 환산·사이즈 추정 금지.** 예외는 편의점(`cvs`)의 100ml(g)당 값 × 포장 총내용량, 그리고 fl oz로 게시된 용량의 ml 단위 환산(미국, SPEC §9.9)뿐이다.
- 당류·카페인 미공개는 둘 다 `None`으로 남긴다. **행을 드롭하지 않는다**(SPEC §9.2). 당 기록이 본체라 논커피 메뉴를 카페인 결측으로 버리면 안 된다.
- 카탈로그 ID(`brand:drink-slug:temp:size-slug`) 정의는 `sugarcap_scrape/ids.py` 한 곳. 바꾸면 기존 기록의 참조가 끊기니 SPEC에 마이그레이션 절을 먼저 쓴다.
- 빌더는 쓰기 전에 `validate.py`를 돌리고 실패 시 파일을 쓰지 않는다. 새 브랜드를 추가하면 `MIN_DRINKS_PER_BRAND`에도 등록한다.
- 파서는 네트워크(`http.fetch_text`)와 파싱(순수 함수)을 분리한다. 테스트는 실호출(`@pytest.mark.live`) 우선, 목 금지.

## 함정
- Windows 콘솔 한글: 파이썬 실행 시 `PYTHONIOENCODING=utf-8`. 소스 치환에 PowerShell Get/Set-Content 왕복 금지(모지바케).
- 브랜드별 함정은 SPEC §2 표. 이디야 `drink.html` 추천 팝업 값은 플레이스홀더, 메가 카페인 단위 오타("g"), 더벤티 원두별 카페인 2값, 컴포즈 당류 결측, 투썸은 `mo.` 도메인.
- 투썸 상세 페이지는 온도 탭 블록을 두 번 렌더한다. 중복 제거를 빼면 serving이 2배로 만들어져 빌더가 duplicate id로 죽는다.
- 더벤티 상세는 표 헤더(`라지(600ml) 점보(960ml)`)가 아니라 **설명문의 "기준치 : X(Nml) 사이즈 기준"**이 수치의 기준 사이즈다. 헤더 첫 사이즈를 쓰면 아인슈페너류가 틀린다.
- 편의점 출처 K-FIND 엑셀은 사이트가 활용정보 양식(소속·기관유형·목적)을 받은 뒤에 내려준다. 빌더가 받지 않고 사람이 받아 `tools/scrape/.raw/`에 둔다. 서버 연결이 자주 끊겨서 curl은 `-4`와 재시도가 필요했다(2026-10-01). 엑셀 읽기 약 1분.
- K-FIND `데이터생성일자`는 출시일이 아니라 일괄 적재일이다(2019-06-30·2021-06-30 다수). 날짜로 자르면 스테디셀러가 빠진다.
- live 테스트는 실사이트를 전수 호출해 느리다(투썸 약 3분, 더벤티 약 1분). 전체 빌드는 약 12분.
- UI 테스트는 정리 단계(설정 되돌리기 등)도 대기 + assert로 확인한다. 탭만 하고 넘어가면 실패해도 통과하고, 뒤이은 CI 스크린샷이 오염된 상태로 찍힌다(Phase 2b, 당 기준 100 g이 남은 사례).
- UIKit 외형 설정(`UISegmentedControl.appearance()` 등)을 `App.init`에서 부르면 에셋 `AccentColor`가 안 붙고 앱 전체가 시스템 파랑이 된다(2026-09-26). 첫 화면 `onAppear`에서 부른다. 루트에 `.tint(Color("AccentColor"))`도 걸려 있다.
- UI 테스트는 이름순으로 돌고, 첫 실행(온보딩) 테스트 `testRecording…`이 맨 앞이어야 한다. 새 테스트 이름이 그보다 앞서면(`testOpen…` 등) 온보딩을 먼저 끝내 첫 테스트가 "첫 실행에 온보딩이 없음"으로 죽는다(2026-10-05).
- iOS 26 `confirmationDialog` 안 버튼의 식별자는 두 요소로 잡힌다. UI 테스트에서 `matching(identifier:)` 중 `isHittable`인 것을 골라 누른다. 실패하면 상태(감소 목표 등)가 남아 뒤 테스트까지 연쇄 실패한다.
- 색·레이아웃 변경은 CI 스크린샷을 눈으로 확인한 뒤에 끝낸다. 빌드·테스트 녹색은 색이 틀어진 걸 못 잡는다.
- 모션그래픽(온보딩 릴·로슈카인 소개·먹이기 전환)에는 에어브러시류를 쓰지 않는다: 글로우 box-shadow, 방사형·부드러운 그라데이션 번쩍임, 그라데이션 하늘. 단색 면·또렷한 선만(대표님 2026-09-26 "구려져"). 큰 한글 제목 자간은 -0.02em보다 좁히지 않는다(좁히면 받침·느낌표가 붙는다).
- 여러 글자가 든 줄(HStack·VStack)에 `accessibilityIdentifier`를 달면 안쪽 글자마다 같은 식별자가 붙는다. UI 테스트가 줄 수를 5배로 셌다(2026-09-26 하루 기록 시트). 줄에는 `.accessibilityElement(children: .contain)`을 먼저 건다.
- 시각 레퍼런스(스크린샷)를 받으면 대상 부분을 원본 해상도로 잘라 보고 모양·위치·세기를 수치로 잰 뒤 만든다. 축소본만 보고 물리 계산으로 먼저 가면 엇나간다(2026-09-29 로슈 컵 반사: 레퍼런스는 몸통만 있는 옅은 윤곽이었는데 볼록 유리 계산·좌우반전·얼굴까지 넣었다가 되돌림). 로슈 그림자는 대표님 허락으로 에어브러시(부드러운 방사형) 예외.
- 모션그래픽을 시각 t의 순수 함수로 옮길 때 `.position(x: a + b * lerp(...) * sin(.pi * k), ...)`처럼 한 줄에 몰면 "unable to type-check this expression in reasonable time"으로 빌드가 죽는다. 중간값을 `let x: Double = ...`로 쪼개고 `Double.pi`를 쓴다.
- Swift 소스를 셸 heredoc + Python 치환으로 고치면 `\n`·`\(`의 역슬래시가 한 겹 벗겨져 문자열 안에 실제 줄바꿈이 들어간다(2026-10-05 UI 테스트 "unterminated string literal"로 CI 실패). 역슬래시가 든 Swift 문자열은 Edit 도구로 고친다.
- 매 프레임 다시 그리는 뷰(`TimelineView` + `Canvas`, 대기 자세)는 넘기는 중·화면 밖이면 멈춘다. 넘길 때 그리면 컵보다 늦게 따라오고(대표님 2026-09-29), 탭 뒤에서 계속 그리면 UI 테스트가 요소를 못 찾고 타임아웃 난다. 워크플로는 `cancel-in-progress`라 푸시 빌드가 끝난 뒤에 TestFlight를 dispatch한다.
- 카인 동작에 한 바퀴(360도) 이상 도는 회전을 넣지 않는다. 반응·연타·대기 자세·매달리기 전부(대표님 2026-10-06 "절대 넣지 마"). 갸웃처럼 기울였다 돌아오는 건 괜찮다. 유일한 예외는 커피 속 헤엄(swim)의 한 바퀴다(같은 날 대표님이 직접 요청). 다른 동작으로 넓히지 않는다.
- Dutch Bros 영양 PDF는 섹션마다 열 구성이 다르고(프로틴은 카페인 앞에 3열, Myst는 뒤에 2열), 시즌 쪽은 넓은 헤더 아래 12열 행이 섞인다. 열은 헤더 이름으로 찾고, 행 값 수가 헤더와 다르면 기본 12열로 읽는다. 원본 자체가 한 칸 밀린 행(포화지방 > 총지방, 당 > 총탄수, 2026-10-07 Pumpkin Pie Spice Breve 6행)은 당·카페인을 null로 둔다. 같은 음료가 두 섹션에 실리면 첫 번째만 남긴다.
- `colors.py`에 영어 키워드를 넣으면 K-FIND 편의점 제품 중 영문명(`Mango Ice Ade`, `…Blueberry`)의 색이 바뀌어 `test_colors` 회귀가 깨진다. 한국 카탈로그를 다시 빌드하지 않을 거면 그런 단어는 넣지 않는다(`mango`·`blueberry`·`ginger` 보류, `berry`는 `(?<!blue)berry`).
- 영어판(SPEC §9.9): 사용자 문구의 SSOT는 `SugarCap/Resources/Localizable.xcstrings`(원문 ko, 번역 en). 새 문구를 넣으면 en도 같이 넣는다. 키 목록은 CI `localizations` 산출물로 받는다(개발 PC에 Xcode 없음). 시뮬레이터 기본 언어가 영어라 테스트는 스킴 `language: ko`, 스크린샷은 `-AppleLanguages (ko)`로 고정돼 있다. 영어 화면은 `en-*` 스크린샷으로 본다.
- 스크린샷 단계는 UI 테스트가 남긴 SwiftData를 그대로 쓴다. 테스트가 설정을 "원래 값"으로 되돌려도 저장된 값이 생겨 기기 지역 기본값을 덮는다(2026-10-07 메뉴 국가: en_US인데 한국으로 찍힘). 지역·기본값에 기대는 화면은 Debug 전용 `-screenshot…` 인자로 고정한다(`-screenshotMenuCountry us`).
- 대만판(SPEC §9.9 ④): 대만 파서·테스트는 전각 문장부호(`：` `（` `】`)를 그대로 다뤄 ruff RUF001~003을 `pyproject.toml` per-file-ignores로 끈다(`brands/tw_*.py`, `tests/test_tw_*.py`). 다른 파일로 넓히지 않는다.
- `colors.py`에 한자 키워드를 넣을 때도 영어와 같은 함정이 있다. K-FIND에 한자 이름 제품(`宾格瑞草莓牛奶`, `柚子風味乳酸菌飮料`)이 있어 `草莓`·`莓`·`柚`는 넣지 않았다(2026-10-08).
- 可不可(`tw-kebuke`)는 카페인 줄이 【中杯】【大杯】 뒤에 한 번만 나오는 음료가 있다. 그 줄은 마지막 잔이 아니라 음료 전체 값이다(`rows_of`). Cama(`tw-cama`)는 음료 단위 구간보다 `其他資訊`의 사이즈별 값이 우선이고, "최고값·全糖 기준" 안내문이 바뀌면 파서가 거부한다.
- 대만 카페인 구간(`≤100` `101~200` `≥201`)은 schema v2 `caffeine_range`로 싣고, 합계는 상한(열린 구간은 하한)으로 센다. 기록 스냅샷에는 구간을 남기지 않는다.
