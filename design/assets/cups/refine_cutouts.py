# 누끼 다듬기(2026-09-27 대표님 피드백: 잔 바닥의 회색 그림자 띠, 유리 옆면 울퉁불퉁).
# rembg(u2net) 알파를 그대로 쓰지 않고, 잔 윤곽을 직접 다시 그린다.
#  1) rembg 알파에서 잔 실루엣(가장 큰 덩어리, 구멍 메움)을 얻는다
#  1b) 위: 테두리 양 끝을 잇는 타원으로 뒤쪽 잔 테두리를 채운다(가득 찬 잔은 rembg가 얼음 윗면에서 잘랐다)
#  2) 바닥: 알파 200 이상이 끝나는 줄을 열마다 찾아 2차 곡선(바닥 호)으로 맞추고, 그 아래(그림자 띠)를 자른다
#  3) 윤곽선을 따라 점들을 가우시안으로 펴서 옆면 들쭉날쭉을 없앤다
#  4) 4배 크기로 채워 그린 뒤 줄여 가장자리를 부드럽게(안티에일리어싱) 하고, 안쪽은 불투명으로 둔다
# 입력: cups/<세트>/9x16/<단계>.png(원본)  출력: cups/cutouts/cutout-<세트>-<단계>.png(937×1666, 원본 캔버스 그대로)
import os
import sys

import cv2
import numpy as np
from PIL import Image
from rembg import new_session, remove

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "cutouts")
SETS = ["strawberry-latte", "iced-americano"]
STEPS = [0, 10, 20, 30, 40, 50, 70, 80, 100]
SUPER = 4
# 바닥 호에서 위로 몇 px 더 자를지(받침 아래 어두운 접지선 제거).
BOTTOM_TRIM = 4
# 바닥 모서리 둥글기 반지름(px).
CORNER = 22
# 잔 테두리 타원의 높이/폭 비율(깨끗한 단계들에서 잰 중간값).
RIM_RATIO = 0.25


def silhouette(alpha: np.ndarray) -> np.ndarray:
    solid = (alpha > 128).astype(np.uint8)
    count, labels, stats, _ = cv2.connectedComponentsWithStats(solid, 8)
    biggest = 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
    mask = (labels == biggest).astype(np.uint8)
    # 구멍(투명 유리 안쪽이 비어 보인 곳) 메우기
    flood = mask.copy() * 255
    h, w = flood.shape
    cv2.floodFill(flood, np.zeros((h + 2, w + 2), np.uint8), (0, 0), 128)
    return ((flood != 128)).astype(np.uint8)


def fill_rim(mask: np.ndarray) -> np.ndarray:
    """잔 뒤쪽 테두리(위로 볼록한 타원 호)를 되살린다. rembg가 가득 찬 잔(100%)에서 테두리 대신
    얼음 윗면을 따라 잘랐다(대표님 2026-09-27). 흰 벽 앞 투명한 테두리 선은 밝기로 안 잡혀서,
    테두리 양 끝(윗부분에서 가장 넓은 줄)을 잇는 타원을 그려 그 안을 잔으로 채운다.
    타원 높이/폭 비율은 테두리가 깨끗한 단계들에서 잰 값(0.24~0.29, 중간값 0.25)."""
    ys, xs = np.nonzero(mask)
    top, bottom = ys.min(), ys.max()
    band = mask[top:top + int((bottom - top) * 0.15)]
    rim_row = top + int(np.argmax(band.sum(axis=1)))
    rim_cols = np.nonzero(mask[rim_row])[0]
    left, right = rim_cols.min(), rim_cols.max()
    center, half = (left + right) / 2, (right - left) / 2
    height = RIM_RATIO * half
    out = mask.copy()
    for x in range(left, right + 1):
        t = (x - center) / half
        y0 = int(round(rim_row - height * np.sqrt(max(0.0, 1 - t * t))))
        out[y0:rim_row + 1, x] = 1
    return out


def cut_bottom(mask: np.ndarray, alpha: np.ndarray) -> np.ndarray:
    """잔 받침 아래 그림자 띠를 자른다. 그림자는 알파가 200 아래로 떨어지는 가장자리라,
    열마다 알파 200 이상이 끝나는 줄을 찾아 2차 곡선(바닥 호)으로 맞추고 조금 위에서 자른다.
    밝기로 찾으면 커피색이 비치는 받침(아메리카노)까지 잘려서 쓰지 않는다."""
    ys, xs = np.nonzero(mask)
    left, right = xs.min(), xs.max()
    margin = int((right - left) * 0.15)  # 양 끝은 둥근 모서리라 제외
    cols, rows = [], []
    for x in range(left + margin, right - margin, 3):
        solid = np.nonzero(alpha[:, x] > 200)[0]
        if solid.size:
            cols.append(x)
            rows.append(solid.max())
    if len(cols) < 10:
        return mask
    coeffs = np.polyfit(np.array(cols, float), np.array(rows, float), 2)
    floor = np.polyval(coeffs, np.arange(mask.shape[1], dtype=float)) - BOTTOM_TRIM
    yy = np.arange(mask.shape[0])[:, None]
    return (mask.astype(bool) & (yy <= floor[None, :])).astype(np.uint8)


def smooth_outline(mask: np.ndarray, sigma: float = 7.0) -> np.ndarray:
    contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    contour = max(contours, key=cv2.contourArea)[:, 0, :].astype(np.float64)
    radius = int(sigma * 3)
    kernel = np.exp(-0.5 * (np.arange(-radius, radius + 1) / sigma) ** 2)
    kernel /= kernel.sum()
    padded = np.concatenate([contour[-radius:], contour, contour[:radius]])
    smooth = np.stack([np.convolve(padded[:, i], kernel, mode="valid") for i in range(2)], axis=1)
    h, w = mask.shape
    big = np.zeros((h * SUPER, w * SUPER), np.uint8)
    points = np.round(smooth * SUPER).astype(np.int32)
    cv2.fillPoly(big, [points], 255, lineType=cv2.LINE_AA)
    # 가장자리 어두운 테두리(배경 섞인 픽셀)를 1px 안쪽으로
    big = cv2.erode(big, np.ones((SUPER + 1, SUPER + 1), np.uint8))
    return cv2.resize(big, (w, h), interpolation=cv2.INTER_AREA)


def refine(set_id: str, step: int, session) -> None:
    src = Image.open(os.path.join(HERE, set_id, "9x16", f"{step}.png")).convert("RGB")
    rgb = np.array(src)
    alpha = np.array(remove(src, session=session))[:, :, 3]
    mask = cut_bottom(fill_rim(silhouette(alpha)), alpha)
    # 바닥 호가 옆면과 만나 생긴 뾰족한 모서리를 둥글게(원래 잔 바닥은 둥글다).
    mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (CORNER * 2 + 1, CORNER * 2 + 1)))
    new_alpha = smooth_outline(mask)
    Image.fromarray(np.dstack([rgb, new_alpha])).save(os.path.join(OUT, f"cutout-{set_id}-{step}.png"), optimize=True)


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    session = new_session("u2net")
    only = sys.argv[1:]  # 예: strawberry-latte:100
    for set_id in SETS:
        for step in STEPS:
            if only and f"{set_id}:{step}" not in only:
                continue
            refine(set_id, step, session)
            print("done", set_id, step)


if __name__ == "__main__":
    main()
