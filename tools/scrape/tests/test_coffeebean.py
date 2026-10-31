from __future__ import annotations

import httpx
import pytest

from sugarcap_scrape.brands.coffeebean import (
    BRAND,
    has_next_page,
    parse_list_page,
    scrape,
)
from sugarcap_scrape.models import RawServing, Temperature

URL = "https://www.coffeebeankorea.com/menu/list.asp?category=13&page=1"


def _dl(cls: str, value: str, label: str) -> str:
    return f'<dl class="{cls}"><dt>{value}</dt><dd>{label}</dd></dl>'


def _item(kor: str, eng: str, *pairs: str) -> str:
    return (
        f'<li><dl class="txt"><dt><span class="eng">{eng}</span><span class="kor">{kor}</span>'
        f'</dt><dd>설명</dd></dl><div class="info">{"".join(pairs)}</div></li>'
    )


def _page(*items: str) -> str:
    return f'<ul class="menu_list  _thumb5">{"".join(items)}</ul>'


def _row(rows: list[RawServing], name: str) -> RawServing:
    matches = [r for r in rows if r.drink_name == name]
    assert len(matches) == 1, f"{name}: {len(matches)} rows"
    return matches[0]


def test_brand_contract() -> None:
    assert BRAND.id == "coffeebean"
    assert BRAND.has_size_choice is False


def test_values_are_read_by_label() -> None:
    html = _page(
        _item(
            "아이스 커피빈라떼",
            "Iced Coffeebean Latte",
            _dl("bg1", "120", "열량<br /> Kcal"),
            _dl("bg4", "9", "당<br /> g"),
            _dl("bg2", "193", "카페인<br />mg"),
        ),
        # 카페인 dl missing: the next dl must not be read as caffeine.
        _item(
            "제주 레몬 스웨디쉬",
            "Jeju Lemon Swedish",
            _dl("bg4", "34", "당<br /> g"),
            _dl("bg1", "0", "단백질<br />g"),
        ),
    )
    rows = parse_list_page(html, category="에스프레소 음료", source_url=URL)
    latte = _row(rows, "아이스 커피빈라떼")
    assert (latte.sugar_g, latte.caffeine_mg, latte.temperature) == (9, 193, Temperature.ICED)
    assert latte.drink_name_en == "Iced Coffeebean Latte"
    tea = _row(rows, "제주 레몬 스웨디쉬")
    assert (tea.sugar_g, tea.caffeine_mg, tea.temperature) == (34, None, Temperature.BOTH)


def test_ice_blended_section_is_cold() -> None:
    html = _page(_item("모카 아이스 블렌디드", "Mocha", _dl("bg4", "50", "당<br /> g")))
    (row,) = parse_list_page(html, category="아이스 블렌디드 (Coffee)", source_url=URL)
    assert row.temperature is Temperature.ICED


def test_next_page_link() -> None:
    assert has_next_page('<a href="?page=2&category=13">2</a>', 1) is True
    assert has_next_page('<a href="?page=12&category=13">12</a>', 1) is False


@pytest.mark.live
def test_scrape_live(client: httpx.Client) -> None:
    rows = scrape(client)
    assert len(rows) >= 80
    assert {r.brand_id for r in rows} == {BRAND.id}
    keys = [(r.drink_name, r.temperature) for r in rows]
    assert len(keys) == len(set(keys))
    assert sum(r.sugar_g is not None for r in rows) >= len(rows) * 0.9
    assert {"에스프레소 음료", "티", "아이스 블렌디드 (Coffee)"} <= {r.category for r in rows}
