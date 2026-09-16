"""더벤티: category tabs on all.html?mode=N -> one popup detail page per uid.

Nutrition lives in a single 8-column table row on the detail page. The table's
serving cell lists both cup sizes ("라지(600ml) 점보(960ml)") but the description
states which one the numbers belong to ("*영양성분 ... 기준치 : 라지(600ml) 사이즈
기준"), so that note is the size of record. Rows whose serving cell carries no ml
value are food and are skipped.

Two cell shapes need care:
- 카페인 "(고카페인) 시그니처:168 다크:266" -> one serving with two bean variants.
- 당류/카페인 "43 (43%) (Hot) / 39 (39%) (Iced)" -> the brand publishes a value per
  temperature, so the row is split into a hot row and an iced row.
Values labelled by size ("미디엄 34 (34%) / 라지 48 (48%)") are read at the size the
description names. "-" means the brand published no value. The brand spells the
420ml size both 미디엄 and 미디움; the label is canonicalised so one size does not
become two servings.
"""

from __future__ import annotations

import re
import time
from typing import NamedTuple

import httpx
from bs4 import BeautifulSoup, Tag

from sugarcap_scrape.http import fetch_text
from sugarcap_scrape.models import Brand, CaffeineVariant, RawServing, Temperature
from sugarcap_scrape.parse import ParseError, clean_text, optional_number

BRAND = Brand(
    id="theventi",
    name="더벤티",
    serving_note="더벤티가 영양성분 기준으로 밝힌 사이즈(대부분 라지 600ml) 기준입니다.",
    has_size_choice=False,
)

BASE_URL = "https://theventi.co.kr/new2022/menu/all.html"
DETAIL_URL = "https://theventi.co.kr/new2022/menu/all-view.new.html"
DEFAULT_SIZE_LABEL = "기본"
NEW_CATEGORY = "신메뉴"
EXCLUDED_CATEGORIES = frozenset({"사이드메뉴/RTD"})
SIZE_WORDS = frozenset({"라지", "미디엄", "미디움", "점보", "벤티", "레귤러", "스몰"})
SIZE_ALIASES = {"미디움": "미디엄"}
REQUEST_PAUSE_SECONDS = 0.2
NUTRITION_COLUMNS = 8
SUGAR_COLUMN = 2
CAFFEINE_COLUMN = 6

_MODE = re.compile(r"\?mode=(\d+)")
_UID = re.compile(r"uid=(\d+)")
_BASIS_NOTE = re.compile(r"기준치\s*:?\s*([가-힣]*)\s*\(?\s*(\d+)\s*ml\s*\)?\s*사이즈")
_SERVING_ML = re.compile(r"([가-힣A-Za-z]+)?\s*[:(]?\s*(\d+)\s*ml", re.IGNORECASE)
_TEMPERATURE_TOKEN = re.compile(r"\b(hot|ice|iced)\b", re.IGNORECASE)
_VARIANT = re.compile(r"([^\s:()/]+)\s*:\s*(\d+(?:\.\d+)?)")
_SIZE_SUFFIX = re.compile(r"\s*\(([^()]*)\)\s*$")


class Category(NamedTuple):
    mode: str
    name: str


class ListItem(NamedTuple):
    uid: str
    name: str
    temperature: Temperature


class Basis(NamedTuple):
    size_label: str
    volume_ml: int


def list_url(mode: str) -> str:
    return str(httpx.URL(BASE_URL, params={"mode": mode}))


def detail_url(uid: str) -> str:
    return str(httpx.URL(DETAIL_URL, params={"uid": uid}))


def parse_categories(html: str) -> list[Category]:
    """Read the menu tabs of a list page (mode + label), in page order."""
    soup = BeautifulSoup(html, "html.parser")
    categories: list[Category] = []
    for node in soup.select(".tabwrap a[href]"):
        href = node.get("href")
        if not isinstance(href, str):
            continue
        match = _MODE.search(href)
        if match is None:
            continue
        categories.append(Category(mode=match.group(1), name=clean_text(node.get_text())))
    if not categories:
        raise ParseError("no category tabs found on list page")
    return categories


