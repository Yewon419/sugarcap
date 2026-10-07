from __future__ import annotations

import httpx
import pytest

from sugarcap_scrape.brands.us_dutchbros import (
    BASE_COLUMNS,
    BRAND,
    PDF_URL,
    display_category,
    parse_guide,
    parse_header,
    pdf_text,
    scrape,
    title_of,
)
from sugarcap_scrape.http import fetch_bytes
from sugarcap_scrape.models import RawServing, Temperature
from sugarcap_scrape.parse import ParseError

BASE_HEADER = """Dutch Bros Coffee Nutritional Guide
 Type
 Size
 Total calories (kcal)
 Calories from fat (fat
cal)
 Total fat (g)
 Saturated fat (g)
 Trans fat (g)
 Cholesterol (mg)
 Sodium (mg)
 Total Carbs (g)
 Dietary fiber (g)
 Total sugars (g)
 Protein (g)
 Caffeine (mg)
 Allergies
"""

# Lines copied from the 2026-10-07 guide.
GUIDE = (
    BASE_HEADER
    + """DUTCH FAVES™
911 Hot Large 630 330 37 24 0 120 240 62 2 58 14 290 Contains Milk.
911 Iced Small 280 60 7 4.5 0 20 40 52 2 48 4 290 Contains Milk.
Caramelizer Cold Brew Toasted Large 200 20 2 1.5 0 10 200 40 0 30 4 285 Contains Milk.
Caramelizer Nitro Cold Brew Iced Nitro 200 20 2 1.5 0 10 300 39 0 30 3 295 Contains Milk.
WHERE IT ALL BEGAN - FAN FAVORITES, GUARANTEED TO SATISFY.
COFFEE CLASSICS
911 Hot Large 630 330 37 24 0 120 240 62 2 58 14 290 Contains Milk.
TOPPINGS
Soft Top 2 Scoops 100 70 8 7 0 5 30 6 0 5 1 0 Contains Milk, Soy.
ESPRESSO
Private Reserve Espresso Dub Shot 10 0 0 0 0 0 0 2 1 0 1 95
Dutch Bros Coffee Nutritional Guide
 Type
 Size
 Total calories (kcal)
 Calories from fat (fat cal)
 Total fat (g)
 Saturated fat (g)
 Trans fat (g)
 Cholesterol (mg)
 Sodium (mg)
 Total Carbs (g)
 Dietary fiber (g)
 Total sugars (g)
 Protein (g)
 *Caffeine (mg)
Magnesium
Vitamin C
 Allergies
Autumn Berry
Autumn Berry Rebel Blended Large 630 0 0 0 0 0 150 162 0 158 2 130
Autumn Berry Myst Iced Large 200 0 0 0 0 0 5 49 0 44 0 145 150 33
Pumpkin Pie Spice Breve Hot Medium 610 390 43 52 <1 29 0 115 40 96 14 380 Contains: Milk, Soy
 Total calories
(kcal)
 Total fat (g)
 Total sugars (g)
 Allergies
EATS N' SWEETS
Banana Bread 330 17 3.5 0 40 370 44 1 24 4 Contains Egg, Milk, Soy, Wheat.
"""
)


def _row(rows: list[RawServing], name: str, size: str) -> RawServing:
    matches = [row for row in rows if row.drink_name == name and row.size_label == size]
    assert len(matches) == 1, f"{name} {size}: {len(matches)} rows"
    return matches[0]


def test_brand_contract() -> None:
    assert BRAND.id == "us-dutchbros"
    assert BRAND.has_size_choice is True


def test_header_joins_wrapped_column_names() -> None:
    header = parse_header(BASE_HEADER.splitlines()[1:])
    assert header.has_type is True
    assert header.columns == BASE_COLUMNS


def test_titles_and_descriptions() -> None:
    assert title_of("DUTCH FAVES™") == "DUTCH FAVES™"
    assert title_of("Cherry Pie Chai") == "Cherry Pie Chai"
    assert title_of("LEMONADE LEMONADE INFUSED WITH ANY FLAVOR.") == "LEMONADE"
    assert title_of("Chocolate Milk     OUR EXCLUSIVE CHOCOLATE MILK,  WITH A FLAVOR.") == (
        "Chocolate Milk"
    )
    assert title_of("CHAI IT YOUR WAY! TRY IT HOT OR ICED!") is None
    assert title_of("AVAILABILITY MAY VARY BY LOCATION") is None


