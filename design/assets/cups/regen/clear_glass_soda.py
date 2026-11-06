# 유리 과일 소다 잔 속을 맑게(2026-11-06 빌드 407 대표님 "유리 음료 살짝 색보정", 방향 "더 맑고 투명하게").
# 잔 안 물·빈 유리(누끼 안, 채도 낮고 밝은 픽셀)가 배경보다 회색(밝기 약 218 대 238)이라 탁해 보였다.
# 그 픽셀만 저주파 밝기를 배경 쪽으로 끌어올리고 색 끼를 뺀 뒤 기포·윤곽 디테일은 되살린다.
# 저주파는 물 픽셀만으로 구해(정규화 흐림) 과일 둘레에 흰 테가 생기지 않게 하고, 어두운 윤곽선(밝기 175 아래)은 건드리지 않는다.
# 대기 영상(30~80%)은 앱 번들 패치를 프레임마다 풀어 같은 보정을 걸고 make_idle_patch.py와 같은 설정으로 다시 인코딩한다.
# make_glass_set.py를 다시 돌리면 보정이 풀리니 그 뒤에 이 스크립트, 그다음 make_hero_toppings.py를 돌린다.
#
# 사용: python clear_glass_soda.py [--preview <파일.jpg>]   (시스템 파이썬 3.12, cv2·ffmpeg)
from __future__ import annotations

import argparse
import json
import os
import subprocess
import tempfile

import cv2
import numpy as np
from numpy.typing import NDArray

CUPS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = os.path.abspath(os.path.join(CUPS, "..", "..", ".."))
RES = os.path.join(REPO, "SugarCap", "Resources")
ASSETS = os.path.join(RES, "Assets.xcassets")
SET_ID = "glass-soda"
STEPS = (0, 30, 50, 80, 100)
IDLE_STEPS = (30, 50, 80)
WING = 300
BACKGROUND = 242.0
LIFT = 0.7
DETAIL = 1.15
COOL = 2.0
SIGMA = 12.0


def read(path: str, flags: int) -> NDArray[np.uint8]:
    img = cv2.imdecode(np.fromfile(path, dtype=np.uint8), flags)
    if img is None:
        raise FileNotFoundError(path)
    return np.asarray(img, dtype=np.uint8)


def write(path: str, img: NDArray[np.uint8], ext: str) -> None:
    params = [cv2.IMWRITE_JPEG_QUALITY, 88] if ext == ".jpg" else []
    ok, buf = cv2.imencode(ext, img, params)
    if not ok:
        raise RuntimeError(f"인코딩 실패: {path}")
    buf.tofile(path)


def clear(bgr: NDArray[np.uint8], alpha: NDArray[np.uint8]) -> NDArray[np.uint8]:
    f = bgr.astype(np.float32)
    hsv = cv2.cvtColor(bgr, cv2.COLOR_BGR2HSV).astype(np.float32)
    inside = cv2.GaussianBlur(alpha.astype(np.float32), (0, 0), 3) / 255
    w = np.clip(1 - (hsv[:, :, 1] - 10) / 20, 0, 1) * inside
    w = w * np.clip((hsv[:, :, 2] - 175) / 30, 0, 1)
    w = np.asarray(cv2.GaussianBlur(w, (0, 0), 0.8), dtype=np.float32)
    w0 = w + 1e-3
    low = (
        cv2.GaussianBlur(f * w0[:, :, None], (0, 0), SIGMA)
        / cv2.GaussianBlur(w0, (0, 0), SIGMA)[:, :, None]
    )
    gray = low.mean(axis=2, keepdims=True)
    target = low + LIFT * (BACKGROUND - gray) + (gray - low) * 0.6
    target[:, :, 0] += COOL
    out = target + (f - low) * DETAIL
    blended = f * (1 - w[:, :, None]) + out * w[:, :, None]
    return np.asarray(np.clip(blended, 0, 255), dtype=np.uint8)


