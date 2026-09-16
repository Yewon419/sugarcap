from __future__ import annotations

import json
from collections import Counter
from pathlib import Path

import pytest

from sugarcap_scrape.ids import serving_id_parts
from sugarcap_scrape.models import Brand, CaffeineVariant, Catalog, Drink, Serving, Temperature
from sugarcap_scrape.validate import MIN_DRINKS_PER_BRAND, validate

CATALOG_PATH = Path(__file__).resolve().parents[3] / "data" / "catalog.json"
BRAND = Brand(id="theventi", name="더벤티", serving_note="라지 600ml", has_size_choice=False)


def _serving(
    drink_id: str,
    size: str = "라지",
    *,
    sugar: float | None = 11.0,
    caffeine: float | None = 92.0,
    volume: int | None = 600,
    variants: tuple[CaffeineVariant, ...] = (),
) -> Serving:
    return Serving(
        id=serving_id_parts(drink_id, size),
        size_label=size,
        volume_ml=volume,
        sugar_g=sugar,
        caffeine_mg=caffeine,
        caffeine_variants=variants,
    )


def _drink(
    name: str = "카페라떼",
    *,
    sugar: float | None = 11.0,
    caffeine: float | None = 92.0,
    volume: int | None = 600,
    variants: tuple[CaffeineVariant, ...] = (),
) -> Drink:
    drink_id = f"{BRAND.id}:{name}:hot"
    return Drink(
        id=drink_id,
        brand_id=BRAND.id,
        name=name,
        name_en=None,
        category="커피",
        temperature=Temperature.HOT,
        servings=(
            _serving(drink_id, sugar=sugar, caffeine=caffeine, volume=volume, variants=variants),
        ),
    )


def _catalog(*drinks: Drink, brands: tuple[Brand, ...] = (BRAND,)) -> Catalog:
    return Catalog(
        schema_version=1, built_at="2026-09-16T00:00:00+00:00", brands=brands, drinks=drinks
    )


def _enough(name: str) -> list[Drink]:
    return [_drink(f"{name}{index}") for index in range(MIN_DRINKS_PER_BRAND[BRAND.id])]


def test_a_full_brand_passes() -> None:
    assert validate(_catalog(*_enough("메뉴"))) == []


def test_a_short_brand_is_reported() -> None:
    problems = validate(_catalog(*_enough("메뉴")[:-1]))
    assert any("expected >=" in problem for problem in problems)


def test_an_unknown_brand_is_reported() -> None:
    drinks = _enough("메뉴")
    stray = drinks[0].model_copy(update={"brand_id": "ghost", "id": "ghost:x:hot"})
    problems = validate(_catalog(*drinks, stray))
    assert any("unknown brand ghost" in problem for problem in problems)


def test_a_duplicate_serving_id_is_reported() -> None:
    drinks = _enough("메뉴")
    twin = drinks[0].model_copy(update={"id": drinks[0].id + "-2"})
    problems = validate(_catalog(*drinks, twin))
    assert any("listed 2 times" in problem for problem in problems)


def test_an_id_that_does_not_follow_the_recipe_is_reported() -> None:
    drinks = _enough("메뉴")
    serving = drinks[0].servings[0].model_copy(update={"id": "theventi:손으로:쓴:id"})
    drinks[0] = drinks[0].model_copy(update={"servings": (serving,)})
    problems = validate(_catalog(*drinks))
    assert any("ids must be stable" in problem for problem in problems)


@pytest.mark.parametrize(
    ("outlier", "expected"),
    [
        (_drink("과당", sugar=260.0), "sugar"),
        (_drink("과카페인", caffeine=900.0), "caffeine"),
        (_drink("작은컵", volume=5), "volume"),
        (_drink("양동이", volume=5000), "volume"),
    ],
)
def test_outliers_are_reported(outlier: Drink, expected: str) -> None:
    drinks = _enough("메뉴")
    drinks[0] = outlier
    problems = validate(_catalog(*drinks))
    assert any(expected in problem for problem in problems)


def test_caffeine_must_match_the_first_variant() -> None:
    drinks = _enough("메뉴")
    variants = (
        CaffeineVariant(label="시그니처", caffeine_mg=168),
        CaffeineVariant(label="다크", caffeine_mg=266),
    )
    drinks[0] = _drink("원두선택", caffeine=266.0, variants=variants)
    problems = validate(_catalog(*drinks))
    assert any("is not the first variant" in problem for problem in problems)


def test_a_single_size_brand_with_several_servings_is_reported() -> None:
    drinks = _enough("메뉴")
    first = drinks[0]
    drinks[0] = first.model_copy(
        update={"servings": (*first.servings, _serving(first.id, "점보", volume=960))}
    )
    problems = validate(_catalog(*drinks))
    assert any("has_size_choice is False" in problem for problem in problems)


def test_a_brand_without_a_configured_minimum_is_reported() -> None:
    unknown = BRAND.model_copy(update={"id": "newbrand"})
    problems = validate(_catalog(brands=(unknown,)))
    assert any("no minimum drink count" in problem for problem in problems)


def test_the_committed_catalog_is_valid() -> None:
    """data/catalog.json is what the app ships; it has to pass the same checks."""
    catalog = Catalog.model_validate(json.loads(CATALOG_PATH.read_text(encoding="utf-8")))
    assert validate(catalog) == []
    assert catalog.schema_version == 1
    counts = Counter(drink.brand_id for drink in catalog.drinks)
    assert set(counts) == set(MIN_DRINKS_PER_BRAND)
