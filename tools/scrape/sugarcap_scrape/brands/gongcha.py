"""공차 scraper.

The 영양정보 tab of the menu page loads one HTML fragment (`/brand/menu/product_nutrition`)
with a table per category: `div.item > div.inner > h4` (category) + `table`. Columns are
메뉴명 · 구분 (COLD/HOT) · 사이즈 (L/J/G) · 컵 용량(ml) · … 당류(g) · … 카페인(mg) · 알레르기,
with 메뉴명 / 구분 / 알레르기 merged by rowspan.

Published values are the 기본 레시피: 당도 0% for customizable drinks (smoothies are
fixed). The note says so; the app must not present them as the sweetness people order.
NEW / 베스트셀러 repeat drinks from the real categories; each drink is kept once.
"""

from __future__ import annotations

import logging

import httpx
from bs4 import BeautifulSoup, Tag

from sugarcap_scrape.http import fetch_text
from sugarcap_scrape.models import Brand, RawServing, Temperature
from sugarcap_scrape.parse import ParseError, clean_text, optional_number

log = logging.getLogger(__name__)

BRAND = Brand(
    id="gongcha",
    name="공차",
    serving_note=(
        "사이즈별 컵용량 기준. 공차 공식 영양정보 게시값이며, 당류는 기본 레시피"
        "(당도 0%, 스무디는 고정 당도) 기준입니다. 당도를 올리면 당이 더 많아요."
    ),
    has_size_choice=True,
)

NUTRITION_URL = "https://www.gong-cha.co.kr/brand/menu/product_nutrition"

# Categories that only repeat drinks listed elsewhere; a drink takes one of these only
# when no real category lists it (seasonal drinks live in NEW alone).
ROLLUP_CATEGORIES = ("NEW 시즌 메뉴", "베스트셀러")

# L / J are named LARGE / JUMBO in the brand's nutrition guide. "G" (946ml on a few
# drinks) is never named, so it is labelled by its published volume.
SIZE_LABELS = {"L": "라지", "J": "점보"}
_TEMPERATURES = {"COLD": Temperature.ICED, "HOT": Temperature.HOT}


def _expand_rowspans(table: Tag) -> list[list[str]]:
    """Body rows as full-width text grids, copying rowspan cells down."""
    carried: dict[int, tuple[str, int]] = {}
    grid: list[list[str]] = []
    for tr in table.select("tbody tr"):
        cells = iter(tr.find_all(["td", "th"], recursive=False))
        row: list[str] = []
        column = 0
        while True:
            if column in carried:
                text, left = carried[column]
                row.append(text)
                if left > 1:
                    carried[column] = (text, left - 1)
                else:
                    del carried[column]
                column += 1
                continue
            cell = next(cells, None)
            if cell is None:
                break
            text = clean_text(cell.get_text(" "))
            span = int(str(cell.get("rowspan", "1")))
            if span > 1:
                carried[column] = (text, span - 1)
            row.append(text)
            column += 1
        grid.append(row)
    return grid


def _column(headers: list[str], name: str, context: str) -> int:
    for index, header in enumerate(headers):
        if header.startswith(name):
            return index
    raise ParseError(f"column {name!r} missing in {headers} ({context})")


def _size_label(cup: str, volume: float | None, context: str) -> str:
    if cup in SIZE_LABELS:
        return SIZE_LABELS[cup]
    if cup and volume is not None:
        return f"{int(volume)}ml"
    raise ParseError(f"unknown cup size {cup!r} ({context})")


def parse_table(table: Tag, *, category: str, source_url: str) -> list[RawServing]:
    header_row = table.select_one("thead tr")
    if header_row is None:
        raise ParseError(f"gongcha: table without thead ({category})")
    headers = [
        clean_text(th.get_text("")).replace(" ", "")
        for th in header_row.find_all(["th", "td"], recursive=False)
    ]
    name_col = _column(headers, "메뉴명", category)
    temperature_col = _column(headers, "구분", category)
    size_col = _column(headers, "사이즈", category)
    volume_col = _column(headers, "컵용량", category)
    sugar_col = _column(headers, "당류", category)
    caffeine_col = _column(headers, "카페인", category)

    rows: list[RawServing] = []
    for cells in _expand_rowspans(table):
        context = f"{category} row {cells}"
        if len(cells) != len(headers):
            raise ParseError(f"gongcha: row width {len(cells)} != {len(headers)} ({context})")
        label = cells[temperature_col].upper()
        if label not in _TEMPERATURES:
            raise ParseError(f"gongcha: unknown temperature {label!r} ({context})")
        volume = optional_number(cells[volume_col])
        rows.append(
            RawServing(
                brand_id=BRAND.id,
                drink_name=cells[name_col],
                category=category,
                temperature=_TEMPERATURES[label],
                size_label=_size_label(cells[size_col].upper(), volume, context),
                volume_ml=int(volume) if volume is not None else None,
                sugar_g=optional_number(cells[sugar_col]),
                caffeine_mg=optional_number(cells[caffeine_col]),
                source_url=source_url,
            )
        )
    return rows


def parse_nutrition_page(html: str, source_url: str) -> list[RawServing]:
    """Every drink once, under a real category when one lists it."""
    soup = BeautifulSoup(html, "html.parser")
    by_category: list[tuple[str, list[RawServing]]] = []
    for table in soup.find_all("table"):
        inner = table.find_parent(class_="inner")
        heading = inner.find("h4") if isinstance(inner, Tag) else None
        if not isinstance(heading, Tag):
            raise ParseError("gongcha: nutrition table without a category heading")
        category = clean_text(heading.get_text())
        by_category.append((category, parse_table(table, category=category, source_url=source_url)))
    if not by_category:
        raise ParseError(f"gongcha: no nutrition tables at {source_url}")

    ordered = [c for c in by_category if c[0] not in ROLLUP_CATEGORIES] + [
        c for c in by_category if c[0] in ROLLUP_CATEGORIES
    ]
    owner: dict[str, str] = {}
    kept: list[RawServing] = []
    for category, servings in ordered:
        for serving in servings:
            first = owner.setdefault(serving.drink_name, category)
            if first == category:
                kept.append(serving)
    return kept


def scrape(client: httpx.Client) -> list[RawServing]:
    return parse_nutrition_page(fetch_text(client, NUTRITION_URL), NUTRITION_URL)
