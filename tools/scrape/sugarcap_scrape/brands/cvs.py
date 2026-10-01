"""편의점 음료 from the MFDS 식품영양성분 DB (K-FIND) 가공식품 export.

No convenience-store chain publishes nutrition, so the source is the national
가공식품 DB: an xlsx downloaded by hand from
https://various.foodsafetykorea.go.kr/nutrient/ (영양성분 DB 내려받기 → 가공식품 DB;
the site asks for a short usage form first, so the builder does not fetch it).
It lists products, not stores, so every product becomes one `cvs` brand drink.
There is no date cutoff: 데이터생성일자 is a bulk-load date (many rows carry
2019-06-30 or 2021-06-30), not a launch date, so cutting by it drops long-selling
products such as 데자와. Repeats of a name and pack size keep the newest record.

The DB publishes values per 100ml or 100g. The one conversion allowed here
(SPEC §2, 2026-10-01) is multiplying by the package's own 식품중량 when it is in
the same unit, which gives the whole bottle or can. Nothing else is estimated:
rows without a usable 식품중량 are skipped, never guessed.

The DB has no caffeine column, so `caffeine_mg` is always None ("미공개").
"""

from __future__ import annotations

import re
from collections.abc import Iterable
from dataclasses import dataclass
from pathlib import Path

from python_calamine import CalamineWorkbook

from sugarcap_scrape.ids import slugify
from sugarcap_scrape.models import Brand, RawServing, Temperature
from sugarcap_scrape.parse import ParseError, clean_text

BRAND = Brand(
    id="cvs",
    name="편의점",
    serving_note="한 병·한 캔 기준 (식약처 식품영양성분DB 값을 총내용량으로 환산)",
    has_size_choice=True,
)

# Ready-to-drink 대표식품명 under the two 대분류 that hold drinks. Left out on
# purpose: 원두/인스턴트커피, 고형차, 침출차, 농축음료/베이스 (not drunk as packed),
# cheese/butter/분유 and the spoonable 농후발효유.
DRINK_GROUPS: dict[str, frozenset[str]] = {
    "음료류": frozenset(
        {
            "액상음료",
            "과·채주스",
            "과·채음료",
            "액상차",
            "액상커피",
            "탄산음료",
            "탄산수",
            "인삼/홍삼음료",
            "두유",
            "발효음료",
            "유산균음료",
            "효모음료",
        }
    ),
    "유가공품류": frozenset(
        {
            "우유",
            "우유(멸균)",
            "가공우유",
            "가공우유(멸균)",
            "강화우유",
            "유당분해우유",
            "발효유",
        }
    ),
}

MIN_PACK = 100.0
MAX_PACK = 600.0
# Above this per 100, the 2026-10-01 survey found only syrups, 청 and tonics
# that are diluted or taken by the spoon, not drinks poured from the pack.
MAX_SUGAR_PER_100 = 25.0
_NOT_A_DRINK = re.compile(r"청$|진액|원액|베이스|농축|시럽|엑기스|발효액")
_AMOUNT = re.compile(r"^\s*([\d.,]+)\s*(ml|g)\s*$", re.IGNORECASE)

COLUMNS = {
    "code": "식품코드",
    "name": "식품명",
    "group": "식품대분류명",
    "kind": "대표식품명",
    "basis": "영양성분함량기준량",
    "sugar": "당류(g)",
    "pack": "식품중량",
    "maker": "제조사명",
    "created": "데이터생성일자",
}


@dataclass(frozen=True)
class KfindRow:
    """The K-FIND columns this brand reads, as text exactly as exported."""

    code: str
    name: str
    group: str
    kind: str
    basis: str
    sugar: str
    pack: str
    maker: str
    created: str


@dataclass(frozen=True)
class Amount:
    value: float
    unit: str


def parse_amount(text: str) -> Amount | None:
    """'500ml' / '240 g' -> Amount. None for anything else (blank, '1개', ranges)."""
    match = _AMOUNT.match(text)
    if match is None:
        return None
    return Amount(value=float(match.group(1).replace(",", "")), unit=match.group(2).lower())


def size_label(pack: Amount) -> str:
    number = f"{pack.value:g}"
    return f"{number}{pack.unit}"


def is_drink(row: KfindRow) -> bool:
    kinds = DRINK_GROUPS.get(row.group)
    return kinds is not None and row.kind in kinds and _NOT_A_DRINK.search(row.name) is None


def to_serving(row: KfindRow, *, source: str) -> RawServing | None:
    """One K-FIND row -> a whole-pack serving, or None when the row is out of scope."""
    if not is_drink(row):
        return None
    basis = parse_amount(row.basis)
    pack = parse_amount(row.pack)
    if basis is None or pack is None or basis.unit != pack.unit:
        return None
    if not MIN_PACK <= pack.value <= MAX_PACK:
        return None
    try:
        per_basis = float(row.sugar.replace(",", ""))
    except ValueError as exc:
        raise ParseError(f"당류 {row.sugar!r} is not a number ({row.code} {row.name})") from exc
    per_100 = per_basis * 100.0 / basis.value
    if per_100 > MAX_SUGAR_PER_100:
        return None
    name = clean_text(row.name)
    if not name:
        return None
    return RawServing(
        brand_id=BRAND.id,
        drink_name=name,
        category=row.kind,
        temperature=Temperature.BOTH,
        size_label=size_label(pack),
        volume_ml=round(pack.value) if pack.unit == "ml" else None,
        sugar_g=round(per_100 * pack.value / 100.0, 1),
        caffeine_mg=None,
        source_url=f"{source}#{row.code}",
    )


def parse_rows(rows: Iterable[KfindRow], *, source: str) -> list[RawServing]:
    """Keep in-scope rows; when a name and pack size repeat, the newest DB record wins."""
    newest: dict[tuple[str, str], tuple[str, str, RawServing]] = {}
    for row in rows:
        serving = to_serving(row, source=source)
        if serving is None:
            continue
        key = (slugify(serving.drink_name), slugify(serving.size_label))
        rank = (row.created[:10], row.code)
        current = newest.get(key)
        if current is None or rank > current[:2]:
            newest[key] = (*rank, serving)
    return [entry[2] for _, entry in sorted(newest.items())]


def read_rows(path: Path) -> list[KfindRow]:
    """Read the K-FIND 가공식품 xlsx. Raises `ParseError` if an expected column is missing."""
    workbook = CalamineWorkbook.from_path(path)
    sheet = workbook.get_sheet_by_index(0)
    rows = sheet.iter_rows()
    header = [str(cell) for cell in next(rows)]
    missing = [title for title in COLUMNS.values() if title not in header]
    if missing:
        raise ParseError(f"{path.name}: missing columns {missing}")
    index = {field: header.index(title) for field, title in COLUMNS.items()}
    return [
        KfindRow(**{field: str(cells[i]).strip() for field, i in index.items()}) for cells in rows
    ]


def scrape(path: Path) -> list[RawServing]:
    return parse_rows(read_rows(path), source=path.name)
