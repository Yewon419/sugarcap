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
    registry,
    tw_basic,
    tw_estimated_likes,
    tw_registry,
    us_basic,
    us_estimated_likes,
    us_registry,
)
from sugarcap_scrape.build import group_rows, in_registry_order, merge_catalog
from sugarcap_scrape.estimate import Likes, fill_estimates
from sugarcap_scrape.models import Brand, Catalog

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
