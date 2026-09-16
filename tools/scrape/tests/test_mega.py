from __future__ import annotations

import httpx
import pytest

from sugarcap_scrape.brands import mega
from sugarcap_scrape.http import fetch_text
from sugarcap_scrape.ids import serving_id
from sugarcap_scrape.models import RawServing, Temperature
from sugarcap_scrape.parse import ParseError

ITEM_TEMPLATE = """
<ul id="menu_list">
  <li>
    <a class="inner_modal_open">
      <div class="cont_gallery_list_img">{label}</div>
    </a>
    <div class="inner_modal">
      <div class="cont_text inner_modal_title">
        <div class="cont_text_inner cont_text_title"><b>{name}</b></div>
        <div class="cont_text_inner cont_text_info">{en}</div>
      </div>
      <div class="cont_text">
        <div class="cont_text_inner">컵용량 : 591ml</div>
        <div class="cont_text_inner">1회 제공량 328kcal</div>
      </div>
      <div class="cont_list">
        <ul>{nutrition}</ul>
      </div>
    </div>
  </li>
</ul>
"""


def render(name: str, *, label: str = "", en: str = "", nutrition: str) -> str:
    label_html = f'<div class="cont_gallery_list_label">{label}</div>' if label else ""
    return ITEM_TEMPLATE.format(name=name, label=label_html, en=en, nutrition=nutrition)


def find(rows: list[RawServing], name: str, volume_ml: int) -> RawServing:
    matches = [r for r in rows if r.drink_name == name and r.volume_ml == volume_ml]
    assert len(matches) == 1, f"{name} {volume_ml}ml: {matches}"
    return matches[0]


def test_parse_unit_typo_and_prefix_stripped() -> None:
    html = render(
        "(ICE)헛개리카노",
        label="ICE",
        en="Hutgae-ricano",
        nutrition="<li>포화지방 0g</li><li>당류 15g</li><li>카페인 181.6g</li>",
    )
    (row,) = mega.parse_menu_page(html, category="커피", source_url="u")
    assert row.drink_name == "헛개리카노"
    assert row.drink_name_en == "Hutgae-ricano"
    assert row.temperature is Temperature.ICED
    assert row.volume_ml == 591
    assert row.sugar_g == 15.0
    assert row.caffeine_mg == 181.6
    assert row.size_label == "기본"
    assert row.category == "커피"


def test_parse_without_label_is_both_and_missing_nutrients_are_none() -> None:
    html = render("ARIH 소다", nutrition="<li>나트륨 10mg</li>")
    (row,) = mega.parse_menu_page(html, category="신상품", source_url="u")
    assert row.temperature is Temperature.BOTH
    assert row.sugar_g is None
    assert row.caffeine_mg is None


def test_parse_label_prefix_conflict_raises() -> None:
    html = render("(HOT)헛개리카노", label="ICE", nutrition="<li>당류 0g</li>")
    with pytest.raises(ParseError):
        mega.parse_menu_page(html, category="커피", source_url="u")


def test_parse_empty_fragment_returns_no_rows() -> None:
    assert mega.parse_menu_page("<ul id='menu_list'></ul>", category="커피", source_url="u") == []


@pytest.mark.live
def test_live_shell_subcategories(client: httpx.Client) -> None:
    html = fetch_text(client, mega.SHELL_URL, params=mega.DRINK_TAB_PARAMS)
    subs = mega.parse_subcategories(html)
    labels = {sub.label for sub in subs}
    assert {"커피", "티", "음료"} <= labels
    assert all(sub.value for sub in subs)


@pytest.mark.live
def test_live_scrape(client: httpx.Client) -> None:
    rows = mega.scrape(client)
    assert len(rows) >= 60

    americano_hot = find(rows, "아메리카노", 591)
    assert americano_hot.temperature is Temperature.HOT
    assert americano_hot.sugar_g == 0.0
    assert americano_hot.caffeine_mg == 204.2
    assert americano_hot.category == "커피"

    hazelnut = find(rows, "헤이즐넛아메리카노", 591)
    assert hazelnut.sugar_g == 9.5
    assert hazelnut.caffeine_mg == 209.8

    assert {"커피", "티", "음료"} <= {r.category for r in rows}
    assert all(r.brand_id == "mega" for r in rows)
    assert all(r.size_label == "기본" for r in rows)
    assert all(r.source_url.startswith(mega.LIST_URL) for r in rows)
    assert not any(r.drink_name.startswith("(") for r in rows)

    ids = [serving_id(r) for r in rows]
    assert len(ids) == len(set(ids))
