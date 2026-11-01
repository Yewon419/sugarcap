from __future__ import annotations

import httpx
import pytest

from sugarcap_scrape.brands.oozy import BRAND, LIKE, archive_url, is_dessert, parse_menu, scrape
from sugarcap_scrape.parse import ParseError

ITEM = """
<div class="_item item_gallary"><a href="#"><div class="title">{name}
 <span class="body">설명</span></div></a></div>
"""
MENU = "".join(
    ITEM.format(name=name)
    for name in ("녹차 프라페", "망고 빙수", "딸기빙수프라페", "아포가토", "녹차 프라페")
)


def test_brand_contract() -> None:
    assert BRAND.id == "oozy"
    assert BRAND.has_size_choice is False


def test_names_are_deduped_and_desserts_dropped() -> None:
    assert parse_menu(MENU) == ["녹차 프라페", "딸기빙수프라페"]


def test_dessert_words() -> None:
    assert is_dessert("망고 빙수")
    assert is_dessert("요거트 스무디 볼")
    assert not is_dessert("초코빙수프라페")
    assert not is_dessert("딸기 요거트스무디")


def test_empty_title_is_an_error() -> None:
    with pytest.raises(ParseError, match="empty"):
        parse_menu('<div class="_item item_gallary"><div class="title"> </div></div>')


def test_archive_url_is_the_raw_snapshot() -> None:
    assert (
        archive_url("https://oozycoffee.com/27", "20260308131800")
        == "https://web.archive.org/web/20260308131800id_/https://oozycoffee.com/27"
    )


@pytest.mark.live
def test_scrape_live(client: httpx.Client) -> None:
    rows = scrape(client)
    assert len(rows) >= 100
    names = [r.drink_name for r in rows]
    assert len(names) == len(set(names))
    assert {"콜드브루 커피", "녹차 라떼", "레몬에이드"} <= set(names)
    assert not any(is_dessert(name) for name in names)
    assert all(r.sugar_g is None and r.caffeine_mg is None for r in rows)
    assert set(LIKE) <= set(names)
