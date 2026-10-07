"""Starbucks US: the ordering menu tree, then one product JSON per (product, form).

The menu lists every product with its form code (`Hot`, `Iced`, `Packaged`, ...).
Nutrition lives on the product endpoint, one block per size, with sugar under
`totalCarbs.subfacts[sugars]` and caffeine as its own fact. Cup volume is only
published as "12 fl oz"; SPEC §9.9 allows converting that unit to ml.

Kept: made-to-order beverages (`Hot`, `Iced`). Dropped: bottled third-party
drinks (`Packaged`), food, whole bean, and the 96 fl oz Coffee Traveler box,
which is not a single cup.
"""

from __future__ import annotations

import json
import logging
import re
from collections.abc import Mapping, Sequence
from typing import NamedTuple

import httpx

from sugarcap_scrape.http import fetch_text
from sugarcap_scrape.models import Brand, RawServing, Temperature
from sugarcap_scrape.parse import ParseError, clean_text

log = logging.getLogger(__name__)

BRAND = Brand(
    id="us-starbucks",
    name="Starbucks",
    serving_note="Per cup size, as published",
    has_size_choice=True,
)

MENU_URL = "https://www.starbucks.com/apiproxy/v1/ordering/menu"
PRODUCT_URL = "https://www.starbucks.com/apiproxy/v1/ordering/{number}/{form}"
SOURCE_URL = "https://www.starbucks.com/menu/product/{number}/{form}"
FORMS = {"Hot": Temperature.HOT, "Iced": Temperature.ICED}
# The seasonal shelf repeats products filed under their own category elsewhere.
SHELF_MENUS = frozenset({"The Latest"})
EXCLUDED_SIZES = frozenset({"Traveler"})
ML_PER_US_FL_OZ = 29.5735

_FL_OZ = re.compile(r"(\d+(?:\.\d+)?)\s*fl\s*oz", re.IGNORECASE)

type Json = bool | int | float | str | list[Json] | dict[str, Json] | None


class MenuProduct(NamedTuple):
    number: int
    form: str
    name: str
    category: str


def _obj(value: Json, context: str) -> dict[str, Json]:
    if not isinstance(value, dict):
        raise ParseError(f"expected object, got {type(value).__name__} ({context})")
    return value


def _list(value: Json, context: str) -> list[Json]:
    if not isinstance(value, list):
        raise ParseError(f"expected array, got {type(value).__name__} ({context})")
    return value


def _str(item: Mapping[str, Json], key: str, context: str) -> str:
    value = item.get(key)
    if not isinstance(value, str):
        raise ParseError(f"{key}: expected string, got {value!r} ({context})")
    return value


def _walk(node: Mapping[str, Json], menu: str, found: list[tuple[str, MenuProduct]]) -> None:
    for child_value in _list(node.get("children", []), menu):
        child = _obj(child_value, menu)
        category = clean_text(_str(child, "name", menu))
        for product_value in _list(child.get("products", []), f"{menu} > {category}"):
            product = _obj(product_value, category)
            if product.get("productType") != "Beverage":
                continue
            number = product.get("productNumber")
            if not isinstance(number, int):
                raise ParseError(f"productNumber: expected int, got {number!r} ({category})")
            found.append(
                (
                    menu,
                    MenuProduct(
                        number=number,
                        form=_str(product, "formCode", category),
                        name=clean_text(_str(product, "name", category)),
                        category=category,
                    ),
                )
            )
        _walk(child, menu, found)


def parse_menu(text: str) -> list[MenuProduct]:
    """Every made-to-order beverage once, filed under its own category before the seasonal shelf."""
    payload = _obj(json.loads(text), MENU_URL)
    found: list[tuple[str, MenuProduct]] = []
    for menu_value in _list(payload.get("menus"), MENU_URL):
        menu = _obj(menu_value, MENU_URL)
        _walk(menu, clean_text(_str(menu, "name", MENU_URL)), found)
    if not found:
        raise ParseError(f"no beverages in {MENU_URL}")
    ordered = [p for menu, p in found if menu not in SHELF_MENUS] + [
        p for menu, p in found if menu in SHELF_MENUS
    ]
    seen: set[tuple[int, str]] = set()
    products: list[MenuProduct] = []
    for product in ordered:
        key = (product.number, product.form)
        if key in seen or product.form not in FORMS:
            continue
        seen.add(key)
        products.append(product)
    return products


def volume_ml(serving_size: str) -> int | None:
    """'12 fl oz' -> 355. None when the size is not published in fl oz."""
    match = _FL_OZ.search(serving_size)
    if match is None:
        return None
    return round(float(match.group(1)) * ML_PER_US_FL_OZ)


def _fact_value(facts: Sequence[Json], fact_id: str, context: str) -> float | None:
    for fact_value in facts:
        fact = _obj(fact_value, context)
        if fact.get("id") == fact_id:
            return _number(fact.get("value"), fact_id, context)
    return None


def _number(value: Json, field: str, context: str) -> float | None:
    if value is None:
        return None
    if isinstance(value, bool) or not isinstance(value, int | float):
        raise ParseError(f"{field}: expected number, got {value!r} ({context})")
    return float(value)


def _sugar(facts: Sequence[Json], context: str) -> float | None:
    for fact_value in facts:
        fact = _obj(fact_value, context)
        if fact.get("id") == "totalCarbs":
            return _fact_value(_list(fact.get("subfacts", []), context), "sugars", context)
    return None


def parse_product(text: str, product: MenuProduct) -> list[RawServing]:
    """One row per published size of one (product, form)."""
    context = f"{product.name} ({product.number}/{product.form})"
    payload = _obj(json.loads(text), context)
    entries = _list(payload.get("products"), context)
    if len(entries) != 1:
        raise ParseError(f"expected one product, got {len(entries)} ({context})")
    sizes = _list(_obj(entries[0], context).get("sizes"), context)
    rows: list[RawServing] = []
    for size_value in sizes:
        size = _obj(size_value, context)
        label = _str(size, "sizeCode", context)
        if label in EXCLUDED_SIZES:
            continue
        where = f"{context} {label}"
        nutrition = _obj(size.get("nutrition") or {}, where)
        facts = _list(nutrition.get("additionalFacts", []), where)
        serving = nutrition.get("servingSize")
        display = _obj(serving, where).get("displayValue") if serving is not None else None
        rows.append(
            RawServing(
                brand_id=BRAND.id,
                drink_name=product.name,
                category=product.category,
                temperature=FORMS[product.form],
                size_label=label,
                volume_ml=volume_ml(display) if isinstance(display, str) else None,
                sugar_g=_sugar(facts, where),
                caffeine_mg=_fact_value(facts, "caffeine", where),
                source_url=SOURCE_URL.format(number=product.number, form=product.form.lower()),
            )
        )
    if not rows:
        log.warning("us-starbucks: %s has no cup sizes", context)
    return rows


def scrape(client: httpx.Client) -> list[RawServing]:
    products = parse_menu(fetch_text(client, MENU_URL))
    rows: list[RawServing] = []
    for product in products:
        url = PRODUCT_URL.format(number=product.number, form=product.form.lower())
        rows.extend(parse_product(fetch_text(client, url), product))
    return rows
