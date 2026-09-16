"""투썸플레이스: the mobile site (`mo.`) is the only one that serves the menu.

www.twosome.co.kr has no menu pages, so everything here talks to `mo.`. Five
calls stack up per drink:

1. `menuInfoMidListAjax.json` (grtCd=1)      -> drink sub-categories
2. `menuInfoListAjax.json`                   -> menu codes, paged via NEXT_PAGE
3. `menuInfoDetail.do`                       -> the temperature tabs (핫/아이스)
4. `menuSizeOptListAjax.json`                -> sizes for that temperature
5. `menuAddInfoCntnListAjax.json`            -> the nutrition rows for that cup

Nutrition is published per (temperature, size), which is why this brand has a
size choice. Values arrive as label/percent pairs ("당류(g/%)": "0/0"); only the
absolute value is kept. A menu whose serving row carries no ml is not a drink
and is skipped. `midCd` is sent empty exactly as the site's own detail page does.
"""

from __future__ import annotations

import json
import logging
import re
import time
from collections.abc import Mapping
from typing import NamedTuple

import httpx
from bs4 import BeautifulSoup

from sugarcap_scrape.http import fetch_text
from sugarcap_scrape.models import Brand, RawServing, Temperature
from sugarcap_scrape.parse import ParseError, clean_text, optional_number

log = logging.getLogger(__name__)

BRAND = Brand(
    id="twosome",
    name="투썸플레이스",
    serving_note="온도·사이즈별 컵용량 기준. 투썸플레이스 모바일 메뉴 페이지 게시값입니다.",
    has_size_choice=True,
)

BASE_URL = "https://mo.twosome.co.kr"
MID_LIST_URL = f"{BASE_URL}/mn/menuInfoMidListAjax.json"
MENU_LIST_URL = f"{BASE_URL}/mn/menuInfoListAjax.json"
DETAIL_URL = f"{BASE_URL}/mn/menuInfoDetail.do"
SIZE_LIST_URL = f"{BASE_URL}/mn/menuSizeOptListAjax.json"
NUTRITION_URL = f"{BASE_URL}/mn/menuAddInfoCntnListAjax.json"

DRINK_GRT_CD = "1"
NEW_CATEGORY = "NEW"
EXCLUDED_CATEGORIES = frozenset({"아이스크림/빙수"})
DEFAULT_SIZE_LABEL = "기본"
SERVING_TITLE = "1회 제공량"
SUGAR_TITLE = "당류(g/%)"
CAFFEINE_TITLE = "카페인(mg/%)"
SUCCESS_CODE = "1000"
REQUEST_PAUSE_SECONDS = 0.15

_LABEL_TO_TEMPERATURE = {"핫": Temperature.HOT, "아이스": Temperature.ICED}
_VOLUME_ML = re.compile(r"(\d+)\s*ml", re.IGNORECASE)


class MidCategory(NamedTuple):
    code: str
    name: str


class MenuItem(NamedTuple):
    code: str
    name: str
    name_en: str | None


class OndoOption(NamedTuple):
    code: str
    label: str


class SizeOption(NamedTuple):
    code: str
    label: str


class Page(NamedTuple):
    items: list[MenuItem]
    next_page: int


def detail_url(menu_cd: str) -> str:
    return str(httpx.URL(DETAIL_URL, params={"menuCd": menu_cd}))


def _objects(text: str, context: str) -> list[Mapping[str, object]]:
    """Read a bare JSON array of objects."""
    payload: object = json.loads(text)
    if not isinstance(payload, list):
        raise ParseError(f"{context}: payload is not an array")
    rows: list[Mapping[str, object]] = []
    for index, item in enumerate(payload):
        if not isinstance(item, dict):
            raise ParseError(f"{context}: [{index}] is not an object")
        rows.append(item)
    return rows


