# 오늘 화면 큰 숫자(CupHero)를 가리는 토핑 마스크 만들기(대표님 베타 피드백 2026-10-31, 빌드 362
# "망고랑 이파리 글자 위에 올라가게", "크림이 글자 위로").
# 숫자는 잔 뒤에 서 있다. 유리는 비치니 유리 선만 숫자를 끊지만(`make_rim_lines.py`), 입구 위로 솟거나 입구를 채운
# 불투명한 토핑(과일·잎·크림·시럽)은 숫자를 통째로 가린다.
# 세 가지 단서를 합친다.
#   1) 색: 채도가 높거나 어두운 픽셀(망고·잎·초코 시럽). 흰 벽·유리는 무채색·밝음이라 안 걸린다.
#   2) 누끼: 이 단계 누끼에서 빈 잔(0%) 누끼를 뺀 곳 = 잔 밖으로 솟은 것(프라페 크림 산).
#      망고는 누끼가 입구에서 잘려 있어 1)로 잡는다.
#   3) 흰 크림 윗면: 벽과 색이 같아 1)·2)로 못 잡는다. `SURFACE`에 잰 크림 윗면(사진 높이 비율)부터
#      입구 타원 안을 채운다. 크림 윗면 타원은 입구 타원을 그만큼 내린 것으로 본다.
# 숫자 바닥(사진 0.33) 아래는 숫자가 없어 자른다. 산출물 = 흰색 + 알파 PNG, 원본 캔버스 그대로.
# 토핑이 없는 단계는 에셋을 만들지 않는다(앱은 `topping-*`이 있을 때만 그린다).
#
# 사용: python make_hero_toppings.py   (cv2 필요, 리포 .venv에는 없어 시스템 파이썬)
from __future__ import annotations

import json
import os
import shutil

import cv2
import numpy as np
from numpy.typing import NDArray

from make_rim_lines import fit_rim, read_image, smooth_edges, write_image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
ASSETS = os.path.join(REPO, "SugarCap", "Resources", "Assets.xcassets")
STEPS = (30, 50, 80, 100)
# 토핑이 숫자 자리까지 올라오는 세트만. 나머지 세트는 수면이 숫자 바닥보다 아래다.
SETS = ("choco-frappe", "mango", "einspanner")
# 세트 → 단계 → 흰 크림 윗면(사진 높이 비율, 가운데 열). `IdleCast.swift` `liquid`와 같은 값이고, 프라페 100%는
# 크림이 입구를 덮어 입구 뒤 가장자리(`chocoFrappe.rim[100].back`, 아메리카노 잔 값)를 쓴다.
SURFACE: dict[str, dict[int, float]] = {
    "einspanner": {80: 0.32, 100: 0.30},
    "choco-frappe": {100: 0.2683},
}
BOTTOM = 0.33  # 숫자 바닥(CupHero.baselineRatio 0.328) 바로 아래
SATURATION = 70  # HSV S(0~255). 이보다 진하면 토핑 색
DARK = 110  # HSV V. 이보다 어두우면 토핑(초코 시럽)
CLOSE = 7  # 토핑 덩어리 안 틈(망고 조각 사이 하이라이트 등)을 메우는 지름(px)
SPECK = 300  # 이보다 작은 덩어리(px)는 잡티
RISEN_MARGIN = 4  # 누끼 차이를 보는 아래끝 = 입구 타원 위끝 - 이 값(px)


def photo_path(cup_set: str, step: int) -> str:
    folder = os.path.join(ASSETS, f"cup-{cup_set}-{step}.imageset")
    names = [n for n in os.listdir(folder) if n.endswith((".png", ".jpg"))]
    if len(names) != 1:
        raise RuntimeError(f"단계 사진이 1장이 아님: {folder} {names}")
    return os.path.join(folder, names[0])


def cutout_alpha(cup_set: str, step: int) -> NDArray[np.uint8]:
    path = os.path.join(ASSETS, f"cutout-{cup_set}-{step}.imageset", f"{step}.png")
    img = read_image(path, cv2.IMREAD_UNCHANGED)
    if img.ndim != 3 or img.shape[2] != 4:
        raise RuntimeError(f"누끼에 알파가 없음: {path}")
    return np.asarray(img[:, :, 3], dtype=np.uint8)


def rim_ellipse(
    cup_set: str, step: int
) -> tuple[tuple[float, float], tuple[float, float], float]:
    path = os.path.join(ASSETS, f"rimline-{cup_set}-{step}.imageset", f"{step}.png")
    alpha = read_image(path, cv2.IMREAD_UNCHANGED)[:, :, 3]
    return fit_rim(alpha > 128)


