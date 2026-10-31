"""배스킨라빈스 scraper (drinks only: 음료 and 커피; scooped ice cream is not a drink).

`/menu/list_subcategory.php?category=C` (음료) and `D` (커피) link product groups as
`view_subcategory.php?seq=N`. A group page holds one `.subcategory-view__product` per
cup, each with an `h4` POS-style name and `dt/dd` pairs: 1회 제공량(g), 당류(g), 카페인(mg).

The `h4` carries temperature, size and decaf in several spellings:
`I_R)믹솔로지 티 프로스티`, `H_LD)아메리카노`, `I_R)D몬치치(보이)아메리카노`,
`ICED 연유라떼R`, `카페31 아메리카노 ICED R`, `바나나 카페라떼(DECAF)`, `자몽 히비스커스 티(ICED)`.
`parse_cup_name` reads all of them. Cups without a temperature mark stay `both`.

Values as published: sugar ranges ("38~63") count at the upper bound, caffeine ranges are
a `caffeine_range`, "*" marks high caffeine, and the page defines "-" as 해당없음 (0).
Serving size is printed in grams only, so `volume_ml` stays empty.
"""

from __future__ import annotations

import re
from dataclasses import dataclass

import httpx
from bs4 import BeautifulSoup

from sugarcap_scrape.http import fetch_text
from sugarcap_scrape.models import Brand, CaffeineRange, RawServing, Temperature
from sugarcap_scrape.parse import ParseError, clean_text, first_number

BRAND = Brand(
    id="baskin",
    name="배스킨라빈스",
    serving_note="사이즈별 1회 제공량 기준. 배스킨라빈스 공식 영양정보 게시값",
    has_size_choice=True,
)

BASE_URL = "https://www.baskinrobbins.co.kr/menu/"
LIST_URL = BASE_URL + "list_subcategory.php"
VIEW_URL = BASE_URL + "view_subcategory.php"
CATEGORIES = (("C", "음료"), ("D", "커피"))

SIZE_LABELS = {"R": "레귤러", "L": "라지", "K": "킹"}
DEFAULT_SIZE = "기본"
NOT_APPLICABLE = "-"

_PREFIX = re.compile(r"^(?P<temp>[HI])_(?P<size>[RLK])?(?P<decaf>D)?\)?\s*")
_DECAF_AFTER_PREFIX = re.compile(r"^D(?=[가-힣])")
_TEMPERATURE_WORD = re.compile(r"\(?(?<![A-Za-z])(HOT|ICED)(?![A-Za-z])\)?")
_DECAF_WORD = re.compile(r"\(DECAF\)")
_TRAILING_SIZE = re.compile(r"(?<=[가-힣\s)])([RLK])$")
_RANGE = re.compile(r"^(\d+(?:\.\d+)?)\s*~\s*(\d+(?:\.\d+)?)$")
_SEQ = re.compile(r"view_subcategory\.php\?seq=(\d+)")
_PREFIX_TEMPERATURES = {"H": Temperature.HOT, "I": Temperature.ICED}
_WORD_TEMPERATURES = {"HOT": Temperature.HOT, "ICED": Temperature.ICED}


@dataclass(frozen=True)
class CupName:
    drink_name: str
    temperature: Temperature
    size_label: str


def parse_cup_name(raw: str) -> CupName:
    """Split a POS-style cup title into drink name, temperature and size."""
    text = clean_text(raw)
    temperature = Temperature.BOTH
    size: str | None = None
    decaf = False

    prefix = _PREFIX.match(text)
    if prefix is not None:
        temperature = _PREFIX_TEMPERATURES[prefix.group("temp")]
        size = prefix.group("size")
        decaf = prefix.group("decaf") is not None
        text = text[prefix.end() :]
        if _DECAF_AFTER_PREFIX.match(text):
            decaf = True
            text = text[1:]

    for word in _TEMPERATURE_WORD.finditer(text):
        temperature = _WORD_TEMPERATURES[word.group(1)]
    text = clean_text(_TEMPERATURE_WORD.sub(" ", text))

    if _DECAF_WORD.search(text):
        decaf = True
        text = clean_text(_DECAF_WORD.sub(" ", text))

    trailing = _TRAILING_SIZE.search(text)
    if trailing is not None:
        if size is None:
            size = trailing.group(1)
        text = clean_text(text[: trailing.start()])

    if size == "K" and text.startswith("킹 "):
        text = text[len("킹 ") :]
    if decaf and "디카페인" not in text:
        text = f"디카페인 {text}"
    if not text:
        raise ParseError(f"empty drink name in cup title {raw!r}")
    label = SIZE_LABELS[size] if size is not None else DEFAULT_SIZE
    return CupName(drink_name=text, temperature=temperature, size_label=label)


