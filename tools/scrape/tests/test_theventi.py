from __future__ import annotations

import httpx
import pytest

from sugarcap_scrape.brands.theventi import (
    BRAND,
    Basis,
    detail_url,
    list_url,
    parse_basis,
    parse_caffeine_variants,
    parse_categories,
    parse_detail,
    parse_list,
    scrape,
    split_by_temperature,
    strip_size_suffix,
    value_at_size,
)
from sugarcap_scrape.http import fetch_text
from sugarcap_scrape.models import RawServing, Temperature
from sugarcap_scrape.parse import ParseError

LARGE_NOTE = "*영양성분 및 성분별 기준치 : 라지(600ml) 사이즈 기준"
MEDIUM_NOTE = "*영양성분 및 성분별 기준치 : 미디엄(420ml) 사이즈 기준"


def _detail(
    *,
    name: str = "카페라떼 (라지/점보)",
    serving: str = "라지(600ml) 점보(960ml)",
    sugar: str = "11 (11%)",
    caffeine: str = "92 (고카페인)",
    description: str = LARGE_NOTE,
) -> str:
    return f"""
    <div class="menu_desc_wrap">
      <div class="txt_bx">
        <p class="tit"><span></span><span class="tag"></span><span>{name}</span></p>
        <div class="txt scroll-con-y">{description}</div>
        <div class="menu-ingredient"><table class="table"><tbody><tr>
          <td>{serving}</td><td>160</td><td>{sugar}</td><td>8 (14%)</td>
          <td>5.2 (34.7%)</td><td>113 (6%)</td><td>{caffeine}</td><td>우유</td>
        </tr></tbody></table></div>
      </div>
    </div>"""


def _list_page(*items: tuple[str, str, str]) -> str:
    entries = "".join(
        f"""<li class="col-lg-3 item"><a href="/new2022/menu/all-view.new.html?uid={uid}">
        <div class="txt_bx"><p class="type">{icons}</p><p class="tit">{name}</p></div></a></li>"""
        for uid, name, icons in items
    )
    return f'<div class="menu_list"><ul>{entries}</ul></div>'


def _parse_one(html: str, temperature: Temperature = Temperature.BOTH) -> RawServing:
    rows = parse_detail(html, category="커피", temperature=temperature, source_url="u")
    assert len(rows) == 1
    return rows[0]


def _by_name(rows: list[RawServing], name: str) -> list[RawServing]:
    matches = [row for row in rows if row.drink_name == name]
    assert matches, f"{name} not scraped"
    return matches


def test_brand_contract() -> None:
    assert BRAND.id == "theventi"
    assert BRAND.has_size_choice is False


def test_strip_size_suffix() -> None:
    assert strip_size_suffix("카페라떼 (라지/점보)") == "카페라떼"
    assert strip_size_suffix("아인슈페너 (미디엄/라지)") == "아인슈페너"
    assert strip_size_suffix("핫 아메리카노 (라지)") == "핫 아메리카노"
    assert strip_size_suffix("리치캐모마일 스파클링") == "리치캐모마일 스파클링"
    assert strip_size_suffix("우베 크림 슈 (신메뉴)") == "우베 크림 슈 (신메뉴)"


def test_parse_basis_prefers_the_description_note() -> None:
    assert parse_basis(MEDIUM_NOTE, "미디엄(420ml) / 라지(600ml)") == Basis("미디엄", 420)
    assert parse_basis(LARGE_NOTE, "라지(600ml) 점보(960ml)") == Basis("라지", 600)


def test_parse_basis_falls_back_to_the_serving_cell() -> None:
    assert parse_basis("", "라지 : 600ml") == Basis("라지", 600)
    assert parse_basis("", "미디움 (420ml) / 라지 (600ml)") == Basis("미디엄", 420)
    assert parse_basis("", "ICE : 600ml / HOT : 600ml") == Basis("기본", 600)
    assert parse_basis("", "600ml") == Basis("기본", 600)


def test_parse_basis_rejects_food() -> None:
    assert parse_basis("", "120g") is None
    assert parse_basis("", "1ea (24g)") is None


def test_split_by_temperature() -> None:
    assert split_by_temperature("43 (43%) (Hot) / 39 (39%) (Iced)") == {
        Temperature.HOT: 43,
        Temperature.ICED: 39,
    }
    assert split_by_temperature("ICE : 42 (42%) / HOT : 45 (45%)") == {
        Temperature.ICED: 42,
        Temperature.HOT: 45,
    }


def test_split_by_temperature_ignores_one_value_for_both() -> None:
    assert split_by_temperature("266 (HOT / ICED) (고카페인)") is None
    assert split_by_temperature("미디엄 34 (34%) / 라지 48 (48%)") is None
    assert split_by_temperature("31 (31%)") is None


def test_value_at_size() -> None:
    assert value_at_size("미디엄 34 (34%) / 라지 48 (48%)", "라지") == 48
    assert value_at_size("미디움 43 (43%) / 라지 58 (58%)", "미디엄") == 43
    assert value_at_size("라지 36 (36%) / 점보 56 (56%)", "라지") == 36
    assert value_at_size("17 (17%) ※저당옵션 적용시 11 (11%)", "라지") == 17
    assert value_at_size("- (0%)", "라지") == 0
    assert value_at_size("-", "라지") is None


