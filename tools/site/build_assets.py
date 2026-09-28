# 웹사이트(site/) 히어로용 컵 에셋 만들기.
# 단계 사진(cups/<세트>/9x16/<단계>.png)을 잔 영역으로 잘라 webp로, 앱 대기 루프 패치를 사진 위에 합성해
# H.264 mp4(1회 루프, 10fps)로 쓴다. 앱과 같은 합성 방식이라 사진과 영상이 겹쳐도 이음새가 없다.
# 사용: python tools/site/build_assets.py   (시스템 python. 리포 .venv에는 Pillow·cv2가 없다)
from __future__ import annotations

import json
import os
import subprocess

import cv2
import numpy as np
from numpy.typing import NDArray
from PIL import Image

REPO = os.path.abspath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
)
CUPS = os.path.join(REPO, "design", "assets", "cups")
RES = os.path.join(REPO, "SugarCap", "Resources")
OUT = os.path.join(REPO, "site", "assets", "cups")
SETS = {"strawberry-latte": "latte", "iced-americano": "americano"}
STEPS = [0, 30, 50, 80, 100]
# 원본 캔버스(937×1666)에서 잔·받침이 들어오는 영역. 위 여백은 벽이라 페이지 배경색으로 대신한다.
CROP = (96, 330, 744, 1336)  # x, y, w, h
WIDTH = 720


def read(path: str, flags: int) -> NDArray[np.uint8]:
    img = cv2.imdecode(np.fromfile(path, dtype=np.uint8), flags)
    if img is None:
        raise FileNotFoundError(path)
    return np.asarray(img, dtype=np.uint8)


def crop(img: NDArray[np.uint8]) -> NDArray[np.uint8]:
    x, y, w, h = CROP
    part = img[y : y + h, x : x + w]
    height = round(h * WIDTH / w) & ~1
    return np.asarray(
        cv2.resize(part, (WIDTH, height), interpolation=cv2.INTER_AREA), dtype=np.uint8
    )


def write_photo(set_id: str, step: int) -> NDArray[np.uint8]:
    src = read(os.path.join(CUPS, set_id, "9x16", f"{step}.png"), cv2.IMREAD_COLOR)
    rgb = cv2.cvtColor(crop(src), cv2.COLOR_BGR2RGB)
    Image.fromarray(rgb).save(
        os.path.join(OUT, f"{SETS[set_id]}-{step}.webp"), quality=82, method=6
    )
    return src


def write_idle(set_id: str, step: int, src: NDArray[np.uint8]) -> None:
    name = f"cup-{set_id}-{step}"
    video = os.path.join(RES, "CupIdle", f"{name}-idle.mp4")
    if not os.path.exists(video):
        return
    mask_png = os.path.join(
        RES, "Assets.xcassets", f"{name}-idle-mask.imageset", "mask.png"
    )
    mask = (
        read(mask_png, cv2.IMREAD_UNCHANGED)[:, :, 3].astype(np.float32)[..., None]
        / 255
    )
    with open(
        os.path.join(RES, "CupIdle", f"{name}-idle.json"), encoding="utf-8"
    ) as fh:
        rect = json.load(fh)
    x, y, w, h = rect["x"], rect["y"], rect["width"], rect["height"]
    cap = cv2.VideoCapture(video)
    first = crop(src)
    out = os.path.join(OUT, f"{SETS[set_id]}-{step}-idle.mp4")
    cmd = [
        "ffmpeg", "-y", "-loglevel", "error",
        "-f", "rawvideo", "-pix_fmt", "bgr24", "-s", f"{first.shape[1]}x{first.shape[0]}", "-r", "10", "-i", "-",
        "-an", "-c:v", "libx264", "-preset", "slow", "-crf", "26", "-pix_fmt", "yuv420p",
        "-movflags", "+faststart", out,
    ]  # fmt: skip
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    if proc.stdin is None:
        raise RuntimeError("ffmpeg stdin unavailable")
    base = src.astype(np.float32)
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        canvas = base.copy()
        region = canvas[y : y + h, x : x + w]
        canvas[y : y + h, x : x + w] = (
            region * (1 - mask) + frame.astype(np.float32) * mask
        )
        proc.stdin.write(np.ascontiguousarray(crop(canvas.astype(np.uint8))).tobytes())
    proc.stdin.close()
    if proc.wait() != 0:
        raise RuntimeError(f"ffmpeg failed: {out}")


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    for set_id in SETS:
        for step in STEPS:
            src = write_photo(set_id, step)
            write_idle(set_id, step, src)
            print("done", set_id, step)


if __name__ == "__main__":
    main()
