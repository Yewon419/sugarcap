from __future__ import annotations

import httpx
import pytest

from sugarcap_scrape.brands.paulbassett import (
    BRAND,
    parse_caffeine,
    parse_product_ids,
    parse_product_page,
    parse_sub_categories,
    scrape,
)
from sugarcap_scrape.models import CaffeineRange, RawServing, Temperature
from sugarcap_scrape.parse import ParseError

URL = "https://www.baristapaulbassett.co.kr/menu/View.pb?dpid=PB181113"


def _size(code: str, ml: str, sugar: str, caffeine: str) -> str:
    return (
        f'<div id="pSize_{code}"><span class="sizeMl">제공량(ml)<span>{ml}</span></span><ul>'
        '<li><span class="tit">열량(kcal)</span><span class="num">30</span></li>'
        f'<li><span class="tit">당류(g)</span><span class="num">{sugar}</span></li>'
        f'<li><span class="tit">카페인(mg)</span><span class="num">{caffeine}</span></li>'
        "</ul></div>"
    )


def _page(kind: str | None, options: str, blocks: str) -> str:
    info = "<li><span>알레르기 유발물질</span></li>"
    if kind is not None:
        info = f"<li><span>구분</span>\n  {kind}\n</li>" + info
    return (
        '<div class="menuTit"><dl><dt><span>Decaf Cafe Latte</span>디카페인 카페라떼 </dt>'
        f'</dl></div><ul class="info">{info}</ul>'
        f'<select id="pSize">{options}</select><div id="pSizeInfoLayer">{blocks}</div>'
    )


DECAF_LATTE = _page(
    "Hot",
    '<option value="S">Standard</option><option value="G">Grand</option>',
    _size("S", "360", "15", "10mg이하") + _size("G", "460", "18", "15mg이하"),
)


def _row(rows: list[RawServing], name: str, temperature: Temperature, size: str) -> RawServing:
    matches = [
        r
        for r in rows
        if r.drink_name == name and r.temperature is temperature and r.size_label == size
    ]
    assert len(matches) == 1, f"{name}/{temperature}/{size}: {len(matches)} rows"
    return matches[0]


def test_brand_contract() -> None:
    assert BRAND.id == "paulbassett"
    assert BRAND.has_size_choice is True


def test_caffeine_values() -> None:
    assert parse_caffeine("225") == (225, None)
    assert parse_caffeine("10mg이하") == (10, CaffeineRange(min_mg=0, max_mg=10))
    assert parse_caffeine("10이하") == (10, CaffeineRange(min_mg=0, max_mg=10))
    assert parse_caffeine("-") == (None, None)
    assert parse_caffeine("") == (None, None)
    with pytest.raises(ParseError, match="unreadable caffeine"):
        parse_caffeine("약간")


def test_product_page_reads_every_size() -> None:
    rows = parse_product_page(DECAF_LATTE, category="Decaf", source_url=URL)
    assert len(rows) == 2
    grand = _row(rows, "디카페인 카페라떼", Temperature.HOT, "Grand")
    assert (grand.volume_ml, grand.sugar_g, grand.caffeine_mg) == (460, 18, 15)
    assert grand.caffeine_range == CaffeineRange(min_mg=0, max_mg=15)
    assert grand.drink_name_en == "Decaf Cafe Latte"


def test_unpublished_sugar_stays_none() -> None:
    html = _page("Iced Only", '<option value="S">Standard</option>', _size("S", "360", "-", "160"))
    (row,) = parse_product_page(html, category="Coffee", source_url=URL)
    assert (row.temperature, row.sugar_g, row.caffeine_mg) == (Temperature.ICED, None, 160)


def test_missing_kind_is_both_and_unknown_kind_raises() -> None:
    options = '<option value="O">Original</option>'
    blocks = _size("O", "127", "22", "10이하")
    (row,) = parse_product_page(_page(None, options, blocks), category="Decaf", source_url=URL)
    assert row.temperature is Temperature.BOTH
    with pytest.raises(ParseError, match="unknown temperature"):
        parse_product_page(_page("Warm", options, blocks), category="Decaf", source_url=URL)


def test_list_page_links() -> None:
    html = (
        '<div class="tabStyleF"><ul><li><a href="/menu/List.pb?cid1=A&cid2=B">Coffee</a></li>'
        '<li><a href="/menu/List.pb?cid1=A&cid2=C">Latte</a></li></ul></div>'
        "<a onclick=\"goView('PB1');return false;\"></a><a onclick=\"goView('PB1')\"></a>"
        "<a onclick=\"goView('PB2')\"></a>"
    )
    assert parse_sub_categories(html) == [("B", "Coffee"), ("C", "Latte")]
    assert parse_product_ids(html) == ["PB1", "PB2"]


@pytest.mark.live
def test_scrape_live(client: httpx.Client) -> None:
    rows = scrape(client)
    assert len({(r.drink_name, r.temperature) for r in rows}) >= 80
    assert {r.brand_id for r in rows} == {BRAND.id}
    assert all(r.volume_ml is not None for r in rows)
    keys = [(r.drink_name, r.temperature, r.size_label) for r in rows]
    assert len(keys) == len(set(keys))
    assert {"Latte", "Decaf", "Tea"} <= {r.category for r in rows}
    latte = _row(rows, "카페라떼", Temperature.HOT, "Standard")
    assert (latte.volume_ml, latte.sugar_g, latte.caffeine_mg) == (360, 15, 225)
