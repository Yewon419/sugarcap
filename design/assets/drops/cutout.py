"""흰 배경에서 생성한 음료 방울을 투명 PNG로 오린다.

배경(흰색)과 바닥 그림자(회색)는 채도가 거의 없고, 방울만 색이 있다는 점을 쓴다.
채도 마스크 → 가장 큰 덩어리만 남김 → 속을 채움(흰 빛 반사가 구멍으로 빠지지 않게) → 가장자리를 살짝 흐림.

사용: python cutout.py sugar-raw.png sugar.png
"""

from __future__ import annotations

import sys
from pathlib import Path

import cv2
import numpy as np

CHROMA_THRESHOLD = 14
OUTPUT_MAX_SIDE = 512
PADDING = 12


def cutout(source: Path, target: Path) -> None:
    image = cv2.imread(str(source), cv2.IMREAD_COLOR)
    if image is None:
        raise FileNotFoundError(f"이미지를 읽지 못함: {source}")

    chroma = image.max(axis=2).astype(np.int16) - image.min(axis=2).astype(np.int16)
    mask = (chroma > CHROMA_THRESHOLD).astype(np.uint8) * 255
    mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, np.ones((5, 5), np.uint8))

    contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    if not contours:
        raise ValueError(f"색이 있는 영역을 찾지 못함: {source}")
    drop = max(contours, key=cv2.contourArea)
    solid = np.zeros_like(mask)
    cv2.drawContours(solid, [drop], -1, 255, thickness=cv2.FILLED)
    alpha = cv2.GaussianBlur(solid, (0, 0), sigmaX=1.6)

    x, y, w, h = cv2.boundingRect(drop)
    x0, y0 = max(0, x - PADDING), max(0, y - PADDING)
    x1, y1 = min(image.shape[1], x + w + PADDING), min(image.shape[0], y + h + PADDING)
    rgba = cv2.cvtColor(image, cv2.COLOR_BGR2BGRA)
    rgba[:, :, 3] = alpha
    rgba = rgba[y0:y1, x0:x1]

    scale = OUTPUT_MAX_SIDE / max(rgba.shape[:2])
    if scale < 1:
        rgba = cv2.resize(rgba, None, fx=scale, fy=scale, interpolation=cv2.INTER_AREA)
    if not cv2.imwrite(str(target), rgba):
        raise OSError(f"저장 실패: {target}")
    print(f"{target}: {rgba.shape[1]}x{rgba.shape[0]}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("사용: python cutout.py <원본.png> <결과.png>")
    cutout(Path(sys.argv[1]), Path(sys.argv[2]))
