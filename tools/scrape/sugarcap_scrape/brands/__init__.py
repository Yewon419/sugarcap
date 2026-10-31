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
        baskin,
        bluebottle,
        coffeebean,
        compose,
        ediya,
        gongcha,
        hollys,
        mega,
        paik,
        parisbaguette,
        paulbassett,
        starbucks,
        theventi,
        twosome,
    )

    modules = (
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
    )
    return {module.BRAND.id: (module.BRAND, module.scrape) for module in modules}


def estimated_likes() -> Likes:
    """Korean brands that publish no nutrition, with their comparable-drink overrides."""
    from sugarcap_scrape.brands import amasvin, bluebottle

    return {bluebottle.BRAND.id: bluebottle.LIKE, amasvin.BRAND.id: amasvin.LIKE}


def us_registry() -> dict[str, tuple[Brand, Scraper]]:
    """US brands, built into their own `catalog-us.json` (SPEC §9.9)."""
    from sugarcap_scrape.brands import us_dutchbros, us_starbucks

    modules = (us_starbucks, us_dutchbros)
    return {module.BRAND.id: (module.BRAND, module.scrape) for module in modules}


def tw_registry() -> dict[str, tuple[Brand, Scraper]]:
    """Taiwan brands, built into `catalog-tw.json` (SPEC §9.9)."""
    from sugarcap_scrape.brands import tw_cama, tw_kebuke

    modules = (tw_cama, tw_kebuke)
    return {module.BRAND.id: (module.BRAND, module.scrape) for module in modules}
