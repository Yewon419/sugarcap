from __future__ import annotations

import json

from sugarcap_scrape.estimate import Reference, estimate, fill_estimates, words
from sugarcap_scrape.models import Brand, Catalog, Drink, Serving, Temperature


def _drink(brand: str, name: str, sugar: float | None, caffeine: float | None) -> Drink:
    return Drink(
        id=f"{brand}:{name}:both",
        brand_id=brand,
        name=name,
        name_en=None,
        category="c",
        temperature=Temperature.BOTH,
        liquid_color="#000000",
        servings=(
            Serving(
                id=f"{brand}:{name}:both:기본",
                size_label="기본",
                volume_ml=None,
                sugar_g=sugar,
                caffeine_mg=caffeine,
            ),
        ),
    )


def _brand(brand_id: str) -> Brand:
    return Brand(id=brand_id, name=brand_id, serving_note="", has_size_choice=False)


def _catalog(*drinks: Drink) -> Catalog:
    ids = dict.fromkeys(drink.brand_id for drink in drinks)
    return Catalog(
        schema_version=3,
        built_at="2026-10-31T00:00:00+00:00",
        brands=tuple(_brand(brand_id) for brand_id in ids),
        drinks=drinks,
    )


def _ref(key: str, sugar: float | None, caffeine: float | None = None) -> Reference:
    return Reference(key=key, sugar_g=sugar, caffeine_mg=caffeine)


def test_words_drop_temperature_and_notes() -> None:
    assert words("아이스 바닐라 라떼 (ICE)") == ("바닐라", "라떼")
    assert words("HOT Latte") == ("latte",)


def test_same_name_wins_over_wider_matches() -> None:
    pool = [_ref("카페라떼", 10, 150), _ref("카페라떼", 12, 170), _ref("바닐라카페라떼", 30, 150)]
    assert estimate(("카페", "라떼"), pool).sugar_g == 11


def test_leading_words_are_dropped_until_enough_cups() -> None:
    pool = [_ref("밀크티", 20), _ref("흑당밀크티", 30), _ref("타로", 99)]
    assert estimate(("루이보스", "밀크티"), pool).sugar_g == 25


def test_one_cup_is_not_enough() -> None:
    assert estimate(("사하라",), [_ref("사하라", 40)]).sugar_g is None


def test_sides_fall_back_separately() -> None:
    pool = [
        _ref("얼그레이밀크티", None, 160),
        _ref("얼그레이밀크티", None, 170),
        _ref("밀크티", 20, 50),
        _ref("밀크티", 30, 50),
    ]
    guess = estimate(("얼그레이", "밀크티"), pool)
    assert (guess.sugar_g, guess.caffeine_mg) == (25, 165)


def test_decaf_cups_only_estimate_decaf() -> None:
    pool = [
        _ref("아메리카노", 0, 150),
        _ref("아메리카노", 0, 170),
        _ref("디카페인아메리카노", 0, 5),
    ]
    assert estimate(("아메리카노",), pool).caffeine_mg == 160


def test_fill_only_touches_listed_brands_and_skips_cvs() -> None:
    catalog = _catalog(
        _drink("a", "카페라떼", 10, 150),
        _drink("b", "카페라떼", 20, 170),
        _drink("cvs", "카페라떼", 90, 900),
        _drink("blue", "카페라떼", None, None),
        _drink("blue", "지브롤터", None, None),
        _drink("blue", "플로트", None, None),
    )
    likes = {"blue": {"지브롤터": "카페라떼", "플로트": None}}
    filled = fill_estimates(catalog, likes)
    cups = {(d.brand_id, d.name): d.servings[0] for d in filled.drinks}
    assert (cups["blue", "카페라떼"].sugar_g, cups["blue", "카페라떼"].caffeine_mg) == (15, 160)
    assert cups["blue", "카페라떼"].estimated is True
    assert cups["blue", "지브롤터"].sugar_g == 15
    assert (cups["blue", "플로트"].sugar_g, cups["blue", "플로트"].estimated) == (None, False)
    assert cups["a", "카페라떼"].estimated is False
    assert fill_estimates(filled, likes) == filled


def test_estimated_key_is_written_only_when_true() -> None:
    filled = fill_estimates(
        _catalog(
            _drink("a", "라떼", 10, 1), _drink("b", "라떼", 20, 1), _drink("x", "라떼", None, None)
        ),
        {"x": {}},
    )
    servings = [d["servings"][0] for d in json.loads(filled.model_dump_json())["drinks"]]
    assert ["estimated" in s for s in servings] == [False, False, True]