def test_parse_caffeine_variants() -> None:
    variants = parse_caffeine_variants("(고카페인) 시그니처:168 다크:266")
    assert [(v.label, v.caffeine_mg) for v in variants] == [("시그니처", 168), ("다크", 266)]
    assert parse_caffeine_variants("고카페인 266") == ()
    assert parse_caffeine_variants("-") == ()


def test_parse_detail_reads_one_serving() -> None:
    row = _parse_one(_detail(), Temperature.HOT)
    assert (row.drink_name, row.size_label, row.volume_ml) == ("카페라떼", "라지", 600)
    assert (row.sugar_g, row.caffeine_mg) == (11, 92)
    assert row.temperature is Temperature.HOT
    assert row.caffeine_variants == ()


def test_parse_detail_keeps_the_first_bean_as_the_default() -> None:
    row = _parse_one(_detail(caffeine="(고카페인) 시그니처:168 다크:266"))
    assert row.caffeine_mg == 168
    assert [(v.label, v.caffeine_mg) for v in row.caffeine_variants] == [
        ("시그니처", 168),
        ("다크", 266),
    ]


def test_parse_detail_splits_a_row_published_per_temperature() -> None:
    rows = parse_detail(
        _detail(sugar="28 (28%) (HOT) / 27 (27%) (ICED)", caffeine="266 (HOT / ICED) (고카페인)"),
        category="커피",
        temperature=Temperature.BOTH,
        source_url="u",
    )
    assert [(row.temperature, row.sugar_g, row.caffeine_mg) for row in rows] == [
        (Temperature.HOT, 28, 266),
        (Temperature.ICED, 27, 266),
    ]


def test_parse_detail_leaves_an_unpublished_value_none() -> None:
    row = _parse_one(_detail(sugar="-", caffeine="-"))
    assert (row.sugar_g, row.caffeine_mg) == (None, None)


def test_parse_detail_skips_food() -> None:
    assert (
        parse_detail(
            _detail(name="말차머핀", serving="120g", description=""),
            category="사이드",
            temperature=Temperature.BOTH,
            source_url="u",
        )
        == []
    )


def test_parse_detail_without_nutrition_row_raises() -> None:
    with pytest.raises(ParseError, match="without nutrition row"):
        parse_detail(
            '<div class="menu_desc_wrap"><p class="tit">x</p></div>',
            category="커피",
            temperature=Temperature.BOTH,
            source_url="u",
        )


def test_parse_list_reads_temperature_from_the_icons() -> None:
    items = parse_list(
        _list_page(
            ("1", "카페라떼 (라지/점보)", "<i class='hot'></i><i class='ice'></i>"),
            ("2", "복숭아에이드 (라지/점보)", "<i class='ice'></i>"),
            ("3", "핫 아메리카노 (라지)", "<i class='hot'></i>"),
        )
    )
    assert [(item.uid, item.temperature) for item in items] == [
        ("1", Temperature.BOTH),
        ("2", Temperature.ICED),
        ("3", Temperature.HOT),
    ]


def test_parse_list_without_items_raises() -> None:
    with pytest.raises(ParseError, match="no menu items"):
        parse_list('<div class="menu_list"><ul></ul></div>')


def test_parse_categories_without_tabs_raises() -> None:
    with pytest.raises(ParseError, match="no category tabs"):
        parse_categories("<html></html>")


@pytest.fixture(scope="module")
def coffee_html(client: httpx.Client) -> str:
    return fetch_text(client, list_url("2"))


@pytest.mark.live
def test_parse_categories_live(coffee_html: str) -> None:
    categories = parse_categories(coffee_html)
    names = [category.name for category in categories]
    assert {"신메뉴", "커피", "디카페인", "사이드메뉴/RTD"} <= set(names)
    assert names[0] == "신메뉴"


@pytest.mark.live
def test_parse_list_live(coffee_html: str) -> None:
    items = parse_list(coffee_html)
    assert len(items) >= 15
    assert all(item.uid.isdigit() for item in items)
    assert any(item.name.startswith("아이스 아메리카노") for item in items)


@pytest.mark.live
def test_parse_detail_live(client: httpx.Client, coffee_html: str) -> None:
    item = next(
        item for item in parse_list(coffee_html) if item.name.startswith("아이스 아메리카노")
    )
    url = detail_url(item.uid)
    row = _parse_one(fetch_text(client, url), item.temperature)
    assert row.drink_name == "아이스 아메리카노"
    assert (row.size_label, row.volume_ml) == ("라지", 600)
    assert row.sugar_g == 0
    assert [v.label for v in row.caffeine_variants] == ["시그니처", "다크"]
    assert row.caffeine_mg == row.caffeine_variants[0].caffeine_mg


@pytest.mark.live
def test_scrape_live(client: httpx.Client) -> None:
    rows = scrape(client)
    assert len(rows) >= 100
    assert {row.brand_id for row in rows} == {BRAND.id}
    assert {row.size_label for row in rows} <= {"라지", "미디엄", "기본"}
    keys = [(row.drink_name, row.temperature) for row in rows]
    assert len(keys) == len(set(keys))
    assert all(row.volume_ml is not None for row in rows)
    assert "사이드메뉴/RTD" not in {row.category for row in rows}
    latte = _by_name(rows, "카페라떼")[0]
    assert latte.sugar_g == 11
    assert [v.label for v in latte.caffeine_variants] == ["시그니처", "다크"]
    assert _by_name(rows, "콜드브루")[0].caffeine_mg == 92
