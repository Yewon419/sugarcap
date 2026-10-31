"""커피빈 scraper.

`/menu/list.asp?category=N&page=P` is server-rendered, 9 drinks a page, and carries the
nutrition on the list itself: `ul.menu_list > li` with `span.kor` / `span.eng` and
`div.info > dl` pairs of value (`dt`) and label (`dd`, e.g. "당<br/> g", "카페인<br/>mg").
Some drinks omit the 당 or 카페인 `dl` entirely, so values are read by label, not position.
A next page exists when the HTML links `page=P+1`.

One value per drink and no size or volume anywhere on the site, so every drink has a
single serving labelled 기본. Hot and iced are separate products; the iced one carries
"아이스" in its name, and the ice blended sections are cold only.
"""

from __future__ import annotations

import re

import httpx
from bs4 import BeautifulSoup, Tag

from sugarcap_scrape.http import fetch_text
from sugarcap_scrape.models import Brand, RawServing, Temperature
from sugarcap_scrape.parse import ParseError, clean_text, optional_number

BRAND = Brand(
    id="coffeebean",
    name="커피빈",
    serving_note="1잔 기준(사이즈 미게시). 커피빈 공식 영양정보 게시값",
    has_size_choice=False,
)

LIST_URL = "https://www.coffeebeankorea.com/menu/list.asp"
SIZE_LABEL = "기본"

# (category code, name as in the site menu). Food (4-8) is not scraped.
CATEGORIES = (
    ("32", "신음료"),
    ("13", "에스프레소 음료"),
    ("14", "브루드 커피"),
    ("18", "티"),
    ("17", "티 라떼"),
    ("12", "아이스 블렌디드 (Coffee)"),
    ("11", "아이스 블렌디드 (Non-Coffee)"),
    ("26", "커피빈 주스(병음료)"),
    ("24", "기타 제조 음료"),
)
ICED_ONLY_CATEGORIES = frozenset({"아이스 블렌디드 (Coffee)", "아이스 블렌디드 (Non-Coffee)"})
MAX_PAGES = 30


def classify_temperature(name: str, category: str) -> Temperature:
    tokens = name.split()
    if "아이스" in tokens:
        return Temperature.ICED
    if "핫" in tokens:
        return Temperature.HOT
    if category in ICED_ONLY_CATEGORIES:
        return Temperature.ICED
    return Temperature.BOTH


def _nutrients(item: Tag) -> dict[str, str]:
    """Label word (e.g. '당', '카페인') -> value text."""
    values: dict[str, str] = {}
    for pair in item.select("div.info > dl"):
        value = pair.find("dt")
        label = pair.find("dd")
        if not isinstance(value, Tag) or not isinstance(label, Tag):
            continue
        word = clean_text(label.get_text(" ")).split(" ")[0]
        values[word] = clean_text(value.get_text())
    return values


def parse_list_page(html: str, *, category: str, source_url: str) -> list[RawServing]:
    soup = BeautifulSoup(html, "html.parser")
    rows: list[RawServing] = []
    for item in soup.select("ul.menu_list > li"):
        kor = item.select_one("span.kor")
        if kor is None:
            raise ParseError(f"{category}: menu item without span.kor at {source_url}")
        name = clean_text(kor.get_text())
        if not name:
            raise ParseError(f"{category}: empty drink name at {source_url}")
        eng = item.select_one("span.eng")
        name_en = clean_text(eng.get_text()) if eng is not None else ""
        values = _nutrients(item)
        rows.append(
            RawServing(
                brand_id=BRAND.id,
                drink_name=name,
                drink_name_en=name_en or None,
                category=category,
                temperature=classify_temperature(name, category),
                size_label=SIZE_LABEL,
                sugar_g=optional_number(values.get("당")),
                caffeine_mg=optional_number(values.get("카페인")),
                source_url=source_url,
            )
        )
    return rows


def has_next_page(html: str, page: int) -> bool:
    return re.search(rf"[?&]page={page + 1}(?!\d)", html) is not None


def scrape(client: httpx.Client) -> list[RawServing]:
    rows: list[RawServing] = []
    for code, category in CATEGORIES:
        for page in range(1, MAX_PAGES + 1):
            params = {"category": code, "page": str(page)}
            html = fetch_text(client, LIST_URL, params=params)
            source_url = f"{LIST_URL}?category={code}&page={page}"
            page_rows = parse_list_page(html, category=category, source_url=source_url)
            if page == 1 and not page_rows:
                raise ParseError(f"{category}: no drinks at {source_url}")
            rows.extend(page_rows)
            if not has_next_page(html, page):
                break
        else:
            raise ParseError(f"{category}: more than {MAX_PAGES} pages")
    return rows
