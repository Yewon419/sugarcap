"""Basic (US): a fixed list of everyday cafe drinks; values are estimates, `estimate.py`.

The US twin of `basic.py`. Only Starbucks and Dutch Bros publish, so most medians are two
cups of one brand (iced and hot of the same drink). Cappuccino has a single published cup
and is left out.
"""

from __future__ import annotations

import httpx

from sugarcap_scrape.models import Brand, RawServing, Temperature

BRAND = Brand(
    id="us-basic",
    name="Basic",
    serving_note="Typical café drink, estimated values",
    has_size_choice=False,
)

SIZE_LABEL = "Regular"

DRINKS: tuple[tuple[str, str], ...] = (
    ("Coffee", "Espresso"),
    ("Coffee", "Drip Coffee"),
    ("Coffee", "Americano"),
    ("Coffee", "Iced Coffee"),
    ("Coffee", "Latte"),
    ("Coffee", "Vanilla Latte"),
    ("Coffee", "Caramel Latte"),
    ("Coffee", "Pumpkin Spice Latte"),
    ("Coffee", "Flat White"),
    ("Coffee", "Mocha"),
    ("Coffee", "White Chocolate Mocha"),
    ("Coffee", "Caramel Macchiato"),
    ("Coffee", "Cold Brew"),
    ("Coffee", "Nitro Cold Brew"),
    ("Tea", "Chai Latte"),
    ("Tea", "Matcha Latte"),
    ("Tea", "London Fog"),
    ("Tea", "Iced Black Tea"),
    ("Tea", "Iced Green Tea"),
    ("Other", "Hot Chocolate"),
    ("Other", "Lemonade"),
)

# Drip coffee: Starbucks brewed roasts (median of five, decaf and half-caff included).
# Hot chocolate: "hot chocolate" alone widens to every chocolate drink; cocoas are closer.
LIKE: dict[str, str | None] = {
    "Drip Coffee": "roast",
    "Hot Chocolate": "cocoa",
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
