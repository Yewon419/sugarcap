"""컴포즈커피: XE gallery list pages -> one detail page per item with a nutrition grid.

Every drink is published at a single cup size, so `size_label` is always "기본"
and `volume_ml` is the detail page's "컵용량". Temperature comes from the
"I-"/"H-" name prefix; items without a prefix (프라페, 에이드, 에스프레소...) are
recorded as `Temperature.BOTH` because the brand does not state it.
Items whose nutrition grid has "무게" instead of "컵용량" are food and skipped.
"""

from __future__ import annotations

import re
import time
from typing import NamedTuple

import httpx
from bs4 import BeautifulSoup, Tag

from sugarcap_scrape.http import fetch_text
from sugarcap_scrape.models import Brand, RawServing, Temperature
from sugarcap_scrape.parse import ParseError, clean_text, first_number, optional_number

BRAND = Brand(
    id="compose",
    name="컴포즈커피",
    serving_note="컵용량 기준(사이즈 1종). 당류가 공개되지 않은 음료는 당류 없음으로 표시됩니다.",
    has_size_choice=False,
)

BASE_URL = "https://composecoffee.com/index.php"
ENTRY_CATEGORY_SRL = "303364"
SIZE_LABEL = "기본"
EXCLUDED_CATEGORIES = frozenset({"푸드ㆍ디저트", "아이스크림"})
REQUEST_PAUSE_SECONDS = 0.2

_TEMPERATURE_PREFIX = re.compile(r"^([IH])\s*-\s*")
_PREFIX_TO_TEMPERATURE = {"I": Temperature.ICED, "H": Temperature.HOT}
_CATEGORY_SRL = re.compile(r"category_srl=(\d+)")
_ITEM_SRL = re.compile(r"item_srl=(\d+)")


class Category(NamedTuple):
    srl: str
    name: str


class ListItem(NamedTuple):
    item_srl: str
    name: str


def list_url(category_srl: str, page: int) -> str:
    params = {
        "mid": "compose",
        "act": "dispCafemenuGalleryList",
        "category_srl": category_srl,
        "page": str(page),
    }
    return str(httpx.URL(BASE_URL, params=params))


def item_url(category_srl: str, item_srl: str) -> str:
    params = {
        "mid": "compose",
        "act": "dispCafemenuGalleryItem",
        "category_srl": category_srl,
        "item_srl": item_srl,
    }
    return str(httpx.URL(BASE_URL, params=params))


def _href(node: Tag) -> str:
    href = node.get("href")
    if not isinstance(href, str):
        raise ParseError(f"anchor without string href: {node!r}")
    return href


def parse_categories(html: str) -> list[Category]:
    """Read the category buttons of a list page (name + srl), in page order."""
    soup = BeautifulSoup(html, "html.parser")
    categories: list[Category] = []
    for node in soup.select("a.cafemenu-category-btn"):
        match = _CATEGORY_SRL.search(_href(node))
        if match is None:
            # The "전체" button links to the unfiltered list and carries no srl.
            continue
        categories.append(Category(srl=match.group(1), name=clean_text(node.get_text())))
    if not categories:
        raise ParseError("no category buttons found on list page")
    return categories


def parse_list_items(html: str) -> list[ListItem]:
    """Read the menu items of one list page. Empty list means past the last page."""
    soup = BeautifulSoup(html, "html.parser")
    items: list[ListItem] = []
    for node in soup.select("a.cafemenu-menu-item"):
        match = _ITEM_SRL.search(_href(node))
        if match is None:
            raise ParseError(f"menu item without item_srl: {node!r}")
        name_node = node.select_one(".cafemenu-menu-name")
        if not isinstance(name_node, Tag):
            raise ParseError(f"menu item {match.group(1)} without name")
        items.append(ListItem(item_srl=match.group(1), name=clean_text(name_node.get_text())))
    return items


def split_name(raw_name: str) -> tuple[str, Temperature]:
    """ "I-카페라떼" -> ("카페라떼", ICED). No prefix -> BOTH."""
    name = clean_text(raw_name)
    match = _TEMPERATURE_PREFIX.match(name)
    if match is None:
        return name, Temperature.BOTH
    return name[match.end() :].strip(), _PREFIX_TO_TEMPERATURE[match.group(1)]


def _nutrition_table(soup: BeautifulSoup) -> dict[str, str]:
    table: dict[str, str] = {}
    for item in soup.select(".cafemenu-nutrition-item"):
        label = item.select_one(".cafemenu-nutrition-label")
        value = item.select_one(".cafemenu-nutrition-value")
        if not isinstance(label, Tag) or not isinstance(value, Tag):
            raise ParseError(f"nutrition item without label/value: {item!r}")
        table[clean_text(label.get_text())] = clean_text(value.get_text(" "))
    return table


def parse_item(html: str, *, category: str, source_url: str) -> list[RawServing]:
    """Parse one detail page. Returns [] for non-drink items (no "컵용량" row)."""
    soup = BeautifulSoup(html, "html.parser")
    title = soup.select_one("h1.cafemenu-detail-title")
    if not isinstance(title, Tag):
        raise ParseError(f"detail page without title ({source_url})")
    table = _nutrition_table(soup)
    if "컵용량" not in table:
        return []
    name, temperature = split_name(title.get_text())
    context = f"{name} {source_url}"
    volume = first_number(table["컵용량"], field="컵용량", context=context)
    caffeine_text = table.get("카페인")
    return [
        RawServing(
            brand_id=BRAND.id,
            drink_name=name,
            category=category,
            temperature=temperature,
            size_label=SIZE_LABEL,
            volume_ml=int(volume),
            sugar_g=optional_number(table.get("당류")),
            caffeine_mg=(
                first_number(caffeine_text, field="카페인", context=context)
                if caffeine_text is not None
                else None
            ),
            source_url=source_url,
        )
    ]


def _list_category_items(client: httpx.Client, category: Category) -> list[ListItem]:
    items: list[ListItem] = []
    page = 1
    while True:
        page_items = parse_list_items(fetch_text(client, list_url(category.srl, page)))
        time.sleep(REQUEST_PAUSE_SECONDS)
        if not page_items:
            return items
        items.extend(page_items)
        page += 1


def scrape(client: httpx.Client) -> list[RawServing]:
    categories = parse_categories(fetch_text(client, list_url(ENTRY_CATEGORY_SRL, 1)))
    time.sleep(REQUEST_PAUSE_SECONDS)
    # 추천메뉴 is a mixed showcase; visit it last so items also listed under a
    # proper category keep that category and only recommendation-exclusive ones remain.
    ordered = sorted(categories, key=lambda c: c.name == "추천메뉴")
    seen: set[str] = set()
    rows: list[RawServing] = []
    for category in ordered:
        if category.name in EXCLUDED_CATEGORIES:
            continue
        for item in _list_category_items(client, category):
            if item.item_srl in seen:
                continue
            seen.add(item.item_srl)
            url = item_url(category.srl, item.item_srl)
            rows.extend(parse_item(fetch_text(client, url), category=category.name, source_url=url))
            time.sleep(REQUEST_PAUSE_SECONDS)
    return rows
