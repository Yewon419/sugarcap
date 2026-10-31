from __future__ import annotations

import httpx
import pytest

from sugarcap_scrape.brands.bluebottle import BRAND, LIKE, menu_image, rows, scrape
from sugarcap_scrape.parse import ParseError


def test_brand_contract() -> None:
    assert BRAND.id == "bluebottle"
    assert BRAND.has_size_choice is False


def test_menu_image_name() -> None:
    html = '<img src="//cdn.shopify.com/s/files/1/0699/9588/8893/files/CN_260414.jpg?v=1">'
    assert menu_image(html) == "CN_260414.jpg"
    with pytest.raises(ParseError, match="no menu image"):
        menu_image("<p>메뉴</p>")


def test_overrides_name_listed_drinks() -> None:
    names = [r.drink_name for r in rows()]
    assert len(names) == len(set(names))
    assert set(LIKE) <= set(names)


@pytest.mark.live
def test_menu_image_unchanged_live(client: httpx.Client) -> None:
    """Fails when Blue Bottle swaps the menu image: re-read it into `DRINKS`."""
    assert len(scrape(client)) == len(rows())
