"""Cut Roshu pose art into a body layer and limb layers for rigged idle motion.

The art is flat colour without outlines, so limbs are cut along hand-measured
curves (canvas pixels, measured on gridded zooms). Cut edges get the same soft
falloff as the drawn silhouette. Limbs sit behind the body and keep a "root"
that continues under the body, so rotating a limb never opens a gap. Stroke
parts (a limb drawn as a light line inside the body) are lifted off the body
and the body is repainted with the body colour underneath.

    python design/assets/characters/split_limbs.py

Writes roshu/parts/<pose>/<part>.png (cropped) and roshu/parts/parts.json.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import TypeAlias

import cv2
import numpy as np
from numpy.typing import NDArray
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent
POSES = ROOT / "roshu" / "poses"
STAND = (
    ROOT.parents[2]
    / "SugarCap/Resources/Shared.xcassets/character-roshu.imageset/roshu.png"
)
OUT = ROOT / "roshu" / "parts"

SUPERSAMPLE = 4
EDGE_FAINT = 0.2
EDGE_FILL_SIGMA = 6.0
CUT_SOFTNESS = 5.0
ROOT_REACH = 90
# Roots stay this far inside the silhouette so a turned limb never pokes a root corner out.
# A limb turned by angle a moves its root edge out by about ROOT_REACH * sin(a): 90 * sin(14 deg) = 22.
ROOT_INSET = 32
# Lighter than the body by this much counts as stroke (0..1 scale).
STROKE_MIN = 2 / 255
# Depth inside the silhouette the painted leg keeps per px of height above the cut.
LEG_TAPER = 0.25
# The leg starts this far inside the silhouette so it never doubles the soft edge at rest.
LEG_EDGE = 3

Point = tuple[float, float]
FloatImage: TypeAlias = NDArray[np.float64]


def bezier(p0: Point, c: Point, p1: Point, count: int = 40) -> list[Point]:
    t = np.linspace(0.0, 1.0, count)
    xs = (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * c[0] + t**2 * p1[0]
    ys = (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * c[1] + t**2 * p1[1]
    return [(float(x), float(y)) for x, y in zip(xs, ys, strict=True)]


@dataclass(frozen=True)
class Cut:
    """A limb cut off the silhouette. `region` is a closed polygon around the limb."""

    name: str
    region: list[Point]
    pivot: Point
    # Small for limbs that never turn but get uncovered when the body lifts: the root then keeps almost
    # the full width. 11 keeps it inside the soft edge so the pose still composites back exactly.
    root_inset: int = ROOT_INSET
    # Feet that slide sideways: body colour painted up behind the body from the cut, `leg` px high.
    # It stays LEG_TAPER px deeper inside the silhouette per px of height, so a slid foot shows a
    # sloped leg that runs back into the body outline instead of a step. 0 = off.
    leg: int = 0


@dataclass(frozen=True)
class Stroke:
    """A limb drawn as a light line inside the body, lifted off inside `box`."""

    name: str
    box: tuple[int, int, int, int]
    pivot: Point


@dataclass(frozen=True)
class PoseSpec:
    source: Path
    cuts: list[Cut] = field(default_factory=list)
    strokes: list[Stroke] = field(default_factory=list)


SPECS: dict[str, PoseSpec] = {
    "walk": PoseSpec(
        POSES / "walk.png",
        cuts=[
            Cut(
                "flipper_front",
                [
                    *bezier((580, 1400), (578, 1560), (622, 1672)),
                    (612, 1702),
                    (440, 1702),
                    (440, 1400),
                ],
                pivot=(580, 1400),
            ),
            Cut(
                "foot_back",
                [
                    *bezier((724, 2125), (736, 2174), (955, 2168)),
                    (955, 2320),
                    (600, 2320),
                    (600, 2125),
                ],
                pivot=(724, 2125),
                leg=220,
            ),
            Cut(
                "foot_front",
                [
                    *bezier((1395, 2168), (1690, 2180), (1707, 2109)),
                    (1800, 2109),
                    (1800, 2320),
                    (1395, 2320),
                ],
                pivot=(1707, 2109),
                leg=220,
            ),
        ],
        strokes=[Stroke("flipper_side", (1520, 1470, 1830, 1770), pivot=(1625, 1530))],
    ),
    "watch": PoseSpec(
        POSES / "watch.png",
        cuts=[
            Cut(
                "foot_left",
                [
                    *bezier((655, 2140), (720, 2200), (962, 2186)),
                    (962, 2420),
                    (560, 2420),
                    (560, 2140),
                ],
                pivot=(655, 2140),
                root_inset=11,
            ),
            Cut(
                "foot_right",
                [
                    *bezier((1110, 2189), (1300, 2215), (1438, 2190)),
                    (1520, 2190),
                    (1520, 2440),
                    (1110, 2440),
                ],
                pivot=(1438, 2190),
                root_inset=11,
            ),
            Cut(
                "arm",
                [
                    *bezier((1838, 1140), (1826, 1300), (1815, 1440)),
                    (2100, 1440),
                    (2100, 1060),
                    (1890, 1060),
                    (1884, 1136),
                ],
                pivot=(1815, 1440),
            ),
        ],
    ),
    "slump": PoseSpec(
        POSES / "slump.png",
        cuts=[
            Cut(
                "foot_left",
                [
                    *bezier((596, 2050), (620, 2290), (958, 2290)),
                    (958, 2440),
                    (380, 2440),
                    (380, 2050),
                ],
                pivot=(958, 2290),
            ),
            Cut(
                "foot_right",
                [
                    *bezier((960, 2292), (1170, 2345), (1390, 2358)),
                    (1480, 2358),
                    (1480, 2460),
                    (960, 2460),
                ],
                pivot=(960, 2292),
            ),
        ],
    ),
    "in-cup": PoseSpec(
        POSES / "in-cup.png",
        cuts=[
            Cut(
                "foot_left",
                [
                    *bezier((775, 2104), (850, 2168), (1072, 2148)),
                    (1072, 2340),
                    (700, 2340),
                    (700, 2104),
                ],
                pivot=(775, 2104),
            ),
            Cut(
                "foot_right",
                [
                    *bezier((1348, 2148), (1545, 2168), (1620, 2104)),
                    (1700, 2104),
                    (1700, 2340),
                    (1348, 2340),
                ],
                pivot=(1620, 2104),
            ),
        ],
    ),
    "stand": PoseSpec(
        STAND,
        cuts=[
            Cut(
                "arm_left",
                [
                    *bezier((122, 485), (112, 550), (134, 616)),
                    (118, 622),
                    (0, 622),
                    (0, 485),
                ],
                pivot=(134, 616),
            ),
            Cut(
                "arm_right",
                [
                    *bezier((812, 485), (822, 560), (799, 619)),
                    (816, 624),
                    (935, 624),
                    (935, 485),
                ],
                pivot=(799, 619),
            ),
            Cut(
                "foot_left",
                [
                    *bezier((227, 922), (272, 934), (318, 929)),
                    (318, 1024),
                    (150, 1024),
                    (150, 922),
                ],
                pivot=(227, 922),
            ),
            Cut(
                "foot_right",
                [
                    *bezier((610, 929), (656, 936), (705, 920)),
                    (760, 920),
                    (760, 1024),
                    (610, 1024),
                ],
                pivot=(705, 920),
            ),
        ],
    ),
}


def soft_mask(
    size: tuple[int, int], polygon: list[Point], softness: float
) -> FloatImage:
    width, height = size
    big = Image.new("L", (width * SUPERSAMPLE, height * SUPERSAMPLE), 0)
    ImageDraw.Draw(big).polygon(
        [(x * SUPERSAMPLE, y * SUPERSAMPLE) for x, y in polygon], fill=255
    )
    mask = np.asarray(big.resize(size, Image.Resampling.BOX), dtype=np.float64) / 255
    if softness > 0:
        mask = np.asarray(cv2.GaussianBlur(mask, (0, 0), softness), dtype=np.float64)
    return mask


def body_colour(rgba: FloatImage) -> NDArray[np.float64]:
    opaque = rgba[..., 3] > 0.99
    colours = rgba[..., :3][opaque]
    values, counts = np.unique(
        np.round(colours * 255).astype(int), axis=0, return_counts=True
    )
    return np.asarray(values[int(np.argmax(counts))], dtype=np.float64) / 255


def crop_save(layer: FloatImage, path: Path) -> list[int]:
    alpha = layer[..., 3]
    ys, xs = np.nonzero(alpha > 1 / 255)
    if len(ys) == 0:
        raise ValueError(f"empty layer {path}")
    x0, y0, x1, y1 = int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1
    pixels = np.clip(np.round(layer[y0:y1, x0:x1] * 255), 0, 255).astype(np.uint8)
    Image.fromarray(pixels, "RGBA").save(path, optimize=True)
    return [x0, y0, x1 - x0, y1 - y0]


def split(pose: str, spec: PoseSpec) -> dict[str, object]:
    rgba = np.asarray(Image.open(spec.source).convert("RGBA"), dtype=np.float64) / 255
    # Faint edge pixels carry junk colour (0 or 255) that bleeds in when a moved layer is resampled.
    # Give them the colour of their opaque neighbourhood instead.
    weight = rgba[..., 3]
    spread = cv2.GaussianBlur(weight, (0, 0), EDGE_FILL_SIGMA)
    filled = (
        np.stack(
            [
                cv2.GaussianBlur(rgba[..., c] * weight, (0, 0), EDGE_FILL_SIGMA)
                for c in range(3)
            ],
            axis=-1,
        )
        / np.maximum(spread, 1e-6)[..., None]
    )
    faint = weight < EDGE_FAINT
    rgba[..., :3][faint] = np.where(
        spread[faint, None] > 1e-6, filled[faint], body_colour(rgba)
    )
    height, width = rgba.shape[:2]
    alpha = rgba[..., 3]
    colour = body_colour(rgba)
    body = rgba.copy()
    parts: list[dict[str, object]] = []
    out_dir = OUT / pose
    out_dir.mkdir(parents=True, exist_ok=True)

    solid = (alpha > 0.5).astype(np.uint8)

    # Limbs behind the body, in spec order (first = furthest back).
    softs = [soft_mask((width, height), cut.region, CUT_SOFTNESS) for cut in spec.cuts]
    removed = np.clip(np.sum(softs, axis=0), 0, 1) if softs else np.zeros_like(alpha)
    body_alpha = alpha * (1 - removed)
    # Behind a body of alpha a_b the limbs together need P = (alpha - a_b) / (1 - a_b) for the
    # stack to composite back to the drawn alpha. Limbs that meet share P by their mask weight:
    # 1 - prod(1 - P_i) = P with P_i = 1 - (1 - P) ** w_i.
    needed = np.where(
        body_alpha < 1, (alpha - body_alpha) / np.maximum(1 - body_alpha, 1e-6), 0
    )
    total = np.sum(softs, axis=0) if softs else np.zeros_like(alpha)
    kernel = cv2.getStructuringElement(
        cv2.MORPH_ELLIPSE, (ROOT_REACH * 2 + 1, ROOT_REACH * 2 + 1)
    )
    for cut, soft in zip(spec.cuts, softs, strict=True):
        hard = soft_mask((width, height), cut.region, 0) > 0.5
        inset = cv2.getStructuringElement(
            cv2.MORPH_ELLIPSE, (cut.root_inset * 2 + 1, cut.root_inset * 2 + 1)
        )
        inside = cv2.erode(solid, inset) if cut.root_inset > 0 else solid
        reach = np.asarray(
            cv2.dilate(hard.astype(np.uint8), kernel), dtype=np.uint8
        ) & np.asarray(inside, dtype=np.uint8)
        leg = np.zeros_like(hard)
        if cut.leg > 0:
            depth = cv2.distanceTransform(solid, cv2.DIST_L2, 5)
            above = np.clip(cut.pivot[1] - np.arange(height, dtype=np.float64), 0, None)
            near = cv2.getStructuringElement(
                cv2.MORPH_ELLIPSE, (cut.leg * 2 + 1, cut.leg * 2 + 1)
            )
            leg = (
                (depth >= LEG_EDGE + LEG_TAPER * above[:, None])
                & (above[:, None] > 0)
                & (above[:, None] <= cut.leg)
                & (cv2.dilate(hard.astype(np.uint8), near) > 0)
                & ~hard
            )
            reach = reach | leg.astype(np.uint8)
        root = cv2.GaussianBlur(reach.astype(np.float64), (0, 0), CUT_SOFTNESS)
        weight = np.where(total > 0, soft / np.maximum(total, 1e-6), 0)
        share = 1 - np.power(np.clip(1 - needed, 0, 1), weight)
        layer = rgba.copy()
        layer[..., :3][leg] = colour
        layer[..., 3] = np.clip(np.maximum(share, alpha * root), 0, 1)
        box = crop_save(layer, out_dir / f"{cut.name}.png")
        parts.append(
            {"name": cut.name, "z": "back", "frame": box, "pivot": list(cut.pivot)}
        )
    body[..., 3] = body_alpha

    for stroke in spec.strokes:
        x0, y0, x1, y1 = stroke.box
        region = body[y0:y1, x0:x1]
        light = region[..., :3].mean(-1)
        base = float(colour.mean())
        peak = float(light.max())
        amount = np.clip((light - base) / (peak - base), 0, 1) * region[..., 3]
        amount[light < base + STROKE_MIN] = 0
        layer = np.zeros_like(rgba)
        layer[y0:y1, x0:x1, :3] = peak
        layer[y0:y1, x0:x1, 3] = np.clip(amount, 0, 1)
        region[..., :3] = np.where(amount[..., None] > 0, colour, region[..., :3])
        box = crop_save(layer, out_dir / f"{stroke.name}.png")
        parts.append(
            {
                "name": stroke.name,
                "z": "front",
                "frame": box,
                "pivot": list(stroke.pivot),
            }
        )

    body_box = crop_save(body, out_dir / "body.png")
    return {"canvas": [width, height], "body": body_box, "parts": parts}


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    meta = {pose: split(pose, spec) for pose, spec in SPECS.items()}
    (OUT / "parts.json").write_text(json.dumps(meta, indent=1) + "\n", encoding="utf-8")
    for pose, spec in SPECS.items():
        print(pose, [c.name for c in spec.cuts] + [s.name for s in spec.strokes])


if __name__ == "__main__":
    main()
