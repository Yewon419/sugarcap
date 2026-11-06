# 유리 과일 소다 대기 루프 원본(AI 영상)에 make_glass_set.py와 같은 단계별 잔 맞춤(FIT)을 걸어 패치를 다시 만든다
# (2026-11-06 대표님 "컵사이즈가 다른애들이랑 여전히 다른데"). 영상은 단계 사진을 시작·끝으로 뽑아
# 맞추기 전 사진과 같은 자리라, 사진과 같은 배율을 영상 좌표로 옮겨 프레임마다 늘인 뒤
# 무손실 임시 영상으로 make_idle_patch.py(--bottom 1800)에 넘긴다.
# 순서: make_glass_set.py → 이 스크립트 30 50 80 → clear_glass_soda.py → 이 스크립트 100
# (100% 원본은 색 보정된 사진에서 뽑아 색 편차 기준도 보정된 사진이어야 한다).
#
# 사용: python fit_glass_soda_idle.py <단계>...   (시스템 파이썬 3.12, cv2·ffmpeg)
from __future__ import annotations

import os
import subprocess
import sys
import tempfile

import cv2
import numpy as np
from make_glass_set import FIT, FIT_X, FIT_Y

CUPS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SET_ID = "glass-soda"
CANVAS_W, CANVAS_H = 937, 1666
BOTTOM = "1800"


def fit_video(step: int, out: str) -> None:
    raw = os.path.join(CUPS, SET_ID, "idle", f"{step}_minimax768_raw.mp4")
    cap = cv2.VideoCapture(raw)
    fps = cap.get(cv2.CAP_PROP_FPS)
    w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    if w == 0 or h == 0:
        raise RuntimeError(f"영상을 못 엶: {raw}")
    # make_idle_patch.to_canvas와 같은 대응(폭 기준 배율 s, 세로 가운데 oy)으로 고정점을 영상 좌표로 옮긴다.
    s = CANVAS_W / w
    oy = (CANVAS_H - h * s) / 2
    cx, cy = FIT_X / s, (FIT_Y - oy) / s
    sx, sy = FIT[SET_ID][step]
    m = np.array([[sx, 0, cx * (1 - sx)], [0, sy, cy * (1 - sy)]], dtype=np.float32)
    with tempfile.TemporaryDirectory() as tmp:
        count = 0
        while True:
            ok, frame = cap.read()
            if not ok:
                break
            warped = cv2.warpAffine(
                frame,
                m,
                (w, h),
                flags=cv2.INTER_LANCZOS4,
                borderMode=cv2.BORDER_REPLICATE,
            )
            ok, buf = cv2.imencode(".png", warped)
            if not ok:
                raise RuntimeError(f"PNG 인코딩 실패: {raw} {count}")
            buf.tofile(os.path.join(tmp, f"f{count:04d}.png"))
            count += 1
        cap.release()
        if count == 0:
            raise RuntimeError(f"프레임 없음: {raw}")
        cmd = [
            "ffmpeg",
            "-y",
            "-loglevel",
            "error",
            "-framerate",
            str(fps),
            "-i",
            os.path.join(tmp, "f%04d.png"),
            "-c:v",
            "libx264rgb",
            "-qp",
            "0",
            out,
        ]
        subprocess.run(cmd, check=True)
    print(SET_ID, step, count, "frames", (sx, sy))


def main() -> None:
    steps = [int(a) for a in sys.argv[1:]]
    if not steps:
        raise SystemExit("사용: python fit_glass_soda_idle.py <단계>...")
    patch = os.path.join(CUPS, "make_idle_patch.py")
    with tempfile.TemporaryDirectory() as tmp:
        for step in steps:
            video = os.path.join(tmp, f"{step}.mkv")
            fit_video(step, video)
            cmd = [sys.executable, patch, SET_ID, str(step), video, "--bottom", BOTTOM]
            subprocess.run(cmd, check=True)


if __name__ == "__main__":
    main()
