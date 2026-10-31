"""블루보틀 (names only; values are estimates, `estimate.py`).

Blue Bottle Korea publishes no nutrition. The only drink menu on the official store is one
image (`/pages/blue-bottle-menu-cn`, Chinese and English names), so the drinks below are
transcribed from it by hand. `scrape` fails when the page points at a different image, which
means the menu changed and this list has to be re-read. Ice cream is not a drink and is left
out. Sizes (12oz/16oz on some drinks) are prices only, so every drink is one cup.
"""

from __future__ import annotations

import re

import httpx

from sugarcap_scrape.http import fetch_text
from sugarcap_scrape.models import Brand, RawServing, Temperature
from sugarcap_scrape.parse import ParseError

BRAND = Brand(
    id="bluebottle",
    name="블루보틀",
    serving_note="영양정보 비공개. 다른 카페 같은 메뉴로 낸 추정치",
    has_size_choice=False,
)

MENU_URL = "https://kr.bluebottlecoffee.com/pages/blue-bottle-menu-cn"
MENU_IMAGE = "CN_260414.jpg"
SIZE_LABEL = "기본"
_IMAGE = re.compile(r"/files/([A-Za-z]+_\d+\.jpg)")

# (Korean name, English name on the menu, menu section)
DRINKS = (
    ("에스프레소", "Espresso", "에스프레소"),
    ("아메리카노", "Americano", "에스프레소"),
    ("지브롤터", "Gibraltar", "에스프레소"),
    ("카푸치노", "Cappuccino", "에스프레소"),
    ("카페라떼", "Latte", "에스프레소"),
    ("모카", "Mocha", "에스프레소"),
    ("체리 블라썸 라떼", "Cherry Blossom Latte", "에스프레소"),
    ("블렌드", "Blend", "푸어 오버"),
    ("싱글 오리진", "Single Origin", "푸어 오버"),
    ("오지", "Oji", "오지"),
    ("뉴올리언스", "NOLA", "뉴올리언스"),
    ("뉴올리언스 플로트", "NOLA Float", "뉴올리언스"),
    ("콜드브루", "Cold Brew", "콜드브루"),
    ("오렌지 주스", "Orange Juice", "티 앤 모어"),
    ("레몬티", "Lemon Tea", "티 앤 모어"),
    ("레몬 유자 피즈", "Lemon Yuza Fizz", "티 앤 모어"),
    ("스트로베리 피즈", "Strawberry Fizz", "티 앤 모어"),
    ("초콜릿 밀크", "Chocolate Milk", "티 앤 모어"),
    ("호지차 라떼", "Hojicha Latte", "티 앤 모어"),
    ("말차 라떼", "Matcha Latte", "티 앤 모어"),
    ("체리 블라썸 말차 라떼", "Cherry Blossom Matcha Latte", "티 앤 모어"),
)

# Comparable drinks for names that do not say what they are (`estimate.py`).
LIKE: dict[str, str | None] = {
    "지브롤터": "플랫화이트",
    "모카": "카페모카",
    "체리 블라썸 라떼": "바닐라 라떼",
    "블렌드": "드립커피",
    "싱글 오리진": "드립커피",
    "오지": "콜드브루",
    "뉴올리언스": "콜드브루 라떼",
    "뉴올리언스 플로트": None,
    "레몬 유자 피즈": "레몬에이드",
    "초콜릿 밀크": "초코라떼",
    "호지차 라떼": "호지 라떼",
    "체리 블라썸 말차 라떼": "말차 라떼",
}


def menu_image(html: str) -> str:
    found = _IMAGE.search(html)
    if found is None:
        raise ParseError(f"no menu image on {MENU_URL}")
    return found.group(1)


def rows() -> list[RawServing]:
    return [
        RawServing(
            brand_id=BRAND.id,
            drink_name=name,
            drink_name_en=name_en,
            category=category,
            temperature=Temperature.BOTH,
            size_label=SIZE_LABEL,
            source_url=MENU_URL,
        )
        for name, name_en, category in DRINKS
    ]


def scrape(client: httpx.Client) -> list[RawServing]:
    image = menu_image(fetch_text(client, MENU_URL))
    if image != MENU_IMAGE:
        raise ParseError(
            f"{MENU_URL} now shows {image}, not {MENU_IMAGE}: re-read the menu into DRINKS"
        )
    return rows()
