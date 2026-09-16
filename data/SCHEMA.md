# catalog.json 스키마 (schema_version 1)

> 이 파일은 `data/catalog.json`의 계약서다. 앱이 번들·원격으로 읽는 유일한 데이터 형식.
> 손으로 고치지 않는다. `tools/scrape/`의 파이프라인만 이 파일을 만든다.
> 스펙 본문은 `SPEC.md` §2. 여기는 필드 단위 정의와 불변식만 적는다.

## 생성

```
cd tools\scrape
..\..\.venv\Scripts\python -m sugarcap_scrape.build --out ..\..\data\catalog.json
```

빌더는 쓰기 전에 `sugarcap_scrape.validate.validate()`를 돌린다. 문제가 하나라도 있으면
`INVALID ...`를 찍고 **파일을 쓰지 않은 채 exit 1**. `--only`로 일부 브랜드만 돌릴 때는
카탈로그가 불완전하므로 검증을 건너뛴다(그 산출물은 커밋하지 않는다).

## 최상위

| 필드 | 타입 | 설명 |
|---|---|---|
| `schema_version` | int | 현재 1. 앱이 읽을 수 있는 버전인지 먼저 확인한다. 깨는 변경 시 +1 |
| `built_at` | string | 수집 시각, UTC ISO 8601(초 단위). 설정 화면의 "데이터 갱신 날짜" |
| `brands` | Brand[] | 등록 순서 |
| `drinks` | Drink[] | `(brand_id, 이름 slug, temperature)` 사전순 |

## Brand

| 필드 | 타입 | 설명 |
|---|---|---|
| `id` | string | `starbucks` `mega` `compose` `ediya` `paik` `twosome` `hollys` `theventi` |
| `name` | string | 한국어 표시명 |
| `serving_note` | string | 이 브랜드 수치가 어느 잔 기준인지 한 줄. 상세 화면에 그대로 노출 |
| `has_size_choice` | bool | true면 사이즈 선택 UI를 켠다. 현재 `ediya`, `twosome`만 true |

`has_size_choice`가 false인 브랜드의 drink는 serving이 정확히 1개다(검증이 강제).

## Drink

| 필드 | 타입 | 설명 |
|---|---|---|
| `id` | string | `{brand_id}:{이름 slug}:{temperature}` |
| `brand_id` | string | Brand.id 참조 |
| `name` | string | 브랜드 표기 그대로(앞뒤 공백 없음) |
| `name_en` | string \| null | 브랜드가 영문명을 주는 경우만 |
| `category` | string | 브랜드의 자체 분류명. 표준화하지 않는다 |
| `temperature` | `"hot"` \| `"iced"` \| `"both"` | `both`는 브랜드가 온도를 구분해 게시하지 않았다는 뜻 |
| `servings` | Serving[] | 최소 1개 |

## Serving

| 필드 | 타입 | 설명 |
|---|---|---|
| `id` | string | `{drink.id}:{사이즈 slug}` |
| `size_label` | string | 브랜드 표기 그대로(`Tall` `레귤러` `라지` `L` `EX` `기본`...) |
| `volume_ml` | int \| null | 브랜드가 게시한 컵용량. **ml 환산·추정 금지**, 미게시는 null |
| `sugar_g` | float \| null | null = 브랜드 미공개 |
| `caffeine_mg` | float \| null | null = 브랜드 미공개. 변형이 있으면 첫 변형 값과 같다 |
| `caffeine_variants` | CaffeineVariant[] | 원두 선택에 따라 카페인이 갈리는 경우만. 없으면 `[]` |

### CaffeineVariant

| 필드 | 타입 | 설명 |
|---|---|---|
| `label` | string | 브랜드 표기(`시그니처` `다크`) |
| `caffeine_mg` | float | 해당 선택의 카페인 |

현재 더벤티만 사용한다(11 servings).

## 불변식 (`validate.py`가 강제)

1. `brand.id`, `drink.id`, `serving.id`는 전부 유일하다.
2. 모든 `drink.brand_id`는 `brands`에 존재한다.
3. `serving.id == f"{drink.id}:{slugify(size_label)}"` — **id 규칙을 바꾸면 사용자 기록의 참조가 끊긴다.** 바꿔야 하면 SPEC에 마이그레이션 절을 먼저 쓴다(`tools/scrape/sugarcap_scrape/ids.py`가 유일한 정의 지점).
4. `drink.name`은 비어 있지 않고 앞뒤 공백이 없다.
5. 브랜드별 drink 수가 `MIN_DRINKS_PER_BRAND` 이상이다. 파서가 조용히 망가지면 여기서 걸린다.
6. 이상치: `sugar_g <= 200`, `caffeine_mg <= 800`, `20 <= volume_ml <= 1200`. 실제 최대치(138g / 680mg / 990ml)보다 넉넉하다 — 걸리면 신메뉴가 아니라 파싱 버그다.
7. `caffeine_variants`가 있으면 `caffeine_mg`는 첫 변형의 값이다.

## null 값 처리 (앱 규칙)

- `sugar_g == null`, `caffeine_mg == null`은 **"브랜드 미공개"**다. 0이 아니다.
- 합계에는 0으로 더하되, 해당 음료 표시에는 "미공개"를 남긴다. 사용자가 모르고 계산이 틀렸다고 생각하지 않게.
- 주스·에이드·스무디는 카페인을 게시하지 않는 브랜드가 많다. 당 기록이 이 앱의 본체이므로 이런 행을 버리지 않는다.
- 기록(`Entry`)은 기록 시점 값을 스냅샷한다. 카탈로그가 갱신돼도 과거 기록은 변하지 않는다(SPEC §2.2).
