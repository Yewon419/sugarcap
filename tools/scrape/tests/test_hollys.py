from __future__ import annotations

import httpx
import pytest

from sugarcap_scrape.brands.hollys import (
    BRAND,
    CATEGORY_KEYS,
    CATEGORY_URL,
    parse_category_page,
    parse_serving_note,
    scrape,
)
from sugarcap_scrape.http import fetch_text
from sugarcap_scrape.models import RawServing, Temperature
from sugarcap_scrape.parse import ParseError

ESPRESSO_URL = CATEGORY_URL.format(key="espresso")

ERROR_PAGE = (
    '<!DOCTYPE html><html lang="ko"><head>\r\n<title>Hollys</title>\r\n'
    "<script type=\"text/javascript\">\r\nalert('메뉴 정보가 정확하지 않습니다.');\r\n"
    " document.location.href='/';\r\n</script>\r\n</head></html>\r\n"
)


def _table(name: str, note: str, rows: list[list[str]]) -> str:
    body = "".join(
        "<tr><th>{}</th>{}</tr>".format(row[0], "".join(f"<td>{cell}</td>" for cell in row[1:]))
        for row in rows
    )
    return (
        f'<div class="menu_info02" id="menuView2_7"><div class="tableInfo03">'
        f'<span class="ft16B">제품영양정보 ({note})</span></div>'
        f"<table><caption>{name}</caption><thead><tr><th></th><th>칼로리</th><th>당류</th>"
        f"<th>단백질</th><th>포화지방</th><th>나트륨</th><th>카페인</th></tr></thead>"
        f"<tbody>{body}</tbody></table></div>"
    )


def _page(*tables: str, category: str = "COFFEE", view: str = "") -> str:
    return f'<html><body><h2 class="h2menu">{category}</h2>{view}{"".join(tables)}</body></html>'


def _rows(rows: list[RawServing], name: str, temperature: Temperature) -> RawServing:
    matches = [r for r in rows if r.drink_name == name and r.temperature is temperature]
    assert len(matches) == 1, f"{name}/{temperature}: {len(matches)} rows"
    return matches[0]


def test_brand_contract() -> None:
    assert BRAND.id == "hollys"
    assert BRAND.has_size_choice is False


@pytest.mark.parametrize(
    ("note", "label", "volume"),
    [
        ("1회 제공량 / Regular / 354ml 기준 ( Grande / 472ml, Venti / 591ml )", "Regular", 354),
        ("1회 제공량 / Grande / 472ml 기준( Venti / 591ml )", "Grande", 472),
        ("1회 제공량 / Solo / 25ml 기준 ( Doppio / 50ml )", "Solo", 25),
        ("1회 제공량/ Regular 기준", "Regular", None),
        (
            "1회 제공량 HOT - R) 316g, G) 437g / ICED - R) 369g, G) 482g, V) 552g 기준",
            "Regular",
            None,
        ),
        ("1회 제공량 / 150ml 기준", "150ml", 150),
    ],
)
def test_parse_serving_note(note: str, label: str, volume: int | None) -> None:
    assert parse_serving_note(note) == (label, volume)


def test_parse_serving_note_rejects_unknown_shape() -> None:
    with pytest.raises(ParseError, match="serving note not understood"):
        parse_serving_note("총 중량 387g, 1회 제공량 387g")


def test_error_page_raises() -> None:
    with pytest.raises(ParseError, match="error page"):
        parse_category_page(ERROR_PAGE, ESPRESSO_URL)


def test_missing_values_and_non_drinks() -> None:
    html = _page(
        _table(
            "레드티",
            "1회 제공량 / Regular / 354ml 기준",
            [["HOT", "208 kcal", "50g (50%)", "0g", "-", "139mg", "-"]],
        ),
        _table("팥 듬뿍 빙수", "총 중량 541g, 1회 제공량 541g", []),
        _table(
            "블랙아리아딥라떼",
            "1회 제공량 / Regular / 354ml 기준 ( Grande / 472ml )",
            [["ICED", "96kcal", "7g/7%", "5g/9%", "3.4g/23%", "73mg/4%", "153mg"]],
        ),
        category="라떼 · 초콜릿 · 티",
        view=(
            '<div class="menu_view01" id="menuView1_7"><div class="menu_detail">'
            "<p><span>레드티</span>\n Red Tea\n </p></div></div>"
        ),
    )
    rows = parse_category_page(html, ESPRESSO_URL)
    assert [r.drink_name for r in rows] == ["레드티", "블랙아리아딥라떼"]
    tea, latte = rows
    assert tea.caffeine_mg is None
    assert tea.sugar_g == 50
    assert tea.drink_name_en == "Red Tea"
    assert tea.category == "라떼 · 초콜릿 · 티"
    assert latte.temperature is Temperature.ICED
    assert (latte.sugar_g, latte.caffeine_mg) == (7, 153)
    assert latte.source_url == ESPRESSO_URL


def test_unknown_temperature_row_raises() -> None:
    html = _page(
        _table("x", "1회 제공량 / Regular / 354ml 기준", [["WARM", "1", "2", "3", "4", "5", "6"]])
    )
    with pytest.raises(ParseError, match="unknown temperature"):
        parse_category_page(html, ESPRESSO_URL)


@pytest.fixture(scope="module")
def espresso_rows(client: httpx.Client) -> list[RawServing]:
    return parse_category_page(fetch_text(client, ESPRESSO_URL), ESPRESSO_URL)


@pytest.mark.live
def test_parse_espresso_page_live(espresso_rows: list[RawServing]) -> None:
    assert len(espresso_rows) >= 30
    assert {r.category for r in espresso_rows} == {"COFFEE"}
    for temperature in (Temperature.HOT, Temperature.ICED):
        americano = _rows(espresso_rows, "아메리카노", temperature)
        assert (americano.sugar_g, americano.caffeine_mg) == (0, 114)
        assert (americano.size_label, americano.volume_ml) == ("Regular", 354)
    assert _rows(espresso_rows, "카페 라떼", Temperature.HOT).sugar_g == 12
    assert _rows(espresso_rows, "카페 라떼", Temperature.ICED).sugar_g == 6
    assert _rows(espresso_rows, "카페 라떼", Temperature.ICED).caffeine_mg == 127
    assert _rows(espresso_rows, "카페 라떼", Temperature.HOT).drink_name_en == "Caffe Latte"


@pytest.mark.live
def test_scrape_live(client: httpx.Client) -> None:
    rows = scrape(client)
    assert len(rows) >= 30
    assert {r.brand_id for r in rows} == {BRAND.id}
    assert len({r.category for r in rows}) == len(CATEGORY_KEYS)
    assert not any("빙수" in r.drink_name for r in rows)
    assert all(r.sugar_g is not None for r in rows)
    latte = _rows(rows, "카페 라떼", Temperature.HOT)
    assert (latte.sugar_g, latte.caffeine_mg, latte.volume_ml) == (12, 127, 354)
    keys = [(r.drink_name, r.temperature, r.size_label) for r in rows]
    assert len(keys) == len(set(keys))
