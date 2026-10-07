from __future__ import annotations

import json

import httpx
import pytest

from sugarcap_scrape.brands.us_starbucks import (
    BRAND,
    MENU_URL,
    PRODUCT_URL,
    MenuProduct,
    parse_menu,
    parse_product,
    scrape,
    volume_ml,
)
from sugarcap_scrape.http import fetch_text
from sugarcap_scrape.models import Temperature
from sugarcap_scrape.parse import ParseError

LATTE = MenuProduct(number=407, form="Hot", name="Caffè Latte", category="Lattes")

type Json = bool | int | float | str | list[Json] | dict[str, Json] | None


def _product(name: str, number: int, form: str, kind: str = "Beverage") -> dict[str, Json]:
    return {"name": name, "productNumber": number, "formCode": form, "productType": kind}


def _menu(*menus: tuple[str, str, list[dict[str, Json]]]) -> str:
    return json.dumps(
        {
            "menus": [
                {"name": menu, "children": [{"name": category, "products": products}]}
                for menu, category, products in menus
            ]
        }
    )


def _size(code: str, display: str | None, sugar: float | None, caffeine: float | None) -> Json:
    facts: list[Json] = [
        {"id": "totalCarbs", "value": 20, "subfacts": [{"id": "sugars", "value": sugar}]}
    ]
    facts.append({"id": "caffeine", "value": caffeine})
    serving: Json = None if display is None else {"displayValue": display}
    return {"sizeCode": code, "nutrition": {"servingSize": serving, "additionalFacts": facts}}


def _detail(*sizes: Json) -> str:
    return json.dumps({"products": [{"sizes": list(sizes)}]})


def test_brand_contract() -> None:
    assert BRAND.id == "us-starbucks"
    assert BRAND.has_size_choice is True


def test_fl_oz_is_converted_to_ml() -> None:
    assert volume_ml(" 12 fl oz") == 355
    assert volume_ml("16 fl oz") == 473
    assert volume_ml("1.5 fl oz") == 44
    assert volume_ml("1 shot") is None


def test_menu_keeps_made_to_order_drinks_once_under_their_own_category() -> None:
    text = _menu(
        ("The Latest", "Fall", [_product("Pumpkin Spice Latte", 2123, "Hot")]),
        (
            "Drinks",
            "Lattes",
            [
                _product("Pumpkin Spice Latte", 2123, "Hot"),
                _product("Bottled Frappuccino", 9, "Packaged"),
                _product("Croissant", 10, "Single", kind="Food"),
            ],
        ),
    )
    assert parse_menu(text) == [
        MenuProduct(number=2123, form="Hot", name="Pumpkin Spice Latte", category="Lattes")
    ]


def test_menu_without_beverages_raises() -> None:
    with pytest.raises(ParseError):
        parse_menu(_menu(("Food", "Bakery", [_product("Croissant", 10, "Single", kind="Food")])))


def test_product_rows_per_size_with_unpublished_values_left_none() -> None:
    rows = parse_product(
        _detail(
            _size("Tall", " 12 fl oz", 14, 75),
            _size("Grande", "16 fl oz", None, None),
            _size("Traveler", "96 fl oz", 0, 1000),
        ),
        LATTE,
    )
    assert [(r.size_label, r.volume_ml, r.sugar_g, r.caffeine_mg) for r in rows] == [
        ("Tall", 355, 14.0, 75.0),
        ("Grande", 473, None, None),
    ]
    assert rows[0].temperature is Temperature.HOT
    assert rows[0].source_url == "https://www.starbucks.com/menu/product/407/hot"


def test_non_numeric_nutrition_raises() -> None:
    bad = json.dumps(
        {
            "products": [
                {
                    "sizes": [
                        {
                            "sizeCode": "Tall",
                            "nutrition": {"additionalFacts": [{"id": "caffeine", "value": "75"}]},
                        }
                    ]
                }
            ]
        }
    )
    with pytest.raises(ParseError):
        parse_product(bad, LATTE)


@pytest.mark.live
def test_live_latte_matches_published_values(client: httpx.Client) -> None:
    text = fetch_text(client, PRODUCT_URL.format(number=407, form="hot"))
    rows = {row.size_label: row for row in parse_product(text, LATTE)}
    assert rows["Grande"].volume_ml == 473
    assert rows["Grande"].sugar_g is not None
    assert rows["Grande"].caffeine_mg == 150.0


@pytest.mark.live
def test_live_menu_has_most_of_the_drinks(client: httpx.Client) -> None:
    products = parse_menu(fetch_text(client, MENU_URL))
    assert len(products) >= 120
    assert {p.form for p in products} == {"Hot", "Iced"}


@pytest.mark.live
def test_live_scrape(client: httpx.Client) -> None:
    rows = scrape(client)
    assert len(rows) >= 300
    assert sum(1 for row in rows if row.sugar_g is not None) >= len(rows) * 0.9
    assert all(row.volume_ml is None or 20 <= row.volume_ml <= 1200 for row in rows)
