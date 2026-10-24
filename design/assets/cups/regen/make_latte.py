# 카페라떼(카인 거래 상품, 2026-10-24). 아메리카노 단계 사진을 참조로 음료만 바꾼 편집본이라
# 잔이 아메리카노 원본과 같은 자리다(ECC 정합 배율 1.005, 어긋남 수 px). 그래서 정렬 없이
# 아메리카노와 같은 변환(transforms.json, 100%는 "80")으로 9x16·가로를 자르고,
# 누끼 알파·유리선은 같은 단계 아메리카노 것을 그대로 쓴다. 0%는 같은 잔이라 아메리카노 빈 잔을 복사한다.
import json
import os
import shutil

import numpy as np
from PIL import Image, ImageFilter

CUPS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(
    CUPS, "..", "..", "..", "SugarCap", "Resources", "Assets.xcassets"
)
SET = "cafe-latte"
BASE = "iced-americano"
WING = 300
CONTENTS = '{\n  "images" : [\n    {\n      "filename" : "%s",\n      "idiom" : "universal"\n    }\n  ],\n  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n'


def imageset(kind: str, step: int, name: str) -> str:
    folder = os.path.join(ASSETS, f"{kind}-{SET}-{step}.imageset")
    os.makedirs(folder, exist_ok=True)
    with open(os.path.join(folder, "Contents.json"), "w", newline="\n") as f:
        f.write(CONTENTS % name)
    return os.path.join(folder, name)


def copy_base(kind: str, step: int, name: str) -> None:
    src = os.path.join(ASSETS, f"{kind}-{BASE}-{step}.imageset", name)
    shutil.copyfile(src, imageset(kind, step, name))


def main() -> None:
    with open(os.path.join(CUPS, "transforms.json")) as f:
        transforms = json.load(f)
    for d in ("original", "9x16", "wide"):
        os.makedirs(os.path.join(CUPS, SET, d), exist_ok=True)
    for kind, name in (("cup", "0.png"), ("cupwide", "0.jpg"), ("cutout", "0.png"), ("rimline", "0.png")):
        copy_base(kind, 0, name)
    for step in (30, 50, 80, 100):
        src = Image.open(os.path.join(CUPS, SET, "candidates", f"{step}_a.png")).convert("RGB")
        src = src.filter(ImageFilter.UnsharpMask(radius=2.2, percent=90, threshold=2))
        src.save(os.path.join(CUPS, SET, "original", f"{step}.png"))
        t = transforms["80" if step == 100 else str(step)]
        side = round(2048 * t["scale"])
        big = src.resize((side, side), Image.Resampling.LANCZOS)
        narrow = big.crop((t["dx"], t["dy"], t["dx"] + 937, t["dy"] + 1666))
        wide = big.crop((t["dx"] - WING, t["dy"], t["dx"] + 937 + WING, t["dy"] + 1666))
        narrow.save(os.path.join(CUPS, SET, "9x16", f"{step}.png"))
        wide.save(os.path.join(CUPS, SET, "wide", f"{step}.jpg"), quality=88)
        narrow.save(imageset("cup", step, f"{step}.png"), optimize=True)
        wide.save(imageset("cupwide", step, f"{step}.jpg"), quality=88)
        base_cut = Image.open(
            os.path.join(ASSETS, f"cutout-{BASE}-{step}.imageset", f"{step}.png")
        ).convert("RGBA")
        alpha = np.asarray(base_cut)[:, :, 3]
        cut = np.dstack([np.asarray(narrow), alpha])
        Image.fromarray(cut).save(imageset("cutout", step, f"{step}.png"), optimize=True)
        cut_path = os.path.join(CUPS, "cutouts", f"cutout-{SET}-{step}.png")
        Image.fromarray(cut).save(cut_path, optimize=True)
        copy_base("rimline", step, f"{step}.png")
        print(step, narrow.size, wide.size)


if __name__ == "__main__":
    main()
