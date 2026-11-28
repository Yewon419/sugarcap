"""基本 (Taiwan): a fixed list of everyday drinks; values are estimates, `estimate.py`.

The Taiwan twin of `basic.py`. Only cama café (coffee) and 可不可 (tea) publish, and tea
caffeine is a band whose upper bound is the value (`caffeine_range`), so teas come out at
200 mg. 濃縮咖啡 has no second cup and is left out.
"""

from __future__ import annotations

import httpx

from sugarcap_scrape.models import Brand, RawServing, Temperature

BRAND = Brand(
    id="tw-basic",
    name="基本",
    serving_note="一般飲品，數值為估計",
    has_size_choice=False,
)

SIZE_LABEL = "標準"

DRINKS: tuple[tuple[str, str], ...] = (
    ("咖啡", "美式咖啡"),
    ("咖啡", "拿鐵"),
    ("咖啡", "香草拿鐵"),
    ("咖啡", "焦糖拿鐵"),
    ("咖啡", "卡布奇諾"),
    ("咖啡", "摩卡"),
    ("茶", "珍珠奶茶"),
    ("茶", "奶茶"),
    ("茶", "紅茶"),
    ("茶", "綠茶"),
    ("茶", "抹茶拿鐵"),
)

# 拿鐵 alone takes every flavored latte (sugar 20.8 g vs 12.4 g plain); 白玉 is 可不可's pearls.
LIKE: dict[str, str | None] = {
    "美式咖啡": "美式",
    "拿鐵": "CAMA金獎拿鐵",
    "摩卡": "摩卡咖啡",
    "珍珠奶茶": "白玉奶茶",
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
