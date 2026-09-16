"""Catalog checks that run before `catalog.json` is written.

Three kinds of problem are caught here:

- structure: unknown brand ids, empty drinks, duplicate or unstable ids
- coverage: a brand that suddenly returns far fewer drinks than it has, which is
  how a silently broken parser shows up
- outliers: a value outside a range no published cup reaches, which is how a
  misread cell (a percentage read as grams, ml read as mg) shows up

Thresholds are deliberately wider than the real menu: the highest published
values today are 138g sugar (빽다방 빽스치노), 680mg caffeine (스타벅스 시그니처
더 블랙 콜드 브루) and 990ml (빽사이즈). A hit means a bug, not a new drink.
"""

from __future__ import annotations

from collections import Counter

from sugarcap_scrape.ids import serving_id_parts
from sugarcap_scrape.models import Catalog, Drink

MAX_SUGAR_G = 200.0
MAX_CAFFEINE_MG = 800.0
MIN_VOLUME_ML = 20
MAX_VOLUME_ML = 1200

# A parser returning fewer drinks than this has lost most of its menu. Set at
# roughly half of what each brand published on 2026-09-16.
MIN_DRINKS_PER_BRAND = {
    "starbucks": 90,
    "mega": 70,
    "compose": 45,
    "ediya": 60,
    "paik": 130,
    "twosome": 35,
    "hollys": 35,
    "theventi": 60,
}


def _check_ids(catalog: Catalog) -> list[str]:
    problems: list[str] = []
    brand_ids = [brand.id for brand in catalog.brands]
    for brand_id, count in Counter(brand_ids).items():
        if count > 1:
            problems.append(f"brand {brand_id}: listed {count} times")
    known = set(brand_ids)

    drink_ids: Counter[str] = Counter()
    serving_ids: Counter[str] = Counter()
    for drink in catalog.drinks:
        drink_ids[drink.id] += 1
        if drink.brand_id not in known:
            problems.append(f"drink {drink.id}: unknown brand {drink.brand_id}")
        if not drink.servings:
            problems.append(f"drink {drink.id}: no servings")
        if drink.name != drink.name.strip() or not drink.name:
            problems.append(f"drink {drink.id}: name {drink.name!r} is empty or unstripped")
        for serving in drink.servings:
            serving_ids[serving.id] += 1
            expected = serving_id_parts(drink.id, serving.size_label)
            if serving.id != expected:
                problems.append(f"serving {serving.id}: id is not {expected} (ids must be stable)")
    for drink_id, count in drink_ids.items():
        if count > 1:
            problems.append(f"drink {drink_id}: listed {count} times")
    for serving_id, count in serving_ids.items():
        if count > 1:
            problems.append(f"serving {serving_id}: listed {count} times")
    return problems


def _check_values(drink: Drink) -> list[str]:
    problems: list[str] = []
    for serving in drink.servings:
        where = f"serving {serving.id}"
        if serving.sugar_g is not None and serving.sugar_g > MAX_SUGAR_G:
            problems.append(f"{where}: sugar {serving.sugar_g}g over {MAX_SUGAR_G}g")
        if serving.caffeine_mg is not None and serving.caffeine_mg > MAX_CAFFEINE_MG:
            problems.append(f"{where}: caffeine {serving.caffeine_mg}mg over {MAX_CAFFEINE_MG}mg")
        if serving.volume_ml is not None and not (
            MIN_VOLUME_ML <= serving.volume_ml <= MAX_VOLUME_ML
        ):
            problems.append(f"{where}: volume {serving.volume_ml}ml outside the cup range")
        if serving.caffeine_variants:
            first = serving.caffeine_variants[0].caffeine_mg
            if serving.caffeine_mg != first:
                problems.append(
                    f"{where}: caffeine {serving.caffeine_mg} is not the first variant {first}"
                )
    return problems


def _check_coverage(catalog: Catalog) -> list[str]:
    problems: list[str] = []
    counts = Counter(drink.brand_id for drink in catalog.drinks)
    for brand in catalog.brands:
        minimum = MIN_DRINKS_PER_BRAND.get(brand.id)
        if minimum is None:
            problems.append(f"brand {brand.id}: no minimum drink count configured")
            continue
        if counts[brand.id] < minimum:
            problems.append(f"brand {brand.id}: {counts[brand.id]} drinks, expected >= {minimum}")
        if not brand.has_size_choice:
            multi = [
                drink.id
                for drink in catalog.drinks
                if drink.brand_id == brand.id and len(drink.servings) > 1
            ]
            if multi:
                problems.append(
                    f"brand {brand.id}: has_size_choice is False but {len(multi)} drinks have "
                    f"several servings (e.g. {multi[0]})"
                )
    return problems


def validate(catalog: Catalog) -> list[str]:
    """Return every problem found in a built catalog. Empty means it is publishable."""
    problems = _check_ids(catalog)
    for drink in catalog.drinks:
        problems.extend(_check_values(drink))
    problems.extend(_check_coverage(catalog))
    return problems
