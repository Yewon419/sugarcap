"""폴바셋 scraper.

`/menu/List.pb?cid1=A` (COFFEE) and `?cid1=B` (BEVERAGE) carry a sub-category tab bar
(`a[href*="cid2="]`); each sub-category list links drinks as `goView('PB…')`. cid1 C/D/E
are ice cream, food and goods, so they are not scraped.

`/menu/View.pb?dpid=…` is one drink: `.menuTit dt` (Korean name + English span),
`ul.info` 구분 (Hot / Iced / Hot Only / Iced Only, absent on a few), and one
`#pSize_<code>` block per `#pSize` option with 제공량(ml), 당류(g), 카페인(mg).
Hot and iced are separate products. Decaf caffeine is printed as "10mg이하"; that is a
band, kept as `caffeine_range` and counted at its bound. "-" and blanks are unpublished.
"""

from __future__ import annotations

import re

import httpx
from bs4 import BeautifulSoup, Tag

from sugarcap_scrape.http import fetch_text
from sugarcap_scrape.models import Brand, CaffeineRange, RawServing, Temperature
from sugarcap_scrape.parse import ParseError, clean_text, optional_number

BRAND = Brand(
    id="paulbassett",
    name="폴바셋",
    serving_note="사이즈별 1회 제공량(ml) 기준. 폴바셋 공식 영양 정보 게시값",
    has_size_choice=True,
)

BASE_URL = "https://www.baristapaulbassett.co.kr"
LIST_URL = BASE_URL + "/menu/List.pb"
VIEW_URL = BASE_URL + "/menu/View.pb"
DRINK_SECTIONS = ("A", "B")

_TEMPERATURES = {
    "Hot": Temperature.HOT,
    "Hot Only": Temperature.HOT,
    "Iced": Temperature.ICED,
    "Iced Only": Temperature.ICED,
}
_PRODUCT_ID = re.compile(r"goView\('([^']+)'\)")
_SUB_CATEGORY = re.compile(r"cid2=(\w+)")
_AT_MOST = re.compile(r"^(\d+(?:\.\d+)?)\s*(?:mg)?\s*이하$")


def parse_sub_categories(html: str) -> list[tuple[str, str]]:
    """(cid2 code, tab name) pairs from a section list page."""
    soup = BeautifulSoup(html, "html.parser")
    pairs: list[tuple[str, str]] = []
    for link in soup.select('.tabStyleF a[href*="cid2="]'):
        match = _SUB_CATEGORY.search(str(link.get("href", "")))
        if match is None:
            continue
        pairs.append((match.group(1), clean_text(link.get_text())))
    if not pairs:
        raise ParseError("section page without cid2 tabs")
    return pairs


def parse_product_ids(html: str) -> list[str]:
    return list(dict.fromkeys(_PRODUCT_ID.findall(html)))


def parse_caffeine(text: str) -> tuple[float | None, CaffeineRange | None]:
    """'225' -> exact, '10mg이하' -> band 0..10 counted as 10, '-' or '' -> unpublished."""
    value = clean_text(text)
    band = _AT_MOST.match(value)
    if band is not None:
        bound = float(band.group(1))
        return bound, CaffeineRange(min_mg=0, max_mg=bound)
    if value in ("", "-"):
        return None, None
    number = optional_number(value)
    if number is None:
        raise ParseError(f"unreadable caffeine {value!r}")
    return number, None


def _info(soup: BeautifulSoup) -> dict[str, str]:
    """`ul.info` label -> value text (label span removed)."""
    values: dict[str, str] = {}
    for item in soup.select("ul.info > li"):
        label = item.find("span")
        if not isinstance(label, Tag):
            continue
        key = clean_text(label.get_text())
        label.extract()
        values[key] = clean_text(item.get_text())
    return values


def _nutrients(block: Tag) -> dict[str, str]:
    values: dict[str, str] = {}
    for item in block.select("li"):
        title = item.select_one(".tit")
        number = item.select_one(".num")
        if title is not None and number is not None:
            values[clean_text(title.get_text())] = clean_text(number.get_text())
    return values


def parse_product_page(html: str, *, category: str, source_url: str) -> list[RawServing]:
    soup = BeautifulSoup(html, "html.parser")
    title = soup.select_one(".menuTit dt")
    if title is None:
        raise ParseError(f"product page without .menuTit dt at {source_url}")
    en_node = title.find("span")
    name_en = ""
    if isinstance(en_node, Tag):
        name_en = clean_text(en_node.get_text())
        en_node.extract()
    name = clean_text(title.get_text())
    if not name:
        raise ParseError(f"empty drink name at {source_url}")

    kind = _info(soup).get("구분", "")
    if kind and kind not in _TEMPERATURES:
        raise ParseError(f"{name}: unknown temperature {kind!r}")
    temperature = _TEMPERATURES.get(kind, Temperature.BOTH)

    rows: list[RawServing] = []
    for option in soup.select("#pSize option"):
        code = str(option.get("value", ""))
        block = soup.select_one(f"#pSize_{code}")
        if block is None:
            raise ParseError(f"{name}: size option {code!r} without #pSize_{code}")
        volume = block.select_one(".sizeMl span")
        values = _nutrients(block)
        if "당류(g)" not in values or "카페인(mg)" not in values:
            raise ParseError(f"{name} {code}: missing 당류/카페인 rows ({sorted(values)})")
        caffeine_mg, caffeine_range = parse_caffeine(values["카페인(mg)"])
        volume_ml = optional_number(volume.get_text()) if volume is not None else None
        rows.append(
            RawServing(
                brand_id=BRAND.id,
                drink_name=name,
                drink_name_en=name_en or None,
                category=category,
                temperature=temperature,
                size_label=clean_text(option.get_text()),
                volume_ml=int(volume_ml) if volume_ml is not None else None,
                sugar_g=optional_number(values["당류(g)"]),
                caffeine_mg=caffeine_mg,
                caffeine_range=caffeine_range,
                source_url=source_url,
            )
        )
    if not rows:
        raise ParseError(f"{name}: no size options at {source_url}")
    return rows


def scrape(client: httpx.Client) -> list[RawServing]:
    categories: dict[str, str] = {}
    for section in DRINK_SECTIONS:
        page = fetch_text(client, LIST_URL, params={"cid1": section})
        for code, tab in parse_sub_categories(page):
            listed = fetch_text(client, LIST_URL, params={"cid1": section, "cid2": code})
            for product_id in parse_product_ids(listed):
                categories.setdefault(product_id, tab)
    if not categories:
        raise ParseError("no drinks listed in any 폴바셋 drink section")

    rows: list[RawServing] = []
    for product_id, category in categories.items():
        html = fetch_text(client, VIEW_URL, params={"dpid": product_id})
        rows.extend(
            parse_product_page(html, category=category, source_url=f"{VIEW_URL}?dpid={product_id}")
        )
    return rows
