"""Basic (everywhere else): everyday cafe drinks for countries without a catalog.

For devices outside Korea, the US and Taiwan (SPEC §9.9, 2026-11-28). English names, values
from the Korean catalog (`estimate.py` over its publishing brands, the deepest pool we have),
so every drink names the Korean drink it is compared with.
"""

from __future__ import annotations

import httpx

from sugarcap_scrape.models import Brand, RawServing, Temperature

BRAND = Brand(
    id="global-basic",
    name="Basic",
    serving_note="Typical café drink, estimated values",
    has_size_choice=False,
)

SIZE_LABEL = "Regular"

DRINKS: tuple[tuple[str, str], ...] = (
    ("Coffee", "Espresso"),
    ("Coffee", "Americano"),
    ("Coffee", "Decaf Americano"),
    ("Coffee", "Latte"),
    ("Coffee", "Decaf Latte"),
    ("Coffee", "Vanilla Latte"),
    ("Coffee", "Hazelnut Latte"),
    ("Coffee", "Cappuccino"),
    ("Coffee", "Flat White"),
    ("Coffee", "Mocha"),
    ("Coffee", "Caramel Macchiato"),
    ("Coffee", "Cold Brew"),
    ("Coffee", "Cold Brew Latte"),
    ("Latte", "Matcha Latte"),
    ("Latte", "Hot Chocolate"),
    ("Latte", "Strawberry Latte"),
    ("Tea", "Milk Tea"),
    ("Tea", "Peach Iced Tea"),
    ("Tea", "Earl Grey"),
    ("Tea", "Chamomile"),
    ("Tea", "Peppermint Tea"),
    ("Other", "Lemonade"),
    ("Other", "Yogurt Smoothie"),
    ("Other", "Mango Smoothie"),
)

# The Korean drink each one is compared with (same queries as `basic.py`).
LIKE: dict[str, str | None] = {
    "Espresso": "에스프레소",
    "Americano": "아메리카노",
    "Decaf Americano": "디카페인 아메리카노",
    "Latte": "카페라떼",
    "Decaf Latte": "디카페인 카페라떼",
    "Vanilla Latte": "바닐라라떼",
    "Hazelnut Latte": "헤이즐넛라떼",
    "Cappuccino": "카푸치노",
    "Flat White": "플랫화이트",
    "Mocha": "카페모카",
    "Caramel Macchiato": "카라멜마키아또",
    "Cold Brew": "콜드브루",
    "Cold Brew Latte": "콜드브루 라떼",
    "Matcha Latte": "그린티 라떼",
    "Hot Chocolate": "초코라떼",
    "Strawberry Latte": "딸기라떼",
    "Milk Tea": "밀크티",
    "Peach Iced Tea": "복숭아 아이스티",
    "Earl Grey": "얼그레이",
    "Chamomile": "캐모마일",
    "Peppermint Tea": "페퍼민트",
    "Lemonade": "레몬에이드",
    "Yogurt Smoothie": "요거트 스무디",
    "Mango Smoothie": "망고 스무디",
}


def scrape(_client: httpx.Client) -> list[RawServing]:
    return [
        RawServing(
            brand_id=BRAND.id,
            drink_name=name,
            category=category,
            temperature=Temperature.BOTH,
            size_label=SIZE_LABEL,
            source_url="",
        )
        for category, name in DRINKS
    ]
