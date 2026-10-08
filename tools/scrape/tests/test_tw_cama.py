from __future__ import annotations

import httpx
import pytest

from sugarcap_scrape.brands.tw_cama import (
    BRAND,
    parse_caffeine,
    parse_menu,
    per_size_caffeine,
    scrape,
)
from sugarcap_scrape.models import CaffeineRange, RawServing, Temperature
from sugarcap_scrape.parse import ParseError


def _modal(modal_id: str, name: str, sugar: str, band: str, other: str) -> str:
    return f"""<div id='{modal_id}' class='ingredient_modal section modal'>
<div class='modal-header'><div class='col-md-8 name'>{name}</div></div><div class='modal-body'>
<div class='calories_box'><div class='ti'>熱量(大卡)</div><ul class='calories'></ul></div>
<div class='calories_box'><div class='ti'> 糖(g)</div><ul class='calories'>{sugar}</ul></div>
<ul class='row dli'><li><div class='col-md-3 ti'>原料產地</div><div class='col-md-9'>泰國</div></li>
<li><div class='col-md-3 ti'>咖啡因總含量</div><div class='col-md-9'>
<span class='total_content02'></span>{band}</div></li>
<li><div class='col-md-3 ti'>其他資訊</div><div class='col-md-9'>{other}</div></li></ul></div></div>"""


def _li(size: str, hot: str, iced: str) -> str:
    return f"<li><span>{size} </span> <span>熱 {hot}</span> <span>冰 {iced}</span></li>"


# Rows copied from camacafe.com/Menu/1 on 2026-10-08, trimmed to the parts the parser reads.
PAGE = (
    """<div class='menu'><div class='ti classno_1'>奶咖 Milk Coffee<span> </span></div>
<a data-target='#ingredient47'></a><a data-target='#ingredient51'></a></div>
<div class='menu'><div class='ti'>黑咖 Black Coffee</div><a data-target='#ingredient299'></a>
<a data-target='#ingredient92'></a></div>
<div class='menu'><div class='ti'>純茶、奶茶 Others</div><a data-target='#ingredient80'></a>
<a data-target='#ingredient115'></a></div>
<ul>2. 本表所含之糖量、熱量、咖啡因，以最高值計算。表以全糖量計算（黑咖啡、手沖、濃縮、冷萃除外）</ul>"""
    + _modal(
        "ingredient47",
        "CAMA金獎拿鐵<span>Latte</span>",
        _li("M", "14.6", "10.2") + _li("L", "16.5", "12.5") + _li("XL", "19.6", "15.4"),
        "201mg以上",
        "咖啡因總含量：M：207.8mg、L：311.7mg、XL：415.6mg",
    )
    + _modal(
        "ingredient51",
        "抹茶拿鐵<span>Matcha Coffee Latte</span>",
        _li("M", "20.7", "15.0") + _li("XL", "30.4", "25.9"),
        "201mg以上",
        "咖啡因總含量：M：115mg、XL(熱)：318mg、XL(冰)：422mg",
    )
    + _modal(
        "ingredient299",
        "精品冷萃-盛夏草莓精品冷萃<span></span>",
        _li("L", "-", "0.2"),
        "101~200mg",
        "咖啡因199.4mg",
    )
    + _modal(
        "ingredient92",
        "濃縮咖啡<span>Espresso</span>",
        _li("M", "0.2", "-") + _li("L", "-", "-"),
        "101~200mg",
        "僅限內用．容量30ml，咖啡因總含量：103.9mg",
    )
    + _modal(
        "ingredient80",
        "抹茶歐蕾<span>Matcha Milk</span>",
        _li("M", "21.2", "16.9") + _li("L", "25.1", "20.8") + _li("XL", "37.8", "36.9"),
        "",
        "咖啡因總含量：M、L : 100mg以下、XL：101-200mg",
    )
    + _modal(
        "ingredient115",
        "熟香紅茶<span>Black Tea</span>",
        _li("M", "-", "-") + _li("L", "18.0", "18.0"),
        "101~200mg",
        "",
    )
)


