from __future__ import annotations

import httpx
import pytest

from sugarcap_scrape.brands import paik
from sugarcap_scrape.http import fetch_text
from sugarcap_scrape.ids import serving_id
from sugarcap_scrape.models import RawServing, Temperature
from sugarcap_scrape.parse import ParseError

PAGE_TEMPLATE = """
<div class="sub_visual"><h1>커피</h1></div>
<div class="menu_list clear"><ul>{items}</ul></div>
"""

ITEM_TEMPLATE = """
<li>
  <p class="menu_tit">{name}</p>
  <div class="hover">
    <div class="menu_tit2 color-1 ">{en}</div>
    <div class="ingredient_table_box">
      <p class="menu_ingredient_basis">※ 알레르기 유발 성분 : 우유</p>
      {basis}
      <ul class="ingredient_table">{table}</ul>
    </div>
  </div>
</li>
"""


def item(name: str, *, en: str = "", basis: str = "", table: str = "") -> str:
    return ITEM_TEMPLATE.format(name=name, en=en, basis=basis, table=table)


def cell(label: str, value: str) -> str:
    return f"<li><div>{label}</div><div>{value}</div></li>"


def find(rows: list[RawServing], name: str, temperature: Temperature) -> RawServing:
    matches = [r for r in rows if r.drink_name == name and r.temperature is temperature]
    assert len(matches) == 1, f"{name} {temperature}: {matches}"
    return matches[0]


@pytest.mark.parametrize(
    ("raw", "name", "temperature"),
    [
        ("아메리카노(ICED)", "아메리카노", Temperature.ICED),
        ("아메리카노(HOT)", "아메리카노", Temperature.HOT),
        ("패션후르츠스무디 (ICED)", "패션후르츠스무디", Temperature.ICED),
        ("챔피언스 블랙 벨벳 라떼 HOT", "챔피언스 블랙 벨벳 라떼", Temperature.HOT),
        ("바닐라 빽스치노(BASIC)", "바닐라 빽스치노(BASIC)", Temperature.BOTH),
        ("아이스티샷추가(아샷추)", "아이스티샷추가(아샷추)", Temperature.BOTH),
    ],
)
def test_split_temperature(raw: str, name: str, temperature: Temperature) -> None:
    assert paik.split_temperature(raw) == (name, temperature)


def test_parse_table_label_variants_and_missing_values() -> None:
    html = PAGE_TEMPLATE.format(
        items=item(
            "카페라떼(ICED)",
            en="cafe latte",
            basis='<p class="menu_ingredient_basis">※ 컵용량 : 660ml</p>',
            table=cell("카페인 (mg)", "163") + cell("당류(g)", "6"),
        )
        + item("콜드브루 원액", table=cell("나트륨", "1"))
    )
    latte, concentrate = paik.parse_menu_page(html, source_url="u")
    assert latte.drink_name == "카페라떼"
    assert latte.drink_name_en == "cafe latte"
    assert latte.temperature is Temperature.ICED
    assert latte.category == "커피"
    assert latte.volume_ml == 660
    assert latte.caffeine_mg == 163.0
    assert latte.sugar_g == 6.0
    assert concentrate.temperature is Temperature.BOTH
    assert concentrate.drink_name_en is None
    assert concentrate.volume_ml is None
    assert concentrate.caffeine_mg is None
    assert concentrate.sugar_g is None


def test_parse_page_without_items_raises() -> None:
    with pytest.raises(ParseError):
        paik.parse_menu_page(PAGE_TEMPLATE.format(items=""), source_url="u")


@pytest.mark.live
def test_live_category_page_parses(client: httpx.Client) -> None:
    url = paik.BASE_URL + "/menu/menu_ccino/"
    rows = paik.parse_menu_page(fetch_text(client, url), source_url=url)
    assert len(rows) >= 10
    assert {r.category for r in rows} == {"빽스치노"}


@pytest.mark.live
def test_live_scrape(client: httpx.Client) -> None:
    rows = paik.scrape(client)
    assert len(rows) >= 40

    iced = find(rows, "아메리카노", Temperature.ICED)
    assert iced.volume_ml == 660
    assert iced.caffeine_mg == 166.0
    assert iced.sugar_g == 0.0

    hot = find(rows, "아메리카노", Temperature.HOT)
    assert hot.volume_ml == 510
    assert hot.caffeine_mg == 197.0
    assert hot.sugar_g == 0.0

    latte = find(rows, "카페라떼", Temperature.ICED)
    assert latte.caffeine_mg == 163.0
    assert latte.sugar_g == 6.0

    assert {r.category for r in rows} == {"커피", "음료", "빽스치노"}
    assert all(r.brand_id == "paik" for r in rows)
    assert all(r.size_label == "기본" for r in rows)
    assert not any(r.drink_name.endswith(("HOT", "ICED", "(HOT)", "(ICED)")) for r in rows)

    ids = [serving_id(r) for r in rows]
    assert len(ids) == len(set(ids))
