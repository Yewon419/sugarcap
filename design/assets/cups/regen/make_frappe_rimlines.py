# 초코 프라페 유리선(rimline). 입구 높이가 아메리카노와 맞아서 유리선은 아메리카노 빈 잔 것을 쓰고,
# 크림·음료처럼 불투명한 덩어리(빈 잔 사진과 크게 다른 곳)는 숫자를 가리게 더한다.
# make_rim_lines.py를 그대로 돌리면 시럽 줄기·크림 시럽 선을 유리선으로 잡아 숫자가 얼룩덜룩 지워진다.
import os

import cv2
import numpy as np

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(
    HERE, "..", "..", "..", "SugarCap", "Resources", "Assets.xcassets"
)
BOTTOM = 0.33  # make_rim_lines.BOTTOM과 같다
DIFF = 40  # 빈 잔과 이만큼 다르면 내용물
OPEN = 21  # 이보다 가는 것(시럽 줄기)은 뺀다
MIN_AREA = 1500


def read(path: str, flags: int) -> np.ndarray:
    image = cv2.imdecode(np.fromfile(path, dtype=np.uint8), flags)
    if image is None:
        raise RuntimeError(f"image decode failed: {path}")
    return image


def main() -> None:
    # 내용물 기준은 같은 잔의 프라페 빈 잔(align_frappe_empty). 입구 고리는 위치가 맞아 아메리카노 것을 그대로 쓴다.
    empty = read(
        os.path.join(HERE, "choco-frappe", "9x16", "0.png"), cv2.IMREAD_COLOR
    ).astype(np.int16)
    rim = read(
        os.path.join(ASSETS, "rimline-iced-americano-0.imageset", "0.png"),
        cv2.IMREAD_UNCHANGED,
    )[:, :, 3]
    h = empty.shape[0]
    for step in (0, 30, 50, 80, 100):
        photo = read(
            os.path.join(HERE, "choco-frappe", "9x16", f"{step}.png"), cv2.IMREAD_COLOR
        ).astype(np.int16)
        cut = read(
            os.path.join(HERE, "cutouts", f"cutout-choco-frappe-{step}.png"),
            cv2.IMREAD_UNCHANGED,
        )[:, :, 3]
        diff = np.abs(photo - empty).max(axis=2)
        content = ((diff > DIFF) & (cut > 128)).astype(np.uint8)
        content[int(BOTTOM * h) :] = 0
        content = cv2.morphologyEx(
            content,
            cv2.MORPH_OPEN,
            cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (OPEN, OPEN)),
        )
        n, labels, stats, _ = cv2.connectedComponentsWithStats(content, connectivity=8)
        keep = np.zeros(n, dtype=bool)
        keep[1:] = stats[1:, cv2.CC_STAT_AREA] >= MIN_AREA
        content = cv2.morphologyEx(
            keep[labels].astype(np.uint8), cv2.MORPH_CLOSE, np.ones((15, 15), np.uint8)
        )
        soft = cv2.GaussianBlur(content.astype(np.float32), (0, 0), 1.2)
        alpha = np.maximum(rim.astype(np.float32), soft * cut.astype(np.float32))
        out = np.zeros((*alpha.shape, 4), dtype=np.uint8)
        out[:, :, :3] = 255
        out[:, :, 3] = np.clip(alpha, 0, 255).astype(np.uint8)
        ok, buf = cv2.imencode(".png", out)
        if not ok:
            raise RuntimeError(f"png encode failed: {step}")
        buf.tofile(
            os.path.join(ASSETS, f"rimline-choco-frappe-{step}.imageset", f"{step}.png")
        )
        print(step, int((out[:, :, 3] > 0).sum()))


if __name__ == "__main__":
    main()
