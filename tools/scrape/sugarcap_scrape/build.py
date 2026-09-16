"""Build `catalog.json` from every registered brand scraper.

Usage:
    python -m sugarcap_scrape.build --out ../../data/catalog.json [--only starbucks,mega]
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
from collections import defaultdict
from datetime import UTC, datetime
from pathlib import Path

from sugarcap_scrape.brands import registry
from sugarcap_scrape.http import make_client
from sugarcap_scrape.ids import drink_id, serving_id, slugify
from sugarcap_scrape.models import Brand, Catalog, Drink, RawServing, Serving
from sugarcap_scrape.validate import validate

SCHEMA_VERSION = 1
log = logging.getLogger(__name__)


def drink_key(row: RawServing) -> tuple[str, str, str]:
    return (row.brand_id, slugify(row.drink_name), row.temperature.value)


def group_rows(rows: list[RawServing]) -> list[Drink]:
    """Group raw rows into drinks with one serving per published size."""
    grouped: dict[tuple[str, str, str], list[RawServing]] = defaultdict(list)
    for row in rows:
        grouped[drink_key(row)].append(row)

    drinks: list[Drink] = []
    for (brand_id, _drink_slug, temperature), group in sorted(grouped.items()):
        head = group[0]
        seen: set[str] = set()
        servings: list[Serving] = []
        for row in group:
            sid = serving_id(row)
            if sid in seen:
                raise ValueError(f"duplicate serving id {sid} from {row.source_url}")
            seen.add(sid)
            servings.append(
                Serving(
                    id=sid,
                    size_label=row.size_label,
                    volume_ml=row.volume_ml,
                    sugar_g=row.sugar_g,
                    caffeine_mg=row.caffeine_mg,
                    caffeine_variants=row.caffeine_variants,
                )
            )
        drinks.append(
            Drink(
                id=drink_id(brand_id, head.drink_name, temperature),
                brand_id=brand_id,
                name=head.drink_name,
                name_en=head.drink_name_en,
                category=head.category,
                temperature=head.temperature,
                servings=tuple(servings),
            )
        )
    return drinks


def summarize(brand: Brand, rows: list[RawServing]) -> str:
    sugar_missing = sum(1 for row in rows if row.sugar_g is None)
    caffeine_missing = sum(1 for row in rows if row.caffeine_mg is None)
    return (
        f"{brand.id:10s} rows={len(rows):4d} sugar_missing={sugar_missing:4d} "
        f"caffeine_missing={caffeine_missing:4d}"
    )


def build(only: set[str] | None) -> Catalog:
    brands: list[Brand] = []
    all_rows: list[RawServing] = []
    with make_client() as client:
        for brand_id, (brand, scrape) in registry().items():
            if only is not None and brand_id not in only:
                continue
            log.info("scraping %s", brand_id)
            rows = scrape(client)
            if not rows:
                raise RuntimeError(f"{brand_id}: scraper returned zero rows")
            for row in rows:
                if row.caffeine_mg is None:
                    log.info("%s: no caffeine published for %s", brand_id, row.drink_name)
            print(summarize(brand, rows), file=sys.stderr)
            brands.append(brand)
            all_rows.extend(rows)
    return Catalog(
        schema_version=SCHEMA_VERSION,
        built_at=datetime.now(UTC).isoformat(timespec="seconds"),
        brands=tuple(brands),
        drinks=tuple(group_rows(all_rows)),
    )


def write_catalog(catalog: Catalog, out: Path) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    payload = catalog.model_dump(mode="json")
    out.write_text(json.dumps(payload, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--only", type=str, default=None, help="comma-separated brand ids")
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args(argv)
    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.INFO)
    only = set(args.only.split(",")) if args.only else None
    catalog = build(only)
    problems = validate(catalog) if only is None else []
    if problems:
        for problem in problems:
            print(f"INVALID {problem}", file=sys.stderr)
        print(f"{len(problems)} problems, {args.out} not written", file=sys.stderr)
        return 1
    write_catalog(catalog, args.out)
    print(
        f"wrote {args.out} drinks={len(catalog.drinks)} brands={len(catalog.brands)}",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
