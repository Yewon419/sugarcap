"""Brand scraper registry.

Each brand module exposes `BRAND: Brand` and `scrape(client: httpx.Client) -> list[RawServing]`.
"""

from __future__ import annotations

from collections.abc import Callable

import httpx

from sugarcap_scrape.estimate import Likes
from sugarcap_scrape.models import Brand, RawServing

Scraper = Callable[[httpx.Client], list[RawServing]]


def registry() -> dict[str, tuple[Brand, Scraper]]:
    """Import brand modules lazily so one broken module does not block the others at import."""
    from sugarcap_scrape.brands import (
        amasvin,
        basic,
        baskin,
        bluebottle,
        coffeebean,
        compose,
        ediya,
        gongcha,
        hollys,
        mega,
        oozy,
        paik,
        parisbaguette,
        paulbassett,
        starbucks,
        theventi,
        twosome,
    )

    modules = (
        basic,
        starbucks,
        mega,
        compose,
        ediya,
        paik,
        twosome,
        hollys,
        theventi,
        gongcha,
        paulbassett,
        baskin,
        coffeebean,
        parisbaguette,
        bluebottle,
        amasvin,
        oozy,
    )
    return {module.BRAND.id: (module.BRAND, module.scrape) for module in modules}


def estimated_likes() -> Likes:
    """Korean brands that publish no nutrition, with their comparable-drink overrides."""
    from sugarcap_scrape.brands import amasvin, basic, bluebottle, oozy

    return {
        basic.BRAND.id: basic.LIKE,
        bluebottle.BRAND.id: bluebottle.LIKE,
        amasvin.BRAND.id: amasvin.LIKE,
        oozy.BRAND.id: oozy.LIKE,
    }


def us_registry() -> dict[str, tuple[Brand, Scraper]]:
    """US brands, built into their own `catalog-us.json` (SPEC §9.9)."""
    from sugarcap_scrape.brands import us_basic, us_dutchbros, us_starbucks

    modules = (us_basic, us_starbucks, us_dutchbros)
    return {module.BRAND.id: (module.BRAND, module.scrape) for module in modules}


def us_estimated_likes() -> Likes:
    """US estimated brands: only Basic (`us_basic.py`)."""
    from sugarcap_scrape.brands import us_basic

    return {us_basic.BRAND.id: us_basic.LIKE}


def tw_registry() -> dict[str, tuple[Brand, Scraper]]:
    """Taiwan brands, built into `catalog-tw.json` (SPEC §9.9)."""
    from sugarcap_scrape.brands import tw_basic, tw_cama, tw_kebuke

    modules = (tw_basic, tw_cama, tw_kebuke)
    return {module.BRAND.id: (module.BRAND, module.scrape) for module in modules}


def tw_estimated_likes() -> Likes:
    """Taiwan estimated brands: only 基本 (`tw_basic.py`)."""
    from sugarcap_scrape.brands import tw_basic

    return {tw_basic.BRAND.id: tw_basic.LIKE}


def global_registry() -> dict[str, tuple[Brand, Scraper]]:
    """Everywhere else: only Basic, built into `catalog-global.json` (SPEC §9.9)."""
    from sugarcap_scrape.brands import global_basic

    return {global_basic.BRAND.id: (global_basic.BRAND, global_basic.scrape)}


def global_estimated_likes() -> Likes:
    """Basic (everywhere else), compared against the Korean catalog (`global_basic.py`)."""
    from sugarcap_scrape.brands import global_basic

    return {global_basic.BRAND.id: global_basic.LIKE}
