"""Dutch Bros: the published nutritional guide PDF, read as text.

Each section opens with a header block (one column name per line, from "Type"
to "Allergies"), followed by a title line and rows like

    911 Hot Large 630 330 37 24 0 120 240 62 2 58 14 290 Contains Milk.

Column sets differ by section: protein coffee adds %DV and calcium before
caffeine, Myst adds magnesium and vitamin C after it. The seasonal pages print
one wide header over rows of both widths, so a row whose value count does not
match its header is read with the base 12-column layout.

The guide publishes no cup volume, so `volume_ml` stays None. Food (header
without "Type") and toppings are skipped. Blended and toasted rows share names
with iced rows, so the type is kept in the drink name.
"""

from __future__ import annotations

import io
import logging
import re
from typing import NamedTuple

import httpx
from pypdf import PdfReader

from sugarcap_scrape.http import fetch_bytes
from sugarcap_scrape.ids import serving_id
from sugarcap_scrape.models import Brand, RawServing, Temperature
from sugarcap_scrape.parse import ParseError, clean_text

log = logging.getLogger(__name__)

BRAND = Brand(
    id="us-dutchbros",
    name="Dutch Bros",
    serving_note="Per cup size, as published",
    has_size_choice=True,
)

PDF_URL = "https://www.dutchbros.com/website/menu/nutritional-guide.pdf"

SUGAR = "Total sugars (g)"
CAFFEINE = "Caffeine (mg)"
CARBS = "Total Carbs (g)"
TOTAL_FAT = "Total fat (g)"
SATURATED_FAT = "Saturated fat (g)"
BASE_COLUMNS = (
    "Total calories (kcal)",
    "Calories from fat (fat cal)",
    TOTAL_FAT,
    SATURATED_FAT,
    "Trans fat (g)",
    "Cholesterol (mg)",
    "Sodium (mg)",
    CARBS,
    "Dietary fiber (g)",
    SUGAR,
    "Protein (g)",
    CAFFEINE,
)
TYPES = {
    "Hot": Temperature.HOT,
    "Iced": Temperature.ICED,
    "Blended": Temperature.ICED,
    "Toasted": Temperature.ICED,
}
NAMED_TYPES = frozenset({"Blended", "Toasted"})
SKIPPED_CATEGORIES = frozenset({"TOPPINGS"})
IGNORED_LINES = frozenset(
    {"Dutch Bros Coffee Nutritional Guide", "AVAILABILITY MAY VARY BY LOCATION"}
)
MAX_TITLE_WORDS = 5

_ROW = re.compile(
    r"^(?P<name>.+?) (?P<size>Small|Medium|Large|Kids|Nitro|Dub Shot|2 Scoops|Hashtag)"
    r"(?P<values>(?: <?\d+(?:\.\d+)?)+)(?: (?P<rest>\D.*))?$"
)
_TYPE_SUFFIX = re.compile(r"^(?P<name>.+) (?P<type>Hot|Iced|Blended|Toasted)$")


class Header(NamedTuple):
    columns: tuple[str, ...]
    has_type: bool


def parse_header(lines: list[str]) -> Header:
    """Column names between 'Size' and 'Allergies', joining names wrapped onto two lines."""
    names: list[str] = []
    for raw in lines:
        line = clean_text(raw).lstrip("*")
        if not line:
            continue
        if names and (line.startswith("(") or names[-1].count("(") > names[-1].count(")")):
            names[-1] = clean_text(f"{names[-1]} {line}")
        else:
            names.append(line)
    has_type = "Type" in names
    columns = tuple(name for name in names if name not in {"Type", "Size", "Allergies"})
    return Header(columns=columns, has_type=has_type)


def title_of(line: str) -> str | None:
    """A section title, or None for description and footer lines."""
    text = line.strip()
    words = text.split()
    # "LEMONADE LEMONADE INFUSED WITH ANY FLAVOR." is a title run into its description.
    if len(words) > 1 and words[0] == words[1]:
        return words[0]
    # "Chocolate Milk     OUR EXCLUSIVE CHOCOLATE MILK, ..." likewise, split by a wide gap.
    text = re.split(r"\s{3,}", text)[0]
    if not text or text in IGNORED_LINES:
        return None
    if any(mark in text for mark in ".!,") or len(text.split()) > MAX_TITLE_WORDS:
        return None
    return text


