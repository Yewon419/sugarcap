# 초코 프라페 누끼. rembg를 그대로 쓰면 시럽 줄기·냅킨 때문에 바닥 호와 옆선이 울퉁불퉁해진다
# (대표님 2026-10-24 "누끼 퀄리티가 아쉬운걸"). 아메리카노 윤곽을 빌리면 프라페 잔은 밑동이 넓고 바닥이
# 75px쯤 높아 안 맞는다. 그래서 잔을 도형으로 다시 그린다:
#   옆벽 = rembg 가장자리에 맞춘 직선, 입구 = 윗선에 맞춘 타원호, 바닥 = 유리 바닥 아래 접촉선에 맞춘 타원호,
#   바닥 모서리는 둥글게. 100%는 입구 위로 올라온 크림을 rembg 알파에서 더한다.
# 가장자리는 사진 밝기에서 직접 잰다. 이 스크립트는 cutouts/에만 쓴다.
import os

import cv2
import numpy as np
from PIL import Image
from rembg import new_session, remove

CUPS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(
    CUPS, "..", "..", "..", "SugarCap", "Resources", "Assets.xcassets"
)
Q = 4  # 매끄러운 가장자리를 위해 4배로 그린 뒤 줄인다
CORNER = 26  # 바닥 모서리 반지름(9x16 px)
RIM_CORNER = 9  # 입구 양 끝 모서리 반지름
INSET = 1.5  # 옆벽을 안쪽으로 당겨 바닥 모서리에 배경이 끼지 않게 한다
RIM_BELOW = 520  # 100% 크림은 이 줄 위만 더한다


def robust_fit(design: np.ndarray, target: np.ndarray) -> np.ndarray:
    keep = np.ones(len(target), bool)
    coef = np.zeros(design.shape[1])
    for _ in range(6):
        coef = np.linalg.lstsq(design[keep], target[keep], rcond=None)[0]
        r = np.abs(target - design @ coef)
        keep = r < max(2.0, 2.5 * float(np.median(r[keep])))
    return coef


