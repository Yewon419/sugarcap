"""아마스빈 (names only; values are estimates, `estimate.py`).

Amasvin publishes no nutrition. `/sub/menu.html` is static HTML: `#tab_drink >
ul.menu_gallery > li` is one tab, its first `a` the tab name and every `h3` a drink. The
bakery tab is food and is skipped. One cup per drink, temperature not split.
"""

from __future__ import annotations

import httpx
from bs4 import BeautifulSoup

from sugarcap_scrape.http import fetch_text
from sugarcap_scrape.models import Brand, RawServing, Temperature
from sugarcap_scrape.parse import ParseError, clean_text

BRAND = Brand(
    id="amasvin",
    name="아마스빈",
    serving_note="영양정보 비공개, 값은 추정치",
    has_size_choice=False,
)

MENU_URL = "https://www.amasvin.com/sub/menu.html"
FOOD_TABS = frozenset({"베이커리"})
SIZE_LABEL = "기본"

# Comparable drinks for names that do not say what they are (`estimate.py`).
LIKE: dict[str, str | None] = {
    "얼그레이 프렌치 블루": None,
    "레자몽 버블에이드": "자몽 에이드",
    "리얼레몬 버블에이드": "레몬에이드",
}


def parse_menu(html: str) -> list[tuple[str, str]]:
    """(tab name, drink name) for every drink tab."""
    soup = BeautifulSoup(html, "html.parser")
    tabs = soup.select("#tab_drink > ul.menu_gallery > li")
    if not tabs:
        raise ParseError(f"no #tab_drink tabs on {MENU_URL}")
    items: list[tuple[str, str]] = []
    for tab in tabs:
        title = tab.find("a")
        if title is None:
            raise ParseError(f"menu tab without a name on {MENU_URL}")
        category = clean_text(title.get_text())
        if category in FOOD_TABS:
            continue
        items.extend((category, clean_text(h3.get_text())) for h3 in tab.select("h3"))
    return items


def scrape(client: httpx.Client) -> list[RawServing]:
    items = parse_menu(fetch_text(client, MENU_URL))
    if not items:
        raise ParseError(f"no drinks on {MENU_URL}")
    return [
        RawServing(
            brand_id=BRAND.id,
            drink_name=name,
            category=category,
            temperature=Temperature.BOTH,
            size_label=SIZE_LABEL,
            source_url=MENU_URL,
        )
        for category, name in items
    ]
