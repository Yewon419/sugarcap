# 대기 영상이 없는 잔의 물방울 층 만들기(대표님 2026-11-03 "원래 물방울 없는 사진에 있는 사진을 얹어놓고 서서히 보이게").
# 입력 = Seedream 5.0 lite로 단계 사진에 물방울만 더한 편집본(`<세트>/condense/<단계>.png`, 힉스필드 웹 Unlimited).
# 편집본은 잔 크기·위치가 몇 % 어긋나고 음료색이 바래서 그대로 못 쓴다.
#   1) 편집본을 단계 사진에 어파인으로 맞춘다(ECC, 흐린 회색조).
#   2) 큰 흐림(SIGMA)끼리의 비로 저주파 색을 원본에 맞춘다. 방울 모양·하이라이트(고주파)는 편집본 그대로.
#   3) 누끼 잔 안, `TOP`(px) 아래만 남긴다. 위쪽(망고·민트·입구)은 원본 픽셀이 보이게 비운다.
# 산출물 = `condense-<세트>-<단계>` 이미지셋, 원본 캔버스 크기 RGBA. 앱(`CupCondensation`)이 단계 사진 위에 얹고
# 투명도를 0에서 1로 올린다.
#
# 사용: python make_condense.py   (cv2 필요, 리포 .venv에는 없어 시스템 파이썬)
from __future__ import annotations

import json
import os

import cv2
import numpy as np
from numpy.typing import NDArray

from make_rim_lines import photo_path, read_image, write_image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
ASSETS = os.path.join(REPO, "SugarCap", "Resources", "Assets.xcassets")
# 세트 → 단계 → 물방울이 시작하는 높이(px). 망고 100%는 입구 위로 솟은 망고 조각 아래 끝.
TOP: dict[str, dict[int, int]] = {
    "mango": {30: 1090, 50: 940, 80: 780, 100: 640},
    "choco-frappe": {30: 1020, 50: 690, 80: 575, 100: 560},
}
SIGMA = (
    30  # 색 맞춤 흐림(px). 방울(지름 5~40px)보다 커야 방울이 색 보정에 먹히지 않는다.
)
FEATHER = 50  # TOP에서 이만큼 아래까지 서서히 드러난다(px)
EDGE = 3  # 누끼 경계 흐림(px)


def aligned(
    photo: NDArray[np.float32], edit: NDArray[np.float32]
) -> NDArray[np.float32]:
    def gray(img: NDArray[np.float32]) -> NDArray[np.float32]:
        return np.asarray(
            cv2.GaussianBlur(cv2.cvtColor(img, cv2.COLOR_BGR2GRAY), (0, 0), 3) / 255,
            dtype=np.float32,
        )

    criteria = (cv2.TERM_CRITERIA_EPS | cv2.TERM_CRITERIA_COUNT, 200, 1e-6)
    score, warp = cv2.findTransformECC(
        gray(photo),
        gray(edit),
        np.eye(2, 3, dtype=np.float32),
        cv2.MOTION_AFFINE,
        criteria,
    )
    if score < 0.95:
        raise RuntimeError(f"편집본이 단계 사진과 안 맞음(ECC {score:.3f})")
    h, w = photo.shape[:2]
    out = cv2.warpAffine(
        edit,
        warp,
        (w, h),
        flags=cv2.INTER_LINEAR + cv2.WARP_INVERSE_MAP,
        borderMode=cv2.BORDER_REPLICATE,
    )
    return np.asarray(out, dtype=np.float32)


def layer(cup_set: str, step: int, top: int) -> NDArray[np.uint8]:
    photo = read_image(photo_path(cup_set, step), cv2.IMREAD_COLOR).astype(np.float32)
    h, w = photo.shape[:2]
    raw = read_image(
        os.path.join(HERE, cup_set, "condense", f"{step}.png"), cv2.IMREAD_COLOR
    )
    edit = aligned(
        photo, cv2.resize(raw, (w, h), interpolation=cv2.INTER_AREA).astype(np.float32)
    )
    ratio = (cv2.GaussianBlur(photo, (0, 0), SIGMA) + 1) / (
        cv2.GaussianBlur(edit, (0, 0), SIGMA) + 1
    )
    color = np.clip(edit * ratio, 0, 255)
    cutout = read_image(
        os.path.join(ASSETS, f"cutout-{cup_set}-{step}.imageset", f"{step}.png"),
        cv2.IMREAD_UNCHANGED,
    )
    glass = cv2.GaussianBlur((cutout[:, :, 3] > 128).astype(np.float32), (0, 0), EDGE)
    rows = np.arange(h, dtype=np.float32)[:, None]
    alpha = glass * np.clip((rows - top) / FEATHER, 0, 1)
    out = np.zeros((h, w, 4), dtype=np.uint8)
    out[:, :, :3] = color.astype(np.uint8)
    out[:, :, 3] = (alpha * 255).astype(np.uint8)
    out[out[:, :, 3] == 0] = 0  # 빈 곳 색을 비워 PNG를 줄인다
    return out


def main() -> None:
    for cup_set, steps in TOP.items():
        for step, top in steps.items():
            folder = os.path.join(ASSETS, f"condense-{cup_set}-{step}.imageset")
            os.makedirs(folder, exist_ok=True)
            write_image(os.path.join(folder, f"{step}.png"), layer(cup_set, step, top))
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
            print(cup_set, step, folder)


if __name__ == "__main__":
    main()