def _item_temperature(item: Tag) -> Temperature:
    """Temperature comes from the hot/ice icons; the detail page does not state it."""
    classes = {
        cls
        for icon in item.select("p.type i")
        for cls in (icon.get("class") or [])
        if isinstance(cls, str)
    }
    hot = "hot" in classes
    iced = "ice" in classes
    if hot and not iced:
        return Temperature.HOT
    if iced and not hot:
        return Temperature.ICED
    return Temperature.BOTH


def parse_list(html: str) -> list[ListItem]:
    """Read the menu items of one category page."""
    soup = BeautifulSoup(html, "html.parser")
    items: list[ListItem] = []
    for item in soup.select(".menu_list li.item"):
        anchor = item.select_one("a[href]")
        title = item.select_one("p.tit")
        if not isinstance(anchor, Tag) or not isinstance(title, Tag):
            raise ParseError(f"menu item without link/title: {item!r}")
        href = anchor.get("href")
        if not isinstance(href, str):
            raise ParseError(f"menu item with non-string href: {anchor!r}")
        match = _UID.search(href)
        if match is None:
            raise ParseError(f"menu item without uid: {href!r}")
        items.append(
            ListItem(
                uid=match.group(1),
                name=clean_text(title.get_text()),
                temperature=_item_temperature(item),
            )
        )
    if not items:
        raise ParseError("no menu items found on category page")
    return items


def strip_size_suffix(name: str) -> str:
    """ "카페라떼 (라지/점보)" -> "카페라떼". Non-size parentheticals are kept."""
    match = _SIZE_SUFFIX.search(name)
    if match is None:
        return name
    tokens = [token.strip() for token in match.group(1).split("/") if token.strip()]
    if tokens and all(token in SIZE_WORDS for token in tokens):
        return name[: match.start()].strip()
    return name


def canonical_size(label: str) -> str:
    """One spelling per size: 미디움 and 미디엄 are the same 420ml cup."""
    return SIZE_ALIASES.get(label, label)


def canonical_text(text: str) -> str:
    """Rewrite size spellings inside a cell so a canonical label still matches it."""
    for alias, canonical in SIZE_ALIASES.items():
        text = text.replace(alias, canonical)
    return text


def parse_basis(description: str, serving_cell: str) -> Basis | None:
    """Size the numbers are published at. None means the row is not a drink."""
    note = _BASIS_NOTE.search(description)
    if note is not None:
        label = note.group(1) or DEFAULT_SIZE_LABEL
        return Basis(size_label=canonical_size(label), volume_ml=int(note.group(2)))
    match = _SERVING_ML.search(serving_cell)
    if match is None:
        return None
    label = match.group(1) or ""
    return Basis(
        size_label=canonical_size(label) if label in SIZE_WORDS else DEFAULT_SIZE_LABEL,
        volume_ml=int(match.group(2)),
    )


def split_by_temperature(cell: str) -> dict[Temperature, float] | None:
    """ "43 (43%) (Hot) / 39 (39%) (Iced)" -> {HOT: 43, ICED: 39}. None when not split."""
    parts = [part for part in cell.split("/") if part.strip()]
    if len(parts) < 2:
        return None
    values: dict[Temperature, float] = {}
    for part in parts:
        tokens = _TEMPERATURE_TOKEN.findall(part)
        value = optional_number(part)
        if len(tokens) != 1 or value is None:
            return None
        temperature = Temperature.HOT if tokens[0].lower() == "hot" else Temperature.ICED
        if temperature in values:
            return None
        values[temperature] = value
    return values if len(values) == 2 else None


def value_at_size(cell: str, size_label: str) -> float | None:
    """Read the number published for `size_label` out of a size-labelled cell."""
    parts = [part for part in cell.split("/") if part.strip()]
    if len(parts) >= 2:
        for part in parts:
            if size_label in canonical_text(part):
                return optional_number(part)
    return optional_number(cell)


