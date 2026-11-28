from __future__ import annotations

import json
from pathlib import Path
from types import ModuleType

import httpx
import pytest

from sugarcap_scrape.brands import (
    Scraper,
    basic,
    estimated_likes,
    global_basic,
    global_estimated_likes,
    global_registry,
    registry,
    tw_basic,
    tw_estimated_likes,
    tw_registry,
    us_basic,
    us_estimated_likes,
    us_registry,
)
from sugarcap_scrape.build import group_rows, in_registry_order, merge_catalog
from sugarcap_scrape.estimate import Likes, fill_estimates, fill_estimates_from, references
from sugarcap_scrape.models import Brand, Catalog
from sugarcap_scrape.validate import validate

DATA = Path(__file__).resolve().parents[3] / "data"

Registry = dict[str, tuple[Brand, Scraper]]
COUNTRIES: list[tuple[ModuleType, str, Registry, Likes]] = [
    (basic, "catalog.json", registry(), estimated_likes()),
    (us_basic, "catalog-us.json", us_registry(), us_estimated_likes()),
    (tw_basic, "catalog-tw.json", tw_registry(), tw_estimated_likes()),
]


@pytest.mark.parametrize(("module", "file", "brands", "likes"), COUNTRIES)
def test_brand_contract_and_rows(
    module: ModuleType, file: str, brands: Registry, likes: Likes
) -> None:
    assert module.BRAND.has_size_choice is False
    assert next(iter(brands)) == module.BRAND.id
    assert module.BRAND.id in likes
    with httpx.Client() as client:
        rows = module.scrape(client)
    assert [(r.category, r.drink_name) for r in rows] == list(module.DRINKS)
    assert all(r.sugar_g is None and r.caffeine_mg is None for r in rows)
    assert set(module.LIKE) <= {name for _, name in module.DRINKS}


@pytest.mark.parametrize(("module", "file", "brands", "likes"), COUNTRIES)
def test_every_drink_gets_both_estimates(
    module: ModuleType, file: str, brands: Registry, likes: Likes
) -> None:
    base = Catalog.model_validate(json.loads((DATA / file).read_text(encoding="utf-8")))
    with httpx.Client() as client:
        update = base.model_copy(
            update={"brands": (module.BRAND,), "drinks": tuple(group_rows(module.scrape(client)))}
        )
    filled = fill_estimates(in_registry_order(merge_catalog(base, update), list(brands)), likes)
    assert filled.brands[0].id == module.BRAND.id
    drinks = [d for d in filled.drinks if d.brand_id == module.BRAND.id]
    assert len(drinks) == len(module.DRINKS)
    for drink in drinks:
        (serving,) = drink.servings
        assert serving.estimated, drink.name
        assert serving.sugar_g is not None and serving.caffeine_mg is not None, drink.name


def test_global_basic_contract() -> None:
    assert global_basic.BRAND.has_size_choice is False
    assert list(global_registry()) == [global_basic.BRAND.id]
    assert global_basic.BRAND.id in global_estimated_likes()
    names = [name for _, name in global_basic.DRINKS]
    assert set(global_basic.LIKE) == set(names)


def test_global_basic_matches_the_korean_drink_it_names() -> None:
    korean = Catalog.model_validate(json.loads((DATA / "catalog.json").read_text(encoding="utf-8")))
    with httpx.Client() as client:
        drinks = tuple(group_rows(global_basic.scrape(client)))
    empty = Catalog(schema_version=3, built_at="", brands=(global_basic.BRAND,), drinks=drinks)
    pool = references(korean, frozenset(estimated_likes()))
    filled = fill_estimates_from(empty, global_estimated_likes(), pool)
    # Korean basic drinks by the query they are estimated with (`basic.LIKE` renames a few).
    korean_basic = {
        basic.LIKE.get(d.name) or d.name: d.servings[0]
        for d in korean.drinks
        if d.brand_id == basic.BRAND.id
    }
    for drink in filled.drinks:
        (serving,) = drink.servings
        assert serving.estimated, drink.name
        assert serving.sugar_g is not None and serving.caffeine_mg is not None, drink.name
        same = korean_basic.get(global_basic.LIKE[drink.name] or "")
        if same is not None:
            assert (serving.sugar_g, serving.caffeine_mg) == (same.sugar_g, same.caffeine_mg)


def test_bundled_global_catalog_is_the_build() -> None:
    bundled = Catalog.model_validate(
        json.loads((DATA / "catalog-global.json").read_text(encoding="utf-8"))
    )
    assert validate(bundled) == []
    assert [brand.id for brand in bundled.brands] == [global_basic.BRAND.id]
    assert len(bundled.drinks) == len(global_basic.DRINKS)
