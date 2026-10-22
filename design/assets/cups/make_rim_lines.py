# 오늘 화면 큰 숫자(CupHero)를 끊는 유리 선 마스크 만들기(2026-10-13 대표님 시안).
# 숫자는 유리 너머로 그대로 비치고, 입구 앞·뒤 호와 벽 선만 숫자를 지운다.
# 단계 사진에서 주변보다 어두운 가는 줄(블랙햇)을 오린 잔 윤곽 안, 입구 위끝 ~ 숫자 바닥(사진 높이 0.33)까지만 뽑는다.
# 유리 안쪽 잡티(작은 점)는 넓이로 거른다. 선은 잔 안쪽으로만 두껍게 키워 유리 두께의 반사 빛 띠처럼 보이게 한다
# (대표님 "컵 경계 안쪽으로 반사 빛을 표현하기 위해 원본처럼 좀 더 두껍게", 시안 틈 약 3pt).
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
BOTTOM = 0.33  # 숫자 바닥(CupHero.baselineRatio 0.328) 바로 아래. 음료 윗면(가장 높은 곳 0.331)보다 위
SPECK = 60  # 이보다 작은 덩어리(px)는 유리 안쪽 잡티
THICKEN = 5  # 선을 잔 안쪽으로 넓히는 지름(px). 시안 틈 약 3pt(캔버스 7px)에 맞춘다. 11이면 시안의 두 배였다
# 입구 호가 사진에서 하얗게 날아가 블랙햇이 못 잡는 구간은 뽑힌 선으로 맞춘 타원으로 메운다
# (2026-10-22, 10장 모두 뒤쪽 호 오른쪽이 비어 숫자가 그 위로 올라와 있었다).
# 열마다 타원 자리 위아래 NEAR px 안에 뽑힌 선이 없으면 빈 열이다.
NEAR = 8
FIT_BAND = 0.25  # 타원 맞추기에 쓰는 점: 맞춘 타원 반지름의 1±이 비율 안(벽 선 조각을 뺀다)
# 문턱으로 자른 선 경계는 화면에서 1.3배로 커지며 계단이 된다. SUPER배로 키워 윤곽을
# SMOOTH px(원본) 시그마로 다듬고 다시 문턱 → 줄여서 경계 1px만 부드럽게 한다(번짐 아님).
SUPER = 4
SMOOTH = 2.0  # 1.0은 털 같은 들쭉날쭉이 남았다. 선 굵기(7~9px)는 2.0에서도 그대로


def fit_rim(lines: NDArray[np.bool_]) -> tuple[tuple[float, float], tuple[float, float], float]:
    ys, xs = np.nonzero(lines)
    points = np.column_stack([xs, ys]).astype(np.float32)
    if len(points) < 5:
        raise RuntimeError("입구 선 점이 모자람")
    ellipse = cv2.fitEllipse(points)
    for _ in range(4):
        (cx, cy), (w, h), angle = ellipse
        t = np.deg2rad(angle)
        dx, dy = points[:, 0] - cx, points[:, 1] - cy
        u = dx * np.cos(t) + dy * np.sin(t)
        v = -dx * np.sin(t) + dy * np.cos(t)
        r = np.sqrt((u / (w / 2)) ** 2 + (v / (h / 2)) ** 2)
        kept = points[np.abs(r - 1) < FIT_BAND]
        if len(kept) < 5:
            raise RuntimeError("입구 타원 맞추기 실패")
        ellipse = cv2.fitEllipse(kept)
    (cx, cy), (w, h), angle = ellipse
    return (float(cx), float(cy)), (float(w), float(h)), float(angle)


