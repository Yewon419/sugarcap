# 초코 프라페 v3(2026-10-31, 대표님 "아예 갈아엎자, 크림은 지금처럼 높게").
# v2는 생성 모델이 잔 모양을 바꾼 걸 배율·세로 늘이기로만 맞춰서 잔 크기가 아메리카노와 어긋났다.
# v3는 잔을 아메리카노 잔 그대로 쓴다:
#   100% = Seedream이 아메리카노 80%를 고친 사진(candidates/100_raw.png)의 잔 안쪽을 행마다 사다리꼴로
#          아메리카노 잔 옆선에 맞춰 옮기고(입구 위 크림은 평행 이동만), 잔·크림 밖은 아메리카노 80% 원본 픽셀.
#   30·50·80% = Seedream이 걸쭉한 프라페는 덜 찬 잔으로 못 그려서(가득 채우거나 잔을 각진 잔으로 바꿈)
#          100%에서 합성한다: 아메리카노 빈 잔(0%) 위에 같은 단계 아메리카노의 수면 타원까지 100% 음료 몸통을
#          눌러 담고, 수면은 몸통 질감, 크림은 100% 크림을 줄여 수면 가운데에 얹는다.
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

CUPS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(
    CUPS, "..", "..", "..", "SugarCap", "Resources", "Assets.xcassets"
)
SET = "choco-frappe"
CAND = os.path.join(CUPS, SET, "candidates")
# 아메리카노 80% 원본(= 0% 원본과 같은 변환)의 잔 바깥 옆선 x = a*y + b
LA = (6.84789669e-02, 7.44121119e02)
RA = (-7.72184742e-02, 1.32363894e03)
RIM_A, RIM_C = 548, 618  # 입구 윗선: 아메리카노 80%, 100_raw
ANCHOR = 1330  # 이 줄 아래(잔 밑동)는 두 사진이 같다
GLASS_BOTTOM = 1475
BODY_TOP, BODY_BOTTOM = 700, 1430  # 100% 합성본에서 음료 몸통(크림 아래 거품층부터)
CREAM_BASE = 598  # 크림 알파는 이 줄 위만(아래는 잔 입구 선이 섞인다)
# 단계별 수면 타원(80% 좌표계): 중심 y, 세로 반지름, 얹는 크림 배율. 아메리카노 같은 단계 사진에서 잼.
LEVELS = {80: (740, 62, 0.55), 50: (873, 66, 0.45), 30: (1153, 55, 0.35)}


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


def side_lines(gray: np.ndarray, y0: int, y1: int) -> tuple[np.ndarray, np.ndarray]:
    ys: list[int] = []
    lefts: list[int] = []
    rights: list[int] = []
    for y in range(y0, y1, 6):
        row = gray[y, 600:1450]
        hit = np.where(np.abs(row - np.median(gray[y, :300])) > 12)[0]
        if len(hit) < 50:
            continue
        ys.append(y)
        lefts.append(int(hit.min()) + 600)
        rights.append(int(hit.max()) + 600)
    y_arr = np.array(ys)
    fits = []
    for xs in (np.array(lefts), np.array(rights)):
        first = np.polyfit(y_arr, xs, 1)
        keep = np.abs(np.polyval(first, y_arr) - xs) < 6
        fits.append(np.polyfit(y_arr[keep], xs[keep], 1))
    return fits[0], fits[1]


def compose_full(base: np.ndarray, raw: np.ndarray) -> np.ndarray:
    gray = cv2.cvtColor(raw, cv2.COLOR_BGR2GRAY).astype(int)
    lc, rc = side_lines(gray, RIM_C + 40, 1300)
    height, width = base.shape[:2]
    yy, xx = np.mgrid[0:height, 0:width].astype(np.float32)
    squeeze = (ANCHOR - RIM_C) / (ANCHOR - RIM_A)
    ys = np.where(yy > ANCHOR, yy, ANCHOR + (yy - ANCHOR) * squeeze)
    ys = np.where(yy < RIM_A, RIM_C + (yy - RIM_A), ys)
    ya, yc = np.maximum(yy, RIM_A), np.maximum(ys, RIM_C)
    u = (xx - np.polyval(LA, ya)) / (np.polyval(RA, ya) - np.polyval(LA, ya))
    xs = np.polyval(lc, yc) + u * (np.polyval(rc, yc) - np.polyval(lc, yc))
    warped = cv2.remap(
        raw,
        xs.astype(np.float32),
        ys.astype(np.float32),
        cv2.INTER_LANCZOS4,
        borderMode=cv2.BORDER_REPLICATE,
    )
    glass = np.zeros((height, width), np.uint8)
    top = RIM_A - 25
    corners = [
        (np.polyval(LA, top) - 6, top),
        (np.polyval(RA, top) + 6, top),
        (np.polyval(RA, GLASS_BOTTOM) + 6, GLASS_BOTTOM),
        (np.polyval(LA, GLASS_BOTTOM) - 6, GLASS_BOTTOM),
    ]
    cv2.fillPoly(glass, [np.array(corners, np.int32)], 255)
    diff = np.abs(warped.astype(int) - base.astype(int)).max(axis=2)
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
    return (warped * alpha + base * (1 - alpha)).astype(np.uint8)


