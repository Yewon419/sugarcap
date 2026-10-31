from __future__ import annotations

import pytest

from sugarcap_scrape.build import group_rows, merge_catalog
from sugarcap_scrape.ids import slugify
from sugarcap_scrape.models import Brand, Catalog, RawServing, Temperature


def _row(
    name: str, size: str, temp: Temperature = Temperature.ICED, brand: str = "test"
) -> RawServing:
    return RawServing(
        brand_id=brand,
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


def _catalog(built_at: str, version: int, rows: list[RawServing]) -> Catalog:
    brand_ids = list(dict.fromkeys(row.brand_id for row in rows))
    brands = tuple(
        Brand(id=b, name=f"{b} {built_at}", serving_note="", has_size_choice=True)
        for b in brand_ids
    )
    return Catalog(
        schema_version=version, built_at=built_at, brands=brands, drinks=tuple(group_rows(rows))
    )


def test_merge_swaps_only_the_updated_brands() -> None:
    base = _catalog(
        "old",
        1,
        [_row("라떼", "R", brand="a"), _row("모카", "R", brand="b"), _row("티", "R", brand="c")],
    )
    update = _catalog("new", 2, [_row("새 라떼", "R", brand="b"), _row("쉐이크", "R", brand="d")])
    merged = merge_catalog(base, update)
    assert [b.id for b in merged.brands] == ["a", "b", "c", "d"]
    assert merged.brands[1].name == "b new"
    assert sorted(d.id for d in merged.drinks) == [
        "a:라떼:iced",
        "b:새-라떼:iced",
        "c:티:iced",
        "d:쉐이크:iced",
    ]
    assert (merged.schema_version, merged.built_at) == (2, "new")
