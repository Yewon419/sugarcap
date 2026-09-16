"""메가MGC커피 scraper.

The menu page is a shell; the list is loaded from `menu.php` as HTML fragments,
one page at a time. Sub-categories (커피, 티, ...) come from the shell's
`list_checkbox` inputs and are fetched one by one so every row carries its
category. Only `menu_category2=1` (음료) is a drink tab; 2 is 푸드, 3 is 상품.
"""

from __future__ import annotations

import re
from dataclasses import dataclass

import httpx
from bs4 import BeautifulSoup, Tag

from sugarcap_scrape.http import fetch_text
from sugarcap_scrape.models import Brand, RawServing, Temperature
from sugarcap_scrape.parse import ParseError, clean_text, first_number

BRAND = Brand(
    id="mega",
    name="메가MGC커피",
    serving_note="1잔 기준 (컵용량은 메뉴별 표기, HOT 591ml·ICE 710ml 등)",
    has_size_choice=False,
)

SHELL_URL = "https://www.mega-mgccoffee.com/menu/"
LIST_URL = "https://www.mega-mgccoffee.com/menu/menu.php"
DRINK_TAB_PARAMS: dict[str, str] = {"menu_category1": "1", "menu_category2": "1"}
SIZE_LABEL = "기본"
MAX_PAGES = 50

_NAME_PREFIX = re.compile(r"^\((HOT|ICE)\)\s*")
_VOLUME = re.compile(r"컵용량\s*:\s*(\d+)\s*ml")
_NUTRITION_ROW = re.compile(r"^(\S+)\s+(.+)$")
_LABEL_TO_TEMPERATURE = {"HOT": Temperature.HOT, "ICE": Temperature.ICED}


@dataclass(frozen=True)
class SubCategory:
    value: str
    label: str


def parse_subcategories(html: str) -> list[SubCategory]:
    """Read the 분류보기 checkboxes (value + Korean label) from the shell page."""
    soup = BeautifulSoup(html, "html.parser")
    found: list[SubCategory] = []
    for node in soup.select("input[name='list_checkbox']"):
        value = node.get("value")
        if not isinstance(value, str) or not value:
            raise ParseError(f"list_checkbox without value: {node}")
        label_node = node.find_next(class_="checkbox_text")
        if not isinstance(label_node, Tag):
            raise ParseError(f"list_checkbox {value!r} has no checkbox_text label")
        found.append(SubCategory(value=value, label=clean_text(label_node.get_text())))
    if not found:
        raise ParseError("no list_checkbox inputs in shell page")
    return found


def _temperature(label: str | None, prefix: str | None, name: str) -> Temperature:
    from_label = _LABEL_TO_TEMPERATURE.get(label) if label is not None else None
    from_prefix = _LABEL_TO_TEMPERATURE.get(prefix) if prefix is not None else None
    if from_label is not None and from_prefix is not None and from_label != from_prefix:
        raise ParseError(f"temperature label {label!r} disagrees with name prefix ({name!r})")
    if from_prefix is not None:
        return from_prefix
    if from_label is not None:
        return from_label
    return Temperature.BOTH


def _nutrition(modal: Tag, name: str) -> dict[str, float]:
    """Map nutrient label -> number. Units are ignored: the site has typos like '카페인 181.6g'."""
    values: dict[str, float] = {}
    for row in modal.select(".cont_list li"):
        text = clean_text(row.get_text(" "))
        match = _NUTRITION_ROW.match(text)
        if match is None:
            continue
        label, amount = match.groups()
        values[label] = first_number(amount, field=label, context=name)
    return values


def _parse_item(item: Tag, *, category: str, source_url: str) -> RawServing:
    modal = item.select_one("div.inner_modal")
    if modal is None:
        raise ParseError(f"menu item without inner_modal ({category})")
    title = modal.select_one(".cont_text_title b")
    if title is None:
        raise ParseError(f"menu item without title ({category})")
    raw_name = clean_text(title.get_text())
    prefix_match = _NAME_PREFIX.match(raw_name)
    prefix = prefix_match.group(1) if prefix_match else None
    name = _NAME_PREFIX.sub("", raw_name)
    if not name:
        raise ParseError(f"empty drink name after prefix strip: {raw_name!r}")

    label_node = item.select_one(".cont_gallery_list_label")
    label = clean_text(label_node.get_text()) if label_node is not None else None

    en_node = modal.select_one(".inner_modal_title .cont_text_info")
    name_en = clean_text(en_node.get_text()) if en_node is not None else ""

    modal_text = clean_text(modal.get_text(" "))
    volume_match = _VOLUME.search(modal_text)
    nutrition = _nutrition(modal, name)
    return RawServing(
        brand_id=BRAND.id,
        drink_name=name,
        drink_name_en=name_en or None,
        category=category,
        temperature=_temperature(label, prefix, name),
        size_label=SIZE_LABEL,
        volume_ml=int(volume_match.group(1)) if volume_match else None,
        sugar_g=nutrition.get("당류"),
        caffeine_mg=nutrition.get("카페인"),
        source_url=source_url,
    )


def parse_menu_page(html: str, *, category: str, source_url: str) -> list[RawServing]:
    """Parse one `menu.php` fragment. Returns [] on the empty page past the last one."""
    soup = BeautifulSoup(html, "html.parser")
    rows: list[RawServing] = []
    for anchor in soup.select("a.inner_modal_open"):
        item = anchor.parent
        if not isinstance(item, Tag) or item.name != "li":
            raise ParseError(f"inner_modal_open anchor not inside <li> ({category})")
        rows.append(_parse_item(item, category=category, source_url=source_url))
    return rows


def _list_params(sub: SubCategory, page: int) -> dict[str, str]:
    return {
        "page": str(page),
        **DRINK_TAB_PARAMS,
        "category": sub.value,
        "list_checkbox_all": "",
    }


def scrape_subcategory(client: httpx.Client, sub: SubCategory) -> list[RawServing]:
    rows: list[RawServing] = []
    previous: list[RawServing] | None = None
    for page in range(1, MAX_PAGES + 1):
        params = _list_params(sub, page)
        html = fetch_text(client, LIST_URL, params=params)
        source_url = str(httpx.URL(LIST_URL, params=params))
        page_rows = parse_menu_page(html, category=sub.label, source_url=source_url)
        if not page_rows or page_rows == previous:
            return rows
        rows.extend(page_rows)
        previous = page_rows
    raise ParseError(f"{sub.label}: pagination did not terminate within {MAX_PAGES} pages")


def scrape(client: httpx.Client) -> list[RawServing]:
    shell = fetch_text(client, SHELL_URL, params=DRINK_TAB_PARAMS)
    rows: list[RawServing] = []
    for sub in parse_subcategories(shell):
        rows.extend(scrape_subcategory(client, sub))
    return rows
