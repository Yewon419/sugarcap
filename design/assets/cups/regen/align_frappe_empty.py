# 초코 프라페 0%(빈 잔). 아메리카노 빈 잔은 프라페 잔보다 9% 길고 덜 좁아져서 쓸 수 없다(대표님 2026-10-24 "빈컵 왜이리 큰거야").
# v2/30_a.png를 레퍼런스로 내용물만 비운 편집본(v2/0_a.png)이 30%와 같은 자리라, 30%의 정렬 값을 그대로 쓴다.
import json
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import align_frappe_v2 as v2

CUPS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCALE, DX, DY = 0.915, 88, 12  # align_frappe_v2가 30%에서 찾은 값


def main() -> None:
    new = Image.open(os.path.join(CUPS, "choco-frappe", "v2", "0_a.png")).convert("RGB")
    new = new.filter(ImageFilter.UnsharpMask(radius=2.2, percent=90, threshold=2))
    scaled = new.resize(
        (round(new.width * SCALE), round(new.height * SCALE)), Image.Resampling.LANCZOS
    )
    arr = np.pad(np.asarray(scaled), ((DY, 2048), (DX, 2048), (0, 0)), mode="edge")
    canvas = Image.fromarray(arr).crop((0, 0, 2048, 2048))
    canvas.save(os.path.join(CUPS, "choco-frappe", "original", "0.png"))
    with open(os.path.join(CUPS, "transforms.json")) as f:
        t = json.load(f)["80"]
    side = round(2048 * t["scale"])
    big = canvas.resize((side, side), Image.Resampling.LANCZOS)
    k = (v2.BOTTOM - v2.REF_RIM) / (v2.BOTTOM - v2.RIM["30"])
    narrow = v2.stretch(big.crop((t["dx"], t["dy"], t["dx"] + 937, t["dy"] + 1666)), k)
    wide = v2.stretch(
        big.crop((t["dx"] - v2.WING, t["dy"], t["dx"] + 937 + v2.WING, t["dy"] + 1666)),
        k,
    )
    narrow.save(os.path.join(CUPS, "choco-frappe", "9x16", "0.png"))
    wide.save(os.path.join(CUPS, "choco-frappe", "wide", "0.jpg"), quality=88)
    print("saved 0")


if __name__ == "__main__":
    main()
