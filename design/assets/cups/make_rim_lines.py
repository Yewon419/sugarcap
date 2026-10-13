# 오늘 화면 큰 숫자(CupHero)를 끊는 유리 선 마스크 만들기(2026-10-13 대표님 시안).
# 숫자는 유리 너머로 그대로 비치고, 입구 앞·뒤 호와 벽 선만 숫자를 지운다.
# 단계 사진에서 주변보다 어두운 가는 줄(블랙햇)을 오린 잔 윤곽 안, 입구 위끝 ~ 숫자 바닥(사진 높이 0.33)까지만 뽑는다.
# 유리 안쪽 잡티(작은 점)는 넓이로 거른다. 선은 잔 안쪽으로만 두껍게 키워 유리 두께의 반사 빛 띠처럼 보이게 한다
# (대표님 "컵 경계 안쪽으로 반사 빛을 표현하기 위해 원본처럼 좀 더 두껍게", 시안 틈 약 3.5pt = 캔버스 8px).
# 산출물 = 흰색 + 알파(선 세기) PNG, 원본 캔버스(937×1666) 그대로.
#
# 사용: python make_rim_lines.py
from __future__ import annotations

import json
import os

import cv2
import numpy as np
from numpy.typing import NDArray

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
ASSETS = os.path.join(REPO, "SugarCap", "Resources", "Assets.xcassets")
SETS = ("strawberry-latte", "iced-americano")
STEPS = (0, 30, 50, 80, 100)
RIDGE = 15  # 이보다 가는 어두운 줄만 선으로 본다(블랙햇 커널). 벽 안쪽의 넓은 회색 음영은 빠진다
FLOOR = 4  # 주변보다 이만큼 어두워야 선
RAMP = 6  # 여기서부터 선 세기 1. 좁게 둬서 가장자리가 또렷하다(에어브러시 금지)
BOTTOM = 0.33  # 숫자 바닥(CupHero.baseline 0.322) 바로 아래. 음료 윗면(가장 높은 곳 0.331)보다 위
SPECK = 60  # 이보다 작은 덩어리(px)는 유리 안쪽 잡티
THICKEN = 11  # 선을 잔 안쪽으로 넓히는 지름(px). 반지름 5 = 선 2~4px → 7~9px


def read_image(path: str, flags: int) -> NDArray[np.uint8]:
    img = cv2.imdecode(np.fromfile(path, dtype=np.uint8), flags)  # 한글 경로
    if img is None:
        raise FileNotFoundError(path)
    return np.asarray(img, dtype=np.uint8)


def write_image(path: str, img: NDArray[np.uint8]) -> None:
    ok, buf = cv2.imencode(".png", img)
    if not ok:
        raise RuntimeError(f"PNG 인코딩 실패: {path}")
    buf.tofile(path)


def photo_path(cup_set: str, step: int) -> str:
    folder = os.path.join(ASSETS, f"cup-{cup_set}-{step}.imageset")
    names = [n for n in os.listdir(folder) if n.endswith(".png")]
    if len(names) != 1:
        raise RuntimeError(f"단계 사진이 1장이 아님: {folder} {names}")
    return os.path.join(folder, names[0])


def rim_lines(photo: NDArray[np.uint8], cutout_alpha: NDArray[np.uint8]) -> NDArray[np.uint8]:
    gray = cv2.cvtColor(photo, cv2.COLOR_BGR2GRAY)
    height = gray.shape[0]
    ridge = cv2.morphologyEx(gray, cv2.MORPH_BLACKHAT, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (RIDGE, RIDGE)))
    strength = np.clip((ridge.astype(np.float32) - FLOOR) / RAMP, 0.0, 1.0)
    rows = np.where(cutout_alpha.max(axis=1) > 128)[0]
    if rows.size == 0:
        raise RuntimeError("오린 잔이 비어 있음")
    # 잔 윤곽 안쪽만. 바깥으로는 파지 않는다(대표님 "컵 바깥쪽으로 파진 말고").
    core = cutout_alpha > 128
    band = np.zeros_like(core)
    band[int(rows[0]) : int(BOTTOM * height)] = True
    strength = strength * (core & band)
    count, labels, stats, _ = cv2.connectedComponentsWithStats((strength > 0.5).astype(np.uint8), connectivity=8)
    keep = np.zeros(count, dtype=bool)
    keep[1:] = stats[1:, cv2.CC_STAT_AREA] >= SPECK
    solid = cv2.dilate(keep[labels].astype(np.uint8), np.ones((3, 3), np.uint8)) > 0
    lines = strength * solid
    grow = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (THICKEN, THICKEN))
    thick = cv2.dilate(lines, grow) * (core & band)
    return (np.maximum(lines, thick) * 255).astype(np.uint8)


def main() -> None:
    for cup_set in SETS:
        for step in STEPS:
            photo = read_image(photo_path(cup_set, step), cv2.IMREAD_COLOR)
            cut = read_image(
                os.path.join(ASSETS, f"cutout-{cup_set}-{step}.imageset", f"{step}.png"), cv2.IMREAD_UNCHANGED
            )
            if cut.shape[:2] != photo.shape[:2] or cut.shape[2] != 4:
                raise RuntimeError(f"오린 잔과 사진 크기가 다름: {cup_set} {step}")
            alpha = rim_lines(photo, cut[:, :, 3])
            out = np.zeros((*alpha.shape, 4), dtype=np.uint8)
            out[:, :, :3] = 255
            out[:, :, 3] = alpha
            folder = os.path.join(ASSETS, f"rimline-{cup_set}-{step}.imageset")
            os.makedirs(folder, exist_ok=True)
            write_image(os.path.join(folder, f"{step}.png"), out)
            contents = {
                "images": [{"filename": f"{step}.png", "idiom": "universal"}],
                "info": {"author": "xcode", "version": 1},
            }
            with open(os.path.join(folder, "Contents.json"), "w", encoding="utf-8", newline="\n") as f:
                json.dump(contents, f, indent=2)
                f.write("\n")
            print(cup_set, step, int((alpha > 0).sum()))


if __name__ == "__main__":
    main()
