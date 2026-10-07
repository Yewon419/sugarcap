"""Brand scraper registry.

Each brand module exposes `BRAND: Brand` and `scrape(client: httpx.Client) -> list[RawServing]`.
"""

from __future__ import annotations

from collections.abc import Callable

import httpx

from sugarcap_scrape.models import Brand, RawServing

Scraper = Callable[[httpx.Client], list[RawServing]]


def registry() -> dict[str, tuple[Brand, Scraper]]:
    """Import brand modules lazily so one broken module does not block the others at import."""
    from sugarcap_scrape.brands import (
        compose,
        ediya,
        gongcha,
        hollys,
        mega,
        paik,
        starbucks,
        theventi,
        twosome,
    )

    modules = (starbucks, mega, compose, ediya, paik, twosome, hollys, theventi, gongcha)
    return {module.BRAND.id: (module.BRAND, module.scrape) for module in modules}


def us_registry() -> dict[str, tuple[Brand, Scraper]]:
    """US brands, built into their own `catalog-us.json` (SPEC §9.9)."""
    from sugarcap_scrape.brands import us_dutchbros, us_starbucks

    modules = (us_starbucks, us_dutchbros)
    return {module.BRAND.id: (module.BRAND, module.scrape) for module in modules}
