# 컵 대기 루프(SPEC §9-10) 앱 번들용 패치 만들기.
# AI 영상(첫·끝 프레임 = 단계 원본 사진, 9x16)을 원본 캔버스(937×1666)에 맞춘 뒤,
# 얼음이 움직이는 윗부분 사각형만 잘라 HEVC로 쓰고, 같은 사각형의 마스크(오린 컵 윤곽 기반)를 PNG로 쓴다.
# 앱 CupView는 오린 컵 위 같은 자리에 패치 영상을 마스크로 겹친다.
#
# 사용: python make_idle_patch.py <세트> <단계> <원본 AI 영상> [--slow 3] [--fps 10]
from __future__ import annotations

import argparse
import json
import os
import subprocess
import tempfile

import cv2
import numpy as np
from numpy.typing import NDArray

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
RES = os.path.join(REPO, "SugarCap", "Resources")
CANVAS_W, CANVAS_H = 937, 1666
MOTION_BOTTOM = 1000  # 이 아래(잠긴 얼음 아래·잔 바닥)는 움직임이 없어 패치에서 뺀다
FADE = 100  # 패치 아래쪽 경계를 녹이는 높이
GROW = 10  # 얼음이 돌며 윤곽 밖으로 나가는 만큼 마스크를 넓힌다


def read_image(path: str, flags: int) -> NDArray[np.uint8]:
    img = cv2.imdecode(np.fromfile(path, dtype=np.uint8), flags)  # 한글 경로
    if img is None:
        raise FileNotFoundError(path)
    return np.asarray(img, dtype=np.uint8)


def write_image(path: str, img: NDArray[np.uint8]) -> None:
    ok, buf = cv2.imencode(".png", img)
    if not ok:
        raise RuntimeError(f"png encode failed: {path}")
    buf.tofile(path)


def to_canvas(frame: NDArray[np.uint8]) -> NDArray[np.uint8]:
    """모델 출력은 원본을 폭 기준으로 줄이고 세로 가운데를 자른 것이다(첫 프레임 SIFT 정합으로 확인)."""
    h, w = frame.shape[:2]
    s = CANVAS_W / w
    oy = (CANVAS_H - h * s) / 2
    m = np.array([[s, 0, 0], [0, s, oy]], dtype=np.float32)
    out = cv2.warpAffine(
        frame,
        m,
        (CANVAS_W, CANVAS_H),
        flags=cv2.INTER_CUBIC,
        borderMode=cv2.BORDER_REPLICATE,
    )
    return np.asarray(out, dtype=np.uint8)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("set_id")
    ap.add_argument("step", type=int)
    ap.add_argument("video")
    ap.add_argument("--slow", type=float, default=3.0)
    ap.add_argument("--fps", type=int, default=10)
    args = ap.parse_args()

    name = f"cup-{args.set_id}-{args.step}"
    src = read_image(
        os.path.join(HERE, args.set_id, "9x16", f"{args.step}.png"), cv2.IMREAD_COLOR
    )
    cutout = read_image(
        os.path.join(HERE, "cutouts", f"cutout-{args.set_id}-{args.step}.png"),
        cv2.IMREAD_UNCHANGED,
    )
    alpha = cutout[:, :, 3]

    # 마스크: 컵 윤곽을 조금 넓히고 경계를 풀고, 아래쪽은 녹인다.
    grown = cv2.dilate(
        (alpha > 128).astype(np.uint8) * 255,
        np.ones((2 * GROW + 1, 2 * GROW + 1), np.uint8),
    )
    mask = cv2.GaussianBlur(grown, (0, 0), 4).astype(np.float32) / 255
    ramp = np.clip((MOTION_BOTTOM - np.arange(CANVAS_H, dtype=np.float32)) / FADE, 0, 1)
    mask *= ramp[:, None]
    ys, xs = np.nonzero(mask > 0.01)
    x0, y0 = int(xs.min()) & ~1, int(ys.min()) & ~1
    x1, y1 = (
        (int(xs.max()) + 2) & ~1,
        (int(ys.max()) + 2) & ~1,
    )  # HEVC 4:2:0은 짝수 크기
    rect = (x0, y0, x1 - x0, y1 - y0)

    # 영상 프레임 → 캔버스. 색 편차(재인코딩)는 첫 프레임 대 원본의 채널 평균 차로 보정한다.
    cap = cv2.VideoCapture(args.video)
    frames: list[NDArray[np.uint8]] = []
    while True:
        ok, f = cap.read()
        if not ok:
            break
        frames.append(to_canvas(np.asarray(f, dtype=np.uint8)))
    if not frames:
        raise RuntimeError(f"no frames: {args.video}")
    sel = mask > 0.5
    bias = src[sel].astype(np.float32).mean(axis=0) - frames[0][sel].astype(
        np.float32
    ).mean(axis=0)
    print("color bias (BGR) corrected:", np.round(bias, 2))

    with tempfile.TemporaryDirectory() as tmp:
        for i, f in enumerate(frames):
            patch = np.clip(f.astype(np.float32) + bias, 0, 255).astype(np.uint8)
            cv2.imwrite(os.path.join(tmp, f"f{i:04d}.png"), patch[y0:y1, x0:x1])
        src_fps = cap.get(cv2.CAP_PROP_FPS) or 24
        out_dir = os.path.join(RES, "CupIdle")
        os.makedirs(out_dir, exist_ok=True)
        out = os.path.join(out_dir, f"{name}-idle.mp4")
        # 느리게: 원본 fps / slow 로 늘린 뒤 목표 fps로 움직임 보간.
        vf = f"setpts={args.slow}*PTS,minterpolate=fps={args.fps}:mi_mode=mci:mc_mode=aobmc:vsbmc=1"
        cmd = [
            "ffmpeg",
            "-y",
            "-loglevel",
            "error",
            "-framerate",
            str(src_fps),
            "-i",
            os.path.join(tmp, "f%04d.png"),
            "-vf",
            vf,
            "-an",
            "-c:v",
            "libx265",
            "-crf",
            "20",
            "-preset",
            "slow",
            "-tag:v",
            "hvc1",
            "-x265-params",
            "log-level=error",
            "-pix_fmt",
            "yuv420p",
            "-movflags",
            "+faststart",
            out,
        ]
        subprocess.run(cmd, check=True)

    # 마스크는 에셋 카탈로그 이미지. SwiftUI .mask는 밝기가 아니라 알파만 보므로 알파 채널에 넣는다
    # (흑백 PNG로 넣었다가 패치 사각형 전체가 식탁 위에 드러났다, 2026-09-27).
    # 사각형 위치는 JSON으로 앱에 넘긴다.
    mask_set = os.path.join(RES, "Assets.xcassets", f"{name}-idle-mask.imageset")
    os.makedirs(mask_set, exist_ok=True)
    alpha8 = (mask[y0:y1, x0:x1] * 255).round().astype(np.uint8)
    white = np.full_like(alpha8, 255)
    write_image(
        os.path.join(mask_set, "mask.png"), np.dstack([white, white, white, alpha8])
    )
    with open(os.path.join(mask_set, "Contents.json"), "w", encoding="utf-8") as fh:
        json.dump(
            {
                "images": [{"filename": "mask.png", "idiom": "universal"}],
                "info": {"author": "xcode", "version": 1},
            },
            fh,
            indent=2,
        )
    with open(os.path.join(out_dir, f"{name}-idle.json"), "w", encoding="utf-8") as fh:
        json.dump({"x": rect[0], "y": rect[1], "width": rect[2], "height": rect[3]}, fh)
    print(name, "rect", rect, "->", out)


if __name__ == "__main__":
    main()
