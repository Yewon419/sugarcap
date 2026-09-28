# 웹사이트(site/)의 캐릭터·방울 이미지와 글꼴 서브셋 만들기.
# 글꼴은 site/의 HTML에 실제로 쓰인 글자만 남긴다. 문구를 바꾸면 이 스크립트를 다시 돌린다.
# 사용: python tools/site/build_art.py   (시스템 python: Pillow·fontTools 필요)
from __future__ import annotations

import os
import re
import subprocess
import sys

from PIL import Image

REPO = os.path.abspath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
)
SITE = os.path.join(REPO, "site")
SHARED = os.path.join(REPO, "SugarCap", "Resources", "Shared.xcassets")
FONTS = os.path.join(REPO, "SugarCap", "Resources", "Fonts")
ART = [
    (os.path.join(SHARED, "character-roshu.imageset", "roshu.png"), "roshu.webp", 560),
    (os.path.join(SHARED, "character-kain.imageset", "kain.png"), "kain.webp", 408),
    (
        os.path.join(REPO, "design", "assets", "drops", "sugar.png"),
        "drop-sugar.webp",
        96,
    ),
    (
        os.path.join(REPO, "design", "assets", "drops", "caffeine.png"),
        "drop-caffeine.webp",
        96,
    ),
]
PRETENDARD = [
    (500, "Pretendard-Medium.otf"),
    (700, "Pretendard-Bold.otf"),
    (800, "Pretendard-ExtraBold.otf"),
]
# 숫자 전용 글꼴(히어로 수치). 스크립트가 바꿔 넣는 숫자·단위까지 포함한다.
NUMERALS = "0123456789gm/ "


def write_art() -> None:
    out_dir = os.path.join(SITE, "assets", "art")
    os.makedirs(out_dir, exist_ok=True)
    for src, name, width in ART:
        img = Image.open(src).convert("RGBA")
        height = round(img.height * width / img.width)
        img.resize((width, height), Image.Resampling.LANCZOS).save(
            os.path.join(out_dir, name), quality=86, method=6
        )


def page_text() -> str:
    chars: set[str] = set(NUMERALS)
    for root, _, files in os.walk(SITE):
        for name in files:
            if name.endswith(".html"):
                with open(os.path.join(root, name), encoding="utf-8") as fh:
                    html = fh.read()
                # 스크립트 안 문자열(동적으로 넣는 문구)도 화면에 나오므로 태그만 지운다.
                chars.update(re.sub(r"<[^>]+>", "", html))
    return "".join(sorted(c for c in chars if c.isprintable()))


def subset(src: str, out: str, text: str) -> None:
    cmd = [
        sys.executable, "-m", "fontTools.subset", src,
        f"--text={text}", "--flavor=woff", "--layout-features=*",
        f"--output-file={out}",
    ]  # fmt: skip
    subprocess.run(cmd, check=True)


def write_fonts() -> None:
    out_dir = os.path.join(SITE, "assets", "fonts")
    os.makedirs(out_dir, exist_ok=True)
    text = page_text()
    for weight, name in PRETENDARD:
        subset(
            os.path.join(FONTS, name),
            os.path.join(out_dir, f"pretendard-{weight}.woff"),
            text,
        )
    subset(
        os.path.join(FONTS, "ArchivoBlack-Regular.ttf"),
        os.path.join(out_dir, "archivo-black.woff"),
        NUMERALS,
    )
    print("glyphs", len(text))


def main() -> None:
    write_art()
    write_fonts()


if __name__ == "__main__":
    main()
