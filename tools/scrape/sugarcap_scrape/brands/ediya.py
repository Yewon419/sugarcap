"""이디야커피: category checkboxes on drink.html -> paged AJAX list with inline nutrition.

The AJAX endpoint only filters by category when `chked_val` carries the trailing
comma the site's own JS appends ("12," not "12"); without it every category
returns the full menu. Pages hold 8 items and the endpoint answers "none" past
the last page. The list is sorted new-first and repeats some items across page
boundaries, so rows are deduplicated on (name, size, temperature).

Names look like "(L) HOT 카페 아메리카노": size in parentheses, then an optional
HOT/ICED token. Items without the token (콜드브루, 주스...) are recorded as
`Temperature.BOTH` because the brand does not state it. Volume is the item's
"컵용량 : 520ml" line; a gram value (food-like items) yields `volume_ml=None`.
"""

from __future__ import annotations

import re
import time
from typing import NamedTuple

import httpx
from bs4 import BeautifulSoup, Tag
from bs4.element import NavigableString

from sugarcap_scrape.http import fetch_text
from sugarcap_scrape.models import Brand, RawServing, Temperature
from sugarcap_scrape.parse import ParseError, clean_text, optional_number

BRAND = Brand(
    id="ediya",
    name="이디야커피",
    serving_note="사이즈 L/EX별 컵용량 기준. 값은 이디야 공식 메뉴 페이지에 게시된 그대로입니다.",
    has_size_choice=True,
)

SHELL_URL = "https://ediya.com/contents/drink.html"
AJAX_URL = "https://ediya.com/inc/ajax_brand.php"
DEFAULT_SIZE_LABEL = "기본"
EXCLUDED_CATEGORIES = frozenset({"ICE FLAKES", "RTD", "ICE CREAM", "TOPPING"})
REQUEST_PAUSE_SECONDS = 0.2
END_OF_LIST = "none"

_SIZE_PREFIX = re.compile(r"^\((L|EX)\)\s*")
_TEMPERATURE_TOKEN = re.compile(r"^(HOT|ICED)\b\s*", re.IGNORECASE)
_TOKEN_TO_TEMPERATURE = {"HOT": Temperature.HOT, "ICED": Temperature.ICED}
_VOLUME_ML = re.compile(r"(\d+)\s*ml", re.IGNORECASE)


class Category(NamedTuple):
    code: str
    name: str


class ParsedName(NamedTuple):
    name: str
    size_label: str
    temperature: Temperature


def page_url(category_code: str, page: int) -> str:
    params = {
        "gubun": "menu_more",
        "product_cate": "7",
        "chked_val": f"{category_code},",
        "skeyword": "",
        "page": str(page),
    }
    return str(httpx.URL(AJAX_URL, params=params))


def parse_categories(html: str) -> list[Category]:
    """Read the category checkboxes of drink.html (code + label), skipping "전체"."""
    soup = BeautifulSoup(html, "html.parser")
    categories: list[Category] = []
    for node in soup.select('input[name="chkList"]'):
        code = node.get("value")
        if not isinstance(code, str) or code == "all":
            continue
        label = soup.select_one(f'label[for="{node.get("id")}"]')
        if not isinstance(label, Tag):
            raise ParseError(f"category checkbox {code} without label")
        categories.append(Category(code=code, name=clean_text(label.get_text())))
    if not categories:
        raise ParseError("no category checkboxes found on drink.html")
    return categories


def split_name(raw_name: str) -> ParsedName:
    """ "(L) HOT 카페 아메리카노" -> ("카페 아메리카노", "L", HOT)."""
    name = clean_text(raw_name)
    size_label = DEFAULT_SIZE_LABEL
    temperature = Temperature.BOTH
    size_match = _SIZE_PREFIX.match(name)
    if size_match is not None:
        size_label = size_match.group(1)
        name = name[size_match.end() :]
    temperature_match = _TEMPERATURE_TOKEN.match(name)
    if temperature_match is not None:
        temperature = _TOKEN_TO_TEMPERATURE[temperature_match.group(1).upper()]
        name = name[temperature_match.end() :]
    return ParsedName(name=name.strip(), size_label=size_label, temperature=temperature)


def _title_parts(item: Tag) -> tuple[str, str | None]:
    heading = item.select_one(".detail_con h2")
    if not isinstance(heading, Tag):
        raise ParseError(f"list item without h2: {item!r}")
    korean = "".join(str(child) for child in heading.children if isinstance(child, NavigableString))
    english_node = heading.find("span")
    english = clean_text(english_node.get_text()) if isinstance(english_node, Tag) else ""
    return clean_text(korean), english or None


def _nutrition_table(item: Tag) -> dict[str, str]:
    table: dict[str, str] = {}
    for row in item.select(".pro_nutri dl"):
        key = row.find("dt")
        value = row.find("dd")
        if not isinstance(key, Tag) or not isinstance(value, Tag):
            raise ParseError(f"nutrition row without dt/dd: {row!r}")
        table[clean_text(key.get_text())] = clean_text(value.get_text())
    return table


def _volume_ml(item: Tag) -> int | None:
    size_node = item.select_one(".pro_size")
    if not isinstance(size_node, Tag):
        return None
    match = _VOLUME_ML.search(size_node.get_text())
    return int(match.group(1)) if match is not None else None


def parse_page(html: str, *, category: str, source_url: str) -> list[RawServing]:
    """Parse one AJAX page. The literal "none" body (past the last page) yields []."""
    if html.strip() == END_OF_LIST:
        return []
    soup = BeautifulSoup(html, "html.parser")
    rows: list[RawServing] = []
    for item in soup.find_all("li", recursive=False):
        korean, english = _title_parts(item)
        parsed = split_name(korean)
        english_name = split_name(english).name if english is not None else None
        table = _nutrition_table(item)
        rows.append(
            RawServing(
                brand_id=BRAND.id,
                drink_name=parsed.name,
                drink_name_en=english_name,
                category=category,
                temperature=parsed.temperature,
                size_label=parsed.size_label,
                volume_ml=_volume_ml(item),
                sugar_g=optional_number(table.get("당류")),
                caffeine_mg=optional_number(table.get("카페인")),
                source_url=source_url,
            )
        )
    return rows


def _scrape_category(client: httpx.Client, category: Category) -> list[RawServing]:
    rows: list[RawServing] = []
    page = 1
    while True:
        url = page_url(category.code, page)
        page_rows = parse_page(fetch_text(client, url), category=category.name, source_url=url)
        time.sleep(REQUEST_PAUSE_SECONDS)
        if not page_rows:
            return rows
        rows.extend(page_rows)
        page += 1


def dedupe(rows: list[RawServing]) -> list[RawServing]:
    """Keep the first row per (name, size, temperature); the list repeats items across pages."""
    seen: set[tuple[str, str, Temperature]] = set()
    unique: list[RawServing] = []
    for row in rows:
        key = (row.drink_name, row.size_label, row.temperature)
        if key in seen:
            continue
        seen.add(key)
        unique.append(row)
    return unique


def scrape(client: httpx.Client) -> list[RawServing]:
    categories = parse_categories(fetch_text(client, SHELL_URL))
    time.sleep(REQUEST_PAUSE_SECONDS)
    rows: list[RawServing] = []
    for category in categories:
        if category.name in EXCLUDED_CATEGORIES:
            continue
        rows.extend(_scrape_category(client, category))
    return dedupe(rows)
