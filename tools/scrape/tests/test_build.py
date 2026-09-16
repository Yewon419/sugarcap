from __future__ import annotations

import pytest

from sugarcap_scrape.build import group_rows
from sugarcap_scrape.ids import slugify
from sugarcap_scrape.models import RawServing, Temperature


def _row(name: str, size: str, temp: Temperature = Temperature.ICED) -> RawServing:
    return RawServing(
        brand_id="test",
        drink_name=name,
        category="coffee",
        temperature=temp,
        size_label=size,
        volume_ml=355,
        sugar_g=0.0,
        caffeine_mg=150.0,
        source_url="https://example.com",
    )


def test_slugify_is_stable_for_korean_and_spaces() -> None:
    assert slugify("아이스 카페 아메리카노") == "아이스-카페-아메리카노"
    assert slugify(" Tall (355ml) ") == "tall-355ml"


def test_group_rows_merges_sizes_into_one_drink() -> None:
    drinks = group_rows([_row("라떼", "Regular"), _row("라떼", "Large")])
    assert len(drinks) == 1
    assert [s.size_label for s in drinks[0].servings] == ["Regular", "Large"]
    assert drinks[0].id == "test:라떼:iced"


def test_group_rows_rejects_duplicate_serving() -> None:
    with pytest.raises(ValueError, match="duplicate serving id"):
        group_rows([_row("라떼", "Regular"), _row("라떼", "Regular")])
