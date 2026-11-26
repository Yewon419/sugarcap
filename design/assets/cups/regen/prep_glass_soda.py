# 유리 과일 소다 v2(2026-11-26 대표님 "퀄리티가 너무 구려서 다시 뽑자", 비글루 스튜디오 생성) 단계 사진을
# make_glass_set.py가 받는 2048 정사각 후보(candidates/<단계>_a.png)로 옮긴다.
# 새 사진은 단계마다 크기(1024 정사각, 100%만 800×1424)와 잔 자리가 달라, 9x16 캔버스(937×1666)에서
# 아메리카노 0% 누끼 윤곽에 맞는 배율·이동(PHOTO_FIT)을 먼저 정하고, make_glass_set.py의 자르기
# (transforms.json "0"의 scale·dx·dy)를 거꾸로 걸어 후보를 쓴다. 그래서 make_glass_set.py의 FIT은 1이다.
# PHOTO_FIT: 입구 꼭대기(캔버스 y 428)는 윤곽 전체를 밝기 기울기에 맞춰 찾았고, 바깥 바닥(y 1460)은
# 사진에서 눈으로 쟀다(30·50·80·100 = 855.5·833·847·1059). 가로는 옆선(y 520~1300)을 기울기에 맞췄다.
#
# 사용: python prep_glass_soda.py   (시스템 파이썬 3.12, cv2)
from __future__ import annotations

import json
import os

import cv2
import numpy as np
from numpy.typing import NDArray

CUPS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SET_ID = "glass-soda"
SIDE = 2048
# 단계 사진 → 9x16 캔버스: (가로 배율, 세로 배율, x 이동, y 이동).
PHOTO_FIT: dict[int, tuple[float, float, float, float]] = {
    30: (1.47546, 1.60549, -276.559, 86.505),
    50: (1.63816, 1.76195, -366.013, -7.703),
    80: (1.57143, 1.55702, -330.857, 141.200),
    100: (1.43953, 1.47131, -114.442, -98.122),
}


def photo_to_candidate(step: int) -> NDArray[np.float32]:
    """단계 사진 좌표 → 2048 후보 좌표 아핀 행렬."""
    with open(os.path.join(CUPS, "transforms.json")) as f:
        t = json.load(f)["0"]
    k = round(SIDE * t["scale"]) / SIDE
    sx, sy, tx, ty = PHOTO_FIT[step]
    return np.array(
        [[sx / k, 0, (tx + t["dx"]) / k], [0, sy / k, (ty + t["dy"]) / k]],
        dtype=np.float32,
    )


def main() -> None:
    out_dir = os.path.join(CUPS, SET_ID, "candidates")
    os.makedirs(out_dir, exist_ok=True)
    for step in PHOTO_FIT:
        path = os.path.join(CUPS, SET_ID, "source", f"{step}.jpg")
        img = cv2.imdecode(np.fromfile(path, dtype=np.uint8), cv2.IMREAD_COLOR)
        if img is None:
            raise FileNotFoundError(path)
        out = cv2.warpAffine(
            img,
            photo_to_candidate(step),
            (SIDE, SIDE),
            flags=cv2.INTER_LANCZOS4,
            borderMode=cv2.BORDER_REPLICATE,
        )
        ok, buf = cv2.imencode(".png", out)
        if not ok:
            raise RuntimeError(f"PNG 인코딩 실패: {step}")
        buf.tofile(os.path.join(out_dir, f"{step}_a.png"))
        print(step, img.shape[1::-1], "->", (SIDE, SIDE))


if __name__ == "__main__":
    main()
