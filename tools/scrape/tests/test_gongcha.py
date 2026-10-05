from __future__ import annotations

import httpx
import pytest

from sugarcap_scrape.brands.gongcha import BRAND, NUTRITION_URL, parse_nutrition_page, scrape
from sugarcap_scrape.models import RawServing, Temperature
from sugarcap_scrape.parse import ParseError

HEAD = (
    "<thead><tr><th>메뉴명</th><th>구분</th><th>사이즈</th><th>컵 용량(ml)</th>"
    "<th>열량(kcal)</th><th>당류(g)</th><th>단백질(g)</th><th>포화지방(g)</th>"
    "<th>나트륨 (mg)</th><th>카페인(mg)</th><th>알레르기 유발물질</th></tr></thead>"
)


def _section(category: str, body: str) -> str:
    return (
        f'<div class="item"><div class="inner"><h4 class="scroll-item">{category}</h4>'
        f'<div class="table-item"><div class="table-title"></div><table>{HEAD}'
        f"<tbody>{body}</tbody></table></div></div></div>"
    )


def _values(*cells: str) -> str:
    return "".join(f"<td>{cell}</td>" for cell in cells)


# 허니 자몽 블랙티 as published: name / allergy span 4 rows, COLD / HOT span 2 each.
HONEY_GRAPEFRUIT = (
    '<tr><td class="border-none" rowspan="4">허니 자몽 블랙티</td><td rowspan="2">COLD</td>'
    + _values("L", "473", "126", "24", "0", "0", "23", "106")
    + '<td rowspan="4">-</td></tr>'
    + "<tr>"
    + _values("J", "651", "178", "35", "0", "0", "30", "142")
    + "</tr>"
    + '<tr><td rowspan="2">HOT</td>'
    + _values("L", "414", "126", "24", "0", "0", "23", "128")
    + "</tr><tr>"
    + _values("J", "473", "178", "35", "0", "0", "30", "142")
    + "</tr>"
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
    assert BRAND.id == "gongcha"
    assert BRAND.has_size_choice is True
    assert "당도 0%" in BRAND.serving_note


def test_rowspans_fill_name_and_temperature() -> None:
    rows = parse_nutrition_page(_section("프룻티&모어", HONEY_GRAPEFRUIT), NUTRITION_URL)
    assert len(rows) == 4
    assert {r.drink_name for r in rows} == {"허니 자몽 블랙티"}
    hot_jumbo = _row(rows, "허니 자몽 블랙티", Temperature.HOT, "점보")
    assert (hot_jumbo.volume_ml, hot_jumbo.sugar_g, hot_jumbo.caffeine_mg) == (473, 35, 142)
    assert _row(rows, "허니 자몽 블랙티", Temperature.ICED, "라지").caffeine_mg == 106


def test_rollup_category_yields_to_real_category() -> None:
    html = _section("베스트셀러", HONEY_GRAPEFRUIT) + _section("프룻티&모어", HONEY_GRAPEFRUIT)
    rows = parse_nutrition_page(html, NUTRITION_URL)
    assert len(rows) == 4
    assert {r.category for r in rows} == {"프룻티&모어"}


def test_unnamed_size_is_labelled_by_volume() -> None:
    body = (
        '<tr><td rowspan="2">트로피컬 블러쉬 아이스티</td><td rowspan="2">COLD</td>'
        + _values("J", "651", "209", "42", "1", "0", "58", "100")
        + '<td rowspan="2">대두</td></tr><tr>'
        + _values("G", "946", "349", "71", "1", "0", "84", "114")
        + "</tr>"
    )
    rows = parse_nutrition_page(_section("NEW 시즌 메뉴", body), NUTRITION_URL)
    assert [(r.size_label, r.volume_ml, r.sugar_g) for r in rows] == [
        ("점보", 651, 42),
        ("946ml", 946, 71),
    ]


def test_unknown_temperature_raises() -> None:
    body = "<tr><td>x</td><td>WARM</td>" + _values("L", "1", "2", "3", "4", "5", "6", "7", "-")
    with pytest.raises(ParseError, match="unknown temperature"):
        parse_nutrition_page(_section("커피", body + "</tr>"), NUTRITION_URL)


def test_page_without_tables_raises() -> None:
    with pytest.raises(ParseError, match="no nutrition tables"):
        parse_nutrition_page("<html><body></body></html>", NUTRITION_URL)


@pytest.mark.live
def test_scrape_live(client: httpx.Client) -> None:
    rows = scrape(client)
    assert len({r.drink_name for r in rows}) >= 100
    assert {r.brand_id for r in rows} == {BRAND.id}
    assert all(r.sugar_g is not None and r.volume_ml is not None for r in rows)
    keys = [(r.drink_name, r.temperature, r.size_label) for r in rows]
    assert len(keys) == len(set(keys))
    assert {"밀크티", "커피", "스무디", "오리지널 티"} <= {r.category for r in rows}
    milk_tea = _row(rows, "브라운슈가 시그니처 밀크티 +펄", Temperature.ICED, "라지")
    assert (milk_tea.volume_ml, milk_tea.sugar_g, milk_tea.caffeine_mg) == (473, 37, 92)
    americano = _row(rows, "아메리카노 (ESP)", Temperature.HOT, "점보")
    assert (americano.volume_ml, americano.sugar_g, americano.caffeine_mg) == (473, 0, 171)
