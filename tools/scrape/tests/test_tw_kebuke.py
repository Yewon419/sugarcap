from __future__ import annotations

import httpx
import pytest

from sugarcap_scrape.brands.tw_kebuke import BRAND, parse_caffeine, parse_menu, scrape
from sugarcap_scrape.models import CaffeineRange, RawServing, Temperature
from sugarcap_scrape.parse import ParseError

# Blocks copied from kebuke.com/menu/ on 2026-10-08, trimmed to the parts the parser reads.
PAGE = """
<p>飲品容量：大杯 700 ml／中杯 500 ml。</p>
<div class="page-menu__product -limited"><p class="page-menu__product-title">季節限定</p>
<div class="menu-item"><p class="menu-item__name"> 酒吧監製系列——白柚水玉紅烏龍 <icon name="hot"></icon> </p>
<p class="menu-item__sugar"> 【中杯】<br /> 糖量：44.6 g；熱量：187.9 Kcal<br /> 咖啡因總量 135.5 mg ；奶素可食用<br /> 【大杯】<br /> 糖量：67.0 g；熱量：277.8 Kcal<br /> 咖啡因總量 143.8 mg ；奶素可食用<br /> <br /> #本產品含有咖啡因，孩童、懷孕、哺乳婦及咖啡因敏感者請斟酌。 </p></div>
</div>
<div class="page-menu__product"><p class="page-menu__product-title">乎乾 好茶 Classic</p>
<div class="menu-item"><p class="menu-item__name"> 熟成紅茶 <icon name="hot"></icon> </p>
<p class="menu-item__sugar"> 【中杯】<br /> 糖量：45 g；熱量：180 kcal<br /> 咖啡因總含量 101-200 mg；全素者可食用<br /> 【大杯】<br /> 糖量：50 g；熱量：200 kcal<br /> 咖啡因總含量 ≥ 201 mg；全素者可食用 </p></div>
<div class="menu-item"><p class="menu-item__name"> 麗春紅茶 </p>
<p class="menu-item__sugar"> 【中杯】<br /> 糖量：45 g；熱量：180 kcal<br /> 【大杯】<br /> 糖量：50 g；熱量：200 kcal<br /> 咖啡因總含量 101-200 mg；全素者可食用 </p></div>
<div class="menu-item"><p class="menu-item__name"> 雪花冷露 </p>
<p class="menu-item__sugar"> 【中杯】<br /> 糖量：40 g；熱量：169 kcal<br /> 【大杯】<br /> 糖量：55 g；熱量：233 kcal<br /> 無含咖啡因；全素者可食用 </p></div>
</div>
<div class="page-menu__product"><p class="page-menu__product-title">乎乾 奶茶 Milk Tea</p>
<div class="menu-item"><p class="menu-item__name"> 春芽奶茶 <icon name="hot"></icon> </p>
<p class="menu-item__sugar"> ●春芽奶茶<br /> 【中杯】<br /> 糖量：49.9 g；熱量：322.9 Kcal<br /> 咖啡因總含量 ≦100mg ；奶素者可食用<br /> <br /> 【大杯】<br /> 糖量：61.9 g ；熱量：432.4 Kcal<br /> 咖啡因總含量 101~200mg；奶素者可食用 <br /> <br /> ●春芽奶茶(＋酷涼配方)<br /> 【中杯】<br /> 糖量：48.4 g ；熱量：318.7 Kcal<br /> 咖啡因總含量 ≦100mg ；奶素者可食用<br /> <br /> 【大杯】<br /> 糖量：64.3 g ；熱量：444.7 Kcal<br /> 咖啡因總含量 101~200mg ；奶素者可食用 </p></div>
</div>
<div class="page-menu__product"><p class="page-menu__product-title">金蒔燒 Sun-Baked Waffle｜台式雞蛋糕</p>
<div class="menu-item"><p class="menu-item__name"> 經典原味 5入 </p><p class="menu-item__sugar"> </p></div>
</div>
"""


def _row(rows: list[RawServing], name: str, size: str) -> RawServing:
    matches = [row for row in rows if row.drink_name == name and row.size_label == size]
    assert len(matches) == 1, f"{name} {size}: {len(matches)} rows"
    return matches[0]


def test_brand_contract() -> None:
    assert BRAND.id == "tw-kebuke"
    assert BRAND.has_size_choice is True


def test_exact_caffeine_and_published_cup_volume() -> None:
    rows = parse_menu(PAGE)
    medium = _row(rows, "酒吧監製系列——白柚水玉紅烏龍", "中杯")
    assert (medium.sugar_g, medium.caffeine_mg, medium.caffeine_range) == (44.6, 135.5, None)
    assert (medium.volume_ml, medium.temperature) == (500, Temperature.BOTH)
    assert _row(rows, "酒吧監製系列——白柚水玉紅烏龍", "大杯").volume_ml == 700


def test_bands_carry_their_bound() -> None:
    rows = parse_menu(PAGE)
    medium, large = _row(rows, "熟成紅茶", "中杯"), _row(rows, "熟成紅茶", "大杯")
    assert medium.caffeine_range == CaffeineRange(min_mg=101, max_mg=200)
    assert medium.caffeine_mg == 200.0
    assert large.caffeine_range == CaffeineRange(min_mg=201)
    assert large.caffeine_mg == 201.0


def test_one_caffeine_line_after_both_cups_covers_both() -> None:
    rows = parse_menu(PAGE)
    assert _row(rows, "麗春紅茶", "中杯").caffeine_range == CaffeineRange(min_mg=101, max_mg=200)
    assert _row(rows, "雪花冷露", "中杯").caffeine_mg == 0.0


def test_second_recipe_is_its_own_drink_and_food_is_dropped() -> None:
    rows = parse_menu(PAGE)
    cool = _row(rows, "春芽奶茶(＋酷涼配方)", "大杯")
    assert (cool.sugar_g, cool.category) == (64.3, "乎乾 奶茶 Milk Tea")
    assert _row(rows, "春芽奶茶", "中杯").caffeine_range == CaffeineRange(min_mg=0, max_mg=100)
    assert all("5入" not in row.drink_name for row in rows)


def test_caffeine_notations() -> None:
    assert parse_caffeine("咖啡因總量 101～200 mg ；全素可食用", "t") is not None
    at_least = parse_caffeine("咖啡因總含量 ≧ 201mg；奶素者可食用", "t")
    assert at_least is not None and at_least.band == CaffeineRange(min_mg=201)
    assert parse_caffeine("#本產品含有咖啡因，孩童請斟酌。", "t") is None
    with pytest.raises(ParseError):
        parse_caffeine("咖啡因總含量 約一杯", "t")


def test_missing_volume_note_raises() -> None:
    with pytest.raises(ParseError):
        parse_menu(PAGE.replace("飲品容量", "容量"))


@pytest.mark.live
def test_live_scrape(client: httpx.Client) -> None:
    rows = scrape(client)
    assert len({row.drink_name for row in rows}) >= 30
    assert all(row.sugar_g is not None for row in rows)
    classic = [row for row in rows if row.drink_name == "熟成紅茶"]
    assert {row.size_label for row in classic} == {"中杯", "大杯"}
