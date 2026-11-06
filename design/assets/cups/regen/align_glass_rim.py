# 2026 특전 유리 잔(glass-soda, glass-beans)의 유리 선을 그 잔 사진에 맞춘다(2026-11-06, 빌드 407 대표님
# "잔 사이즈가 정확히 안 맞네", "숫자를 뚫어놓으니까 겹치는 부분이 어긋나네").
# make_glass_set.py는 아메리카노 0% 유리 선을 그대로 복사했는데, 생성된 유리 잔은 조금 크고 입구 타원도 더 열려 있다.
# 1단계: 아메리카노 0% 잔 윤곽(입구 호 + 위쪽 옆선) 점을 배율·이동으로 옮겨 그 사진의 밝기 기울기가 가장 센 자리를 찾는다.
# 2단계: 입구 호만 뒤 호 꼭대기를 기준으로 세로로 늘이고 옮겨 한 번 더 맞춘다(소다 50·80%는 입구가 훨씬 열려 범위를 넓힌다).
# 결과는 원본 사진 위에 겹쳐 보고 받는다(--preview 폴더). 시스템 파이썬 3.12(cv2)로 돌린다.
#
# 사용: python align_glass_rim.py [--preview <폴더>]
from __future__ import annotations

import argparse
import os
from dataclasses import dataclass

import cv2
import numpy as np
from numpy.typing import NDArray

CUPS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(
    CUPS, "..", "..", "..", "SugarCap", "Resources", "Assets.xcassets"
)
CENTER = (468.0, 800.0)
STEPS = (30, 50, 80, 100)


@dataclass(frozen=True)
class Search:
    """한 단계 사진의 탐색 범위."""

    scale_min: float = 0.94
    shift_span: int = 30
    wide_rim: bool = False


# 기본 범위에서 엉뚱한 자리(안쪽 수면·과일 윤곽)에 붙은 단계만 좁히거나 넓힌다.
SEARCH: dict[str, Search] = {
    "glass-soda-50": Search(scale_min=0.99, shift_span=12, wide_rim=True),
    "glass-soda-80": Search(scale_min=0.99, shift_span=12, wide_rim=True),
}


def read(name: str, flags: int) -> NDArray[np.uint8]:
    folder = os.path.join(ASSETS, name + ".imageset")
    files = [f for f in os.listdir(folder) if f.endswith(".png")]
    if len(files) != 1:
        raise RuntimeError(f"PNG가 1장이 아님: {folder} {files}")
    img = cv2.imdecode(
        np.fromfile(os.path.join(folder, files[0]), dtype=np.uint8), flags
    )
    if img is None:
        raise FileNotFoundError(folder)
    return np.asarray(img, dtype=np.uint8)


def write(path: str, img: NDArray[np.uint8]) -> None:
    ok, buf = cv2.imencode(".png", img)
    if not ok:
        raise RuntimeError(f"PNG 인코딩 실패: {path}")
    buf.tofile(path)


def gradient(img: NDArray[np.uint8]) -> NDArray[np.float32]:
    gray = cv2.GaussianBlur(
        cv2.cvtColor(img, cv2.COLOR_BGR2GRAY).astype(np.float32), (0, 0), 1.5
    )
    mag = cv2.magnitude(
        cv2.Sobel(gray, cv2.CV_32F, 1, 0), cv2.Sobel(gray, cv2.CV_32F, 0, 1)
    )
    mag = cv2.GaussianBlur(mag, (0, 0), 2.0)
    return np.asarray(mag / (np.percentile(mag, 99.5) + 1e-6), dtype=np.float32)


Coords = NDArray[np.float32] | NDArray[np.float64]


def sample(grad: NDArray[np.float32], xs: Coords, ys: Coords) -> float:
    xi = np.clip(np.round(xs).astype(np.int64), 0, grad.shape[1] - 1)
    yi = np.clip(np.round(ys).astype(np.int64), 0, grad.shape[0] - 1)
    return float(np.minimum(grad[yi, xi], 1.0).mean())


def fit_glass(
    grad: NDArray[np.float32], pts: NDArray[np.float32], search: Search
) -> tuple[float, float, float, float]:
    cx, cy = CENTER
    best = (-1.0, 1.0, 1.0, 0.0, 0.0)
    for s in np.arange(search.scale_min, 1.08, 0.005):
        for tx in range(-search.shift_span, search.shift_span + 1, 3):
            for ty in range(-60, 61, 3):
                xs = cx + s * (pts[:, 0] - cx) + tx
                ys = cy + s * (pts[:, 1] - cy) + ty
                v = sample(grad, xs, ys)
                if v > best[0]:
                    best = (v, float(s), float(s), float(tx), float(ty))
    _, s0, _, tx0, ty0 = best
    for sx in np.arange(s0 - 0.02, s0 + 0.021, 0.004):
        for sy in np.arange(s0 - 0.03, s0 + 0.031, 0.004):
            for ftx in np.arange(tx0 - 3, tx0 + 3.1, 1):
                for fty in np.arange(ty0 - 4, ty0 + 4.1, 1):
                    xs = cx + sx * (pts[:, 0] - cx) + ftx
                    ys = cy + sy * (pts[:, 1] - cy) + fty
                    v = sample(grad, xs, ys)
                    if v > best[0]:
                        best = (v, float(sx), float(sy), float(ftx), float(fty))
    return best[1], best[2], best[3], best[4]


