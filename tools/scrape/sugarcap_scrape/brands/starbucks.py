"""Starbucks Korea: category codes from the drink list page, nutrition from per-category JSON.

Every product is a separate row in Tall (355ml). Hot and iced versions are
separate products (the iced one carries "아이스" in its name).
"""

from __future__ import annotations

import json
import logging
import re
from collections.abc import Mapping
from typing import NamedTuple

import httpx

from sugarcap_scrape.http import fetch_text
from sugarcap_scrape.models import Brand, RawServing, Temperature
from sugarcap_scrape.parse import ParseError, clean_text, optional_number

log = logging.getLogger(__name__)

BRAND = Brand(
    id="starbucks",
    name="스타벅스",
    serving_note="Tall 355ml 기준",
    has_size_choice=False,
)

LIST_URL = "https://www.starbucks.co.kr/menu/drink_list.do"
CATEGORY_JSON_URL = "https://www.starbucks.co.kr/upload/json/menu/{code}.js"
DETAIL_URL = "https://www.starbucks.co.kr/menu/drink_view.do?product_cd={product_cd}"
SIZE_LABEL = "Tall"
VOLUME_ML = 355

# Sections whose drinks are only served cold; product names there carry no "아이스" marker.
ICED_ONLY_CATEGORIES = frozenset(
    {"콜드 브루 커피", "프라푸치노", "블렌디드", "스타벅스 리프레셔", "스타벅스 피지오"}
)

_CODE_MAPPING = re.compile(r'tmp_cate\s*==\s*"(product_\w+)"\)\s*\{\s*result\s*=\s*"(W\d+)"')
_LABEL = re.compile(r'<label for="(product_\w+)">([^<]+)</label>')


class Category(NamedTuple):
    key: str
    code: str
    name: str


def parse_categories(html: str) -> list[Category]:
    """Read (checkbox key, JSON code, Korean label) triples from the drink list page."""
    labels = {key: clean_text(name) for key, name in _LABEL.findall(html)}
    categories: list[Category] = []
    for key, code in _CODE_MAPPING.findall(html):
        if key not in labels:
            raise ParseError(f"category {key} ({code}) has no label on {LIST_URL}")
        categories.append(Category(key=key, code=code, name=labels[key]))
    if not categories:
        raise ParseError(f"no category code mapping found on {LIST_URL}")
    return categories


def _field(item: Mapping[str, object], key: str, context: str) -> str:
    value = item.get(key)
    if not isinstance(value, str):
        raise ParseError(f"{key}: expected string, got {value!r} ({context})")
    return value


def classify_temperature(name: str, category: str) -> Temperature:
    tokens = name.split()
    if "아이스" in tokens:
        return Temperature.ICED
    if "핫" in tokens:
        return Temperature.HOT
    if category in ICED_ONLY_CATEGORIES:
        return Temperature.ICED
    return Temperature.BOTH


def parse_category_json(text: str, category: Category) -> list[RawServing]:
    """Turn one category JSON payload into raw rows. Empty nutrition strings become None."""
    payload: object = json.loads(text.lstrip("﻿"))
    if not isinstance(payload, dict):
        raise ParseError(f"{category.code}: payload is not an object")
    items = payload.get("list")
    if not isinstance(items, list):
        raise ParseError(f"{category.code}: payload has no 'list' array")

    rows: list[RawServing] = []
    for index, item in enumerate(items):
        if not isinstance(item, dict):
            raise ParseError(f"{category.code}: list[{index}] is not an object")
        context = f"{category.code} list[{index}]"
        product_cd = _field(item, "product_CD", context)
        name = clean_text(_field(item, "product_NM", context))
        if not product_cd or not name:
            raise ParseError(f"empty product_CD or product_NM ({context})")
        name_en = clean_text(_field(item, "product_ENGNM", context)) or None
        rows.append(
            RawServing(
                brand_id=BRAND.id,
                drink_name=name,
                drink_name_en=name_en,
                category=category.name,
                temperature=classify_temperature(name, category.name),
                size_label=SIZE_LABEL,
                volume_ml=VOLUME_ML,
                sugar_g=optional_number(_field(item, "sugars", context)),
                caffeine_mg=optional_number(_field(item, "caffeine", context)),
                source_url=DETAIL_URL.format(product_cd=product_cd),
            )
        )
    return rows


def drop_duplicate_names(rows: list[RawServing]) -> list[RawServing]:
    """Keep the first row per (name, temperature); the site lists a few products twice."""
    seen: dict[tuple[str, Temperature], RawServing] = {}
    kept: list[RawServing] = []
    for row in rows:
        key = (row.drink_name, row.temperature)
        first = seen.get(key)
        if first is not None:
            log.warning(
                "starbucks: duplicate name %r, keeping %s and dropping %s",
                row.drink_name,
                first.source_url,
                row.source_url,
            )
            continue
        seen[key] = row
        kept.append(row)
    return kept


def scrape(client: httpx.Client) -> list[RawServing]:
    categories = parse_categories(fetch_text(client, LIST_URL))
    rows: list[RawServing] = []
    for category in categories:
        url = CATEGORY_JSON_URL.format(code=category.code)
        rows.extend(parse_category_json(fetch_text(client, url, encoding="utf-8"), category))
    return drop_duplicate_names(rows)
