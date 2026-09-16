from __future__ import annotations

import json

import httpx
import pytest

from sugarcap_scrape.brands.starbucks import (
    BRAND,
    CATEGORY_JSON_URL,
    LIST_URL,
    Category,
    classify_temperature,
    drop_duplicate_names,
    parse_categories,
    parse_category_json,
    scrape,
)
from sugarcap_scrape.http import fetch_text
from sugarcap_scrape.models import RawServing, Temperature
from sugarcap_scrape.parse import ParseError

ESPRESSO = Category(key="product_espresso", code="W0000003", name="에스프레소")


def _by_name(rows: list[RawServing], name: str) -> RawServing:
    matches = [row for row in rows if row.drink_name == name]
    assert len(matches) == 1, f"{name}: {len(matches)} rows"
    return matches[0]


def _payload(*items: dict[str, str]) -> str:
    return json.dumps({"list": list(items)}, ensure_ascii=False)


def _item(name: str, **overrides: str) -> dict[str, str]:
    base = {
        "product_CD": "1",
        "product_NM": name,
        "product_ENGNM": "",
        "sugars": "10",
        "caffeine": "75",
    }
    return {**base, **overrides}


def test_brand_contract() -> None:
    assert BRAND.id == "starbucks"
    assert BRAND.has_size_choice is False


def test_empty_nutrition_strings_become_none() -> None:
    rows = parse_category_json(
        _payload(_item("에스프레소 플라이트", sugars="", caffeine="")), ESPRESSO
    )
    assert rows[0].sugar_g is None
    assert rows[0].caffeine_mg is None


def test_bom_and_trailing_space_in_name_are_tolerated() -> None:
    rows = parse_category_json("﻿" + _payload(_item("브루드 커피 ")), ESPRESSO)
    assert rows[0].drink_name == "브루드 커피"
    assert rows[0].drink_name_en is None
    assert rows[0].size_label == "Tall"
    assert rows[0].volume_ml == 355
    assert rows[0].source_url.endswith("product_cd=1")


def test_payload_without_list_raises() -> None:
    with pytest.raises(ParseError, match="no 'list' array"):
        parse_category_json('{"rows": []}', ESPRESSO)


def test_non_string_field_raises() -> None:
    with pytest.raises(ParseError, match="sugars"):
        parse_category_json(
            '{"list": [{"product_CD": "1", "product_NM": "x", "product_ENGNM": "", "sugars": 3}]}',
            ESPRESSO,
        )


def test_classify_temperature() -> None:
    assert classify_temperature("아이스 카페 라떼", "에스프레소") is Temperature.ICED
    assert classify_temperature("복숭아 아이스 티", "티(티바나)") is Temperature.ICED
    assert classify_temperature("카페 라떼", "에스프레소") is Temperature.BOTH
    assert classify_temperature("자바 칩 프라푸치노", "프라푸치노") is Temperature.ICED
    assert classify_temperature("아이스크림 라떼", "에스프레소") is Temperature.BOTH


def test_drop_duplicate_names_keeps_first() -> None:
    rows = parse_category_json(
        _payload(_item("콜드 브루", product_CD="a"), _item("콜드 브루", product_CD="b")), ESPRESSO
    )
    kept = drop_duplicate_names(rows)
    assert len(kept) == 1
    assert kept[0].source_url.endswith("product_cd=a")


def test_categories_without_mapping_raise() -> None:
    with pytest.raises(ParseError, match="no category code mapping"):
        parse_categories("<html></html>")


@pytest.fixture(scope="module")
def list_html(client: httpx.Client) -> str:
    return fetch_text(client, LIST_URL)


@pytest.fixture(scope="module")
def espresso_rows(client: httpx.Client) -> list[RawServing]:
    text = fetch_text(client, CATEGORY_JSON_URL.format(code=ESPRESSO.code), encoding="utf-8")
    return parse_category_json(text, ESPRESSO)


@pytest.mark.live
def test_parse_categories_live(list_html: str) -> None:
    categories = parse_categories(list_html)
    assert ESPRESSO in categories
    assert all(category.key != "product_all" for category in categories)
    assert len(categories) >= 10


@pytest.mark.live
def test_parse_espresso_json_live(espresso_rows: list[RawServing]) -> None:
    assert len(espresso_rows) >= 40
    americano = _by_name(espresso_rows, "아이스 카페 아메리카노")
    assert americano.sugar_g == 0
    assert americano.caffeine_mg == 150
    assert americano.temperature is Temperature.ICED
    assert (
        americano.source_url == "https://www.starbucks.co.kr/menu/drink_view.do?product_cd=110563"
    )
    latte = _by_name(espresso_rows, "카페 라떼")
    assert latte.sugar_g == 13
    assert latte.caffeine_mg == 75
    assert latte.source_url.endswith("product_cd=41")
    assert latte.category == "에스프레소"


@pytest.mark.live
def test_scrape_live(client: httpx.Client) -> None:
    rows = scrape(client)
    assert len(rows) >= 80
    assert {row.brand_id for row in rows} == {BRAND.id}
    assert {(row.size_label, row.volume_ml) for row in rows} == {("Tall", 355)}
    keys = [(row.drink_name, row.temperature) for row in rows]
    assert len(keys) == len(set(keys))
    americano = _by_name(rows, "아이스 카페 아메리카노")
    assert (americano.sugar_g, americano.caffeine_mg) == (0, 150)
    latte = _by_name(rows, "카페 라떼")
    assert (latte.sugar_g, latte.caffeine_mg) == (13, 75)
    assert {"에스프레소", "콜드 브루 커피", "프라푸치노", "티(티바나)"} <= {
        row.category for row in rows
    }