def asset(kind: str, step: int, ext: str) -> str:
    return os.path.join(ASSETS, f"{kind}-{SET_ID}-{step}.imageset", f"{step}{ext}")


def clear_photos(step: int) -> tuple[NDArray[np.uint8], NDArray[np.uint8]]:
    cut_path = asset("cutout", step, ".png")
    cut = read(cut_path, cv2.IMREAD_UNCHANGED)
    alpha = np.ascontiguousarray(cut[:, :, 3])
    before = read(asset("cup", step, ".png"), cv2.IMREAD_COLOR)
    after = clear(before, alpha)
    write(asset("cup", step, ".png"), after, ".png")
    rgba = np.dstack([after, alpha])
    write(cut_path, rgba, ".png")
    if step:
        write(os.path.join(CUPS, SET_ID, "9x16", f"{step}.png"), after, ".png")
        write(
            os.path.join(CUPS, "cutouts", f"cutout-{SET_ID}-{step}.png"), rgba, ".png"
        )
    wide = read(asset("cupwide", step, ".jpg"), cv2.IMREAD_COLOR)
    wide_alpha = np.pad(alpha, ((0, 0), (WING, WING)))
    if wide_alpha.shape != wide.shape[:2]:
        raise RuntimeError(f"넓은 판 크기 불일치: {wide.shape} {wide_alpha.shape}")
    wide_after = clear(wide, wide_alpha)
    write(asset("cupwide", step, ".jpg"), wide_after, ".jpg")
    if step:
        write(os.path.join(CUPS, SET_ID, "wide", f"{step}.jpg"), wide_after, ".jpg")
    return before, after


def clear_idle(step: int) -> None:
    name = f"cup-{SET_ID}-{step}-idle"
    video = os.path.join(RES, "CupIdle", f"{name}.mp4")
    with open(os.path.join(RES, "CupIdle", f"{name}.json"), encoding="utf-8") as fh:
        rect: dict[str, int] = json.load(fh)
    alpha = read(asset("cutout", step, ".png"), cv2.IMREAD_UNCHANGED)[:, :, 3]
    x, y, w, h = rect["x"], rect["y"], rect["width"], rect["height"]
    crop = np.ascontiguousarray(alpha[y : y + h, x : x + w])
    cap = cv2.VideoCapture(video)
    fps = cap.get(cv2.CAP_PROP_FPS)
    with tempfile.TemporaryDirectory() as tmp:
        count = 0
        while True:
            ok, frame = cap.read()
            if not ok:
                break
            img = np.asarray(frame, dtype=np.uint8)
            if img.shape[:2] != crop.shape:
                raise RuntimeError(f"패치 크기 불일치: {video} {img.shape} {rect}")
            write(os.path.join(tmp, f"f{count:04d}.png"), clear(img, crop), ".png")
            count += 1
        cap.release()
        if count == 0:
            raise RuntimeError(f"프레임 없음: {video}")
        cmd = [
            "ffmpeg",
            "-y",
            "-loglevel",
            "error",
            "-framerate",
            str(fps),
            "-i",
            os.path.join(tmp, "f%04d.png"),
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
            video,
        ]
        subprocess.run(cmd, check=True)
    print(name, count, "frames", fps, "fps")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--preview")
    args = parser.parse_args()
    preview: str | None = args.preview
    rows: list[NDArray[np.uint8]] = []
    for step in STEPS:
        before, after = clear_photos(step)
        rows.append(
            np.vstack(
                [
                    cv2.resize(before[300:1500], (450, 600)),
                    cv2.resize(after[300:1500], (450, 600)),
                ]
            )
        )
    for step in IDLE_STEPS:
        clear_idle(step)
    if preview is not None:
        write(preview, np.asarray(np.hstack(rows), dtype=np.uint8), ".jpg")


if __name__ == "__main__":
    main()
