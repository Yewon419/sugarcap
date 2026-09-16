"""Catalog id recipe. One place, because ids are what saved entries point at.

Changing any function here renames every id and breaks every `Entry.servingId`
already stored on a phone. SPEC needs a migration section before that happens.
"""

from __future__ import annotations

import re
import unicodedata

from sugarcap_scrape.models import RawServing


def slugify(text: str) -> str:
    """Stable ASCII-safe slug. Korean is kept as NFC so ids stay readable and deterministic."""
    normalized = unicodedata.normalize("NFC", text).strip().lower()
    normalized = re.sub(r"[\s/()\[\],.·]+", "-", normalized)
    return re.sub(r"-{2,}", "-", normalized).strip("-")


def drink_id(brand_id: str, drink_name: str, temperature: str) -> str:
    return f"{brand_id}:{slugify(drink_name)}:{temperature}"


def serving_id_parts(drink_id_value: str, size_label: str) -> str:
    return f"{drink_id_value}:{slugify(size_label)}"


def serving_id(row: RawServing) -> str:
    return serving_id_parts(
        drink_id(row.brand_id, row.drink_name, row.temperature.value), row.size_label
    )
