"""CI 스크린샷 PNG 폴더를 단일 HTML 갤러리로 묶는다.

찰칵(`Yewon419/chalkak`)의 `inline_gallery.py`는 찰칵 액션이 만든 index.html을 전제로 한다.
슈가캡 CI는 PNG만 올리므로 여기서 직접 만든다. 이미지는 폭 460px JPEG로 줄여 data URI로 박는다
(Claude Artifact가 단일 파일 16MB 한도라 원본 1320×2868 PNG 5장이면 넘는다).

    python tools/gallery/build_gallery.py <png-dir> [<png-dir> ...] --out gallery.html --title "..."
"""

from __future__ import annotations

import argparse
import base64
import io
from dataclasses import dataclass
from pathlib import Path

from PIL import Image

THUMB_WIDTH = 460
JPEG_QUALITY = 82


@dataclass(frozen=True)
class Shot:
    name: str
    group: str
    data_uri: str
    width: int
    height: int


def encode(path: Path, group: str) -> Shot:
    image = Image.open(path).convert("RGB")
    width, height = image.size
    if width > THUMB_WIDTH:
        image = image.resize((THUMB_WIDTH, round(height * THUMB_WIDTH / width)), Image.LANCZOS)
    buffer = io.BytesIO()
    image.save(buffer, format="JPEG", quality=JPEG_QUALITY, optimize=True)
    encoded = base64.b64encode(buffer.getvalue()).decode("ascii")
    return Shot(
        name=path.stem,
        group=group,
        data_uri=f"data:image/jpeg;base64,{encoded}",
        width=width,
        height=height,
    )


def render(shots: list[Shot], title: str, subtitle: str) -> str:
    cards = []
    for shot in shots:
        cards.append(
            f"""      <figure>
        <img src="{shot.data_uri}" alt="{shot.name}" loading="lazy">
        <figcaption><b>{shot.name}</b><span>{shot.width}×{shot.height}</span></figcaption>
      </figure>"""
        )
    groups: dict[str, list[str]] = {}
    for shot, card in zip(shots, cards):
        groups.setdefault(shot.group, []).append(card)

    sections = []
    for group, items in groups.items():
        sections.append(
            f"""    <section>
      <h2>{group}</h2>
      <div class="grid">
{chr(10).join(items)}
      </div>
    </section>"""
        )

    return f"""<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<style>
  :root {{ color-scheme: light; --ink:#16161a; --muted:#6b6b72; --line:#e6e6ea; --accent:#5b84aa; }}
  * {{ box-sizing: border-box; }}
  body {{ margin:0; padding:28px 16px 64px; background:#fafafb; color:var(--ink);
         font:15px/1.6 -apple-system, BlinkMacSystemFont, "Apple SD Gothic Neo", "Pretendard", sans-serif; }}
  header {{ max-width:1200px; margin:0 auto 24px; }}
  h1 {{ font-size:1.5rem; margin:0 0 4px; }}
  .meta {{ color:var(--muted); font-size:.9rem; }}
  section {{ max-width:1200px; margin:0 auto 40px; }}
  h2 {{ font-size:1rem; margin:0 0 12px; padding-bottom:8px; border-bottom:1px solid var(--line); color:var(--muted); }}
  .grid {{ display:grid; gap:20px; grid-template-columns:repeat(auto-fill, minmax(230px, 1fr)); }}
  figure {{ margin:0; background:#fff; border:1px solid var(--line); border-radius:14px; overflow:hidden; }}
  img {{ display:block; width:100%; height:auto; }}
  figcaption {{ display:flex; justify-content:space-between; gap:8px; padding:10px 12px;
                font-size:.8rem; border-top:1px solid var(--line); }}
  figcaption span {{ color:var(--muted); }}
  @media (prefers-color-scheme: dark) {{
    :root:not([data-theme="light"]) {{ --ink:#f2f2f5; --muted:#9a9aa3; --line:#2c2c31; }}
    :root:not([data-theme="light"]) body {{ background:#121215; }}
    :root:not([data-theme="light"]) figure {{ background:#1b1b20; }}
  }}
</style>
</head>
<body>
<header>
  <h1>{title}</h1>
  <p class="meta">{subtitle}</p>
</header>
{chr(10).join(sections)}
</body>
</html>
"""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("dirs", nargs="+", type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--title", default="슈가캡 화면")
    parser.add_argument("--subtitle", default="")
    args = parser.parse_args()

    shots: list[Shot] = []
    for directory in args.dirs:
        group = directory.name
        for png in sorted(directory.glob("*.png")):
            shots.append(encode(png, group))

    if not shots:
        raise SystemExit("PNG를 찾지 못했습니다.")

    args.out.write_text(render(shots, args.title, args.subtitle), encoding="utf-8")
    size_mb = args.out.stat().st_size / 1024 / 1024
    print(f"{args.out} ({len(shots)}컷, {size_mb:.1f} MB)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
