# 초코 프라페 v2(아메리카노 100% 사진을 고쳐 만든 단계 사진)를 아메리카노 잔 자리에 맞춘다.
# 생성 모델이 잔을 8~12% 키워서, align_100.best_fit(잔 아래쪽 65% IoU)으로 배율·이동을 찾아 되돌린다.
# 그다음 아메리카노 100%와 같은 "80" 변환으로 9x16·가로 이미지를 만든다. 0%(빈 잔)는 align_frappe_empty.py가 만든다.
import json
import os
import sys

import numpy as np
from PIL import Image, ImageFilter
from rembg import new_session

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import align_100 as a

CUPS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = {"30": "30_a.png", "50": "50_a.png", "80": "80_b.png", "100": "100_a.png"}
WING = 300
# 9x16에서 잰 입구 왼쪽 끝 높이(눈금 크롭으로 읽음). 아메리카노 80% = 485, 바닥 1445.
# 모델이 잔을 세로로도 조금 바꿔서, 바닥 기준으로 세로만 늘이거나 줄여 485에 맞춘다(align_100과 같은 방식).
RIM = {"30": 370, "50": 500, "80": 435, "100": 460}
REF_RIM, BOTTOM = 485, 1445


def stretch(im: Image.Image, k: float) -> Image.Image:
    tall = im.resize((im.width, round(im.height * k)), Image.Resampling.LANCZOS)
    top = round(BOTTOM * k - BOTTOM)
    pad = max(0, -top)
    arr = np.pad(np.asarray(tall), ((pad, im.height), (0, 0), (0, 0)), mode="edge")
    return Image.fromarray(arr).crop((0, top + pad, im.width, top + pad + im.height))


def crops(im: Image.Image, t: dict, step: str) -> None:
    side = round(2048 * t["scale"])
    big = im.resize((side, side), Image.Resampling.LANCZOS)
    k = (BOTTOM - REF_RIM) / (BOTTOM - RIM[step]) if step in RIM else 1.0
    narrow = stretch(big.crop((t["dx"], t["dy"], t["dx"] + 937, t["dy"] + 1666)), k)
    wide = stretch(
        big.crop((t["dx"] - WING, t["dy"], t["dx"] + 937 + WING, t["dy"] + 1666)), k
    )
    narrow.save(os.path.join(CUPS, "choco-frappe", "9x16", f"{step}.png"))
    wide.save(os.path.join(CUPS, "choco-frappe", "wide", f"{step}.jpg"), quality=88)


def main() -> None:
    for d in ("original", "9x16", "wide"):
        os.makedirs(os.path.join(CUPS, "choco-frappe", d), exist_ok=True)
    with open(os.path.join(CUPS, "transforms.json")) as f:
        transforms = json.load(f)
    session = new_session("u2net")
    ref = Image.open(
        os.path.join(CUPS, "iced-americano", "original", "80.png")
    ).convert("RGB")
    ref_mask = a.glass_mask(ref, session)
    for step, name in SRC.items():
        new = Image.open(os.path.join(CUPS, "choco-frappe", "v2", name)).convert("RGB")
        new = new.filter(ImageFilter.UnsharpMask(radius=2.2, percent=90, threshold=2))
        scale, dx, dy = a.best_fit(ref_mask, a.glass_mask(new, session))
        scaled = new.resize(
            (round(new.width * scale), round(new.height * scale)),
            Image.Resampling.LANCZOS,
        )
        arr = np.pad(np.asarray(scaled), ((dy, 2048), (dx, 2048), (0, 0)), mode="edge")
        canvas = Image.fromarray(arr).crop((0, 0, 2048, 2048))
        canvas.save(os.path.join(CUPS, "choco-frappe", "original", f"{step}.png"))
        crops(canvas, transforms["80"], step)
        print(step, scale, dx, dy)


if __name__ == "__main__":
    main()
