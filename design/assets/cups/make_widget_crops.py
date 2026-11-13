# 홈 화면 위젯 잔 사진(SPEC §4.6, 시안 design/proto/widget.html v7 대표님 2026-11-07 확정).
# WidgetKit은 큰 사진을 못 받는다(위젯 면적보다 훨씬 큰 사진은 그리기 전에 실패). 그래서 cupwide-* 원본에서
# 위젯 칸 모양대로 미리 잘라 Widget.xcassets에 넣고, 숫자 줄 아래 끝 높이를 Swift 표로 함께 쓴다.
#
# 좌표는 시안과 같은 단위(cupwide 2/3 축소본, 높이 1111)로 계산하고 원본 픽셀로 바꿔 자른다.
# 칸 치수·숫자 크기는 Swift `WidgetCupFamily`와 같아야 한다.
#   python make_widget_crops.py   (시스템 파이썬 3.12, Pillow)
import json
import os
from dataclasses import dataclass

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.join(HERE, "..", "..", "..", "SugarCap")
SOURCE = os.path.join(APP, "Resources", "Assets.xcassets")
OUT = os.path.join(APP, "Resources", "Widget.xcassets")
SWIFT = os.path.join(APP, "Sources", "WidgetUI", "WidgetCupCrops.swift")

PHOTO_H = 1111.0
ORIGINAL_H = 1666
# 좁은 사진(937폭, 축소 625)이 넓은 사진 가로 300(축소 200)에서 시작하고, 잔 가운데는 좁은 사진 폭의 0.497.
AXIS_X = 200 + 0.497 * 625
STEPS = [0, 30, 50, 80, 100]
# pt당 픽셀. 가장 큰 Small(170pt)도 @3x보다 조금 넉넉하다.
PX_PER_PT = 3.25
CONTENTS = '{\n  "images": [\n    {\n      "filename": "%s",\n      "idiom": "universal"\n    }\n  ],\n  "info": {\n    "author": "xcode",\n    "version": 1\n  }\n}\n'
ROOT_CONTENTS = '{\n  "info": {\n    "author": "xcode",\n    "version": 1\n  }\n}\n'


@dataclass(frozen=True)
class SetMeta:
    side: str
    # 숫자 기준 높이를 칸 세로 어디에 둘지(진한 숫자 0.42, 흰 숫자는 수면을 조금 올려 0.36).
    at: float
    bottom: float
    # 단계 → 기준 높이(사진 높이 비율). 보통은 수면(CupSetGeometry.liquid), 아메리카노는 얼음 꼭대기,
    # 아인슈페너는 크림 아래 커피가 시작하는 높이.
    anchor: dict[int, float]


SETS: dict[str, SetMeta] = {
    "strawberry-latte": SetMeta(
        "sugar", 0.42, 0.885, {0: 0.8, 30: 0.557, 50: 0.4466, 80: 0.3511, 100: 0.3397}
    ),
    "iced-americano": SetMeta(
        "caffeine", 0.36, 0.876, {0: 0.87, 30: 0.624, 50: 0.471, 80: 0.364, 100: 0.344}
    ),
    "cafe-latte": SetMeta(
        "caffeine", 0.42, 0.876, {0: 0.87, 30: 0.782, 50: 0.668, 80: 0.568, 100: 0.537}
    ),
    "choco-frappe": SetMeta(
        "sugar", 0.36, 0.876, {0: 0.87, 30: 0.6987, 50: 0.53, 80: 0.4904, 100: 0.3655}
    ),
    "matcha": SetMeta(
        "caffeine", 0.42, 0.876, {0: 0.87, 30: 0.6, 50: 0.49, 80: 0.413, 100: 0.36}
    ),
    "mango": SetMeta(
        "sugar", 0.42, 0.876, {0: 0.87, 30: 0.64, 50: 0.52, 80: 0.37, 100: 0.336}
    ),
    "einspanner": SetMeta(
        "caffeine", 0.36, 0.876, {0: 0.87, 30: 0.677, 50: 0.534, 80: 0.48, 100: 0.408}
    ),
    "grape": SetMeta(
        "sugar", 0.42, 0.876, {0: 0.87, 30: 0.69, 50: 0.567, 80: 0.475, 100: 0.355}
    ),
    "glass-soda": SetMeta(
        "sugar", 0.42, 0.876, {0: 0.87, 30: 0.694, 50: 0.594, 80: 0.472, 100: 0.354}
    ),
    "glass-beans": SetMeta(
        "caffeine", 0.36, 0.876, {0: 0.87, 30: 0.701, 50: 0.594, 80: 0.471, 100: 0.314}
    ),
}


