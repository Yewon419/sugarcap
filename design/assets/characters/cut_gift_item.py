"""Cut the gift items for the gift reveal stage and the collection (SPEC 4.9).

Strawberry: painted into Roshu's hug-strawberry pose. Its pixels are the red flesh plus the
dark seeds inside it; Roshu's grey body and white arm lines are dropped. Small notches where
the arm crossed the tip are filled with the flesh red so the outline is clean. The cut is
turned tip-down and trimmed.

Coffee bean (Kain's): drawn on its own canvas as two layers, the dark side under the face
(kain/items/coffee-bean/side.png, face.png). They are stacked and trimmed.

Sugar cube (Roshu's): the three face layers of Roshu's sugar-cube pose
(roshu/layers/sugar-cube/cube_right.png, cube_left.png, cube_top.png), stacked as the pose
draws them and trimmed.

Cinnamon stick (Kain's, a box reward): the two stick layers of Kain's cinnamon-stick pose
(kain/layers/cinnamon-stick/foot_stick_back.png, foot_stick_front.png), stacked and trimmed.

All are written for the app at about @3x, the longer side APP_SIZE px.

    python design/assets/characters/cut_gift_item.py

Writes roshu/items/strawberry.png, kain/items/coffee-bean.png, roshu/items/sugar-cube.png,
kain/items/cinnamon-stick.png and the gift-item-strawberry / gift-item-coffee-bean /
gift-item-sugar-cube / gift-item-cinnamon-stick imagesets in SugarCap/Resources/Assets.xcassets.
"""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage
from scipy.spatial import ConvexHull

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "roshu" / "poses" / "hug-strawberry.png"
OUT = ROOT / "roshu" / "items" / "strawberry.png"
BEAN_LAYERS = [
    ROOT / "kain" / "items" / "coffee-bean" / name for name in ("side.png", "face.png")
]
BEAN_OUT = ROOT / "kain" / "items" / "coffee-bean.png"
CUBE_LAYERS = [
    ROOT / "roshu" / "layers" / "sugar-cube" / f"{name}.png"
    for name in ("cube_right", "cube_left", "cube_top")
]
CUBE_OUT = ROOT / "roshu" / "items" / "sugar-cube.png"
CINNAMON_LAYERS = [
    ROOT / "kain" / "layers" / "cinnamon-stick" / f"{name}.png"
    for name in ("foot_stick_back", "foot_stick_front")
]
CINNAMON_OUT = ROOT / "kain" / "items" / "cinnamon-stick.png"
ASSETS = ROOT.parents[2] / "SugarCap" / "Resources" / "Assets.xcassets"
# Turn so the tip points straight down (counterclockwise degrees).
TURN = -28.0
# Drawn at about 110 pt on the phone (the strawberry is wider than tall, so this is its width).
APP_SIZE = 330


def flesh_mask(rgba: np.ndarray) -> np.ndarray:
    r = rgba[..., 0].astype(int)
    g = rgba[..., 1].astype(int)
    b = rgba[..., 2].astype(int)
    a = rgba[..., 3].astype(int)
    red = (r - g > 50) & (r - b > 50) & (a > 40)
    # Keep the largest red region (the strawberry), close the seeds and the arm notches.
    labels, count = ndimage.label(red)
    if count == 0:
        raise SystemExit(f"no red pixels in {SOURCE}")
    sizes = ndimage.sum(red, labels, range(1, count + 1))
    berry = labels == (int(np.argmax(sizes)) + 1)
    # The strawberry is convex; its hull fills the notches where Roshu's arm crossed it.
    ys, xs = np.nonzero(berry)
    points = np.column_stack([xs, ys])
    hull = points[ConvexHull(points).vertices]
    canvas = Image.new("L", (rgba.shape[1], rgba.shape[0]), 0)
    ImageDraw.Draw(canvas).polygon([(int(x), int(y)) for x, y in hull], fill=255)
    return np.asarray(canvas) > 0


def trimmed(cut: Image.Image) -> Image.Image:
    box = cut.getchannel("A").point(lambda v: 255 if v > 20 else 0).getbbox()
    if box is None:
        raise SystemExit("empty cut")
    return cut.crop(box)


def write_item(cut: Image.Image, out: Path, asset: str, filename: str) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    cut.save(out, optimize=True)
    scale = APP_SIZE / max(cut.width, cut.height)
    size = (round(cut.width * scale), round(cut.height * scale))
    catalog = ASSETS / f"{asset}.imageset"
    catalog.mkdir(parents=True, exist_ok=True)
    cut.resize(size, Image.Resampling.LANCZOS).save(catalog / filename, optimize=True)
    contents = {
        "images": [{"filename": filename, "idiom": "universal", "scale": "3x"}],
        "info": {"author": "xcode", "version": 1},
    }
    (catalog / "Contents.json").write_text(
        json.dumps(contents, indent=2) + "\n", encoding="utf-8"
    )
    print(f"{out} {cut.size}, app {size[0]}x{size[1]}")


def cut_strawberry() -> None:
    with Image.open(SOURCE) as image:
        rgba = np.asarray(image.convert("RGBA")).copy()
    mask = flesh_mask(rgba)
    r = rgba[..., 0].astype(int)
    g = rgba[..., 1].astype(int)
    keep_paint = (r - g > 50) | (r < 90)
    flesh = np.median(rgba[mask & (r - g > 50)][:, :3], axis=0).astype(np.uint8)
    out = np.zeros_like(rgba)
    out[mask] = rgba[mask]
    patch = mask & ~keep_paint
    out[patch, :3] = flesh
    out[mask, 3] = 255
    # Soft 1 px edge from the mask so the cut is not jagged.
    edge = ndimage.gaussian_filter(mask.astype(float), 1.2)
    out[..., 3] = np.clip(edge * 255, 0, 255).astype(np.uint8)
    out[~ndimage.binary_dilation(mask, iterations=2), :3] = flesh

    cut = Image.fromarray(out, "RGBA").rotate(
        TURN, resample=Image.Resampling.BICUBIC, expand=True
    )
    write_item(trimmed(cut), OUT, "gift-item-strawberry", "strawberry.png")


def stacked(paths: list[Path], what: str) -> Image.Image:
    layers = []
    for path in paths:
        with Image.open(path) as image:
            layers.append(image.convert("RGBA"))
    stack = Image.new("RGBA", layers[0].size, (0, 0, 0, 0))
    for layer in layers:
        if layer.size != stack.size:
            raise SystemExit(
                f"{layer.size} != {stack.size}: {what} layers differ in size"
            )
        stack.alpha_composite(layer)
    return trimmed(stack)


def cut_coffee_bean() -> None:
    cut = stacked(BEAN_LAYERS, "coffee bean")
    write_item(cut, BEAN_OUT, "gift-item-coffee-bean", "coffee-bean.png")


def cut_sugar_cube() -> None:
    cut = stacked(CUBE_LAYERS, "sugar cube")
    write_item(cut, CUBE_OUT, "gift-item-sugar-cube", "sugar-cube.png")


def cut_cinnamon_stick() -> None:
    cut = stacked(CINNAMON_LAYERS, "cinnamon stick")
    write_item(cut, CINNAMON_OUT, "gift-item-cinnamon-stick", "cinnamon-stick.png")


def main() -> None:
    cut_strawberry()
    cut_coffee_bean()
    cut_sugar_cube()
    cut_cinnamon_stick()


if __name__ == "__main__":
    main()
