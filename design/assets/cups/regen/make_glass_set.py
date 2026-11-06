# 2026 특전 유리 공예 잔 세트(로슈 glass-soda, 카인 glass-beans, 2026-11-05).
# make_latte.py와 같은 자르기지만, 아메리카노 같은 단계가 아니라 빈 잔(0%)을 참조로 뽑은 편집본이라
# 전 단계를 아메리카노 0% 변환(transforms.json "0")으로 자르고 누끼 알파·유리선도 0% 것을 쓴다.
# 입구 위로 솟은 토핑(민트·오렌지)은 0% 알파 밖이라, 입구 위 채도 높은 픽셀을 알파에 더한다.
# 생성된 잔은 아메리카노 잔보다 조금 크거나 작아(2026-11-06 대표님 "컵사이즈가 다른애들이랑 여전히 다른데"),
# 자르기 전에 단계마다 바닥 가운데를 고정한 배율로 아메리카노 0% 누끼 윤곽에 맞춘다(FIT).
# 세로 = 입구 바깥 꼭대기를 아메리카노 누끼 꼭대기(y 430)로, 가로 = 옆선을 누끼 윤곽에 겹쳐 보며 정했다.
# 원두 100%는 원두가 옆선까지 차 옆선을 못 재서 30~80%와 같은 가로 배율을 쓴다.
# 사용: python make_glass_set.py <세트>   (원본 <세트>/candidates/<단계>_a.png)
from __future__ import annotations

import json
import os
import shutil
import sys

import cv2
import numpy as np
from numpy.typing import NDArray
from PIL import Image, ImageFilter

CUPS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(
    CUPS, "..", "..", "..", "SugarCap", "Resources", "Assets.xcassets"
)
BASE = "iced-americano"
WING = 300
# 9x16 사진에서 입구 앞 가장자리 아래로 이만큼까지는 토핑 알파를 더한다(그 아래는 잔 알파가 덮는다).
RIM_Y = 560
SAT_MIN = 70
# 9x16 좌표에서 고정점(잔 바닥 가운데)과 단계별 (가로, 세로) 배율.
FIT_X, FIT_Y = 468.0, 1429.0
FIT: dict[str, dict[int, tuple[float, float]]] = {
    "glass-soda": {
        30: (1.033, 0.9732),
        50: (1.04, 0.968),
        80: (1.04, 0.969),
        100: (0.987, 0.9638),
    },
    "glass-beans": {
        30: (0.98, 0.9906),
        50: (0.972, 0.9847),
        80: (0.974, 0.9842),
        100: (0.975, 0.993),
    },
}
CONTENTS = '{\n  "images" : [\n    {\n      "filename" : "%s",\n      "idiom" : "universal"\n    }\n  ],\n  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n'


def imageset(set_id: str, kind: str, step: int, name: str) -> str:
    folder = os.path.join(ASSETS, f"{kind}-{set_id}-{step}.imageset")
    os.makedirs(folder, exist_ok=True)
    with open(os.path.join(folder, "Contents.json"), "w", newline="\n") as f:
        f.write(CONTENTS % name)
    return os.path.join(folder, name)


def base_path(kind: str, step: int, name: str) -> str:
    return os.path.join(ASSETS, f"{kind}-{BASE}-{step}.imageset", name)


def topping_alpha(rgb: NDArray[np.uint8]) -> NDArray[np.uint8]:
    hsv = cv2.cvtColor(rgb, cv2.COLOR_RGB2HSV)
    mask = (hsv[:, :, 1] > SAT_MIN).astype(np.uint8) * 255
    mask[RIM_Y:] = 0
    mask = np.asarray(
        cv2.morphologyEx(mask, cv2.MORPH_CLOSE, np.ones((9, 9), np.uint8)),
        dtype=np.uint8,
    )
    mask = np.asarray(
        cv2.morphologyEx(mask, cv2.MORPH_OPEN, np.ones((5, 5), np.uint8)),
        dtype=np.uint8,
    )
    return np.asarray(cv2.GaussianBlur(mask, (0, 0), 1.5), dtype=np.uint8)


def fit(
    big: Image.Image, x: float, y: float, scale: tuple[float, float]
) -> Image.Image:
    """(x, y)를 고정하고 가로·세로 배율로 늘인다."""
    sx, sy = scale
    m = np.array([[sx, 0, x * (1 - sx)], [0, sy, y * (1 - sy)]], dtype=np.float32)
    rgb = np.asarray(big.convert("RGB"), dtype=np.uint8)
    out = cv2.warpAffine(
        rgb,
        m,
        (rgb.shape[1], rgb.shape[0]),
        flags=cv2.INTER_LANCZOS4,
        borderMode=cv2.BORDER_REPLICATE,
    )
    return Image.fromarray(np.asarray(out, dtype=np.uint8))


def main() -> None:
    set_id = sys.argv[1]
    with open(os.path.join(CUPS, "transforms.json")) as f:
        t = json.load(f)["0"]
    for d in ("original", "9x16", "wide"):
        os.makedirs(os.path.join(CUPS, set_id, d), exist_ok=True)
    for kind, name in (
        ("cup", "0.png"),
        ("cupwide", "0.jpg"),
        ("cutout", "0.png"),
        ("rimline", "0.png"),
    ):
        shutil.copyfile(base_path(kind, 0, name), imageset(set_id, kind, 0, name))
    base_alpha = np.asarray(
        Image.open(base_path("cutout", 0, "0.png")).convert("RGBA")
    )[:, :, 3]
    side = round(2048 * t["scale"])
    for step in (30, 50, 80, 100):
        src = Image.open(
            os.path.join(CUPS, set_id, "candidates", f"{step}_a.png")
        ).convert("RGB")
        src = src.filter(ImageFilter.UnsharpMask(radius=2.2, percent=90, threshold=2))
        src.save(os.path.join(CUPS, set_id, "original", f"{step}.png"))
        big = fit(
            src.resize((side, side), Image.Resampling.LANCZOS),
            t["dx"] + FIT_X,
            t["dy"] + FIT_Y,
            FIT[set_id][step],
        )
        narrow = big.crop((t["dx"], t["dy"], t["dx"] + 937, t["dy"] + 1666))
        wide = big.crop((t["dx"] - WING, t["dy"], t["dx"] + 937 + WING, t["dy"] + 1666))
        narrow.save(os.path.join(CUPS, set_id, "9x16", f"{step}.png"))
        wide.save(os.path.join(CUPS, set_id, "wide", f"{step}.jpg"), quality=88)
        narrow.save(imageset(set_id, "cup", step, f"{step}.png"), optimize=True)
        wide.save(imageset(set_id, "cupwide", step, f"{step}.jpg"), quality=88)
        rgb = np.asarray(narrow, dtype=np.uint8)
        alpha = np.maximum(base_alpha, topping_alpha(rgb))
        cut = Image.fromarray(np.dstack([rgb, alpha]))
        cut.save(imageset(set_id, "cutout", step, f"{step}.png"), optimize=True)
        cut.save(
            os.path.join(CUPS, "cutouts", f"cutout-{set_id}-{step}.png"), optimize=True
        )
        shutil.copyfile(
            base_path("rimline", 0, "0.png"),
            imageset(set_id, "rimline", step, f"{step}.png"),
        )
        print(step, narrow.size, wide.size)


if __name__ == "__main__":
    main()