@dataclass(frozen=True)
class Family:
    name: str
    width: float
    height: float
    # pt당 시안 단위(칸 폭 / 자른 사진 폭).
    k: float
    # 잔 가운데가 칸 왼쪽에서 몇 pt인지.
    axis: float
    # 숫자 줄 아래 끝의 최소 높이(pt).
    min_bottom: float = 4.0


# Medium 두 잔은 칸마다 169pt인데, 이음새를 섞으려고 가운데 쪽으로 SEAM pt씩 더 자른다(당 = 왼쪽, 카페인 = 오른쪽).
SEAM = 12.0
SMALL = Family("small", 158, 158, 158 / 400, 79)
HALF_LEFT = Family("half", 169 + SEAM, 158, 169 / 420, 84.5)
HALF_RIGHT = Family("half", 169 + SEAM, 158, 169 / 420, SEAM + 84.5)
WIDE = Family("wide", 338, 158, 338 / 760, 0.35 * 338)
# Large(시안 design/proto/widget-large.html A, 대표님 2026-11-09 확정): 잔 전체(입구 위 여유 ~ 냅킨 끝)를 위 262pt에.
# 두 잔은 Medium처럼 칸마다 181pt(가운데 24pt 겹침), 모든 단계를 같은 위끝으로 잘라 입구 높이가 늘 같다.
# 두 잔을 가운데 쪽으로 LARGE_PULL pt씩 당긴다(빌드 448 대표님 "두 음료 거리를 좀 더 좁혀도"). Swift `axis(.large)`와 같아야 한다.
LARGE_TOP = 240.0
LARGE_UNITS = 840.0
LARGE_PULL = 12.0
LARGE_LEFT = Family("large", 181, 262, 262 / LARGE_UNITS, 84.5 + LARGE_PULL)
LARGE_RIGHT = Family("large", 181, 262, 262 / LARGE_UNITS, SEAM + 84.5 - LARGE_PULL)
# 한 면만 켠 사용자: 잔 하나를 가운데, 사진 폭 전체(1024단위)를 338pt에. 그만큼 위아래를 조금 덜 담는다.
LARGE_SOLO = Family("largesolo", 338, 262, 338 / 1024, 338 / 1024 * AXIS_X)
SOLO_TOP = LARGE_TOP + (LARGE_UNITS - 262 / LARGE_SOLO.k) / 2


def families(meta: SetMeta) -> list[Family]:
    sugar = meta.side == "sugar"
    return [
        SMALL,
        HALF_LEFT if sugar else HALF_RIGHT,
        WIDE,
        LARGE_LEFT if sugar else LARGE_RIGHT,
        LARGE_SOLO,
    ]


def fixed_top(family: Family) -> float | None:
    """단계와 상관없이 같은 위끝으로 자르는 칸(Large)."""
    if family.name == "large":
        return LARGE_TOP
    if family.name == "largesolo":
        return SOLO_TOP
    return None


def crop_y(meta: SetMeta, step: int, family: Family) -> float:
    """이 단계 잔을 혼자 그릴 때 자를 위끝(시안 단위): 기준 높이가 칸 세로 `at`에 오게, 사진 바닥은 넘지 않게."""
    height = family.height / family.k
    return min(meta.anchor[step] * PHOTO_H - meta.at * height, PHOTO_H - height)


def crop_and_bottom(
    meta: SetMeta, step: int, family: Family
) -> tuple[tuple[float, float, float, float], float]:
    """자를 칸(시안 단위 x, y, 폭, 높이)과 숫자 줄 아래 끝 높이(pt)."""
    width = family.width / family.k
    height = family.height / family.k
    x = AXIS_X - family.axis / family.k
    top = fixed_top(family)
    y = crop_y(meta, step, family) if top is None else top
    if x < 0 or x + width > 1025 or y < 0:
        raise ValueError(
            f"crop outside photo: family={family.name} step={step} x={x} y={y} w={width} h={height}"
        )
    # 숫자는 잔 안에 선다: 잔 바닥이 칸 안으로 올라오면 숫자 아래 끝을 바닥 위 6pt로 올린다.
    glass_bottom = (meta.bottom * PHOTO_H - y) * family.k
    bottom = max(family.min_bottom, family.height - glass_bottom + 6)
    return (x, y, width, height), bottom


