# 초코 프라페 v3(2026-10-31, 대표님 "아예 갈아엎자, 크림은 지금처럼 높게", 덜 찬 단계 합성본은 "너무 이상함"으로 다시).
# 잔은 아메리카노 잔 그대로 쓰고 음료만 Seedream 생성본(candidates/gen_<단계>.png)에서 가져온다.
# 생성본은 모두 "이 합성 사진을 실제 카페 메뉴 사진처럼 다시 그려줘, 잔·높이는 그대로"로 받았다. 참조는 아메리카노 잔에
# 음료를 대강 채운 사진이라 잔 외곽선이 아메리카노와 거의 겹친다(생성본마다 외곽선을 겹쳐 보고 받음).
#   80·50% = 생성본 그대로. 30% = Seedream이 걸쭉한 음료를 그 높이로 못 그려(몇 번을 해도 55~60%) 30% 생성본의 음료를
#            SHIFT_30만큼 내려 담는다. 행마다 아메리카노 잔 옆선에 맞춰 폭을 옮기고, 잔 밑동은 내리지 않는다.
#   단계 사진 = 아메리카노 빈 잔(0%) 위에 생성본 음료(빈 잔과 다른 곳의 맨 윗줄부터 아래)를 얹은 것.
#   100% = 입구 위로 솟은 크림까지 생성본에서 가져오고 나머지는 아메리카노 80% 원본.
# 그 뒤 make_latte.py로 9x16·가로·누끼·유리선을 만들고, 100% 누끼에만 입구 위 크림 알파를 더한다.
from __future__ import annotations

import json
import os
import subprocess
import sys

import cv2
import numpy as np
from PIL import Image
from rembg import new_session, remove
from scipy.ndimage import median_filter

CUPS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(
    CUPS, "..", "..", "..", "SugarCap", "Resources", "Assets.xcassets"
)
SET = "choco-frappe"
CAND = os.path.join(CUPS, SET, "candidates")
# 아메리카노 80% 원본(= 0% 원본과 같은 변환)의 잔 바깥 옆선 x = a*y + b
LA = (6.84789669e-02, 7.44121119e02)
RA = (-7.72184742e-02, 1.32363894e03)
RIM_A = 548  # 아메리카노 입구 윗선
GLASS_BOTTOM = 1475
BODY_BOTTOM = 1430  # 잔 안쪽 바닥. 이 아래(두꺼운 유리 밑동)는 30%도 생성본 그대로
CREAM_BASE = 598  # 크림 알파는 이 줄 위만(아래는 잔 입구 선이 섞인다)
SHIFT_30 = 265  # 30% 생성본 음료를 내리는 양(px, 80% 좌표계). 거품 꼭대기가 아메리카노 30% 수면 뒤끝 위 ~40px
DRINK_DIFF = 22  # 빈 잔과 이만큼(최대 채널 차) 다르면 음료
DRINK_SEARCH = 600  # 음료 윗면은 이 줄 아래에서 찾는다(입구 아래)


def read(path: str) -> np.ndarray:
    image = cv2.imdecode(np.fromfile(path, dtype=np.uint8), cv2.IMREAD_COLOR)
    if image is None:
        raise RuntimeError(f"image decode failed: {path}")
    return image


def write(path: str, image: np.ndarray) -> None:
    ok, buf = cv2.imencode(".png", image)
    if not ok:
        raise RuntimeError(f"image encode failed: {path}")
    buf.tofile(path)


def reframe(
    image: np.ndarray, src: dict[str, float], dst: dict[str, float]
) -> np.ndarray:
    """원본 좌표계를 단계 src 변환에서 단계 dst 변환으로 옮긴다(transforms.json)."""
    height, width = image.shape[:2]
    yy, xx = np.mgrid[0:height, 0:width].astype(np.float32)
    xs = (xx * dst["scale"] - dst["dx"] + src["dx"]) / src["scale"]
    ys = (yy * dst["scale"] - dst["dy"] + src["dy"]) / src["scale"]
    return cv2.remap(image, xs, ys, cv2.INTER_LANCZOS4, borderMode=cv2.BORDER_REPLICATE)


def drink_top(gen: np.ndarray, empty: np.ndarray) -> np.ndarray:
    """열마다 생성본이 빈 잔과 10줄 연속 다른 첫 줄(음료·거품 윗면). 잡티는 가로 중앙값으로 누른다."""
    diff = np.abs(gen.astype(np.float32) - empty.astype(np.float32)).max(axis=2)
    hit = cv2.GaussianBlur(diff, (0, 0), 2)[DRINK_SEARCH:BODY_BOTTOM] > DRINK_DIFF
    run = cv2.filter2D(
        hit.astype(np.float32), -1, np.ones((10, 1), np.float32), anchor=(0, 0)
    )
    found = run >= 9.5
    top = np.where(found.any(axis=0), found.argmax(axis=0) + DRINK_SEARCH, np.inf)
    cols = np.isfinite(top)
    top[cols] = median_filter(top[cols], 41)
    return top.astype(np.float32)


