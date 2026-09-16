"""Hollys: server-rendered category pages, one nutrition table per drink with HOT / ICED rows."""

from __future__ import annotations

import logging
import re
from typing import NamedTuple

import httpx
from bs4 import BeautifulSoup, Tag

from sugarcap_scrape.http import fetch_text
from sugarcap_scrape.models import Brand, RawServing, Temperature
from sugarcap_scrape.parse import ParseError, clean_text, optional_number

log = logging.getLogger(__name__)

BRAND = Brand(
    id="hollys",
    name="할리스",
    serving_note="Regular 354ml 기준 (일부 음료는 Grande 472ml)",
    has_size_choice=False,
)

CATEGORY_URL = "https://www.hollys.co.kr/menu/{key}.do"
CATEGORY_KEYS = ("espresso", "signature", "hollyccino", "tea", "juice")
ERROR_MARKER = "메뉴 정보가 정확하지 않습니다"
NON_DRINK_MARKER = "빙수"

_SIZED_ML = re.compile(r"(Regular|Grande|Venti|Solo)\s*/\s*(\d+)\s*ml\s*기준")
_SIZED_ONLY = re.compile(r"(Regular|Grande|Venti|Solo)\s*기준")
_SIZED_GRAMS = re.compile(r"HOT\s*-\s*R\)|ICED\s*-\s*R\)")
_ML_ONLY = re.compile(r"/\s*(\d+)\s*ml\s*기준")
_INFO_ID = re.compile(r"menuView2_(\d+)")


class ServingBase(NamedTuple):
    size_label: str
    volume_ml: int | None


def parse_serving_note(note: str) -> ServingBase:
    """Read the base size from "제품영양정보 (1회 제공량 / Regular / 354ml 기준 ...)"."""
    sized_ml = _SIZED_ML.search(note)
    if sized_ml is not None:
        return ServingBase(sized_ml.group(1), int(sized_ml.group(2)))
    sized_only = _SIZED_ONLY.search(note)
    if sized_only is not None:
        return ServingBase(sized_only.group(1), None)
    if _SIZED_GRAMS.search(note) is not None:
        return ServingBase("Regular", None)
    ml_only = _ML_ONLY.search(note)
    if ml_only is not None:
        return ServingBase(f"{ml_only.group(1)}ml", int(ml_only.group(1)))
    raise ParseError(f"serving note not understood: {note!r}")


def _temperature(label: str, context: str) -> Temperature:
    if label == "HOT":
        return Temperature.HOT
    if label == "ICED":
        return Temperature.ICED
    raise ParseError(f"unknown temperature row {label!r} ({context})")


def _column_index(headers: list[str], name: str, context: str) -> int:
    if name not in headers:
        raise ParseError(f"column {name!r} missing in {headers} ({context})")
    return headers.index(name)


def _select_one(root: Tag, selector: str, context: str) -> Tag:
    found = root.select_one(selector)
    if found is None:
        raise ParseError(f"{selector!r} not found ({context})")
    return found


def _english_name(soup: BeautifulSoup, info: Tag) -> str | None:
    info_id = info.get("id")
    id_match = _INFO_ID.search(info_id) if isinstance(info_id, str) else None
    if id_match is None:
        return None
    paragraph = soup.select_one(f"#menuView1_{id_match.group(1)} div.menu_detail > p")
    if paragraph is None or paragraph.span is None:
        return None
    tail = "".join(str(node) for node in paragraph.span.next_siblings if isinstance(node, str))
    return clean_text(tail) or None


def parse_category_page(html: str, source_url: str) -> list[RawServing]:
    """Parse one category page. Raises on the site's "wrong menu" redirect page."""
    if ERROR_MARKER in html:
        raise ParseError(f"{source_url} returned the error page ({ERROR_MARKER})")
    soup = BeautifulSoup(html, "html.parser")
    category = clean_text(_select_one(soup, "h2.h2menu", source_url).get_text())

    rows: list[RawServing] = []
    for info in soup.select("div.menu_info02"):
        name = clean_text(_select_one(info, "caption", source_url).get_text())
        context = f"{name} @ {source_url}"
        if NON_DRINK_MARKER in name:
            continue
        note = clean_text(_select_one(info, "span.ft16B", context).get_text())
        base = parse_serving_note(note)
        headers = [clean_text(th.get_text()) for th in info.select("thead th")]
        sugar_col = _column_index(headers, "당류", context)
        caffeine_col = _column_index(headers, "카페인", context)
        name_en = _english_name(soup, info)

        body_rows = info.select("tbody tr")
        if not body_rows:
            log.warning("hollys: no nutrition rows for %s", context)
        for tr in body_rows:
            cells = [clean_text(cell.get_text()) for cell in tr.find_all(["th", "td"])]
            if len(cells) != len(headers):
                raise ParseError(f"row {cells} does not match headers {headers} ({context})")
            rows.append(
                RawServing(
                    brand_id=BRAND.id,
                    drink_name=name,
                    drink_name_en=name_en,
                    category=category,
                    temperature=_temperature(cells[0], context),
                    size_label=base.size_label,
                    volume_ml=base.volume_ml,
                    sugar_g=optional_number(cells[sugar_col]),
                    caffeine_mg=optional_number(cells[caffeine_col]),
                    source_url=source_url,
                )
            )
    return rows


def scrape(client: httpx.Client) -> list[RawServing]:
    rows: list[RawServing] = []
    for key in CATEGORY_KEYS:
        url = CATEGORY_URL.format(key=key)
        rows.extend(parse_category_page(fetch_text(client, url), url))
    return rows