def surface_fill(
    shape: tuple[int, int],
    ellipse: tuple[tuple[float, float], tuple[float, float], float],
    surface: float,
) -> NDArray[np.bool_]:
    """입구 타원 안에서 크림 윗면 타원(입구 타원을 윗면까지 내린 것)의 위끝 아래를 채운다."""
    height = shape[0]
    (cx, cy), (w, h), angle = ellipse
    opening = np.zeros(shape, dtype=np.uint8)
    cv2.ellipse(opening, ((cx, cy), (w, h), angle), 1, -1)
    back = cy - min(w, h) / 2  # 입구 뒤 가장자리(가운데 열) ≈ 타원 위끝
    drop = surface * height - back
    lowered = np.zeros(shape, dtype=np.uint8)
    cv2.ellipse(lowered, ((cx, cy + drop), (w, h), angle), 1, -1)
    below = np.zeros(shape, dtype=bool)
    below[int(cy + drop) :, :] = True
    return (opening > 0) & ((lowered > 0) | below)


def topping(cup_set: str, step: int) -> NDArray[np.uint8]:
    photo = read_image(photo_path(cup_set, step), cv2.IMREAD_COLOR)
    height, width = photo.shape[:2]
    cut = cutout_alpha(cup_set, step)
    empty = cutout_alpha(cup_set, 0)
    if cut.shape != (height, width) or empty.shape != (height, width):
        raise RuntimeError(f"누끼와 사진 크기가 다름: {cup_set} {step}")
    hsv = cv2.cvtColor(photo, cv2.COLOR_BGR2HSV)
    colored = (hsv[:, :, 1] > SATURATION) | (hsv[:, :, 2] < DARK)
    # 누끼 차이는 입구 타원 위끝보다 위에서만 본다. 아래에서는 단계마다 잔 자리가 몇 px 어긋나
    # 유리 테두리 띠가 통째로 잡혔다(프라페 30~80, 망고·아인슈페너 50 오른쪽 끝).
    ellipse = rim_ellipse(cup_set, step)
    (_, cy), (ew, eh), _ = ellipse
    risen = (cut > 128) & (empty <= 128)
    risen[max(0, int(cy - min(ew, eh) / 2) - RISEN_MARGIN) :, :] = False
    mask = colored | risen
    surface = SURFACE.get(cup_set, {}).get(step)
    if surface is not None:
        mask |= surface_fill((height, width), ellipse, surface)
    mask[int(BOTTOM * height) :, :] = False
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (CLOSE, CLOSE))
    solid = cv2.morphologyEx(mask.astype(np.uint8), cv2.MORPH_CLOSE, kernel)
    count, labels, stats, _ = cv2.connectedComponentsWithStats(solid, connectivity=8)
    keep = np.zeros(count, dtype=bool)
    keep[1:] = stats[1:, cv2.CC_STAT_AREA] >= SPECK
    kept = keep[labels]
    # 덩어리 안 구멍(크림 결 사이 밝은 틈)을 메운다.
    filled = kept.astype(np.uint8)
    flood = filled.copy()
    pad = np.zeros((height + 2, width + 2), dtype=np.uint8)
    cv2.floodFill(flood, pad, (0, 0), 1)
    filled = filled | (1 - flood)
    filled[int(BOTTOM * height) :, :] = 0
    return (smooth_edges(filled > 0) * 255).astype(np.uint8)


def main() -> None:
    for cup_set in SETS:
        for step in STEPS:
            alpha = topping(cup_set, step)
            folder = os.path.join(ASSETS, f"topping-{cup_set}-{step}.imageset")
            pixels = int((alpha > 0).sum())
            if pixels == 0:
                if os.path.isdir(folder):
                    shutil.rmtree(folder)
                print(cup_set, step, "없음")
                continue
            out = np.zeros((*alpha.shape, 4), dtype=np.uint8)
            out[:, :, :3] = 255
            out[:, :, 3] = alpha
            os.makedirs(folder, exist_ok=True)
            write_image(os.path.join(folder, f"{step}.png"), out)
            contents = {
                "images": [{"filename": f"{step}.png", "idiom": "universal"}],
                "info": {"author": "xcode", "version": 1},
            }
            with open(
                os.path.join(folder, "Contents.json"),
                "w",
                encoding="utf-8",
                newline="\n",
            ) as f:
                json.dump(contents, f, indent=2)
                f.write("\n")
            print(cup_set, step, pixels)


if __name__ == "__main__":
    main()
