from __future__ import annotations

import json

import httpx
import pytest

from sugarcap_scrape.brands.twosome import (
    BRAND,
    DRINK_GRT_CD,
    MENU_LIST_URL,
    MID_LIST_URL,
    NUTRITION_URL,
    SIZE_LIST_URL,
    MenuItem,
    MidCategory,
    SizeOption,
    build_row,
    detail_url,
    parse_menu_page,
    parse_mid_categories,
    parse_nutrition,
    parse_ondo_options,
    parse_size_options,
    scrape,
    temperature_of,
    volume_ml,
)
from sugarcap_scrape.http import fetch_text
from sugarcap_scrape.models import RawServing, Temperature
from sugarcap_scrape.parse import ParseError

COFFEE = MidCategory(code="01", name="커피")
AMERICANO = MenuItem(code="10100001", name="아메리카노", name_en="Americano")
REGULAR = SizeOption(code="020R", label="레귤러")


def _wrapped(*rows: dict[str, object]) -> str:
    return json.dumps(
        {"queryCode": 1000, "queryMessage": "SUCCESS", "fetchResultListSet": list(rows)},
        ensure_ascii=False,
    )


def _menu(name: str, code: str, *, next_page: int = 0, name_en: str = "") -> dict[str, object]:
    return {"MENU_CD": code, "MENU_NM": name, "EN_MENU_NM": name_en, "NEXT_PAGE": next_page}


def _nutrition_payload(**values: str) -> str:
    table = {
        "1회 제공량": "(컵용량)355ml",
        "총 제공량": "1잔",
        "열량(Kcal)": "15",
        "당류(g/%)": "0/0",
        "카페인(mg/%)": "186",
        **values,
    }
    return json.dumps(
        [{"ADD_INFO_TITLE": title, "MENU_CNTNT": value} for title, value in table.items()],
        ensure_ascii=False,
    )


def _tab(code: str, label: str) -> str:
    return f'<li><a id="ondo_{code}" href="javascript:fn_ondoTabClick(\'{code}\')">{label}</a></li>'


def _row(table_json: str) -> RawServing | None:
    return build_row(
        parse_nutrition(table_json, "ctx"),
        item=AMERICANO,
        category="커피",
        temperature=Temperature.HOT,
        size=REGULAR,
    )


def test_brand_contract() -> None:
    assert BRAND.id == "twosome"
    assert BRAND.has_size_choice is True


def test_parse_mid_categories() -> None:
    text = _wrapped(
        {"MID_CD": "NEW", "MID_NM": "NEW"},
        {"MID_CD": "01", "MID_NM": "커피"},
        {"MID_CD": "04", "MID_NM": "아이스크림/빙수"},
    )
    assert parse_mid_categories(text) == [
        MidCategory("NEW", "NEW"),
        MidCategory("01", "커피"),
        MidCategory("04", "아이스크림/빙수"),
    ]


def test_parse_mid_categories_rejects_a_failed_query() -> None:
    text = json.dumps({"queryCode": 9000, "queryMessage": "ERROR", "fetchResultListSet": []})
    with pytest.raises(ParseError, match="queryCode"):
        parse_mid_categories(text)


def test_parse_menu_page_reads_paging_off_the_first_row() -> None:
    page = parse_menu_page(
        _wrapped(
            _menu("아메리카노", "10100001", next_page=2, name_en="Americano"),
            _menu("카페 라떼", "10100002", next_page=2),
        ),
        COFFEE,
    )
    assert page.next_page == 2
    assert page.items[0] == AMERICANO
    assert page.items[1].name_en is None


def test_parse_menu_page_ends_on_an_empty_result_set() -> None:
    page = parse_menu_page(_wrapped(), COFFEE)
    assert page == ([], 0)


def test_parse_ondo_options_drops_the_duplicated_tab_block() -> None:
    block = f"<div>{_tab('010H', '핫')}{_tab('010I', '아이스')}</div>"
    assert parse_ondo_options(block + block) == [("010H", "핫"), ("010I", "아이스")]


def test_parse_ondo_options_without_tabs() -> None:
    assert parse_ondo_options("<div>우리 팥 빙수</div>") == []


def test_parse_size_options() -> None:
    text = json.dumps(
        [
            {"OPTS": "020R", "SIZE_OPT_NM": "레귤러"},
            {"OPTS": "020L", "SIZE_OPT_NM": "라지"},
            {"OPTS": "020M", "SIZE_OPT_NM": "맥스"},
        ],
        ensure_ascii=False,
    )
    assert parse_size_options(text, "10100001") == [
        SizeOption("020R", "레귤러"),
        SizeOption("020L", "라지"),
        SizeOption("020M", "맥스"),
    ]


def test_parse_nutrition_rejects_a_non_string_value() -> None:
    with pytest.raises(ParseError, match="MENU_CNTNT"):
        parse_nutrition('[{"ADD_INFO_TITLE": "당류(g/%)", "MENU_CNTNT": 3}]', "ctx")


