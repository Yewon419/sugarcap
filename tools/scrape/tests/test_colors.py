from __future__ import annotations

import json
from pathlib import Path

import pytest

from sugarcap_scrape import colors
from sugarcap_scrape.colors import liquid_color

CATALOG = Path(__file__).resolve().parents[3] / "data" / "catalog.json"


@pytest.mark.parametrize(
    ("name", "category", "expected"),
    [
        # A colouring flavour beats the base it is mixed into.
        ("딸기라떼", "음료", "#E8587A"),
        ("말차 라떼", "티", colors.GREEN_TEA),
        ("바나나맛우유", "가공우유", "#F6E08A"),
        ("초콜렛우유", "가공우유", colors.CHOCO),
        # The longer word wins over the word it contains.
        ("청포도에이드", "에이드", "#B8D86B"),
        ("로얄 밀크티", "티", colors.MILK_TEA),
        # Milky coffee before black coffee.
        ("카페라떼", "커피", colors.LATTE),
        ("아이스 카페 아메리카노", "커피", colors.COFFEE),
        # 콜라겐 is not cola.
        ("마시는콜라겐1000", "액상음료", colors.DEFAULT),
        ("코카콜라 제로", "탄산음료", "#3B1F14"),
        ("코코넛워터", "액상음료", colors.CLEAR),
        # A café's own category decides before broad words in the name (티 inside 에티오피아).
        ("에티오피아 예가체프", "COFFEE", colors.COFFEE),
        # K-FIND category when the name says nothing.
        ("레쓰비", "액상커피", colors.LATTE),
        ("아침에 카톡", "발효유", "#F7F3EA"),
    ],
)
def test_liquid_color(name: str, category: str, expected: str) -> None:
    assert liquid_color(name, category) == expected


def test_every_committed_drink_has_a_colour_from_the_palette() -> None:
    palette = {rule.color for rule in colors.RULES + colors.GENERIC_RULES}
    palette |= set(colors.CATEGORY_COLORS.values()) | {colors.DEFAULT}
    drinks = json.loads(CATALOG.read_text(encoding="utf-8"))["drinks"]
    for drink in drinks:
        assert drink["liquid_color"] == liquid_color(drink["name"], drink["category"]), drink["id"]
        assert drink["liquid_color"] in palette
