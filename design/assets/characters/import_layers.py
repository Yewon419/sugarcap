"""Import a pose drawn as separate layers (body and limbs on one canvas) into the idle rig.

Put full-canvas PNGs of the same size in <character>/layers/<art>/:

    body.png      required
    <part>.png    one per limb; the file name is the part name (foot_* stays on the
                  ground layer, every other part moves with the body)
    rig.json      optional: {"pivots": {"arm": [x, y]}, "front": ["arm"], "overlays": ["eye_closed"]}

Limbs go behind the body unless listed in "front". A limb turns around its pivot.
An overlay (a swapped face part such as closed eyes) sits on the body above the lids,
never turns, is left out of the composite and shows only while its "show.<name>"
motion value is at least 0.5.
The pivot defaults to the middle of where the limb meets the body (limb pixels within
CONTACT px of the body); set it in rig.json when the guess is wrong. A preview with
the pivots marked is written next to the layers.

    python design/assets/characters/import_layers.py <character> <art>

Writes <character>/parts/<art>/*.png (cropped), the <art> entry of parts.json, the
composite <character>/poses/<art>.png and the <art> entry of poses/meta.json. Then add
the pose to <character>/poses.json and run export_ios.py.
"""

from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import TypedDict

import cv2
import numpy as np
from PIL import Image, ImageDraw

from make_pose_meta import CHARACTERS, measure
from split_limbs import EDGE_FAINT, EDGE_FILL_SIGMA, FloatImage, body_colour, crop_save

ROOT = Path(__file__).resolve().parent
# A limb pixel this close to the body counts as the joint.
CONTACT = 12
PART_NAME = re.compile(r"^[a-z][a-z0-9_]*$")


class RigFile(TypedDict, total=False):
    pivots: dict[str, list[int]]
    front: list[str]
    overlays: list[str]


class PartEntry(TypedDict):
    name: str
    z: str
    frame: list[int]
    pivot: list[int]


class ArtEntry(TypedDict):
    canvas: list[int]
    body: list[int]
    parts: list[PartEntry]


@dataclass(frozen=True)
class Layer:
    name: str
    pixels: FloatImage


def load_layer(path: Path, size: tuple[int, int] | None) -> FloatImage:
    with Image.open(path) as image:
        if size is not None and image.size != size:
            raise ValueError(
                f"{path.name}: canvas {image.size} differs from body {size}"
            )
        rgba = np.asarray(image.convert("RGBA"), dtype=np.float64) / 255
    return fill_faint_edges(rgba)


def fill_faint_edges(rgba: FloatImage) -> FloatImage:
    """Faint edge pixels carry junk colour that bleeds in when a moved layer is resampled.

    Give them the colour of their opaque neighbourhood (same treatment as split_limbs).
    """
    out = rgba.copy()
    weight = out[..., 3]
    if not (weight > 0.99).any():
        return out
    spread = cv2.GaussianBlur(weight, (0, 0), EDGE_FILL_SIGMA)
    filled = (
        np.stack(
            [
                cv2.GaussianBlur(out[..., c] * weight, (0, 0), EDGE_FILL_SIGMA)
                for c in range(3)
            ],
            axis=-1,
        )
        / np.maximum(spread, 1e-6)[..., None]
    )
    faint = weight < EDGE_FAINT
    out[..., :3][faint] = np.where(
        spread[faint, None] > 1e-6, filled[faint], body_colour(out)
    )
    return out


def guess_pivot(limb: FloatImage, body: FloatImage, name: str) -> list[int]:
    solid = (body[..., 3] > 0.5).astype(np.uint8)
    kernel = cv2.getStructuringElement(
        cv2.MORPH_ELLIPSE, (CONTACT * 2 + 1, CONTACT * 2 + 1)
    )
    near = cv2.dilate(solid, kernel) > 0
    ys, xs = np.nonzero((limb[..., 3] > 0.5) & near)
    if len(ys) == 0:
        raise ValueError(
            f"{name}: does not touch the body; set its pivot in rig.json "
            '({"pivots": {"' + name + '": [x, y]}})'
        )
    return [int(np.rint(xs.mean())), int(np.rint(ys.mean()))]


def over(top: FloatImage, under: FloatImage) -> FloatImage:
    a = top[..., 3:4]
    b = under[..., 3:4]
    alpha = a + b * (1 - a)
    colour = (top[..., :3] * a + under[..., :3] * b * (1 - a)) / np.maximum(alpha, 1e-6)
    return np.concatenate([colour, alpha], axis=-1)


