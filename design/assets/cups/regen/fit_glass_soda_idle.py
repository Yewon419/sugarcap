# 유리 과일 소다 대기 루프 원본(AI 영상)을 9x16 캔버스에 맞춰 make_idle_patch.py(--bottom 1800)로 패치를 만든다.
# v2(2026-11-26, 비글루 스튜디오): 영상은 단계 사진(source/<단계>.jpg)을 시작·끝으로 뽑아 사진을 그대로 줄인
# 구도다(첫 프레임 ECC 정합으로 확인, 배율 1.000, 이동 0.3px 이하). 그래서 영상 → 사진 크기 배율 뒤
# prep_glass_soda.py의 PHOTO_FIT(사진 → 캔버스)을 걸면 make_glass_set.py가 만든 9x16 사진과 같은 자리다.
# 30·50%는 영상이 진행되며 화면 전체가 조금 어두워져(평균 밝기 약 4 하락) 이음새가 튄다. 프레임마다 잔 밖
# 양옆 띠의 채널 평균을 첫 프레임에 맞추고, 끝 BLEND 프레임은 첫 프레임 쪽으로 섞어 이음새를 메운다.
# 순서: prep_glass_soda.py → make_glass_set.py → 이 스크립트 30 50 80 100
#
# 사용: python fit_glass_soda_idle.py <단계>...   (시스템 파이썬 3.12, cv2·ffmpeg)
from __future__ import annotations

import os
import subprocess
import sys
import tempfile

import cv2
import numpy as np
from numpy.typing import NDArray
from prep_glass_soda import PHOTO_FIT

CUPS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SET_ID = "glass-soda"
CANVAS_W, CANVAS_H = 937, 1666
BOTTOM = "1800"
BLEND = 10


def read_frames(path: str) -> tuple[list[NDArray[np.float32]], float]:
    cap = cv2.VideoCapture(path)
    fps = cap.get(cv2.CAP_PROP_FPS)
    frames: list[NDArray[np.float32]] = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        frames.append(np.asarray(frame, dtype=np.float32))
    cap.release()
    if not frames:
        raise RuntimeError(f"프레임 없음: {path}")
    return frames, fps


def video_to_canvas(step: int, w: int, h: int) -> NDArray[np.float32]:
    photo = os.path.join(CUPS, SET_ID, "source", f"{step}.jpg")
    img = cv2.imdecode(np.fromfile(photo, dtype=np.uint8), cv2.IMREAD_COLOR)
    if img is None:
        raise FileNotFoundError(photo)
    pw, ph = img.shape[1], img.shape[0]
    sx, sy, tx, ty = PHOTO_FIT[step]
    return np.array(
        [[sx * pw / w, 0, tx], [0, sy * ph / h, ty]],
        dtype=np.float32,
    )


def even_out(frames: list[NDArray[np.float32]]) -> list[NDArray[np.float32]]:
    """잔 밖 양옆 띠의 채널 평균을 첫 프레임에 맞추고, 끝 BLEND 프레임을 첫 프레임 쪽으로 섞는다."""
    w = frames[0].shape[1]
    band = w // 6

    def side_mean(f: NDArray[np.float32]) -> NDArray[np.float32]:
        sides = np.concatenate([f[:, :band], f[:, w - band :]], axis=1)
        return np.asarray(sides.reshape(-1, 3).mean(axis=0), dtype=np.float32)

    ref = side_mean(frames[0])
    out = [np.clip(f + (ref - side_mean(f)), 0, 255) for f in frames]
    first = out[0]
    n = len(out)
    for i in range(max(1, n - BLEND), n):
        t = (i - (n - BLEND - 1)) / (BLEND + 1)
        out[i] = out[i] * (1 - t) + first * t
    return out


def fit_video(step: int, out: str) -> None:
    raw = os.path.join(CUPS, SET_ID, "idle", f"{step}_vigloo_raw.mp4")
    frames, fps = read_frames(raw)
    h, w = frames[0].shape[:2]
    m = video_to_canvas(step, w, h)
    seam_before = float(np.abs(frames[0] - frames[-1]).mean())
    frames = even_out(frames)
    seam_after = float(np.abs(frames[0] - frames[-1]).mean())
    with tempfile.TemporaryDirectory() as tmp:
        for i, f in enumerate(frames):
            warped = cv2.warpAffine(
                np.asarray(np.round(f), dtype=np.uint8),
                m,
                (CANVAS_W, CANVAS_H),
                flags=cv2.INTER_LANCZOS4,
                borderMode=cv2.BORDER_REPLICATE,
            )
            ok, buf = cv2.imencode(".png", warped)
            if not ok:
                raise RuntimeError(f"PNG 인코딩 실패: {raw} {i}")
            buf.tofile(os.path.join(tmp, f"f{i:04d}.png"))
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
    print(
        SET_ID,
        step,
        len(frames),
        "frames",
        (w, h),
        "seam",
        round(seam_before, 2),
        "->",
        round(seam_after, 2),
    )


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