def _fetch_result_set(text: str, context: str) -> list[Mapping[str, object]]:
    """Read the `fetchResultListSet` of a wrapped response, checking the query code."""
    payload: object = json.loads(text)
    if not isinstance(payload, dict):
        raise ParseError(f"{context}: payload is not an object")
    code = payload.get("queryCode")
    if str(code) != SUCCESS_CODE:
        raise ParseError(f"{context}: queryCode {code!r}, message {payload.get('queryMessage')!r}")
    items = payload.get("fetchResultListSet")
    if not isinstance(items, list):
        raise ParseError(f"{context}: response has no 'fetchResultListSet' array")
    rows: list[Mapping[str, object]] = []
    for index, item in enumerate(items):
        if not isinstance(item, dict):
            raise ParseError(f"{context}: fetchResultListSet[{index}] is not an object")
        rows.append(item)
    return rows


def _field(item: Mapping[str, object], key: str, context: str) -> str:
    value = item.get(key)
    if not isinstance(value, str):
        raise ParseError(f"{key}: expected string, got {value!r} ({context})")
    return value


def _int_field(item: Mapping[str, object], key: str, context: str) -> int:
    value = item.get(key)
    if isinstance(value, bool) or not isinstance(value, int):
        raise ParseError(f"{key}: expected int, got {value!r} ({context})")
    return value


def parse_mid_categories(text: str) -> list[MidCategory]:
    """Read the drink sub-categories (커피 / 음료 / 티...)."""
    context = "menuInfoMidListAjax"
    categories = [
        MidCategory(
            code=_field(item, "MID_CD", context), name=clean_text(_field(item, "MID_NM", context))
        )
        for item in _fetch_result_set(text, context)
    ]
    if not categories:
        raise ParseError(f"{context}: no sub-categories for grtCd={DRINK_GRT_CD}")
    return categories


def parse_menu_page(text: str, category: MidCategory) -> Page:
    """Read one page of menu items. `next_page` of 0 means this was the last page."""
    context = f"menuInfoListAjax {category.name}"
    rows = _fetch_result_set(text, context)
    items = [
        MenuItem(
            code=_field(item, "MENU_CD", context),
            name=clean_text(_field(item, "MENU_NM", context)),
            name_en=clean_text(_field(item, "EN_MENU_NM", context)) or None,
        )
        for item in rows
    ]
    next_page = _int_field(rows[0], "NEXT_PAGE", context) if rows else 0
    return Page(items=items, next_page=next_page)


def parse_ondo_options(html: str) -> list[OndoOption]:
    """Read the temperature tabs of a detail page. Empty means the menu has none.

    The page renders the tab block twice (one per layout), so the same tab shows
    up twice and has to be deduplicated or every serving would be built twice.
    """
    soup = BeautifulSoup(html, "html.parser")
    options: list[OndoOption] = []
    seen: set[str] = set()
    for node in soup.select('a[id^="ondo_"]'):
        node_id = node.get("id")
        if not isinstance(node_id, str):
            raise ParseError(f"temperature tab without string id: {node!r}")
        code = node_id.removeprefix("ondo_")
        if code in seen:
            continue
        seen.add(code)
        options.append(OndoOption(code=code, label=clean_text(node.get_text())))
    return options


def parse_size_options(text: str, menu_cd: str) -> list[SizeOption]:
    context = f"menuSizeOptListAjax {menu_cd}"
    return [
        SizeOption(
            code=_field(item, "OPTS", context),
            label=clean_text(_field(item, "SIZE_OPT_NM", context)) or DEFAULT_SIZE_LABEL,
        )
        for item in _objects(text, context)
    ]


def parse_nutrition(text: str, context: str) -> dict[str, str]:
    """Turn the nutrition rows into a {title: value} table."""
    return {
        clean_text(_field(item, "ADD_INFO_TITLE", context)): clean_text(
            _field(item, "MENU_CNTNT", context)
        )
        for item in _objects(text, context)
    }


