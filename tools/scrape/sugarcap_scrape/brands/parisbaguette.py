"""파리바게뜨 scraper (커피/음료 only; 빙수 is not a drink).

The product list is filled by `admin-ajax.php?action=pb_get_product_list&cat1=커피-음료
&cat2=<slug>` (GET; robots.txt allows it): an HTML fragment of `a.product-list-item`
links with `h3.product-name`. Each `/product/<slug>/` page has `.product-nutrition`
("총 내용량: 280g · … 당류(g): 0 · …") and free-text `.product-allergy` /
`.product-features` boxes where caffeine is written for some drinks.

Values as published, with these readings:
- sugar is per 총 내용량 or 1회 제공량 (one cup). "100g당" values are not a cup and stay
  null (no conversion outside `cvs`). "제품 뒷면참조" and empty boxes are unpublished.
- caffeine appears in up to three boxes and they disagree (아메리카노 224 / 212.52); the
  largest published number is kept, so a daily cap is never under-counted.
- volume is kept only when printed in ml; grams stay null.
"""

from __future__ import annotations

import re

import httpx
from bs4 import BeautifulSoup, Tag

from sugarcap_scrape.http import fetch_text
from sugarcap_scrape.models import Brand, RawServing, Temperature
from sugarcap_scrape.parse import ParseError, clean_text

BRAND = Brand(
    id="parisbaguette",
    name="파리바게뜨",
    serving_note="1잔(총 내용량) 기준. 파리바게뜨 공식 영양정보 게시값",
    has_size_choice=False,
)

LIST_URL = "https://www.paris.co.kr/wp-admin/admin-ajax.php"
DRINK_SECTION = "커피-음료"
# (cat2 slug, name as on the site). 빙수 is shaved ice, not scraped.
CATEGORIES = (
    ("카페-아다지오", "카페 아다지오"),
    ("라떼류", "라떼류"),
    ("에이드-tea", "에이드/TEA"),
    ("블렌디드", "블렌디드"),
    ("완제음료", "완제음료"),
)
SIZE_LABEL = "기본"
PER_100G = "100g당"

_SUGAR = re.compile(r"당류\(g\)\s*:\s*[|/\s]*(\d+(?:\.\d+)?)")
_CAFFEINE = re.compile(r"카페인\s*(?:함량)?\s*(?:\(mg(?:/1컵)?\))?\s*:?\s*(\d+(?:\.\d+)?)")
_VOLUME_ML = re.compile(r"총 내용량\s*:\s*(\d+)\s*(?:ml|㎖)", re.IGNORECASE)


def classify_temperature(name: str) -> Temperature:
    if name.startswith("아이스") or "아이스" in name.split():
        return Temperature.ICED
    if "핫" in name.split():
        return Temperature.HOT
    return Temperature.BOTH


def parse_sugar(nutrition: str) -> float | None:
    if PER_100G in nutrition:
        return None
    match = _SUGAR.search(nutrition)
    return float(match.group(1)) if match else None


def parse_caffeine(texts: list[str]) -> float | None:
    values = [float(v) for text in texts for v in _CAFFEINE.findall(text)]
    return max(values) if values else None


def parse_volume_ml(nutrition: str) -> int | None:
    match = _VOLUME_ML.search(nutrition)
    return int(match.group(1)) if match else None


def parse_list(html: str) -> list[tuple[str, str]]:
    """(product URL, name) pairs from the AJAX list fragment."""
    soup = BeautifulSoup(html, "html.parser")
    items: list[tuple[str, str]] = []
    for link in soup.select("a.product-list-item"):
        name_node = link.select_one(".product-name")
        href = str(link.get("href", ""))
        if name_node is None or not href:
            raise ParseError("list item without href or .product-name")
        items.append((href, clean_text(name_node.get_text())))
    return items


def _box(soup: BeautifulSoup, cls: str) -> str:
    node = soup.select_one(f".product-info-group.{cls} .product-info-group-description")
    return clean_text(node.get_text(" ")) if isinstance(node, Tag) else ""


def parse_product_page(html: str, *, name: str, category: str, source_url: str) -> RawServing:
    """One cup. Some products (milk cartons, 리얼 딸기라떼) have no nutrition box: kept, null."""
    soup = BeautifulSoup(html, "html.parser")
    nutrition = _box(soup, "product-nutrition")
    boxes = [nutrition, _box(soup, "product-allergy"), _box(soup, "product-features")]
    return RawServing(
        brand_id=BRAND.id,
        drink_name=name,
        category=category,
        temperature=classify_temperature(name),
        size_label=SIZE_LABEL,
        volume_ml=parse_volume_ml(nutrition),
        sugar_g=parse_sugar(nutrition),
        caffeine_mg=parse_caffeine(boxes),
        source_url=source_url,
    )


def scrape(client: httpx.Client) -> list[RawServing]:
    rows: list[RawServing] = []
    for slug, category in CATEGORIES:
        params = {
            "action": "pb_get_product_list",
            "cat1": DRINK_SECTION,
            "cat2": slug,
            "per_page": "200",
            "paged": "1",
        }
        items = parse_list(fetch_text(client, LIST_URL, params=params))
        if not items:
            raise ParseError(f"{category}: no products from {LIST_URL} {params}")
        for url, name in items:
            rows.append(
                parse_product_page(
                    fetch_text(client, url), name=name, category=category, source_url=url
                )
            )
    return rows
