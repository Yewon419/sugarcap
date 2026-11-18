"""기본 메뉴 (a fixed list of everyday cafe drinks; values are estimates, `estimate.py`).

Not a brand. For cups from cafes that are not in the catalog (SPEC §2, 2026-11-18): the same
drink's median over the brands that publish. No network, the list lives here. One cup per
drink, temperature not split.
"""

from __future__ import annotations

import httpx

from sugarcap_scrape.models import Brand, RawServing, Temperature

BRAND = Brand(
    id="basic",
    name="기본 메뉴",
    serving_note="흔한 카페 메뉴, 값은 추정치",
    has_size_choice=False,
)

SIZE_LABEL = "기본"

# (category, drink name), menu order.
DRINKS: tuple[tuple[str, str], ...] = (
    ("커피", "에스프레소"),
    ("커피", "아메리카노"),
    ("커피", "카페라떼"),
    ("커피", "바닐라라떼"),
    ("커피", "카푸치노"),
    ("커피", "플랫화이트"),
    ("커피", "카페모카"),
    ("커피", "카라멜마키아또"),
    ("커피", "콜드브루"),
    ("라떼", "녹차라떼"),
    ("라떼", "초코라떼"),
    ("티", "밀크티"),
    ("티", "복숭아 아이스티"),
    ("에이드", "레몬에이드"),
    ("에이드", "자몽에이드"),
)

# Comparable drinks (`estimate.py`). Most cafes write 녹차라떼 as 그린티 라떼: 2 cups vs 4.
LIKE: dict[str, str | None] = {
    "녹차라떼": "그린티 라떼",
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