def _row(rows: list[RawServing], name: str, temp: Temperature, size: str) -> RawServing:
    matches = [
        row
        for row in rows
        if row.drink_name == name and row.temperature is temp and row.size_label == size
    ]
    assert len(matches) == 1, f"{name} {temp} {size}: {len(matches)} rows"
    return matches[0]


def test_brand_contract() -> None:
    assert BRAND.id == "tw-cama"
    assert BRAND.has_size_choice is True


def test_sugar_per_size_and_temperature_with_exact_caffeine() -> None:
    rows = parse_menu(PAGE)
    hot = _row(rows, "CAMA金獎拿鐵", Temperature.HOT, "L")
    iced = _row(rows, "CAMA金獎拿鐵", Temperature.ICED, "L")
    assert (hot.sugar_g, iced.sugar_g) == (16.5, 12.5)
    assert (hot.caffeine_mg, hot.caffeine_range) == (311.7, None)
    assert (hot.drink_name_en, hot.category) == ("Latte", "奶咖 Milk Coffee")


def test_caffeine_per_temperature() -> None:
    rows = parse_menu(PAGE)
    assert _row(rows, "抹茶拿鐵", Temperature.HOT, "XL").caffeine_mg == 318.0
    assert _row(rows, "抹茶拿鐵", Temperature.ICED, "XL").caffeine_mg == 422.0
    assert _row(rows, "抹茶拿鐵", Temperature.ICED, "M").caffeine_mg == 115.0


def test_unsold_cups_are_skipped_and_single_cups_take_an_unlabeled_number() -> None:
    rows = parse_menu(PAGE)
    cold_brew = "精品冷萃-盛夏草莓精品冷萃"
    sold = {(row.temperature, row.size_label) for row in rows if row.drink_name == cold_brew}
    assert sold == {(Temperature.ICED, "L")}
    assert _row(rows, cold_brew, Temperature.ICED, "L").caffeine_mg == 199.4
    espresso = _row(rows, "濃縮咖啡", Temperature.HOT, "M")
    assert (espresso.volume_ml, espresso.caffeine_mg) == (30, 103.9)
    assert [row.size_label for row in rows if row.drink_name == "熟香紅茶"] == ["L", "L"]


def test_bands_per_size_or_from_the_drink() -> None:
    rows = parse_menu(PAGE)
    medium = _row(rows, "抹茶歐蕾", Temperature.HOT, "L")
    assert medium.caffeine_range == CaffeineRange(min_mg=0, max_mg=100)
    xl = _row(rows, "抹茶歐蕾", Temperature.ICED, "XL")
    assert (xl.caffeine_mg, xl.caffeine_range) == (200.0, CaffeineRange(min_mg=101, max_mg=200))
    tea = _row(rows, "熟香紅茶", Temperature.HOT, "L")
    assert tea.caffeine_range == CaffeineRange(min_mg=101, max_mg=200)


def test_caffeine_notations() -> None:
    assert parse_caffeine("0", "t").mg == 0.0
    assert parse_caffeine("101-200mg以上", "t").band == CaffeineRange(min_mg=101, max_mg=200)
    found = per_size_caffeine("咖啡因總含量：L：  \t 265.7mg", "t")
    assert found[("L", Temperature.HOT)].mg == 265.7
    with pytest.raises(ParseError):
        parse_caffeine("約200mg", "t")


def test_a_changed_basis_note_raises() -> None:
    with pytest.raises(ParseError):
        parse_menu(PAGE.replace("以最高值計算。表以全糖量計算", "以平均值計算"))


@pytest.mark.live
def test_live_scrape(client: httpx.Client) -> None:
    rows = scrape(client)
    assert len({(row.drink_name, row.temperature) for row in rows}) >= 60
    latte = [row for row in rows if row.drink_name == "CAMA金獎拿鐵"]
    assert {row.size_label for row in latte} == {"M", "L", "XL"}
    assert all(row.caffeine_mg is not None for row in latte)