def display_category(title: str) -> str:
    """Core sections are printed in capitals ("DUTCH BROS REBEL®"), seasonal ones in title case.

    Capitalize only the all-caps ones so both read alike next to Starbucks' title-case categories.
    """
    if title != title.upper():
        return title
    return " ".join(word.capitalize() for word in title.split())


def _value(token: str) -> float:
    # "<1" is published for trace amounts; it is below 1, read as 0.
    return 0.0 if token.startswith("<") else float(token)


def _is_shifted(values: dict[str, str]) -> bool:
    """A part larger than its whole: sugar above total carbs, or saturated above total fat."""
    return _value(values[SUGAR]) > _value(values[CARBS]) or _value(values[SATURATED_FAT]) > _value(
        values[TOTAL_FAT]
    )


def _columns_for(header: Header, count: int, context: str) -> tuple[str, ...]:
    if count == len(header.columns):
        needed = (TOTAL_FAT, SATURATED_FAT, CARBS, SUGAR, CAFFEINE)
        missing = [name for name in needed if name not in header.columns]
        if missing:
            raise ParseError(f"header lacks {missing} ({context}): {header.columns}")
        return header.columns
    if count == len(BASE_COLUMNS):
        return BASE_COLUMNS
    raise ParseError(
        f"{count} values, header has {len(header.columns)} ({context}): {header.columns}"
    )


def parse_row(line: str, header: Header, category: str) -> RawServing | None:
    """One guide row, or None when the line is not a drink row."""
    match = _ROW.match(line.strip())
    if match is None:
        return None
    if category in SKIPPED_CATEGORIES:
        return None
    name, size = match.group("name"), match.group("size")
    temperature = Temperature.HOT
    typed = _TYPE_SUFFIX.match(name)
    if typed is not None:
        name, kind = typed.group("name"), typed.group("type")
        temperature = TYPES[kind]
        if kind in NAMED_TYPES and kind not in name.split():
            name = f"{name} {kind}"
    context = f"{name} {temperature.value} {size}"
    tokens = match.group("values").split()
    values = dict(zip(_columns_for(header, len(tokens), context), tokens, strict=True))
    sugar: float | None = _value(values[SUGAR])
    caffeine: float | None = _value(values[CAFFEINE])
    if _is_shifted(values):
        # The guide itself prints some rows shifted by a column; no value there is trustworthy.
        log.warning("us-dutchbros: %s: shifted row %s, values withheld", context, tokens)
        sugar, caffeine = None, None
    return RawServing(
        brand_id=BRAND.id,
        drink_name=clean_text(name),
        category=display_category(category),
        temperature=temperature,
        size_label=size,
        volume_ml=None,
        sugar_g=sugar,
        caffeine_mg=caffeine,
        source_url=PDF_URL,
    )


def parse_guide(text: str) -> list[RawServing]:
    """Every drink row in the guide's extracted text."""
    rows: list[RawServing] = []
    header: Header | None = None
    header_lines: list[str] | None = None
    category: str | None = None
    for line in text.splitlines():
        stripped = clean_text(line)
        if header_lines is not None:
            header_lines.append(line)
            if stripped == "Allergies":
                header, header_lines, category = parse_header(header_lines), None, None
            continue
        if stripped == "Type" or stripped.startswith("Total calories"):
            header_lines = [line]
            continue
        if header is None or not header.has_type:
            continue
        if category is not None:
            row = parse_row(line, header, category)
            if row is not None:
                rows.append(row)
                continue
            if _ROW.match(stripped) is not None:
                continue
        title = title_of(line)
        if title is not None:
            category = title
        elif category is None and _ROW.match(stripped) is not None:
            raise ParseError(f"row before any section title: {stripped!r}")
    if not rows:
        raise ParseError(f"no drink rows in {PDF_URL}")
    return drop_repeats(rows)


def drop_repeats(rows: list[RawServing]) -> list[RawServing]:
    """The guide prints some drinks in two sections; keep the first. Differing values raise."""
    kept: dict[str, RawServing] = {}
    for row in rows:
        key = serving_id(row)
        first = kept.get(key)
        if first is None:
            kept[key] = row
        elif (first.sugar_g, first.caffeine_mg) != (row.sugar_g, row.caffeine_mg):
            raise ParseError(f"{key}: printed twice with different values ({first} / {row})")
    return list(kept.values())


def pdf_text(content: bytes) -> str:
    reader = PdfReader(io.BytesIO(content))
    return "\n".join(page.extract_text() for page in reader.pages)


def scrape(client: httpx.Client) -> list[RawServing]:
    return parse_guide(pdf_text(fetch_bytes(client, PDF_URL)))