def rim_gaps(lines: NDArray[np.bool_]) -> NDArray[np.bool_]:
    """뽑힌 선이 비는 열을 맞춘 입구 타원을 따라 메운다(뒤쪽·앞쪽 호 따로).

    빈 구간 양끝 열에서 실제 선의 가운데(타원에서 어긋난 만큼)와 두께를 재고
    그 사이를 선형으로 이어 이음매에 턱이 없게 한다.
    """
    height, width = lines.shape
    center, axes, angle = fit_rim(lines)
    ring = np.zeros((height, width), dtype=np.uint8)
    scale = 16  # cv2.ellipse 소수 좌표(shift 4)
    cv2.ellipse(
        ring,
        (round(center[0] * scale), round(center[1] * scale)),
        (round(axes[0] / 2 * scale), round(axes[1] / 2 * scale)),
        angle,
        0,
        360,
        1,
        1,
        cv2.LINE_8,
        4,
    )
    fill = np.zeros_like(lines)
    for back in (True, False):
        # 열마다 (타원 자리, 실제 선 가운데 - 타원 자리, 실제 선 두께). 선이 없으면 nan.
        ellipse_y = np.full(width, np.nan)
        offset = np.full(width, np.nan)
        thick = np.full(width, np.nan)
        for x in range(width):
            rows = np.nonzero(ring[:, x])[0]
            arc = rows[rows < center[1]] if back else rows[rows >= center[1]]
            if arc.size == 0:
                continue
            y = float(arc.mean())
            ellipse_y[x] = y
            lo, hi = max(0, int(y) - NEAR), min(height, int(y) + NEAR + 1)
            found = np.nonzero(lines[lo:hi, x])[0]
            if found.size:
                offset[x] = lo + float(found.mean()) - y
                thick[x] = float(found.size)
        # 빈 구간 안의 1~2px 조각은 선으로 치지 않는다. 치면 구간이 잘게 쪼개지고 얇게 메운 데가
        # 다듬기에서 사라져 점선이 된다(딸기 80%·아메리카노 30%).
        typical = float(np.nanmedian(thick))
        weak = thick < 0.5 * typical
        offset[weak] = np.nan
        thick[weak] = np.nan
        has_arc = ~np.isnan(ellipse_y)
        has_line = ~np.isnan(offset)
        x = 0
        while x < width:
            if not has_arc[x] or has_line[x]:
                x += 1
                continue
            start = x
            while x < width and has_arc[x] and not has_line[x]:
                x += 1
            left, right = start - 1, x
            ends = [e for e in (left, right) if 0 <= e < width and has_line[e]]
            if not ends:
                continue
            for col in range(start, x):
                if len(ends) == 2:
                    k = (col - left) / (right - left)
                    d = offset[left] * (1 - k) + offset[right] * k
                    t = thick[left] * (1 - k) + thick[right] * k
                else:
                    d, t = offset[ends[0]], thick[ends[0]]
                # 선이 사라지기 직전 끝(2px)의 두께를 이어받으면 다듬기에서 끊긴다.
                t = max(t, typical)
                mid = ellipse_y[col] + d
                top, bottom = round(mid - t / 2), round(mid + t / 2)
                fill[max(0, top) : min(height, bottom), col] = True
    return fill


def smooth_edges(mask: NDArray[np.bool_]) -> NDArray[np.float32]:
    height, width = mask.shape
    big = cv2.resize(
        mask.astype(np.float32), (width * SUPER, height * SUPER), interpolation=cv2.INTER_LINEAR
    )
    big = cv2.GaussianBlur(big, (0, 0), SMOOTH * SUPER)
    hard = (big > 0.5).astype(np.float32)
    return np.asarray(
        cv2.resize(hard, (width, height), interpolation=cv2.INTER_AREA), dtype=np.float32
    )


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
    ridge = cv2.morphologyEx(
        gray, cv2.MORPH_BLACKHAT, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (RIDGE, RIDGE))
    )
    strength = np.clip((ridge.astype(np.float32) - FLOOR) / RAMP, 0.0, 1.0)
    rows = np.where(cutout_alpha.max(axis=1) > 128)[0]
    if rows.size == 0:
        raise RuntimeError("오린 잔이 비어 있음")
    # 잔 윤곽 안쪽만. 바깥으로는 파지 않는다(대표님 "컵 바깥쪽으로 파진 말고").
    core = cutout_alpha > 128
    band = np.zeros_like(core)
    band[int(rows[0]) : int(BOTTOM * height)] = True
    strength = strength * (core & band)
    count, labels, stats, _ = cv2.connectedComponentsWithStats(
        (strength > 0.5).astype(np.uint8), connectivity=8
    )
    keep = np.zeros(count, dtype=bool)
    keep[1:] = stats[1:, cv2.CC_STAT_AREA] >= SPECK
    solid = cv2.dilate(keep[labels].astype(np.uint8), np.ones((3, 3), np.uint8)) > 0
    lines = (strength * solid) > 0.5
    lines = (lines | rim_gaps(lines)) & core & band
    grow = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (THICKEN, THICKEN))
    thick = (cv2.dilate(lines.astype(np.uint8), grow) > 0) & core & band
    # 잔 바깥으로는 파지 않는다: 오린 잔 알파(경계가 이미 부드럽다)로 자른다.
    clip = (cutout_alpha.astype(np.float32) / 255) * band
    return (smooth_edges(thick) * clip * 255).astype(np.uint8)


def main() -> None:
    for cup_set in SETS:
        for step in STEPS:
            photo = read_image(photo_path(cup_set, step), cv2.IMREAD_COLOR)
            cut = read_image(
                os.path.join(ASSETS, f"cutout-{cup_set}-{step}.imageset", f"{step}.png"),
                cv2.IMREAD_UNCHANGED,
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
            with open(
                os.path.join(folder, "Contents.json"), "w", encoding="utf-8", newline="\n"
            ) as f:
                json.dump(contents, f, indent=2)
                f.write("\n")
            print(cup_set, step, int((alpha > 0).sum()))


if __name__ == "__main__":
    main()
