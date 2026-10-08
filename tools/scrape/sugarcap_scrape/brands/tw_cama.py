"""Cama Café: the drinks menu page, read as HTML.

`camacafe.com/Menu/1` renders every drink twice: a list row under its category
(`div.menu` > `div.ti`, linking `data-target="#ingredientN"`) and a modal
`div#ingredientN` with the nutrition:

- `糖(g)`: one `li` per size, `<span>L </span> <span>熱 15.56</span> <span>冰 12.68</span>`,
  `-` where that size and temperature is not sold
- `咖啡因總含量`: the drink's band ("201mg以上", "101~200mg", "100mg以下", "0"), or empty
- `其他資訊`: free text that usually adds exact mg per size,
  "咖啡因總含量：M：207.8mg、L：311.7mg、XL：415.6mg", sometimes per temperature
  ("XL(熱)：318mg、XL(冰)：422mg") or as bands ("L : 101-200mg、XL：201mg以上")

Per-size text wins over the drink's band. A drink sold in one size may give one
unlabeled number ("咖啡因199.4mg"). The page states every value is the maximum,
at full sugar except black coffee, drip, espresso and cold brew; the parser
refuses the page if that note changes. Cup volume is published only for espresso.
"""

from __future__ import annotations

import re
from dataclasses import dataclass

import httpx
from bs4 import BeautifulSoup, Tag

from sugarcap_scrape.http import fetch_text
from sugarcap_scrape.models import Brand, CaffeineRange, RawServing, Temperature
from sugarcap_scrape.parse import ParseError, clean_text

BRAND = Brand(
    id="tw-cama",
    name="cama café",
    serving_note="每杯最高值，全糖計算（黑咖啡、手沖、濃縮、冷萃除外），依官方公告",
    has_size_choice=True,
)

MENU_URL = "https://www.camacafe.com/Menu/1"
BASIS_NOTE = "以最高值計算。表以全糖量計算"
SIZES = ("M", "L", "XL")
TEMPERATURES = {"熱": Temperature.HOT, "冰": Temperature.ICED}

_SIZE_GROUP = r"(?:M|L|XL)(?:\s*\((?:熱|冰|熱/冰)\))?"
_PER_SIZE = re.compile(
    rf"(?P<sizes>{_SIZE_GROUP}(?:\s*、\s*{_SIZE_GROUP})*)\s*[：:]\s*"
    r"(?P<value>\d+(?:\.\d+)?\s*(?:[-~～]\s*\d+\s*)?mg(?:以上|以下)?)"
)
_ONE_SIZE = re.compile(r"(M|L|XL)(?:\s*\((熱|冰|熱/冰)\))?")
_BAND = re.compile(r"^(\d+)\s*[-~～]\s*(\d+)\s*mg")
_AT_LEAST = re.compile(r"^(\d+)\s*mg以上$")
_AT_MOST = re.compile(r"^(\d+)\s*mg以下$")
_EXACT = re.compile(r"^(\d+(?:\.\d+)?)\s*mg$")
_UNLABELED = re.compile(r"咖啡因(?:總含量)?\s*[：:]?\s*(\d+(?:\.\d+)?)\s*mg")
_VOLUME = re.compile(r"容量\s*(\d+)\s*ml", re.IGNORECASE)
_SUGAR_CELL = re.compile(r"^(熱|冰)\s*(-|\d+(?:\.\d+)?)$")


@dataclass(frozen=True)
class Caffeine:
    mg: float
    band: CaffeineRange | None


def parse_caffeine(text: str, context: str) -> Caffeine:
    """One caffeine value: a number, a band, or "0"."""
    value = clean_text(text)
    if value == "0":
        return Caffeine(mg=0.0, band=None)
    if match := _BAND.match(value):
        # "101-200mg以上" appears once; the range is what the band means.
        low, high = float(match.group(1)), float(match.group(2))
        return Caffeine(mg=high, band=CaffeineRange(min_mg=low, max_mg=high))
    if match := _AT_LEAST.match(value):
        low = float(match.group(1))
        return Caffeine(mg=low, band=CaffeineRange(min_mg=low))
    if match := _AT_MOST.match(value):
        high = float(match.group(1))
        return Caffeine(mg=high, band=CaffeineRange(min_mg=0, max_mg=high))
    if match := _EXACT.match(value):
        return Caffeine(mg=float(match.group(1)), band=None)
    raise ParseError(f"caffeine: unreadable {text!r} ({context})")


type CupKey = tuple[str, Temperature]


def per_size_caffeine(text: str, context: str) -> dict[CupKey, Caffeine]:
    """Caffeine per (size, temperature) from the free text.

    A size without a temperature covers both temperatures.
    """
    found: dict[CupKey, Caffeine] = {}
    for match in _PER_SIZE.finditer(text):
        caffeine = parse_caffeine(match.group("value"), context)
        for size_match in _ONE_SIZE.finditer(match.group("sizes")):
            size, temp = size_match.group(1), size_match.group(2)
            temps = (
                [TEMPERATURES[temp]]
                if temp in TEMPERATURES
                else [Temperature.HOT, Temperature.ICED]
            )
            for temperature in temps:
                found[(size, temperature)] = caffeine
    return found