def compose_level(gen: np.ndarray, empty: np.ndarray, shift: int) -> np.ndarray:
    height, width = empty.shape[:2]
    yy, xx = np.mgrid[0:height, 0:width].astype(np.float32)
    left, right = np.polyval(LA, yy), np.polyval(RA, yy)
    u = (xx - left) / (right - left)
    ys = yy - shift
    xs = np.polyval(LA, ys) + u * (np.polyval(RA, ys) - np.polyval(LA, ys))
    moved = cv2.remap(
        gen,
        xs.astype(np.float32),
        ys.astype(np.float32),
        cv2.INTER_LANCZOS4,
        borderMode=cv2.BORDER_REPLICATE,
    ).astype(np.float32)
    if shift:
        keep = np.clip((yy - (BODY_BOTTOM - 10)) / 20, 0, 1)[..., None]
        moved = moved * (1 - keep) + gen.astype(np.float32) * keep
    top = drink_top(gen, empty)
    top_out = top[np.clip(np.round(xs), 0, width - 1).astype(int)] + shift
    inside = (u > -0.01) & (u < 1.01) & (yy <= GLASS_BOTTOM) & (yy >= top_out)
    a = cv2.GaussianBlur(inside.astype(np.float32), (0, 0), 3)[..., None]
    out = moved * a + empty.astype(np.float32) * (1 - a)
    return np.clip(out, 0, 255).astype(np.uint8)


def compose_full(base: np.ndarray, gen: np.ndarray) -> np.ndarray:
    height, width = base.shape[:2]
    glass = np.zeros((height, width), np.uint8)
    top = RIM_A - 25
    corners = [
        (np.polyval(LA, top) - 6, top),
        (np.polyval(RA, top) + 6, top),
        (np.polyval(RA, GLASS_BOTTOM) + 6, GLASS_BOTTOM),
        (np.polyval(LA, GLASS_BOTTOM) - 6, GLASS_BOTTOM),
    ]
    cv2.fillPoly(glass, [np.array(corners, np.int32)], 255)
    yy = np.arange(height)[:, None]
    diff = np.abs(gen.astype(int) - base.astype(int)).max(axis=2)
    cream = ((diff > 18) & (yy < RIM_A + 30)).astype(np.uint8) * 255
    cream = cv2.morphologyEx(cream, cv2.MORPH_CLOSE, np.ones((15, 15), np.uint8))
    count, labels, stats, _ = cv2.connectedComponentsWithStats(cream)
    big = [i for i in range(1, count) if stats[i, cv2.CC_STAT_AREA] > 2000]
    hull = np.zeros_like(cream)
    if big:
        points = np.column_stack(np.where(np.isin(labels, big))[::-1]).astype(np.int32)
        cv2.fillPoly(hull, [cv2.convexHull(points)], 255)
    mask = cv2.dilate(cv2.bitwise_or(glass, hull), np.ones((5, 5), np.uint8))
    alpha = cv2.GaussianBlur(mask, (0, 0), 3).astype(np.float32)[..., None] / 255
    return (gen * alpha + base * (1 - alpha)).astype(np.uint8)


def cream_alpha(full: np.ndarray) -> np.ndarray:
    box = (700, 250, 1350, 720)
    crop = Image.fromarray(cv2.cvtColor(full, cv2.COLOR_BGR2RGB)).crop(box)
    cut = np.asarray(remove(crop, session=new_session("isnet-general-use")))
    alpha = np.zeros(full.shape[:2], np.float32)
    alpha[box[1] : box[3], box[0] : box[2]] = cut[:, :, 3].astype(np.float32) / 255
    return alpha


def add_cream_to_cutout(
    cream: np.ndarray, transforms: dict[str, dict[str, float]]
) -> None:
    t = transforms["80"]
    side = round(2048 * t["scale"])
    big = cv2.resize(cream, (side, side), interpolation=cv2.INTER_LINEAR)
    narrow = big[int(t["dy"]) : int(t["dy"]) + 1666, int(t["dx"]) : int(t["dx"]) + 937]
    path = os.path.join(ASSETS, f"cutout-{SET}-100.imageset", "100.png")
    rgba = np.array(Image.open(path).convert("RGBA"))
    above = np.zeros_like(narrow)
    rim_line = round(RIM_A * t["scale"] - t["dy"])
    above[:rim_line] = narrow[:rim_line]
    rgba[:, :, 3] = np.maximum(rgba[:, :, 3], (above * 255).astype(np.uint8))
    Image.fromarray(rgba).save(path, optimize=True)
    Image.fromarray(rgba).save(
        os.path.join(CUPS, "cutouts", f"cutout-{SET}-100.png"), optimize=True
    )


def main() -> None:
    with open(os.path.join(CUPS, "transforms.json")) as f:
        transforms: dict[str, dict[str, float]] = json.load(f)
    base80 = read(os.path.join(CUPS, "iced-americano", "original", "80.png"))
    empty = read(os.path.join(CUPS, "iced-americano", "original", "0.png"))
    full = compose_full(base80, read(os.path.join(CAND, "gen_100.png")))
    write(os.path.join(CAND, "100_a.png"), full)
    for step, shift in ((80, 0), (50, 0), (30, SHIFT_30)):
        gen = read(os.path.join(CAND, f"gen_{step}.png"))
        if step != 80:
            gen = reframe(gen, transforms[str(step)], transforms["80"])
        level = compose_level(gen, empty, shift)
        if step != 80:
            level = reframe(level, transforms["80"], transforms[str(step)])
        write(os.path.join(CAND, f"{step}_a.png"), level)
        print(step, "composed")
    subprocess.run(
        [
            sys.executable,
            os.path.join(os.path.dirname(os.path.abspath(__file__)), "make_latte.py"),
            SET,
        ],
        check=True,
    )
    cream = cream_alpha(full) * np.clip(
        (CREAM_BASE - np.arange(2048)[:, None]) / 28, 0, 1
    )
    add_cream_to_cutout(cream, transforms)


if __name__ == "__main__":
    main()