def parse_sugar(text: str) -> float:
    value = clean_text(text)
    if value == NOT_APPLICABLE:
        return 0.0
    band = _RANGE.match(value)
    if band is not None:
        return float(band.group(2))
    return first_number(value, field="당류", context=value)


def parse_caffeine(text: str) -> tuple[float, CaffeineRange | None]:
    """'131*' -> 131, '5~6' -> band counted as 6, '-' (해당없음) -> 0."""
    value = clean_text(text).rstrip("*").strip()
    if value == NOT_APPLICABLE:
        return 0.0, None
    band = _RANGE.match(value)
    if band is not None:
        low, high = float(band.group(1)), float(band.group(2))
        return high, CaffeineRange(min_mg=low, max_mg=high)
    return first_number(value, field="카페인", context=text), None


def parse_group_seqs(html: str) -> list[str]:
    return list(dict.fromkeys(_SEQ.findall(html)))


def parse_group_page(html: str, *, category: str, source_url: str) -> list[RawServing]:
    soup = BeautifulSoup(html, "html.parser")
    rows: list[RawServing] = []
    for product in soup.select(".subcategory-view__product"):
        title = product.find("h4")
        if title is None:
            raise ParseError(f"cup without h4 at {source_url}")
        cup = parse_cup_name(title.get_text())
        values = {
            clean_text(dt.get_text()): clean_text(dd.get_text())
            for dt, dd in zip(product.select("dt"), product.select("dd"), strict=True)
        }
        if "당류(g)" not in values or "카페인(mg)" not in values:
            raise ParseError(f"{cup.drink_name}: missing 당류/카페인 ({sorted(values)})")
        caffeine_mg, caffeine_range = parse_caffeine(values["카페인(mg)"])
        rows.append(
            RawServing(
                brand_id=BRAND.id,
                drink_name=cup.drink_name,
                category=category,
                temperature=cup.temperature,
                size_label=cup.size_label,
                sugar_g=parse_sugar(values["당류(g)"]),
                caffeine_mg=caffeine_mg,
                caffeine_range=caffeine_range,
                source_url=source_url,
            )
        )
    if not rows:
        raise ParseError(f"no .subcategory-view__product at {source_url}")
    return rows


def merge_spellings(rows: list[RawServing]) -> list[RawServing]:
    """One spelling per drink: cups of a drink are spaced differently ("감귤캐모마일티프로스티")."""
    spelling: dict[tuple[str, Temperature], str] = {}
    merged: list[RawServing] = []
    for row in rows:
        key = (row.drink_name.replace(" ", ""), row.temperature)
        name = spelling.setdefault(key, row.drink_name)
        merged.append(
            row if name == row.drink_name else row.model_copy(update={"drink_name": name})
        )
    return merged


def scrape(client: httpx.Client) -> list[RawServing]:
    rows: list[RawServing] = []
    for code, category in CATEGORIES:
        listing = fetch_text(client, LIST_URL, params={"category": code})
        seqs = parse_group_seqs(listing)
        if not seqs:
            raise ParseError(f"category {code}: no product groups at {LIST_URL}")
        for seq in seqs:
            html = fetch_text(client, VIEW_URL, params={"seq": seq})
            rows.extend(
                parse_group_page(html, category=category, source_url=f"{VIEW_URL}?seq={seq}")
            )
    return merge_spellings(rows)