def test_all_caps_categories_read_like_seasonal_ones() -> None:
    assert display_category("DUTCH BROS REBEL®") == "Dutch Bros Rebel®"
    assert display_category("POPPIN' BOBA") == "Poppin' Boba"
    assert display_category("Caramel Pumpkin Brûlée") == "Caramel Pumpkin Brûlée"


def test_rows_read_sugar_and_caffeine_by_column_name() -> None:
    rows = parse_guide(GUIDE)
    hot = _row(rows, "911", "Large")
    assert (hot.temperature, hot.sugar_g, hot.caffeine_mg) == (Temperature.HOT, 58.0, 290.0)
    assert hot.category == "Dutch Faves™"
    assert hot.volume_ml is None
    iced = [r for r in rows if r.drink_name == "911" and r.temperature is Temperature.ICED]
    assert [(r.size_label, r.sugar_g) for r in iced] == [("Small", 48.0)]


def test_blended_and_toasted_stay_in_the_name() -> None:
    rows = parse_guide(GUIDE)
    toasted = _row(rows, "Caramelizer Cold Brew Toasted", "Large")
    assert toasted.temperature is Temperature.ICED
    blended = _row(rows, "Autumn Berry Rebel Blended", "Large")
    assert (blended.sugar_g, blended.caffeine_mg) == (158.0, 130.0)
    nitro = _row(rows, "Caramelizer Nitro Cold Brew", "Nitro")
    assert nitro.caffeine_mg == 295.0


def test_a_narrow_row_under_a_wide_header_uses_the_base_layout() -> None:
    rows = parse_guide(GUIDE)
    myst = _row(rows, "Autumn Berry Myst", "Large")
    assert (myst.sugar_g, myst.caffeine_mg) == (44.0, 145.0)


def test_a_row_shifted_in_the_guide_is_kept_with_values_withheld() -> None:
    breve = _row(parse_guide(GUIDE), "Pumpkin Pie Spice Breve", "Medium")
    assert (breve.sugar_g, breve.caffeine_mg) == (None, None)


def test_toppings_food_and_repeats_are_dropped() -> None:
    rows = parse_guide(GUIDE)
    names = {row.drink_name for row in rows}
    assert "Soft Top" not in names
    assert "Banana Bread" not in names
    assert _row(rows, "911", "Large").category == "Dutch Faves™"
    espresso = _row(rows, "Private Reserve Espresso", "Dub Shot")
    assert (espresso.temperature, espresso.caffeine_mg) == (Temperature.HOT, 95.0)


def test_repeat_with_different_values_raises() -> None:
    changed = GUIDE.replace(
        "COFFEE CLASSICS\n911 Hot Large 630 330 37 24 0 120 240 62 2 58 14 290",
        "COFFEE CLASSICS\n911 Hot Large 630 330 37 24 0 120 240 62 2 50 14 290",
    )
    with pytest.raises(ParseError):
        parse_guide(changed)


def test_unexpected_column_count_raises() -> None:
    with pytest.raises(ParseError):
        parse_guide(BASE_HEADER + "TEA\nGreen Tea Hot Small 0 0 0 0 0 0 15 0 0 0 40\n")


@pytest.mark.live
def test_live_guide_text_matches_the_published_pdf(client: httpx.Client) -> None:
    rows = parse_guide(pdf_text(fetch_bytes(client, PDF_URL)))
    golden = [r for r in rows if r.drink_name == "Golden Eagle" and r.size_label == "Medium"]
    assert {r.temperature for r in golden} == {Temperature.HOT, Temperature.ICED}
    assert all(r.sugar_g is not None and r.caffeine_mg is not None for r in golden)


@pytest.mark.live
def test_live_scrape(client: httpx.Client) -> None:
    rows = scrape(client)
    assert len({(row.drink_name, row.temperature) for row in rows}) >= 200
    assert sum(1 for row in rows if row.sugar_g is None) <= 20