# Medium 두 잔은 입구 높이가 같아야 한다(대표님 2026-11-09). 두 잔을 같은 위끝으로 자르도록
# half 사진은 모든 단계의 위끝 중 가장 높은 곳(HALF_TOP)부터 사진 바닥까지 길게 자르고,
# 단계별 위끝(halfCropY)과 잔 바닥(glassBottom)을 표로 넘겨 Swift가 두 잔 공통 위끝으로 밀어 올린다.
HALF_TOP = float(
    int(min(crop_y(meta, step, HALF_LEFT) for meta in SETS.values() for step in STEPS))
)


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "Contents.json"), "w", newline="\n") as f:
        f.write(ROOT_CONTENTS)
    scale = ORIGINAL_H / PHOTO_H
    bottoms: dict[str, float] = {}
    half_crop_y: dict[str, float] = {}
    for set_id, meta in SETS.items():
        for step in STEPS:
            source = os.path.join(
                SOURCE, f"cupwide-{set_id}-{step}.imageset", f"{step}.jpg"
            )
            photo = Image.open(source).convert("RGB")
            if photo.size != (1537, ORIGINAL_H):
                raise ValueError(f"unexpected cupwide size: {source} {photo.size}")
            for family in families(meta):
                (x, y, w, h), bottom = crop_and_bottom(meta, step, family)
                tall = family.name == "half"
                if tall:
                    y, h = HALF_TOP, PHOTO_H - HALF_TOP
                box = (
                    round(x * scale),
                    round(y * scale),
                    round((x + w) * scale),
                    round((y + h) * scale),
                )
                size = (
                    round(family.width * PX_PER_PT),
                    round(h * family.k * PX_PER_PT),
                )
                image = photo.crop(box).resize(size, Image.Resampling.LANCZOS)
                name = f"widget-{family.name}-{set_id}-{step}"
                folder = os.path.join(OUT, f"{name}.imageset")
                os.makedirs(folder, exist_ok=True)
                image.save(os.path.join(folder, f"{name}.jpg"), quality=85)
                with open(
                    os.path.join(folder, "Contents.json"), "w", newline="\n"
                ) as f:
                    f.write(CONTENTS % f"{name}.jpg")
                if tall:
                    half_crop_y[name] = round(crop_y(meta, step, family), 2)
                else:
                    bottoms[name] = round(bottom / family.height, 4)
    lines = [
        "// 생성 파일: design/assets/cups/make_widget_crops.py. 손으로 고치지 않는다.",
        "",
        "enum WidgetCupCrops {",
        "    /// Small·한 면 Medium·Large 사진마다 숫자 줄 아래 끝 높이(위젯 아래에서, 칸 높이 비율).",
        "    /// 잔 바닥이 칸 안으로 올라온 단계(주로 0%)는 바닥 위 6pt, 아니면 아래 4pt.",
        "    static let numberBottom: [String: Double] = [",
    ]
    lines += [f'        "{name}": {value},' for name, value in bottoms.items()]
    lines += [
        "    ]",
        "",
        "    /// Medium 두 잔 사진(half)은 두 잔 입구 높이를 맞추려고 길게 잘랐다(대표님 2026-11-09).",
        "    /// 사진 단위(cupwide 2/3 축소본) 위끝 `halfTop`부터 사진 바닥 `photoHeight`까지, 1단위 = `halfPointsPerUnit`pt.",
        f"    static let photoHeight = {PHOTO_H}",
        "    /// 잔 가운데 가로 위치(사진 단위). Large 한 잔 칸은 사진 폭 전체(1024단위)를 담아 이 자리가 잔 축이다.",
        f"    static let axisX = {AXIS_X!r}",
        f"    static let halfTop = {HALF_TOP}",
        f"    static let halfPointsPerUnit = {HALF_LEFT.k!r}",
        "    /// 그 단계 잔을 혼자 그릴 때 칸 위끝(사진 단위). 두 잔은 둘 중 큰 값(덜 찬 잔)을 같이 쓴다.",
        "    static let halfCropY: [String: Double] = [",
    ]
    lines += [f'        "{name}": {value},' for name, value in half_crop_y.items()]
    lines += [
        "    ]",
        "    /// 잔 바닥 높이(사진 단위 / photoHeight).",
        "    static let glassBottom: [String: Double] = [",
    ]
    lines += [f'        "{set_id}": {meta.bottom},' for set_id, meta in SETS.items()]
    lines += ["    ]", "}", ""]
    os.makedirs(os.path.dirname(SWIFT), exist_ok=True)
    with open(SWIFT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))
    print(json.dumps({"images": len(bottoms) + len(half_crop_y), "half_top": HALF_TOP}))


if __name__ == "__main__":
    main()