def parse_caffeine_variants(cell: str) -> tuple[CaffeineVariant, ...]:
    """ "(고카페인) 시그니처:168 다크:266" -> two bean variants. Otherwise empty."""
    matches = _VARIANT.findall(cell)
    if len(matches) < 2:
        return ()
    return tuple(CaffeineVariant(label=label, caffeine_mg=float(value)) for label, value in matches)


def _nutrition_cells(soup: BeautifulSoup, source_url: str) -> list[str]:
    row = soup.select_one(".menu-ingredient table tbody tr")
    if not isinstance(row, Tag):
        raise ParseError(f"detail page without nutrition row ({source_url})")
    cells = [clean_text(cell.get_text(" ")) for cell in row.find_all("td")]
    if len(cells) != NUTRITION_COLUMNS:
        raise ParseError(
            f"nutrition row has {len(cells)} cells, expected {NUTRITION_COLUMNS} ({source_url})"
        )
    return cells


def parse_detail(
    html: str, *, category: str, temperature: Temperature, source_url: str
) -> list[RawServing]:
    """Parse one popup detail page. Returns [] for food (serving cell without ml)."""
    soup = BeautifulSoup(html, "html.parser")
    title = soup.select_one(".menu_desc_wrap p.tit")
    if not isinstance(title, Tag):
        raise ParseError(f"detail page without title ({source_url})")
    name = strip_size_suffix(clean_text(title.get_text(" ")))
    if not name:
        raise ParseError(f"detail page with empty title ({source_url})")
    description_node = soup.select_one(".menu_desc_wrap .txt")
    description = clean_text(description_node.get_text(" ")) if description_node is not None else ""
    cells = _nutrition_cells(soup, source_url)
    basis = parse_basis(description, cells[0])
    if basis is None:
        return []

    sugar_cell = cells[SUGAR_COLUMN]
    caffeine_cell = cells[CAFFEINE_COLUMN]
    variants = parse_caffeine_variants(caffeine_cell)
    sugar_split = split_by_temperature(sugar_cell)
    caffeine_split = split_by_temperature(caffeine_cell)
    sugar_at_basis = value_at_size(sugar_cell, basis.size_label)
    caffeine_at_basis = (
        variants[0].caffeine_mg if variants else value_at_size(caffeine_cell, basis.size_label)
    )

    def row(temp: Temperature, sugar: float | None, caffeine: float | None) -> RawServing:
        return RawServing(
            brand_id=BRAND.id,
            drink_name=name,
            category=category,
            temperature=temp,
            size_label=basis.size_label,
            volume_ml=basis.volume_ml,
            sugar_g=sugar,
            caffeine_mg=caffeine,
            caffeine_variants=variants,
            source_url=source_url,
        )

    if sugar_split is None and caffeine_split is None:
        return [row(temperature, sugar_at_basis, caffeine_at_basis)]
    return [
        row(
            temp,
            sugar_split[temp] if sugar_split is not None else sugar_at_basis,
            caffeine_split[temp] if caffeine_split is not None else caffeine_at_basis,
        )
        for temp in (Temperature.HOT, Temperature.ICED)
    ]


def scrape(client: httpx.Client) -> list[RawServing]:
    categories = parse_categories(fetch_text(client, list_url("1")))
    time.sleep(REQUEST_PAUSE_SECONDS)
    # 신메뉴 repeats items from the real categories; visit it last so an item keeps
    # its own category and only new-only items come from the showcase.
    ordered = sorted(categories, key=lambda category: category.name == NEW_CATEGORY)
    seen: set[str] = set()
    rows: list[RawServing] = []
    for category in ordered:
        if category.name in EXCLUDED_CATEGORIES:
            continue
        items = parse_list(fetch_text(client, list_url(category.mode)))
        time.sleep(REQUEST_PAUSE_SECONDS)
        for item in items:
            if item.uid in seen:
                continue
            seen.add(item.uid)
            url = detail_url(item.uid)
            rows.extend(
                parse_detail(
                    fetch_text(client, url),
                    category=category.name,
                    temperature=item.temperature,
                    source_url=url,
                )
            )
            time.sleep(REQUEST_PAUSE_SECONDS)
    return rows