def test_temperature_of() -> None:
    assert temperature_of("핫") is Temperature.HOT
    assert temperature_of("아이스") is Temperature.ICED
    assert temperature_of("") is Temperature.BOTH


def test_volume_ml() -> None:
    assert volume_ml("(컵용량)355ml") == 355
    assert volume_ml("1잔") is None


def test_build_row_keeps_the_absolute_value_of_each_pair() -> None:
    row = _row(_nutrition_payload(**{"당류(g/%)": "31/31", "카페인(mg/%)": "186"}))
    assert row is not None
    assert (row.drink_name, row.drink_name_en) == ("아메리카노", "Americano")
    assert (row.sugar_g, row.caffeine_mg) == (31, 186)
    assert (row.size_label, row.volume_ml) == ("레귤러", 355)
    assert row.temperature is Temperature.HOT
    assert row.source_url == detail_url("10100001")


def test_build_row_leaves_an_unpublished_value_none() -> None:
    row = _row(_nutrition_payload(**{"카페인(mg/%)": "-"}))
    assert row is not None
    assert row.caffeine_mg is None


def test_build_row_without_a_caffeine_line_leaves_it_none() -> None:
    text = json.dumps(
        [
            {"ADD_INFO_TITLE": "1회 제공량", "MENU_CNTNT": "(컵용량)355ml"},
            {"ADD_INFO_TITLE": "당류(g/%)", "MENU_CNTNT": "24/24"},
        ],
        ensure_ascii=False,
    )
    row = _row(text)
    assert row is not None
    assert (row.sugar_g, row.caffeine_mg) == (24, None)


def test_build_row_skips_a_menu_served_without_a_cup() -> None:
    assert _row(_nutrition_payload(**{"1회 제공량": "120g"})) is None


def test_build_row_without_a_serving_line_raises() -> None:
    with pytest.raises(ParseError, match="1회 제공량"):
        _row("[]")


@pytest.fixture(scope="module")
def coffee_menus(client: httpx.Client) -> list[MenuItem]:
    text = fetch_text(
        client,
        MENU_LIST_URL,
        method="POST",
        data={"pageNum": "1", "grtCd": DRINK_GRT_CD, "midCd": COFFEE.code},
    )
    return parse_menu_page(text, COFFEE).items


@pytest.mark.live
def test_parse_mid_categories_live(client: httpx.Client) -> None:
    text = fetch_text(client, MID_LIST_URL, method="POST", data={"grtCd": DRINK_GRT_CD})
    names = {category.name for category in parse_mid_categories(text)}
    assert {"커피", "음료", "티/티라떼"} <= names


@pytest.mark.live
def test_parse_menu_page_live(coffee_menus: list[MenuItem]) -> None:
    assert len(coffee_menus) >= 20
    assert any(item.name == "아메리카노" for item in coffee_menus)


@pytest.mark.live
def test_americano_nutrition_live(client: httpx.Client, coffee_menus: list[MenuItem]) -> None:
    item = next(menu for menu in coffee_menus if menu.name == "아메리카노")
    options = parse_ondo_options(fetch_text(client, detail_url(item.code)))
    assert [option.label for option in options] == ["핫", "아이스"]
    hot = options[0]
    sizes = parse_size_options(
        fetch_text(
            client,
            SIZE_LIST_URL,
            method="POST",
            data={"menuCd": item.code, "ondoOpt": hot.code, "midCd": ""},
        ),
        item.code,
    )
    assert [size.label for size in sizes] == ["레귤러", "라지"]
    table = parse_nutrition(
        fetch_text(
            client,
            NUTRITION_URL,
            method="POST",
            data={
                "menuCd": item.code,
                "ondoOpt": hot.code,
                "sizeOpt": sizes[0].code,
                "midCd": "",
            },
        ),
        "아메리카노 핫 레귤러",
    )
    row = build_row(table, item=item, category="커피", temperature=Temperature.HOT, size=sizes[0])
    assert row is not None
    assert (row.sugar_g, row.caffeine_mg, row.volume_ml) == (0, 186, 355)


@pytest.mark.live
def test_scrape_live(client: httpx.Client) -> None:
    rows = scrape(client)
    assert len(rows) >= 150
    assert {row.brand_id for row in rows} == {BRAND.id}
    assert "아이스크림/빙수" not in {row.category for row in rows}
    keys = [(row.drink_name, row.temperature, row.size_label) for row in rows]
    assert len(keys) == len(set(keys))
    assert all(row.volume_ml is not None for row in rows)
    americano = [row for row in rows if row.drink_name == "아메리카노"]
    # 아이스는 맥스까지 나온다. 온도별로 사이즈 구성이 다르다는 점이 이 브랜드의 특징.
    assert {"레귤러", "라지"} <= {row.size_label for row in americano} <= {"레귤러", "라지", "맥스"}
    assert {row.temperature for row in americano} == {Temperature.HOT, Temperature.ICED}
    hot_regular = next(
        row
        for row in americano
        if row.temperature is Temperature.HOT and row.size_label == "레귤러"
    )
    assert (hot_regular.sugar_g, hot_regular.caffeine_mg) == (0, 186)
