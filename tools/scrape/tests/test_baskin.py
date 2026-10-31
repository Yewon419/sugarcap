from __future__ import annotations

import httpx
import pytest

from sugarcap_scrape.brands.baskin import (
    BRAND,
    merge_spellings,
    parse_caffeine,
    parse_cup_name,
    parse_group_page,
    parse_sugar,
    scrape,
)
from sugarcap_scrape.models import CaffeineRange, RawServing, Temperature
from sugarcap_scrape.parse import ParseError

URL = "https://www.baskinrobbins.co.kr/menu/view_subcategory.php?seq=92"


def _product(title: str, sugar: str, caffeine: str) -> str:
    pairs = (("1회 제공량(g)", "300"), ("당류(g)", sugar), ("카페인(mg)", caffeine))
    items = "".join(
        f'<dl class="menu-view-nutrition__item"><dt class="menu-view-nutrition__name">{k}</dt>'
        f'<dd class="menu-view-nutrition__text">{v}</dd></dl>'
        for k, v in pairs
    )
    return f'<div class="subcategory-view__product"><h4>{title}</h4>{items}</div>'


def _row(rows: list[RawServing], name: str, temperature: Temperature, size: str) -> RawServing:
    matches = [
        r
        for r in rows
        if r.drink_name == name and r.temperature is temperature and r.size_label == size
    ]
    assert len(matches) == 1, f"{name}/{temperature}/{size}: {len(matches)} rows"
    return matches[0]


def test_brand_contract() -> None:
    assert BRAND.id == "baskin"
    assert BRAND.has_size_choice is True


@pytest.mark.parametrize(
    ("raw", "name", "temperature", "size"),
    [
        ("I_R&#41;믹솔로지 티 프로스티 ", "믹솔로지 티 프로스티", Temperature.ICED, "레귤러"),
        ("I_R)믹솔로지 티 프로스티", "믹솔로지 티 프로스티", Temperature.ICED, "레귤러"),
        ("H_LD)아메리카노", "디카페인 아메리카노", Temperature.HOT, "라지"),
        ("I_K)킹 아메리카노", "아메리카노", Temperature.ICED, "킹"),
        ("I_KD)킹 아메리카노", "디카페인 아메리카노", Temperature.ICED, "킹"),
        (
            "I_R)D몬치치(보이)아메리카노",
            "디카페인 몬치치(보이)아메리카노",
            Temperature.ICED,
            "레귤러",
        ),
        ("I_D)납작복숭아아샷추", "디카페인 납작복숭아아샷추", Temperature.ICED, "기본"),
        ("I_납작복숭아아샷추", "납작복숭아아샷추", Temperature.ICED, "기본"),
        ("ICED 연유라떼R", "연유라떼", Temperature.ICED, "레귤러"),
        ("HOT 아메리카노 R", "아메리카노", Temperature.HOT, "레귤러"),
        ("카페31  카페라떼 ICED R", "카페31 카페라떼", Temperature.ICED, "레귤러"),
        ("디카페인 아메리카노 ICED R", "디카페인 아메리카노", Temperature.ICED, "레귤러"),
        ("바나나 카페라떼(DECAF)", "디카페인 바나나 카페라떼", Temperature.BOTH, "기본"),
        ("자몽 히비스커스 티(ICED)", "자몽 히비스커스 티", Temperature.ICED, "기본"),
        ("밀크 쉐이크 L", "밀크 쉐이크", Temperature.BOTH, "라지"),
        ("크런치 쉐이크(마시멜로)", "크런치 쉐이크(마시멜로)", Temperature.BOTH, "기본"),
    ],
)
def test_cup_name(raw: str, name: str, temperature: Temperature, size: str) -> None:
    cup = parse_cup_name(raw.replace("&#41;", ")"))
    assert (cup.drink_name, cup.temperature, cup.size_label) == (name, temperature, size)


def test_values_as_published() -> None:
    assert parse_sugar("38~63") == 63
    assert parse_sugar("-") == 0
    assert parse_sugar("0.8") == 0.8
    assert parse_caffeine("131*") == (131, None)
    assert parse_caffeine("5~6") == (6, CaffeineRange(min_mg=5, max_mg=6))
    assert parse_caffeine("-") == (0, None)


def test_group_page_reads_every_cup() -> None:
    html = (
        "<h3>영양정보</h3>"
        + _product("I_R&#41;믹솔로지 티 프로스티 ", "38~39", "5~6")
        + _product("I_L&#41;믹솔로지 티 프로스티 ", "77", "10~12")
    )
    rows = parse_group_page(html, category="음료", source_url=URL)
    large = _row(rows, "믹솔로지 티 프로스티", Temperature.ICED, "라지")
    assert (large.sugar_g, large.caffeine_mg, large.volume_ml) == (77, 12, None)
    assert large.caffeine_range == CaffeineRange(min_mg=10, max_mg=12)
    assert _row(rows, "믹솔로지 티 프로스티", Temperature.ICED, "레귤러").sugar_g == 39


def test_spacing_variants_become_one_drink() -> None:
    html = _product("I_R)감귤 캐모마일 티 프로스티", "38", "-") + _product(
        "I_L)감귤캐모마일티프로스티", "75", "-"
    )
    rows = merge_spellings(parse_group_page(html, category="음료", source_url=URL))
    assert {r.drink_name for r in rows} == {"감귤 캐모마일 티 프로스티"}


def test_page_without_cups_raises() -> None:
    with pytest.raises(ParseError, match=r"no \.subcategory-view__product"):
        parse_group_page("<html></html>", category="음료", source_url=URL)


@pytest.mark.live
def test_scrape_live(client: httpx.Client) -> None:
    rows = scrape(client)
    assert len({(r.drink_name, r.temperature) for r in rows}) >= 60
    assert {r.brand_id for r in rows} == {BRAND.id}
    assert all(r.sugar_g is not None and r.caffeine_mg is not None for r in rows)
    keys = [(r.drink_name, r.temperature, r.size_label) for r in rows]
    assert len(keys) == len(set(keys))
    assert {r.category for r in rows} == {"음료", "커피"}
    assert _row(rows, "아메리카노", Temperature.ICED, "킹").caffeine_mg == 261
    assert _row(rows, "디카페인 아메리카노", Temperature.HOT, "라지").caffeine_mg == 3
