"""可不可熟成紅茶 (KEBUKE): the menu page, read as HTML text.

`kebuke.com/menu/` lists every drink as `div.menu-item` under a category block
(`p.page-menu__product-title`). The nutrition sits in `p.menu-item__sugar`, one
line per `<br>`:

    【中杯】
    糖量：45 g；熱量：180 kcal
    咖啡因總含量 101-200 mg；全素者可食用
    【大杯】
    ...

Caffeine is printed as a number ("咖啡因總量 135.5 mg"), a Taiwan band
("≦100", "101~200", "≥ 201"), or "無含咖啡因". Several drinks print one caffeine
line after both cup rows; that line covers every size of the drink. Milk teas
list a second recipe under "●<name>(＋酷涼配方)", kept as its own drink.

Values do not differ by temperature, so every drink is `both`. Cup volume is
one page-wide note ("大杯 700 ml／中杯 500 ml"). The waffle block is food.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

import httpx
from bs4 import BeautifulSoup, Tag

from sugarcap_scrape.http import fetch_text
from sugarcap_scrape.models import Brand, CaffeineRange, RawServing, Temperature
from sugarcap_scrape.parse import ParseError, clean_text

BRAND = Brand(
    id="tw-kebuke",
    name="可不可熟成紅茶",
    serving_note="每杯，依官方公告（中杯 500 ml、大杯 700 ml）",
    has_size_choice=True,
)

MENU_URL = "https://kebuke.com/menu/"
FOOD_CATEGORY_MARK = "金蒔燒"
SIZES = ("中杯", "大杯")

_VOLUME_NOTE = re.compile(r"飲品容量：\s*大杯\s*(\d+)\s*ml\s*／\s*中杯\s*(\d+)\s*ml")
_SIZE = re.compile(r"^【(中杯|大杯)】$")
_SUGAR = re.compile(r"糖量\s*[：:]\s*(\d+(?:\.\d+)?)\s*g", re.IGNORECASE)
_CAFFEINE_EXACT = re.compile(r"咖啡因總(?:含)?量\s*(\d+(?:\.\d+)?)\s*mg", re.IGNORECASE)
_CAFFEINE_BAND = re.compile(r"咖啡因總(?:含)?量\s*(\d+)\s*[-~～]\s*(\d+)\s*mg", re.IGNORECASE)
_CAFFEINE_AT_MOST = re.compile(r"咖啡因總(?:含)?量\s*[≦≤]\s*(\d+)\s*mg", re.IGNORECASE)
_CAFFEINE_AT_LEAST = re.compile(r"咖啡因總(?:含)?量\s*[≥≧]\s*(\d+)\s*mg", re.IGNORECASE)
NO_CAFFEINE = "無含咖啡因"


@dataclass(frozen=True)
class Caffeine:
    mg: float
    band: CaffeineRange | None


@dataclass
class _Recipe:
    name: str
    sugar: dict[str, float] = field(default_factory=dict)
    caffeine: dict[str, Caffeine] = field(default_factory=dict)
    sizes: list[str] = field(default_factory=list)


def parse_caffeine(line: str, context: str) -> Caffeine | None:
    """The caffeine on one line, or None when the line does not mention caffeine."""
    if NO_CAFFEINE in line:
        return Caffeine(mg=0.0, band=None)
    if "咖啡因總" not in line:
        return None
    if match := _CAFFEINE_BAND.search(line):
        low, high = float(match.group(1)), float(match.group(2))
        return Caffeine(mg=high, band=CaffeineRange(min_mg=low, max_mg=high))
    if match := _CAFFEINE_AT_MOST.search(line):
        high = float(match.group(1))
        return Caffeine(mg=high, band=CaffeineRange(min_mg=0, max_mg=high))
    if match := _CAFFEINE_AT_LEAST.search(line):
        low = float(match.group(1))
        return Caffeine(mg=low, band=CaffeineRange(min_mg=low))
    if match := _CAFFEINE_EXACT.search(line):
        return Caffeine(mg=float(match.group(1)), band=None)
    raise ParseError(f"caffeine: unreadable {line!r} ({context})")


def volumes(page_text: str) -> dict[str, int]:
    match = _VOLUME_NOTE.search(page_text)
    if match is None:
        raise ParseError(f"no cup volume note on {MENU_URL}")
    return {"大杯": int(match.group(1)), "中杯": int(match.group(2))}


def parse_recipes(name: str, lines: list[str]) -> list[_Recipe]:
    """Every recipe in one item's nutrition text. Lines are already split on `<br>`."""
    recipes: list[_Recipe] = []
    current: _Recipe | None = None
    size: str | None = None
    for raw in lines:
        line = clean_text(raw)
        if not line:
            continue
        if line.startswith("●"):
            current = _Recipe(name=clean_text(line.removeprefix("●")))
            recipes.append(current)
            size = None
            continue
        if current is None:
            current = _Recipe(name=name)
            recipes.append(current)
        if match := _SIZE.match(line):
            size = match.group(1)
            if size in current.sizes:
                raise ParseError(f"{current.name}: {size} printed twice")
            current.sizes.append(size)
            continue
        if line.startswith("#") or size is None:
            continue
        context = f"{current.name} {size}"
        if match := _SUGAR.search(line):
            current.sugar[size] = float(match.group(1))
        caffeine = parse_caffeine(line, context)
        if caffeine is not None:
            current.caffeine[size] = caffeine
    return [recipe for recipe in recipes if recipe.sizes]


