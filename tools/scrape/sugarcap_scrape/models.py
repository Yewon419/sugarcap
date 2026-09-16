"""Data models shared by every brand scraper and the catalog builder.

Raw layer (`RawServing`) is what a brand scraper emits: one row per
(drink, temperature, size) exactly as the brand publishes it. No unit
conversion, no size estimation. The builder turns raw rows into the
catalog layer (`Brand` / `Drink` / `Serving`) consumed by the app.
"""

from __future__ import annotations

from enum import StrEnum

from pydantic import BaseModel, ConfigDict, Field


class Temperature(StrEnum):
    HOT = "hot"
    ICED = "iced"
    BOTH = "both"


class CaffeineVariant(BaseModel):
    """Caffeine that depends on a bean/option choice (e.g. TheVenti signature vs dark)."""

    model_config = ConfigDict(frozen=True)

    label: str
    caffeine_mg: float = Field(ge=0)


class RawServing(BaseModel):
    """One published nutrition row from a brand site.

    `sugar_g is None` / `caffeine_mg is None` mean the brand did not publish
    that value for this row; both are carried through to the catalog so the app
    can say "미공개" instead of hiding the drink. When `caffeine_variants` is
    non-empty, `caffeine_mg` is the first variant's value.
    """

    model_config = ConfigDict(frozen=True)

    brand_id: str
    drink_name: str
    drink_name_en: str | None = None
    category: str
    temperature: Temperature
    size_label: str
    volume_ml: int | None = Field(default=None, ge=0)
    sugar_g: float | None = Field(default=None, ge=0)
    caffeine_mg: float | None = Field(default=None, ge=0)
    caffeine_variants: tuple[CaffeineVariant, ...] = ()
    source_url: str


class Brand(BaseModel):
    model_config = ConfigDict(frozen=True)

    id: str
    name: str
    serving_note: str
    has_size_choice: bool


class Serving(BaseModel):
    """One published cup. A `None` value is a value the brand does not publish."""

    model_config = ConfigDict(frozen=True)

    id: str
    size_label: str
    volume_ml: int | None
    sugar_g: float | None
    caffeine_mg: float | None
    caffeine_variants: tuple[CaffeineVariant, ...] = ()


class Drink(BaseModel):
    model_config = ConfigDict(frozen=True)

    id: str
    brand_id: str
    name: str
    name_en: str | None
    category: str
    temperature: Temperature
    servings: tuple[Serving, ...]


class Catalog(BaseModel):
    model_config = ConfigDict(frozen=True)

    schema_version: int
    built_at: str
    brands: tuple[Brand, ...]
    drinks: tuple[Drink, ...]