def cream_alpha(full: np.ndarray) -> np.ndarray:
    box = (700, 250, 1350, 720)
    crop = Image.fromarray(cv2.cvtColor(full, cv2.COLOR_BGR2RGB)).crop(box)
    cut = np.asarray(remove(crop, session=new_session("isnet-general-use")))
    alpha = np.zeros(full.shape[:2], np.float32)
    alpha[box[1] : box[3], box[0] : box[2]] = cut[:, :, 3].astype(np.float32) / 255
    return alpha


def compose_level(
    empty: np.ndarray,
    full: np.ndarray,
    cream: np.ndarray,
    center: int,
    radius: int,
    cream_scale: float,
) -> np.ndarray:
    height, width = empty.shape[:2]
    yy, xx = np.mgrid[0:height, 0:width].astype(np.float32)
    left, right = np.polyval(LA, yy), np.polyval(RA, yy)
    u = (xx - left) / (right - left)
    source = full.astype(np.float32)

    def sample(ys: np.ndarray) -> np.ndarray:
        sl, sr = np.polyval(LA, ys), np.polyval(RA, ys)
        xs = sl + u * (sr - sl)
        return cv2.remap(
            source,
            xs.astype(np.float32),
            ys.astype(np.float32),
            cv2.INTER_LINEAR,
            borderMode=cv2.BORDER_REPLICATE,
        )

    mid = (np.polyval(LA, center) + np.polyval(RA, center)) / 2
    half_w = (np.polyval(RA, center) - np.polyval(LA, center)) / 2 - 6
    t = np.clip((xx - mid) / half_w, -1, 1)
    half_h = radius * np.sqrt(1 - t**2)
    back, front = center - half_h, center + half_h
    inside = (u > 0) & (u < 1) & (yy <= GLASS_BOTTOM)
    liquid = inside & ((yy >= center) | ((yy >= back) & (np.abs(xx - mid) <= half_w)))
    surface = liquid & (yy <= front)
    body_rows = BODY_TOP + (yy - front) * (BODY_BOTTOM - BODY_TOP) / (
        BODY_BOTTOM - front
    )
    body_rows = np.where(yy > BODY_BOTTOM, yy, body_rows)
    body = sample(np.clip(body_rows, BODY_TOP, GLASS_BOTTOM))
    depth = np.clip((yy - back) / np.maximum(front - back, 1), 0, 1)[..., None]
    top = sample(780 + (yy - back)) * (0.9 + 0.16 * depth)
    out = empty.astype(np.float32)
    for region, layer in ((liquid & ~surface, body), (surface, top)):
        a = cv2.GaussianBlur(region.astype(np.float32), (0, 0), 1.2)[..., None]
        out = out * (1 - a) + layer * a
    move = np.float32(
        [
            [cream_scale, 0, mid - cream_scale * mid],
            [0, cream_scale, center - cream_scale * (CREAM_BASE - 8)],
        ]
    )
    piece = cv2.warpAffine(source, move, (width, height), flags=cv2.INTER_LANCZOS4)
    a = cv2.warpAffine(cream, move, (width, height))[..., None]
    out = out * (1 - a) + piece * a
    return np.clip(out, 0, 255).astype(np.uint8)


def to_step_frame(
    image: np.ndarray, step: int, transforms: dict[str, dict[str, float]]
) -> np.ndarray:
    src, dst = transforms["80"], transforms[str(step)]
    height, width = image.shape[:2]
    yy, xx = np.mgrid[0:height, 0:width].astype(np.float32)
    xs = (xx * dst["scale"] - dst["dx"] + src["dx"]) / src["scale"]
    ys = (yy * dst["scale"] - dst["dy"] + src["dy"]) / src["scale"]
    return cv2.remap(image, xs, ys, cv2.INTER_LANCZOS4, borderMode=cv2.BORDER_REPLICATE)


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
    full = compose_full(base80, read(os.path.join(CAND, "100_raw.png")))
    write(os.path.join(CAND, "100_a.png"), full)
    cream = cream_alpha(full) * np.clip(
        (CREAM_BASE - np.arange(2048)[:, None]) / 28, 0, 1
    )
    for step, (center, radius, scale) in LEVELS.items():
        level = compose_level(
            empty, full, cream.astype(np.float32), center, radius, scale
        )
        if step != 80:
            level = to_step_frame(level, step, transforms)
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
    add_cream_to_cutout(cream, transforms)


if __name__ == "__main__":
    main()
