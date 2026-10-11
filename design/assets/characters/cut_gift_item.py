"""Cut the strawberry out of Roshu's hug-strawberry art for the gift reveal stage (SPEC 4.9).

The strawberry is painted into the pose together with Roshu. Its pixels are the red flesh
plus the dark seeds inside it; Roshu's grey body and white arm lines are dropped. Small
notches where the arm crossed the tip are filled with the flesh red so the outline is clean.
The cut is turned tip-down and trimmed, then written for the app at about @3x.

    python design/assets/characters/cut_gift_item.py

Writes roshu/items/strawberry.png and SugarCap/Resources/Assets.xcassets/gift-item-strawberry.imageset.
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
CATALOG = ROOT.parents[2] / "SugarCap" / "Resources" / "Assets.xcassets" / "gift-item-strawberry.imageset"
# Turn so the tip points straight down (counterclockwise degrees).
TURN = -28.0
# Drawn at about 110 pt on the phone.
APP_WIDTH = 330


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


def main() -> None:
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

    cut = Image.fromarray(out, "RGBA").rotate(TURN, resample=Image.Resampling.BICUBIC, expand=True)
    box = cut.getchannel("A").point(lambda v: 255 if v > 20 else 0).getbbox()
    if box is None:
        raise SystemExit("empty cut")
    cut = cut.crop(box)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    cut.save(OUT, optimize=True)

    height = round(cut.height * APP_WIDTH / cut.width)
    CATALOG.mkdir(parents=True, exist_ok=True)
    cut.resize((APP_WIDTH, height), Image.Resampling.LANCZOS).save(CATALOG / "strawberry.png", optimize=True)
    contents = {
        "images": [{"filename": "strawberry.png", "idiom": "universal", "scale": "3x"}],
        "info": {"author": "xcode", "version": 1},
    }
    (CATALOG / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n", encoding="utf-8")
    print(f"{OUT} {cut.size}, app {APP_WIDTH}x{height}")


if __name__ == "__main__":
    main()