def walls(lum: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """옆벽 = 흰 배경보다 뚜렷이 어두워지는 첫 픽셀(행마다)에 맞춘 2차 곡선(np.polyval 계수).
    입구 근처에서 벽이 살짝 안으로 휘어 직선으로는 위쪽에 배경이 낀다."""
    rows = np.arange(500, 1230, 4).astype(float)
    left, right = [], []
    for y in rows.astype(int):
        bg = float(np.median(lum[y, 20:80]))
        lx = np.nonzero(lum[y, 60:470] < bg - 18)[0]
        rx = np.nonzero(lum[y, 470:880] < bg - 18)[0]
        left.append(60.0 + lx[0] if lx.size else np.nan)
        right.append(470.0 + rx[-1] if rx.size else np.nan)
    design = np.stack([rows**2, rows, np.ones_like(rows)], 1)
    out = []
    for edge in (np.array(left), np.array(right)):
        ok = ~np.isnan(edge)
        out.append(robust_fit(design[ok], edge[ok]))
    return out[0], out[1]


def arc_design(xs: np.ndarray, cx: float, a: float) -> np.ndarray:
    return np.stack(
        [np.ones_like(xs), np.sqrt(np.clip(1 - ((xs - cx) / a) ** 2, 0, 1))], 1
    )


def rim_points(lum: np.ndarray, xl: float, xr: float) -> tuple[np.ndarray, np.ndarray]:
    """입구 뒤쪽 윗선: 흰 배경 아래 처음 회색(<225)이 되는 줄. rembg 윗선은 배경을 둥글게 먹어서 쓰지 않는다."""
    xs, ys = [], []
    for x in range(int(xl) + 20, int(xr) - 20, 4):
        idx = np.nonzero(lum[330:600, x] < 225)[0]
        if idx.size:
            xs.append(float(x))
            ys.append(330.0 + idx[0])
    return np.array(xs), np.array(ys)


def rim_arc(
    lum: np.ndarray, lw: np.ndarray, rw: np.ndarray, depth: float | None
) -> tuple[float, float, float, float]:
    """입구 윗선 y = y0 - b·sqrt(1-((x-cx)/a)^2). depth(b)를 주면 y0만 맞춘다(크림이 가운데를 가린 100%용)."""
    y_side = 470
    xl, xr = float(np.polyval(lw, y_side)), float(np.polyval(rw, y_side))
    cx, a = (xl + xr) / 2, (xr - xl) / 2
    xs, ys = rim_points(lum, xl, xr)
    if depth is None:
        y0, b = robust_fit(arc_design(xs, cx, a) * np.array([1, -1]), ys)
        return cx, a, float(y0), float(b)
    edge = np.abs(xs - cx) > a * 0.6
    curve = depth * np.sqrt(np.clip(1 - ((xs[edge] - cx) / a) ** 2, 0, 1))
    y0 = float(np.median(ys[edge] + curve))
    return cx, a, y0, depth


def bottom_arc(
    lum: np.ndarray, lw: np.ndarray, rw: np.ndarray
) -> tuple[float, float, float, float]:
    """바닥선 y = y0 + b·sqrt(1-((x-cx)/a)^2). 유리 바닥(밝은 띠) 아래 처음 어두워지는 줄을 점으로 쓴다."""
    y_side = 1340
    xl, xr = float(np.polyval(lw, y_side)), float(np.polyval(rw, y_side))
    cx, a = (xl + xr) / 2, (xr - xl) / 2
    xs, ys = [], []
    for x in range(int(xl) + 40, int(xr) - 40, 4):
        bright = 0
        for i, v in enumerate(lum[1300:1440, x]):
            if v > 200:
                bright += 1
            elif bright >= 8 and v < 170:
                xs.append(float(x))
                ys.append(1300.0 + i)
                break
    if len(xs) < 20:
        raise RuntimeError(f"bottom line points too few: {len(xs)}")
    y0, b = robust_fit(arc_design(np.array(xs), cx, a), np.array(ys))
    return cx, a, float(y0), float(b)


def glass_shape(
    shape: tuple[int, int],
    lw: np.ndarray,
    rw: np.ndarray,
    rim: tuple[float, float, float, float],
    bot: tuple[float, float, float, float],
) -> np.ndarray:
    h, w = shape
    yy, xx = np.mgrid[0 : h * Q, 0 : w * Q].astype(np.float32) / Q
    inside = (xx >= np.polyval(lw, yy)) & (xx <= np.polyval(rw, yy))
    for (cx, a, y0, b), sign in ((rim, -1), (bot, 1)):
        arc = y0 + sign * b * np.sqrt(np.clip(1 - ((xx - cx) / a) ** 2, 0, 1))
        inside &= (yy >= arc) if sign < 0 else (yy <= arc)
    m = inside.astype(np.uint8)
    # 바닥 모서리만 둥글게: 열기(opening)를 하되 입구 쪽은 원래 모양을 유지한다
    k = cv2.getStructuringElement(
        cv2.MORPH_ELLIPSE, (2 * CORNER * Q + 1, 2 * CORNER * Q + 1)
    )
    opened = cv2.morphologyEx(m, cv2.MORPH_OPEN, k)
    split = int((bot[2] - 200) * Q)
    m[split:] = opened[split:]
    small = cv2.getStructuringElement(
        cv2.MORPH_ELLIPSE, (2 * RIM_CORNER * Q + 1, 2 * RIM_CORNER * Q + 1)
    )
    m = cv2.morphologyEx(m, cv2.MORPH_OPEN, small)
    return cv2.resize(m.astype(np.float32) * 255, (w, h), interpolation=cv2.INTER_AREA)


def main() -> None:
    session = new_session("u2net")
    rim_depth: float | None = None
    geom30: (
        tuple[
            np.ndarray,
            np.ndarray,
            tuple[float, float, float, float],
            tuple[float, float, float, float],
        ]
        | None
    ) = None
    for step in (30, 50, 80, 100, 0):
        src = Image.open(
            os.path.join(CUPS, "choco-frappe", "9x16", f"{step}.png")
        ).convert("RGB")
        lum = cv2.cvtColor(np.array(src), cv2.COLOR_RGB2GRAY).astype(float)
        if step == 0:
            # 빈 잔(align_frappe_empty)은 30%를 비운 편집본이라 같은 자리다. 안쪽 바닥 선에 바닥 호 피팅이 속아서 30% 도형을 쓴다.
            if geom30 is None:
                raise RuntimeError("30% geometry missing")
            lw, rw, rim, bot = geom30
        else:
            lw, rw = walls(lum)
            lw[-1] += INSET
            rw[-1] -= INSET
            rim = rim_arc(lum, lw, rw, rim_depth if step == 100 else None)
            rim_depth = rim[3] if step == 80 else rim_depth
            bot = bottom_arc(lum, lw, rw)
            geom30 = (lw, rw, rim, bot) if step == 30 else geom30
        alpha = glass_shape(lum.shape, lw, rw, rim, bot)
        if step == 100:
            raw = np.array(remove(src, session=session))[:, :, 3]
            cream = (raw > 128).astype(np.uint8)
            cream[RIM_BELOW:] = 0
            yy, xx = np.mgrid[0 : cream.shape[0], 0 : cream.shape[1]]
            cream[(xx < np.polyval(lw, yy)) | (xx > np.polyval(rw, yy))] = (
                0  # 크림은 옆벽 연장선 안쪽만
            )
            n, labels, stats, _ = cv2.connectedComponentsWithStats(
                cream, connectivity=8
            )
            if n > 1:
                cream = (
                    labels == 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
                ).astype(np.uint8)
            big = cv2.resize(
                cream * 255, None, fx=Q, fy=Q, interpolation=cv2.INTER_NEAREST
            )
            big = (cv2.GaussianBlur(big.astype(np.float32), (0, 0), 10) > 127).astype(
                np.float32
            )
            alpha = np.maximum(
                alpha,
                cv2.resize(
                    big, (cream.shape[1], cream.shape[0]), interpolation=cv2.INTER_AREA
                )
                * 255,
            )
        out = np.dstack([np.array(src), np.clip(alpha, 0, 255).astype(np.uint8)])
        Image.fromarray(out).save(
            os.path.join(CUPS, "cutouts", f"cutout-choco-frappe-{step}.png"),
            optimize=True,
        )
        print(f"cut {step} rim {np.round(rim, 1)} bottom {np.round(bot, 1)}")


if __name__ == "__main__":
    main()
