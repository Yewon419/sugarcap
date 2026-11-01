from __future__ import annotations

import httpx
import pytest

from sugarcap_scrape.brands.compose import BRAND, SIZE_LABEL, label_sizes, scrape
from sugarcap_scrape.models import RawServing, Temperature
from sugarcap_scrape.parse import ParseError


def _row(name: str, temperature: Temperature, volume: int, srl: str) -> RawServing:
    return RawServing(
        brand_id=BRAND.id,
        drink_name=name,
        category="추천메뉴",
        temperature=temperature,
        size_label=SIZE_LABEL,
        volume_ml=volume,
        source_url=f"https://composecoffee.com/?item_srl={srl}",
    )


def test_only_drinks_with_several_pages_are_labelled_by_volume() -> None:
    rows = [
        _row("딥라떼", Temperature.ICED, 414, "1"),
        _row("딥라떼", Temperature.ICED, 591, "2"),
        _row("딥라떼", Temperature.HOT, 414, "3"),
        _row("아메리카노", Temperature.ICED, 591, "4"),
    ]
    assert [r.size_label for r in label_sizes(rows)] == ["414ml", "591ml", "기본", "기본"]


def test_same_volume_twice_is_an_error() -> None:
    rows = [_row("딥라떼", Temperature.ICED, 414, "1"), _row("딥라떼", Temperature.ICED, 414, "2")]
    with pytest.raises(ParseError, match="same"):
        label_sizes(rows)


@pytest.mark.live
def test_scrape_live(client: httpx.Client) -> None:
    rows = scrape(client)
    assert len(rows) >= 100
    keys = [(r.drink_name, r.temperature, r.size_label) for r in rows]
    assert len(keys) == len(set(keys))