def fit_rim(
    grad: NDArray[np.float32], rim: NDArray[np.uint8], search: Search
) -> NDArray[np.float32]:
    ry, rx = np.nonzero(rim > 128)
    keep = ry < np.percentile(ry, 85)
    pts = np.column_stack([rx[keep], ry[keep]]).astype(np.float32)[::2]
    top = float(ry.min())
    cx = CENTER[0]
    if search.wide_rim:
        kxs, dxs = np.arange(0.96, 1.121, 0.01), np.arange(-6, 24.1, 3)
        dys, ks = np.arange(-44, 8.1, 2), np.arange(0.85, 1.5, 0.02)
    else:
        kxs, dxs = np.arange(0.98, 1.021, 0.01), np.array([0.0])
        dys, ks = np.arange(-12, 12.1, 1), np.arange(0.85, 1.5, 0.01)
    best = (-1.0, 1.0, 0.0, 1.0, 0.0)
    for k in ks:
        for dy in dys:
            for kx in kxs:
                for dx in dxs:
                    xs = cx + kx * (pts[:, 0] - cx) + dx
                    ys = top + k * (pts[:, 1] - top) + dy
                    v = sample(grad, xs, ys)
                    if v > best[0]:
                        best = (v, float(k), float(dy), float(kx), float(dx))
    _, k, dy, kx, dx = best
    return np.array(
        [[kx, 0, cx * (1 - kx) + dx], [0, k, top * (1 - k) + dy]], dtype=np.float32
    )


def align(target: str, preview: str | None) -> None:
    base = read("cup-iced-americano-0", cv2.IMREAD_COLOR)
    cut = read("cutout-iced-americano-0", cv2.IMREAD_UNCHANGED)[:, :, 3]
    rim = read("rimline-iced-americano-0", cv2.IMREAD_UNCHANGED)[:, :, 3]
    photo = read("cup-" + target, cv2.IMREAD_COLOR)
    search = SEARCH.get(target, Search())
    template = gradient(base)
    edge = (
        cv2.morphologyEx(
            (cut > 128).astype(np.uint8), cv2.MORPH_GRADIENT, np.ones((3, 3), np.uint8)
        )
        > 0
    )
    edge[:250] = False
    edge[900:] = False
    ys, xs = np.nonzero((edge | (rim > 128)) & (template > 0.25))
    pts = np.column_stack([xs, ys]).astype(np.float32)[::2]
    grad = gradient(photo)
    sx, sy, tx, ty = fit_glass(grad, pts, search)
    first = np.array(
        [[sx, 0, CENTER[0] * (1 - sx) + tx], [0, sy, CENTER[1] * (1 - sy) + ty]],
        dtype=np.float32,
    )
    size = (rim.shape[1], rim.shape[0])
    moved = np.asarray(
        cv2.warpAffine(rim, first, size, flags=cv2.INTER_LINEAR), dtype=np.uint8
    )
    second = fit_rim(grad, moved, search)
    final = np.asarray(
        cv2.warpAffine(moved, second, size, flags=cv2.INTER_LINEAR), dtype=np.uint8
    )
    out = np.zeros((*final.shape, 4), dtype=np.uint8)
    out[:, :, :3] = 255
    out[:, :, 3] = final
    step = target.rsplit("-", 1)[1]
    write(os.path.join(ASSETS, f"rimline-{target}.imageset", f"{step}.png"), out)
    print(target, round(sx, 3), round(sy, 3), tx, ty, second.round(3).tolist())
    if preview is not None:
        overlay = photo.copy()
        overlay[final > 60] = (0, 0, 255)
        write(
            os.path.join(preview, f"rim-{target}.png"),
            np.asarray(overlay[250:900], dtype=np.uint8),
        )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--preview")
    args = parser.parse_args()
    preview: str | None = args.preview
    if preview is not None:
        os.makedirs(preview, exist_ok=True)
    for cup_set in ("glass-soda", "glass-beans"):
        for step in STEPS:
            align(f"{cup_set}-{step}", preview)


if __name__ == "__main__":
    main()
