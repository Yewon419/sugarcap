"""우지커피 (names only; values are estimates, `estimate.py`).

OOZY COFFEE publishes no nutrition. Its own site (`oozycoffee.com`) answers 403 to us (curl
and a real Chrome, 2026-10-31), so the menu is read from Internet Archive copies of the
official menu pages, pinned by snapshot time below. To refresh the menu, pick newer
snapshots (`web.archive.org/cdx/search/cdx?url=oozycoffee.com/27`) and update `PAGES`.
The Wayback Machine answers 429 to the browser-like User-Agent the other brands use, so the
archive is read with its own client that names this tool (2026-11-01).

Each page lists every drink twice (`._item.item_gallary`); the name is the first text of
`.title`, the description sits in its `span.body`. Desserts on the frappe page (bingsu,
affogato, smoothie bowls, sorbet, frozen persimmon) are not drinks and are skipped.
"""

from __future__ import annotations

import httpx
from bs4 import BeautifulSoup

from sugarcap_scrape.http import fetch_text
from sugarcap_scrape.models import Brand, RawServing, Temperature
from sugarcap_scrape.parse import ParseError, clean_text

BRAND = Brand(
    id="oozy",
    name="우지커피",
    serving_note="영양정보 비공개, 값은 추정치",
    has_size_choice=False,
)

ARCHIVE_URL = "https://web.archive.org/web/{timestamp}id_/{url}"
ARCHIVE_USER_AGENT = "sugarcap-scrape/1.0 (+https://github.com/Yewon419/sugarcap)"
SIZE_LABEL = "기본"
# (official menu page, archive snapshot, menu name on the site)
PAGES = (
    ("https://oozycoffee.com/27", "20260308131800", "콜드브루"),
    ("https://www.oozycoffee.com/28", "20260613155557", "베버리지"),
    ("https://www.oozycoffee.com/29", "20260613161036", "프라페"),
    ("https://oozycoffee.com/30", "20260510083523", "에이드 & 모히또"),
    ("https://oozycoffee.com/31", "20260314100333", "티 & 주스"),
)
DESSERT_WORDS = ("아포가토", "스무디 볼", "스무디볼", "샤베트", "아이스홍시")

# Comparable drinks for names that do not say what they are (`estimate.py`).
LIKE: dict[str, str | None] = {
    "디카페인 콜드브루 커피": "디카페인 콜드브루",
    "딥 말차베리 라떼": "말차 라떼",
    "우지 딥 말차 젤라떼": "말차 라떼",
    "딥 초코베리 라떼": "초코 라떼",
    "리얼초코 라떼": "초코 라떼",
    "마시멜로우초코 라떼": "초코 라떼",
    "얼그레이초코 라떼": "초코 라떼",
    "스윗오렌지초코라떼": "초코 라떼",
    "크리미땅콩초코라떼": "초코 라떼",
    "봄딸기쇼콜라떼": "초코 라떼",
    "리얼딸기 라떼": "딸기 라떼",
    "리얼블루베리 라떼": None,
    "브라운슈가 라떼": "흑당 라떼",
    "호지밀크티 라떼": "호지 밀크티",
    "호지넛크림라떼": "호지 라떼",
    "할미숫가루": "미숫가루",
    "율무차": "율무",
    "오곡 프로틴 드링크": None,
    "피넛 프로틴 드링크": None,
    "구슬톡톡 자몽펀치": "자몽 에이드",
    "봄딸기라임에이드": "딸기 에이드",
    "딸기오렌망에이드": "딸기 에이드",
    "체리콕": None,
    "딸기빙수프라페": "딸기 프라페",
    "초코빙수프라페": "초코 프라페",
    "호지밀크티프라페": "밀크티 프라페",
    "나는 요거트오렌망이야": "요거트 스무디",
    "봄딸기밀크쉐이크": "딸기 쉐이크",
    "로열밀크티 쉐이크": "밀크티 쉐이크",
    "수박화채스무디": "수박 스무디",
    "리얼수박주스": "수박 주스",
    "달달고구마식혜": "식혜",
    "홍시듬뿍식혜": "식혜",
    "청귤차": "청귤",
    "연유크리미슈페너": "아인슈페너",
    "오렌지크리미슈페너": "아인슈페너",
    "율무크림콜드브루": "크림 콜드브루",
}


def is_dessert(name: str) -> bool:
    if "빙수" in name and not name.endswith("프라페"):
        return True
    return any(word in name for word in DESSERT_WORDS)


def parse_menu(html: str) -> list[str]:
    """Drink names on one menu page, first appearance order, desserts dropped."""
    soup = BeautifulSoup(html, "html.parser")
    names: list[str] = []
    for title in soup.select("._item.item_gallary .title"):
        name = clean_text(next(title.stripped_strings, ""))
        if not name:
            raise ParseError("menu item with an empty .title")
        if name not in names and not is_dessert(name):
            names.append(name)
    return names


def archive_url(url: str, timestamp: str) -> str:
    return ARCHIVE_URL.format(timestamp=timestamp, url=url)


def archive_client() -> httpx.Client:
    return httpx.Client(
        headers={"User-Agent": ARCHIVE_USER_AGENT},
        timeout=httpx.Timeout(30.0),
        follow_redirects=True,
    )


def scrape(client: httpx.Client) -> list[RawServing]:
    """`client` is unused: the archive blocks its User-Agent (module docstring)."""
    with archive_client() as archive:
        return [row for page in PAGES for row in scrape_page(archive, *page)]


def scrape_page(client: httpx.Client, url: str, timestamp: str, category: str) -> list[RawServing]:
    source = archive_url(url, timestamp)
    names = parse_menu(fetch_text(client, source))
    if not names:
        raise ParseError(f"{category}: no drinks in {source}")
    return [
        RawServing(
            brand_id=BRAND.id,
            drink_name=name,
            category=category,
            temperature=Temperature.BOTH,
            size_label=SIZE_LABEL,
            source_url=source,
        )
        for name in names
    ]
