from __future__ import annotations

import httpx
import pytest

from sugarcap_scrape.brands.parisbaguette import (
    BRAND,
    classify_temperature,
    parse_caffeine,
    parse_list,
    parse_product_page,
    parse_sugar,
    parse_volume_ml,
    scrape,
)
from sugarcap_scrape.models import Temperature

URL = "https://www.paris.co.kr/product/hot-caramel-macchiato-2/"


def _box(cls: str, title: str, *paragraphs: str) -> str:
    body = "".join(f"<p>{p}</p>" for p in paragraphs)
    return (
        f'<div class="product-info-group {cls}"><h4 class="product-info-group-title">{title}</h4>'
        f'<div class="product-info-group-description">{body}</div></div>'
    )


AMERICANO = (
    _box(
        "product-nutrition",
        "영양정보",
        "총 내용량: 280g · 총 내용량당 칼로리(kcal): 15",
        "총 내용량당 - 나트륨(mg): 10 · 당류(g): 0 · 포화지방(g): 0 · 단백질(g): 1",
    )
    + _box("product-allergy", "알레르기 정보", "총 카페인 함량 224mg, 고카페인 함유(어린이…)")
    + _box("product-features", "추가정보", "카페인 212.52mg, 고카페인 함유 “어린이…“")
)


def test_brand_contract() -> None:
    assert BRAND.id == "parisbaguette"
    assert BRAND.has_size_choice is False


def test_conflicting_caffeine_keeps_the_largest() -> None:
    row = parse_product_page(AMERICANO, name="아메리카노", category="카페 아다지오", source_url=URL)
    assert (row.sugar_g, row.caffeine_mg, row.volume_ml) == (0, 224, None)
    assert row.temperature is Temperature.BOTH


@pytest.mark.parametrize(
    ("text", "caffeine"),
    [
        ("카페인함량(mg/1컵) : 23.4mg", 23.4),
        ("1회 제공량당 - 나트륨(mg) : 0/0.0 · 당류(g) : / 0/0 · 카페인(mg) : 25", 25),
        ("카페인 53mg, 고카페인 함유. 어린이, 임산부, 카페인 민감자는 섭취에 주의", 53),
        ("고카페인 함유", None),
        ("", None),
    ],
)
def test_caffeine_spellings(text: str, caffeine: float | None) -> None:
    assert parse_caffeine([text]) == caffeine


@pytest.mark.parametrize(
    ("text", "sugar"),
    [
        ("총 내용량당 - 나트륨(mg): 115 · 당류(g): 25 · 포화지방(g): 4.5", 25),
        ("1회 제공량당 - 나트륨(mg) : 15 · 당류(g) : | 47 | · 포화지방(g) : 0", 47),
        ("1회 제공량당 - 나트륨(mg) : 0/0.0 · 당류(g) : / | 0/0 |", 0),
        ("총 내용량당 - 나트륨(mg): 제품 뒷면참조 · 당류(g): 제품 뒷면참조", None),
        ("총 내용량: 325g · 100g당 칼로리(kcal): 0 | 100g당 - 당류(g): 0", None),
        ("", None),
    ],
)
def test_sugar_readings(text: str, sugar: float | None) -> None:
    assert parse_sugar(text) == sugar


def test_volume_only_in_ml() -> None:
    assert parse_volume_ml("총 내용량: 190ml · 총 내용량당 칼로리(kcal): 134") == 190
    assert parse_volume_ml("총 내용량: 280g · 총 내용량당 칼로리(kcal): 15") is None


def test_page_without_nutrition_is_kept_unpublished() -> None:
    row = parse_product_page("<div></div>", name="리얼 딸기라떼", category="라떼류", source_url=URL)
    assert (row.sugar_g, row.caffeine_mg) == (None, None)


def test_temperature_from_name() -> None:
    assert classify_temperature("아이스초코포레누아") is Temperature.ICED
    assert classify_temperature("빅 아이스 아메리카노") is Temperature.ICED
    assert classify_temperature("복숭아 아이스티") is Temperature.BOTH


def test_list_fragment() -> None:
    html = (
        '<ul data-total-count="1"><li><a href="https://www.paris.co.kr/product/x/" '
        'class="product-list-item"><div class="desc"><h3 class="product-name">아메리카노</h3>'
        "</div></a></li></ul>"
    )
    assert parse_list(html) == [("https://www.paris.co.kr/product/x/", "아메리카노")]


@pytest.mark.live
def test_scrape_live(client: httpx.Client) -> None:
    rows = scrape(client)
    assert len(rows) >= 50
    assert {r.brand_id for r in rows} == {BRAND.id}
    keys = [(r.drink_name, r.temperature) for r in rows]
    assert len(keys) == len(set(keys))
    assert sum(r.sugar_g is not None for r in rows) >= len(rows) * 0.7
    assert "빙수" not in {r.category for r in rows}
    americano = next(r for r in rows if r.drink_name == "아메리카노")
    assert americano.sugar_g == 0 and americano.caffeine_mg is not None