def rows_of(recipe: _Recipe, category: str, cup_ml: dict[str, int]) -> list[RawServing]:
    caffeine = dict(recipe.caffeine)
    if len(caffeine) == 1:
        # One caffeine line after both cup rows is the drink's line, not the last cup's.
        only = next(iter(caffeine.values()))
        caffeine = dict.fromkeys(recipe.sizes, only)
    rows: list[RawServing] = []
    for size in recipe.sizes:
        cup = caffeine.get(size)
        rows.append(
            RawServing(
                brand_id=BRAND.id,
                drink_name=recipe.name,
                category=category,
                temperature=Temperature.BOTH,
                size_label=size,
                volume_ml=cup_ml[size],
                sugar_g=recipe.sugar.get(size),
                caffeine_mg=None if cup is None else cup.mg,
                caffeine_range=None if cup is None else cup.band,
                source_url=MENU_URL,
            )
        )
    return rows


def _lines(tag: Tag) -> list[str]:
    return tag.get_text("\n").split("\n")


def parse_menu(page: str) -> list[RawServing]:
    cup_ml = volumes(page)
    soup = BeautifulSoup(page, "html.parser")
    rows: list[RawServing] = []
    for block in soup.select("div.page-menu__product"):
        title = block.select_one("p.page-menu__product-title")
        if title is None:
            raise ParseError(f"category block without a title on {MENU_URL}")
        category = clean_text(title.get_text(" "))
        if FOOD_CATEGORY_MARK in category:
            continue
        for item in block.select("div.menu-item"):
            name_tag = item.select_one("p.menu-item__name")
            sugar_tag = item.select_one("p.menu-item__sugar")
            if name_tag is None or sugar_tag is None:
                raise ParseError(f"{category}: menu item without name or nutrition text")
            name = clean_text(name_tag.get_text(" "))
            recipes = parse_recipes(name, _lines(sugar_tag))
            if not recipes:
                raise ParseError(f"{category} / {name}: no cup rows")
            for recipe in recipes:
                rows.extend(rows_of(recipe, category, cup_ml))
    if not rows:
        raise ParseError(f"no drinks on {MENU_URL}")
    return rows


def scrape(client: httpx.Client) -> list[RawServing]:
    return parse_menu(fetch_text(client, MENU_URL))