def sugar_cells(box: Tag, context: str) -> dict[CupKey, float]:
    """Sugar per sold (size, temperature). `-` cells are combinations not sold."""
    cells: dict[CupKey, float] = {}
    for li in box.select("li"):
        spans = [clean_text(span.get_text(" ")) for span in li.select("span")]
        if not spans or spans[0] not in SIZES:
            raise ParseError(f"sugar row {spans} has no size ({context})")
        size = spans[0]
        for cell in spans[1:]:
            match = _SUGAR_CELL.match(cell)
            if match is None:
                raise ParseError(f"sugar cell {cell!r} ({context})")
            if match.group(2) != "-":
                cells[(size, TEMPERATURES[match.group(1)])] = float(match.group(2))
    return cells


def _details(modal: Tag) -> dict[str, str]:
    details: dict[str, str] = {}
    for li in modal.select("ul.dli li"):
        title, body = li.select_one(".ti"), li.select_one(".col-md-9")
        if title is not None and body is not None:
            details[clean_text(title.get_text(" "))] = clean_text(body.get_text(" "))
    return details


def _sugar_box(modal: Tag, context: str) -> Tag:
    for box in modal.select("div.calories_box"):
        title = box.select_one(".ti")
        if title is not None and clean_text(title.get_text(" ")) == "糖(g)":
            return box
    raise ParseError(f"no 糖(g) table ({context})")


def _names(modal: Tag, context: str) -> tuple[str, str | None]:
    """Chinese name and the brand's English name ("CAMA金獎拿鐵/Latte" renders as name + span)."""
    tag = modal.select_one(".modal-header .name")
    if tag is None:
        raise ParseError(f"modal without a name ({context})")
    span = tag.find("span")
    english = clean_text(span.get_text(" ")) if isinstance(span, Tag) else ""
    if isinstance(span, Tag):
        span.extract()
    name = clean_text(tag.get_text(" "))
    if not name:
        raise ParseError(f"empty drink name ({context})")
    return name, english or None


def parse_modal(modal: Tag, category: str) -> list[RawServing]:
    context = str(modal.get("id"))
    name, name_en = _names(modal, context)
    context = f"{name} ({context})"
    sugar = sugar_cells(_sugar_box(modal, context), context)
    details = _details(modal)
    band_text = details.get("咖啡因總含量", "")
    drink_band = parse_caffeine(band_text, context) if band_text else None
    other = details.get("其他資訊", "")
    exact = per_size_caffeine(other, context)
    sold_sizes = {size for size, _ in sugar}
    if not exact and len(sold_sizes) == 1:
        unlabeled = _UNLABELED.search(other)
        if unlabeled is not None:
            only = Caffeine(mg=float(unlabeled.group(1)), band=None)
            exact = {key: only for key in sugar}
    volume = _VOLUME.search(other)
    rows: list[RawServing] = []
    for size in SIZES:
        for temperature in (Temperature.HOT, Temperature.ICED):
            if (size, temperature) not in sugar:
                continue
            cup = exact.get((size, temperature), drink_band)
            rows.append(
                RawServing(
                    brand_id=BRAND.id,
                    drink_name=name,
                    drink_name_en=name_en,
                    category=category,
                    temperature=temperature,
                    size_label=size,
                    volume_ml=int(volume.group(1)) if volume is not None else None,
                    sugar_g=sugar[(size, temperature)],
                    caffeine_mg=None if cup is None else cup.mg,
                    caffeine_range=None if cup is None else cup.band,
                    source_url=MENU_URL,
                )
            )
    return rows


def categories(soup: BeautifulSoup) -> dict[str, str]:
    """Modal id -> the category whose list links to it."""
    found: dict[str, str] = {}
    for menu in soup.select("div.menu"):
        title = menu.select_one("div.ti")
        if title is None:
            continue
        category = clean_text(title.get_text(" "))
        for link in menu.select("a[data-target]"):
            target = str(link.get("data-target", "")).lstrip("#")
            if target in found and found[target] != category:
                raise ParseError(f"{target} listed under {found[target]} and {category}")
            found[target] = category
    return found


def parse_menu(page: str) -> list[RawServing]:
    if BASIS_NOTE not in page:
        raise ParseError(f"the maximum-at-full-sugar note is gone from {MENU_URL}")
    soup = BeautifulSoup(page, "html.parser")
    category_of = categories(soup)
    rows: list[RawServing] = []
    for modal in soup.select("div.ingredient_modal"):
        modal_id = str(modal.get("id"))
        category = category_of.get(modal_id)
        if category is None:
            raise ParseError(f"{modal_id}: no category lists this drink")
        rows.extend(parse_modal(modal, category))
    if not rows:
        raise ParseError(f"no drinks on {MENU_URL}")
    return rows


def scrape(client: httpx.Client) -> list[RawServing]:
    return parse_menu(fetch_text(client, MENU_URL))
