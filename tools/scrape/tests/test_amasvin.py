from __future__ import annotations

import httpx
import pytest

from sugarcap_scrape.brands.amasvin import BRAND, LIKE, parse_menu, scrape
from sugarcap_scrape.parse import ParseError

MENU = """
<div id="tab_drink"><ul class="menu_gallery tab_menu">
 <li class="on tab_click"><a href="#character_ic">커피</a>
  <div class="best align"><ul class="tab_number"><li class="on_number"><ul>
   <li><img src="1.png"><h3>아메리카노</h3><p><img src="t.png"></p></li>
   <!--<li><img src="5.png"><h3>카페라떼 with 펄</h3></li>-->
   <li><img src="4.png"><h3>카페라떼</h3></li>
  </ul><a href="#character_ic">1</a></li></ul></div></li>
 <li><a href="#character_ic">베이커리</a>
  <div class="best align"><ul><li><h3>레몬 마들렌</h3></li></ul></div></li>
</ul></div>
"""


def test_brand_contract() -> None:
    assert BRAND.id == "amasvin"
    assert BRAND.has_size_choice is False


def test_tabs_and_names_without_comments_or_bakery() -> None:
    assert parse_menu(MENU) == [("커피", "아메리카노"), ("커피", "카페라떼")]


def test_missing_tabs_is_an_error() -> None:
    with pytest.raises(ParseError, match="no #tab_drink tabs"):
        parse_menu("<div></div>")


@pytest.mark.live
def test_scrape_live(client: httpx.Client) -> None:
    rows = scrape(client)
    assert len(rows) >= 50
    names = [r.drink_name for r in rows]
    assert len(names) == len(set(names))
    assert {"아메리카노", "흑당 버블티"} <= set(names)
    assert all(r.sugar_g is None and r.caffeine_mg is None for r in rows)
    assert set(LIKE) <= set(names)