def import_art(source: Path, parts_out: Path) -> tuple[ArtEntry, FloatImage]:
    """Crop the layers into parts_out and return the parts.json entry and the composite."""
    body_path = source / "body.png"
    if not body_path.exists():
        raise FileNotFoundError(f"{body_path} is required")
    with Image.open(body_path) as image:
        size = image.size
    body = load_layer(body_path, None)
    rig: RigFile = {}
    rig_path = source / "rig.json"
    if rig_path.exists():
        rig = json.loads(rig_path.read_text(encoding="utf-8"))
    pivots = rig.get("pivots", {})
    front = set(rig.get("front", []))
    overlays = set(rig.get("overlays", []))
    if front & overlays:
        raise ValueError(
            f"rig.json: {sorted(front & overlays)} are both front and overlay"
        )

    limbs: list[Layer] = []
    for path in sorted(source.glob("*.png")):
        if path.stem == "body" or path.stem.startswith("_"):
            continue
        if not PART_NAME.match(path.stem):
            raise ValueError(f"{path.name}: part names are lower_snake_case")
        limbs.append(Layer(path.stem, load_layer(path, size)))
    if not limbs:
        raise ValueError(f"{source}: no limb layers next to body.png")
    names = {limb.name for limb in limbs}
    for name in [*pivots, *front, *overlays]:
        if name not in names:
            raise ValueError(f"rig.json names {name!r} but there is no {name}.png")

    parts_out.mkdir(parents=True, exist_ok=True)
    for stale in parts_out.glob("*.png"):
        stale.unlink()
    parts: list[PartEntry] = []
    composite = np.zeros_like(body)
    for limb in (limb for limb in limbs if limb.name not in front | overlays):
        composite = over(limb.pixels, composite)
    composite = over(body, composite)
    for limb in (limb for limb in limbs if limb.name in front):
        composite = over(limb.pixels, composite)

    for limb in limbs:
        frame = crop_save(limb.pixels, parts_out / f"{limb.name}.png")
        if limb.name in overlays:
            pivot = [frame[0] + frame[2] // 2, frame[1] + frame[3] // 2]
            z = "overlay"
        else:
            pivot = pivots.get(limb.name) or guess_pivot(limb.pixels, body, limb.name)
            z = "front" if limb.name in front else "back"
        parts.append(
            PartEntry(
                name=limb.name,
                z=z,
                frame=frame,
                pivot=[int(pivot[0]), int(pivot[1])],
            )
        )
    body_box = crop_save(body, parts_out / "body.png")
    entry = ArtEntry(canvas=[size[0], size[1]], body=body_box, parts=parts)
    return entry, composite


def save_preview(composite: FloatImage, entry: ArtEntry, path: Path) -> None:
    pixels = np.clip(np.round(composite * 255), 0, 255).astype(np.uint8)
    image = Image.alpha_composite(
        Image.new("RGBA", (pixels.shape[1], pixels.shape[0]), (255, 255, 255, 255)),
        Image.fromarray(pixels, "RGBA"),
    )
    draw = ImageDraw.Draw(image)
    r = max(6, pixels.shape[1] // 200)
    for part in entry["parts"]:
        x, y = part["pivot"]
        draw.ellipse(
            (x - r, y - r, x + r, y + r), outline=(230, 30, 30, 255), width=r // 2
        )
        draw.text((x + r * 1.5, y - r), part["name"], fill=(230, 30, 30, 255))
    image.save(path)


def update_json(path: Path, key: str, value: object) -> None:
    data = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
    data[key] = value
    path.write_text(
        json.dumps(data, indent=1, ensure_ascii=False) + "\n", encoding="utf-8"
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=(__doc__ or "").split("\n", 1)[0])
    parser.add_argument("character", choices=sorted(CHARACTERS))
    parser.add_argument("art")
    args = parser.parse_args()
    character: str = args.character
    art: str = args.art
    base = ROOT / character
    source = base / "layers" / art
    entry, composite = import_art(source, base / "parts" / art)
    update_json(base / "parts" / "parts.json", art, entry)

    pose_png = base / "poses" / f"{art}.png"
    pixels = np.clip(np.round(composite * 255), 0, 255).astype(np.uint8)
    Image.fromarray(pixels, "RGBA").save(pose_png, optimize=True)
    update_json(
        base / "poses" / "meta.json", art, measure(pose_png, CHARACTERS[character])
    )
    save_preview(composite, entry, source / "_pivots.png")

    for part in entry["parts"]:
        print(
            f"{character}/{art} {part['name']:14s} {part['z']:5s} pivot {part['pivot']}"
        )
    print(f"preview -> {source / '_pivots.png'}")


if __name__ == "__main__":
    main()
