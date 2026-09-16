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
..\..\.venv\Scripts\python -m sugarcap_scrape.build --out ..\..\data\catalog.json
```
게이트: ruff·mypy 0 에러 + pytest 통과 전에 "완료" 금지.

## 데이터 규칙 (SPEC §2, 스키마 계약은 `data/SCHEMA.md`)
- 브랜드가 공개한 값만 기록한다. **ml 환산·사이즈 추정 금지.**
- 당류·카페인 미공개는 둘 다 `None`으로 남긴다. **행을 드롭하지 않는다**(SPEC §9.2). 당 기록이 본체라 논커피 메뉴를 카페인 결측으로 버리면 안 된다.
- 카탈로그 ID(`brand:drink-slug:temp:size-slug`) 정의는 `sugarcap_scrape/ids.py` 한 곳. 바꾸면 기존 기록의 참조가 끊기니 SPEC에 마이그레이션 절을 먼저 쓴다.
- 빌더는 쓰기 전에 `validate.py`를 돌리고 실패 시 파일을 쓰지 않는다. 새 브랜드를 추가하면 `MIN_DRINKS_PER_BRAND`에도 등록한다.
- 파서는 네트워크(`http.fetch_text`)와 파싱(순수 함수)을 분리한다. 테스트는 실호출(`@pytest.mark.live`) 우선, 목 금지.

## 함정
- Windows 콘솔 한글: 파이썬 실행 시 `PYTHONIOENCODING=utf-8`. 소스 치환에 PowerShell Get/Set-Content 왕복 금지(모지바케).
- 브랜드별 함정은 SPEC §2 표. 이디야 `drink.html` 추천 팝업 값은 플레이스홀더, 메가 카페인 단위 오타("g"), 더벤티 원두별 카페인 2값, 컴포즈 당류 결측, 투썸은 `mo.` 도메인.
- 투썸 상세 페이지는 온도 탭 블록을 두 번 렌더한다. 중복 제거를 빼면 serving이 2배로 만들어져 빌더가 duplicate id로 죽는다.
- 더벤티 상세는 표 헤더(`라지(600ml) 점보(960ml)`)가 아니라 **설명문의 "기준치 : X(Nml) 사이즈 기준"**이 수치의 기준 사이즈다. 헤더 첫 사이즈를 쓰면 아인슈페너류가 틀린다.
- live 테스트는 실사이트를 전수 호출해 느리다(투썸 약 3분, 더벤티 약 1분). 전체 빌드는 약 12분.
