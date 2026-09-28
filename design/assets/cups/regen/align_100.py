# 다시 뽑은 100% 사진(80% 원본을 입력으로 편집)을 80% 원본의 잔 위치·크기에 맞춘다.
# 편집 모델이 잔을 약 7% 키우고 조금 올려서, 누끼로 잔 테두리 폭·가운데·바닥을 재 맞춘다.
# 그다음 80%와 같은 변환(transforms.json "80")으로 9x16을 만든다.
import json
import os
import sys

import numpy as np
from PIL import Image
from rembg import new_session, remove

HERE = os.path.dirname(os.path.abspath(__file__))
CUPS = os.path.dirname(HERE)


def glass_mask(img: Image.Image, session) -> np.ndarray:
    return (np.array(remove(img, session=session))[:, :, 3] > 128).astype(np.uint8)


def best_fit(ref: np.ndarray, new: np.ndarray) -> tuple[float, int, int]:
    """아래쪽 잔 모양(참조 잔 높이의 아래 65%)이 가장 많이 겹치는 배율·이동을 찾는다(1/4 크기에서 탐색)."""
    import cv2
    q = 4
    r = cv2.resize(ref, (ref.shape[1] // q, ref.shape[0] // q), interpolation=cv2.INTER_NEAREST).astype(bool)
    n = cv2.resize(new, (new.shape[1] // q, new.shape[0] // q), interpolation=cv2.INTER_NEAREST)
    ys, _ = np.nonzero(r)
    cut = int(ys.min() + (ys.max() - ys.min()) * 0.35)
    r[:cut] = False
    ry, rx = np.nonzero(r)
    best = (0.0, 1.0, 0, 0)
    for scale in np.arange(0.84, 1.06, 0.005):
        m = cv2.resize(n, (round(n.shape[1] * scale), round(n.shape[0] * scale)), interpolation=cv2.INTER_NEAREST).astype(bool)
        my, mx = np.nonzero(m)
        base_dx = int(round(rx.mean() - mx.mean()))
        base_dy = int(round(ry.max() - my.max()))
        for ddx in range(-6, 7):
            for ddy in range(-6, 7):
                dx, dy = base_dx + ddx, base_dy + ddy
                canvas = np.zeros_like(r)
                y0, x0 = max(0, dy), max(0, dx)
                y1, x1 = min(r.shape[0], dy + m.shape[0]), min(r.shape[1], dx + m.shape[1])
                canvas[y0:y1, x0:x1] = m[y0 - dy:y1 - dy, x0 - dx:x1 - dx]
                canvas[:cut] = False
                iou = (canvas & r).sum() / max(1, (canvas | r).sum())
                if iou > best[0]:
                    best = (iou, float(scale), dx * q, dy * q)
    print(f"iou {best[0]:.4f} scale {best[1]:.3f} dx {best[2]} dy {best[3]}")
    return best[1], best[2], best[3]


def rim_top(img: Image.Image, x0: int, x1: int) -> float:
    """잔 뒤쪽 테두리 윗선의 높이(벽보다 뚜렷이 어두운 선이 처음 나오는 줄, 가운데 여러 열의 중간값)."""
    lum = np.array(img.convert("L"), float)
    ys, _ = np.nonzero(lum < 0)  # 자리 채움
    wall = float(np.median(lum[200:400, x0:x1]))
    tops = []
    for x in range(x0, x1, 20):
        dark = lum[300:1400, x] < wall - 25
        edge = np.nonzero(dark[:-1] & dark[1:])[0]
        if edge.size:
            tops.append(300 + edge.min())
    return float(np.median(tops))


def main() -> None:
    new_path, set_id = sys.argv[1], sys.argv[2]
    session = new_session("u2net")
    ref = Image.open(os.path.join(CUPS, "iced-americano", "original", "80.png")).convert("RGB")
    new = Image.open(new_path).convert("RGB").resize(ref.size)
    scale, dx, dy = best_fit(glass_mask(ref, session), glass_mask(new, session))
    scaled = new.resize((round(new.width * scale), round(new.height * scale)), Image.LANCZOS)
    # 가장자리가 비지 않게 새 사진을 먼저 깔고 맞춘 사진을 얹는다
    canvas = new.copy()
    canvas.paste(scaled, (dx, dy))
    # 편집 모델이 잔 비율을 조금 짧게 바꿨다. 바닥은 맞췄으니 바닥 기준으로 세로만 늘려 테두리 높이를 맞춘다.
    ref_mask = glass_mask(ref, session)
    ys, xs = np.nonzero(ref_mask)
    bottom = float(ys.max())
    cx0, cx1 = int(xs.mean() - 90), int(xs.mean() + 90)
    ref_rim, new_rim = rim_top(ref, cx0, cx1), rim_top(canvas, cx0, cx1)
    stretch = (bottom - ref_rim) / (bottom - new_rim)
    print(f"rim ref {ref_rim:.0f} new {new_rim:.0f} bottom {bottom:.0f} -> vertical stretch {stretch:.4f}")
    tall = canvas.resize((canvas.width, round(canvas.height * stretch)), Image.LANCZOS)
    top = round(bottom * stretch - bottom)
    canvas = tall.crop((0, top, canvas.width, top + canvas.height))
    out_original = os.path.join(CUPS, set_id, "original", "100.png")
    canvas.save(out_original)
    t = json.load(open(os.path.join(CUPS, "transforms.json")))["80"]
    big = canvas.resize((round(2048 * t["scale"]), round(2048 * t["scale"])), Image.LANCZOS)
    big.crop((t["dx"], t["dy"], t["dx"] + 937, t["dy"] + 1666)).save(os.path.join(CUPS, set_id, "9x16", "100.png"))
    print("saved", out_original)


if __name__ == "__main__":
    main()