def temperature_of(label: str) -> Temperature:
    """핫/아이스 tab label -> temperature. Anything else is left unstated."""
    temperature = _LABEL_TO_TEMPERATURE.get(label)
    if temperature is None and label:
        log.warning("twosome: unknown temperature tab %r, recording as both", label)
    return temperature or Temperature.BOTH


def volume_ml(serving: str) -> int | None:
    """ "(컵용량)355ml" -> 355. None means the menu is not served in a cup."""
    match = _VOLUME_ML.search(serving)
    return int(match.group(1)) if match is not None else None


def build_row(
    table: Mapping[str, str],
    *,
    item: MenuItem,
    category: str,
    temperature: Temperature,
    size: SizeOption,
) -> RawServing | None:
    """One nutrition table -> one raw row. None for menus served without a cup."""
    serving = table.get(SERVING_TITLE)
    if serving is None:
        raise ParseError(f"{item.name} ({item.code}): nutrition table without {SERVING_TITLE!r}")
    volume = volume_ml(serving)
    if volume is None:
        return None
    return RawServing(
        brand_id=BRAND.id,
        drink_name=item.name,
        drink_name_en=item.name_en,
        category=category,
        temperature=temperature,
        size_label=size.label,
        volume_ml=volume,
        sugar_g=optional_number(table.get(SUGAR_TITLE)),
        caffeine_mg=optional_number(table.get(CAFFEINE_TITLE)),
        source_url=detail_url(item.code),
    )


def _post(client: httpx.Client, url: str, data: dict[str, str]) -> str:
    text = fetch_text(client, url, method="POST", data=data)
    time.sleep(REQUEST_PAUSE_SECONDS)
    return text


def _menu_items(client: httpx.Client, category: MidCategory) -> list[MenuItem]:
    items: list[MenuItem] = []
    page = 1
    while page:
        data = {"pageNum": str(page), "grtCd": DRINK_GRT_CD, "midCd": category.code}
        parsed = parse_menu_page(_post(client, MENU_LIST_URL, data), category)
        items.extend(parsed.items)
        page = parsed.next_page
    return items


def _menu_rows(
    client: httpx.Client, item: MenuItem, category: str, options: list[OndoOption]
) -> list[RawServing]:
    rows: list[RawServing] = []
    for option in options:
        size_text = _post(
            client,
            SIZE_LIST_URL,
            {"menuCd": item.code, "ondoOpt": option.code, "midCd": ""},
        )
        for size in parse_size_options(size_text, item.code):
            context = f"{item.name} {option.code}/{size.code}"
            table = parse_nutrition(
                _post(
                    client,
                    NUTRITION_URL,
                    {
                        "menuCd": item.code,
                        "ondoOpt": option.code,
                        "sizeOpt": size.code,
                        "midCd": "",
                    },
                ),
                context,
            )
            if not table:
                log.warning("twosome: no nutrition published for %s", context)
                continue
            row = build_row(
                table,
                item=item,
                category=category,
                temperature=temperature_of(option.label),
                size=size,
            )
            if row is not None:
                rows.append(row)
    return rows


def scrape(client: httpx.Client) -> list[RawServing]:
    categories = parse_mid_categories(
        _post(client, MID_LIST_URL, {"grtCd": DRINK_GRT_CD}),
    )
    # NEW repeats items from the real sub-categories; visit it last so an item
    # keeps its own category and only new-only items come from the showcase.
    ordered = sorted(categories, key=lambda category: category.name == NEW_CATEGORY)
    seen: set[str] = set()
    rows: list[RawServing] = []
    for category in ordered:
        if category.name in EXCLUDED_CATEGORIES:
            continue
        for item in _menu_items(client, category):
            if item.code in seen:
                continue
            seen.add(item.code)
            html = fetch_text(client, detail_url(item.code))
            time.sleep(REQUEST_PAUSE_SECONDS)
            options = parse_ondo_options(html) or [OndoOption(code="", label="")]
            rows.extend(_menu_rows(client, item, category.name, options))
    return rows
