"""Estimated values for brands that publish no nutrition at all (SPEC §2 exception).

블루보틀 and 아마스빈 publish a menu but no sugar or caffeine. Their drinks get the median of
the same drink at brands that do publish, and the serving is marked `estimated` so the app
prefixes "추정". Nothing here touches a brand that publishes its own values.

Reference cups are the first serving of every drink from a publishing brand, except the
convenience store (packaged goods, not cafe cups), the estimated brands themselves, and
decaf drinks unless the target is decaf. 공차 sugar is left out: it is published for the
0% sweetness recipe, not the cup people get by default.

Sugar and caffeine are matched separately; for each, the first level with at least
`MIN_REFERENCES` published values gives the median:
1. the same name, ignoring spaces and temperature words;
2. names containing every word of the query;
3. the same with leading words dropped one at a time ("루이보스 밀크티" -> "밀크티").
No level with enough values leaves that side null (unpublished).

A brand module can replace a drink's query (`LIKE`): a comparable drink for names that do
not say what they are (지브롤터 -> 플랫화이트), or None to leave the drink unestimated.
"""

from __future__ import annotations

import re
import statistics
from collections.abc import Callable, Iterator, Mapping, Sequence
from dataclasses import dataclass

from sugarcap_scrape.models import Catalog, Drink

CVS_BRAND = "cvs"
ZERO_SWEETNESS_BRANDS = frozenset({"gongcha"})
MIN_REFERENCES = 2
DECAF = "디카페인"
TEMPERATURE_WORDS = frozenset({"아이스", "핫", "ice", "iced", "hot"})
_BRACKETED = re.compile(r"\(.*?\)|\[.*?\]")

# brand id -> {drink name: comparable drink name, or None for "do not estimate"}
Likes = Mapping[str, Mapping[str, str | None]]


@dataclass(frozen=True)
class Reference:
    key: str
    sugar_g: float | None
    caffeine_mg: float | None


Side = Callable[[Reference], float | None]


@dataclass(frozen=True)
class Estimate:
    sugar_g: float | None
    caffeine_mg: float | None


def words(name: str) -> tuple[str, ...]:
    """Lowercased words of a drink name without bracketed notes or temperature words."""
    plain = _BRACKETED.sub(" ", name).lower()
    return tuple(word for word in plain.split() if word not in TEMPERATURE_WORDS)


def references(catalog: Catalog, skip_brands: frozenset[str]) -> list[Reference]:
    return [
        Reference(
            key="".join(words(drink.name)),
            sugar_g=None if drink.brand_id in ZERO_SWEETNESS_BRANDS else drink.servings[0].sugar_g,
            caffeine_mg=drink.servings[0].caffeine_mg,
        )
        for drink in catalog.drinks
        if drink.brand_id not in skip_brands and drink.brand_id != CVS_BRAND
    ]


def levels(query: Sequence[str], pool: Sequence[Reference]) -> Iterator[list[Reference]]:
    """Candidate reference sets, closest first (see the module docstring)."""
    if not query:
        return
    if DECAF not in "".join(query):
        pool = [ref for ref in pool if DECAF not in ref.key]
    yield [ref for ref in pool if ref.key == "".join(query)]
    for start in range(len(query)):
        tail = query[start:]
        yield [ref for ref in pool if all(word in ref.key for word in tail)]


def _median(query: Sequence[str], pool: Sequence[Reference], side: Side) -> float | None:
    for found in levels(query, pool):
        published = [value for value in map(side, found) if value is not None]
        if len(published) >= MIN_REFERENCES:
            return round(statistics.median(published), 1)
    return None


def _sugar(ref: Reference) -> float | None:
    return ref.sugar_g


def _caffeine(ref: Reference) -> float | None:
    return ref.caffeine_mg


def estimate(query: Sequence[str], pool: Sequence[Reference]) -> Estimate:
    return Estimate(
        sugar_g=_median(query, pool, _sugar),
        caffeine_mg=_median(query, pool, _caffeine),
    )


def _query(drink: Drink, like: Mapping[str, str | None]) -> tuple[str, ...]:
    if drink.name not in like:
        return words(drink.name)
    comparable = like[drink.name]
    return words(comparable) if comparable is not None else ()


def fill_estimates(catalog: Catalog, likes: Likes) -> Catalog:
    """`catalog` with every drink of a `likes` brand re-estimated from the publishing brands.

    Always recomputed from scratch, so running it on an already filled catalog is a no-op.
    """
    pool = references(catalog, frozenset(likes))
    drinks: list[Drink] = []
    for drink in catalog.drinks:
        like = likes.get(drink.brand_id)
        if like is None:
            drinks.append(drink)
            continue
        guess = estimate(_query(drink, like), pool)
        known = guess.sugar_g is not None or guess.caffeine_mg is not None
        servings = tuple(
            serving.model_copy(
                update={
                    "sugar_g": guess.sugar_g,
                    "caffeine_mg": guess.caffeine_mg,
                    "estimated": known,
                }
            )
            for serving in drink.servings
        )
        drinks.append(drink.model_copy(update={"servings": servings}))
    return catalog.model_copy(update={"drinks": tuple(drinks)})
