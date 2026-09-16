"""빽다방 scraper.

Category pages are server-rendered. Each `.menu_list` item carries a hover
card with `※ 컵용량 : 660ml` and an `ingredient_table` (카페인/칼로리/당류...).
The 추천메뉴 swiper on top only repeats main-list items, so it is skipped.
`menu_new` has no list of its own (swiper only) and `menu_dessert` is ice
cream and bakery, so neither is scraped.
"""

from __future__ import annotations

import re

import httpx
from bs4 import BeautifulSoup, Tag

from sugarcap_scrape.http import fetch_text
from sugarcap_scrape.models import Brand, RawServing, Temperature
from sugarcap_scrape.parse import ParseError, clean_text, optional_number

BRAND = Brand(
    id="paik",
    name="빽다방",
    serving_note="1잔 기준 (HOT 510ml·ICED 660ml)",
    has_size_choice=False,
)

BASE_URL = "https://paikdabang.com"
CATEGORY_PATHS = ("/menu/menu_coffee/", "/menu/menu_drink/", "/menu/menu_ccino/")
SIZE_LABEL = "기본"

# "아메리카노(ICED)", "패션후르츠스무디 (ICED)", "챔피언스 블랙 벨벳 라떼 HOT"
_TEMPERATURE_SUFFIX = re.compile(r"\s*\(?\s*(ICED|HOT)\s*\)?\s*$")
_VOLUME = re.compile(r"컵용량\s*:\s*(\d+)")
_SUFFIX_TO_TEMPERATURE = {"HOT": Temperature.HOT, "ICED": Temperature.ICED}


def split_temperature(raw_name: str) -> tuple[str, Temperature]:
    match = _TEMPERATURE_SUFFIX.search(raw_name)
    if match is None:
        return raw_name, Temperature.BOTH
    name = raw_name[: match.start()].strip()
    if not name:
        raise ParseError(f"empty drink name after temperature strip: {raw_name!r}")
    return name, _SUFFIX_TO_TEMPERATURE[match.group(1)]


def parse_category_name(html: str) -> str:
    soup = BeautifulSoup(html, "html.parser")
    heading = soup.select_one(".sub_visual h1")
    if heading is None:
        raise ParseError("category page without .sub_visual h1")
    name = clean_text(heading.get_text())
    if not name:
        raise ParseError("category page with empty h1")
    return name


def _table(item: Tag) -> dict[str, str]:
    """Nutrient label (whitespace removed, e.g. '카페인(mg)') -> published value text."""
    values: dict[str, str] = {}
    for row in item.select("ul.ingredient_table > li"):
        cells = [cell for cell in row.find_all("div", recursive=False) if isinstance(cell, Tag)]
        if len(cells) < 2:
            continue
        key = re.sub(r"\s+", "", cells[0].get_text())
        values[key] = clean_text(cells[1].get_text())
    return values


def _lookup(table: dict[str, str], prefix: str) -> float | None:
    for key, value in table.items():
        if key.startswith(prefix):
            return optional_number(value)
    return None


def _parse_item(item: Tag, *, category: str, source_url: str) -> RawServing:
    title = item.select_one("p.menu_tit")
    if title is None:
        raise ParseError(f"menu item without p.menu_tit ({category})")
    name, temperature = split_temperature(clean_text(title.get_text()))

    en_node = item.select_one(".menu_tit2")
    name_en = clean_text(en_node.get_text()) if en_node is not None else ""

    basis = " ".join(clean_text(p.get_text()) for p in item.select(".menu_ingredient_basis"))
    volume_match = _VOLUME.search(basis)
    table = _table(item)
    return RawServing(
        brand_id=BRAND.id,
        drink_name=name,
        drink_name_en=name_en or None,
        category=category,
        temperature=temperature,
        size_label=SIZE_LABEL,
        volume_ml=int(volume_match.group(1)) if volume_match else None,
        sugar_g=_lookup(table, "당류"),
        caffeine_mg=_lookup(table, "카페인"),
        source_url=source_url,
    )


def parse_menu_page(html: str, *, source_url: str) -> list[RawServing]:
    """Parse one category page. The category name is the page's own h1."""
    category = parse_category_name(html)
    soup = BeautifulSoup(html, "html.parser")
    rows: list[RawServing] = []
    for item in soup.select(".menu_list > ul > li"):
        rows.append(_parse_item(item, category=category, source_url=source_url))
    if not rows:
        raise ParseError(f"{category}: no .menu_list items at {source_url}")
    return rows


def scrape(client: httpx.Client) -> list[RawServing]:
    rows: list[RawServing] = []
    for path in CATEGORY_PATHS:
        url = BASE_URL + path
        rows.extend(parse_menu_page(fetch_text(client, url), source_url=url))
    return rows
