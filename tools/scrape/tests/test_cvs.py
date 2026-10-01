from __future__ import annotations

from pathlib import Path

import pytest

from sugarcap_scrape.brands import cvs
from sugarcap_scrape.brands.cvs import KfindRow, parse_rows, to_serving
from sugarcap_scrape.build import group_rows

RAW = Path(__file__).resolve().parents[1] / ".raw"
KFIND_FILES = sorted(RAW.glob("kfind_*.xlsx"))


def _row(
    name: str = "바나나맛우유",
    *,
    code: str = "P1",
    group: str = "유가공품류",
    kind: str = "가공우유",
    basis: str = "100ml",
    sugar: str = "10.00",
    pack: str = "240ml",
    created: str = "2024-01-01",
) -> KfindRow:
    return KfindRow(
        code=code,
        name=name,
        group=group,
        kind=kind,
        basis=basis,
        sugar=sugar,
        pack=pack,
        maker="빙그레",
        created=created,
    )


def test_whole_pack_sugar_from_per_100() -> None:
    serving = to_serving(_row(), source="db.xlsx")
    assert serving is not None
    assert serving.size_label == "240ml"
    assert serving.volume_ml == 240
    assert serving.sugar_g == 24.0
    assert serving.caffeine_mg is None
    assert serving.source_url == "db.xlsx#P1"


def test_gram_pack_keeps_volume_unknown() -> None:
    serving = to_serving(_row(basis="100g", pack="150g", sugar="8"), source="x")
    assert serving is not None
    assert serving.size_label == "150g"
    assert serving.volume_ml is None
    assert serving.sugar_g == 12.0


@pytest.mark.parametrize(
    "row",
    [
        _row(basis="100g", pack="240ml"),  # unit mismatch would need a density
        _row(pack=""),
        _row(pack="1000ml"),
        _row(pack="80ml"),
        _row(sugar="30"),  # syrup territory
        _row(name="생강청", group="음료류", kind="액상차"),
        _row(name="홍삼진액", group="음료류", kind="인삼/홍삼음료"),
        _row(group="음료류", kind="원두/원두분말"),
        _row(group="유가공품류", kind="치즈"),
    ],
)
def test_out_of_scope_rows_are_skipped(row: KfindRow) -> None:
    assert to_serving(row, source="x") is None


def test_newest_record_wins_for_same_name_and_pack() -> None:
    rows = [
        _row(code="P1", sugar="9", created="2019-06-30"),
        _row(code="P2", sugar="10", created="2025-02-01"),
        _row(code="P3", sugar="11", created="2021-06-30"),
    ]
    servings = parse_rows(rows, source="x")
    assert [s.source_url for s in servings] == ["x#P2"]


def test_pack_sizes_become_size_choices() -> None:
    rows = [_row(pack="240ml"), _row(code="P2", pack="500ml")]
    drinks = group_rows(parse_rows(rows, source="x"))
    assert len(drinks) == 1
    assert [s.size_label for s in drinks[0].servings] == ["240ml", "500ml"]
    assert cvs.BRAND.has_size_choice


@pytest.mark.skipif(not KFIND_FILES, reason="no K-FIND xlsx in tools/scrape/.raw")
def test_real_kfind_export() -> None:
    servings = cvs.scrape(KFIND_FILES[-1])
    assert len(servings) >= 9000
    assert all(s.caffeine_mg is None for s in servings)
    assert all(s.sugar_g is not None and s.sugar_g <= 150 for s in servings)
    names = {s.drink_name for s in servings}
    assert {"바나나맛우유", "데자와로얄밀크티", "몬스터 에너지"} <= names
