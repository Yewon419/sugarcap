"""Measure Roshu pose art for the motion prototype and, later, SwiftUI.

For every pose PNG this records the opaque bounding box, the eye blobs (small
pure-white components, used to draw blinking lids) and the body colour next to
each eye (the lid colour). Coordinates are canvas pixels of the source PNG.

    python design/assets/characters/make_pose_meta.py
"""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage  # type: ignore[import-untyped]  # scipy ships no stubs here

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[2]
POSES = ROOT / "roshu" / "poses"
STAND = REPO / "SugarCap/Resources/Shared.xcassets/character-roshu.imageset/roshu.png"

EYE_MAX_AREA_RATIO = 0.004
WHITE_MIN = 240

# The in-cup pose has a transparent line where the cup rim goes (drawn by hand, measured once).
RIM_LINE_Y = {"in-cup": 1100}


def measure(path: Path) -> dict[str, object]:
    rgba = np.array(Image.open(path).convert("RGBA")).astype(int)
    opaque = rgba[..., 3] > 128
    ys, xs = np.nonzero(opaque)
    white = opaque & (rgba[..., :3].min(-1) > WHITE_MIN)
    labels, count = ndimage.label(white)
    max_area = opaque.sum() * EYE_MAX_AREA_RATIO
    rim = RIM_LINE_Y.get(path.stem)
    eyes: list[dict[str, object]] = []
    for index in range(1, count + 1):
        ey, ex = np.nonzero(labels == index)
        if len(ey) < 100 or len(ey) > max_area:
            continue
        if rim is not None and ey.max() > rim:
            continue  # highlights on the submerged body, not eyes
        x0, y0, x1, y1 = int(ex.min()), int(ey.min()), int(ex.max()), int(ey.max())
        sample_x = max(x0 - (x1 - x0) // 2, 0)
        lid = rgba[(y0 + y1) // 2, sample_x, :3]
        eyes.append(
            {
                "box": [x0, y0, x1, y1],
                "lid": "#" + "".join(f"{int(v):02X}" for v in lid),
            }
        )
    eyes.sort(key=lambda eye: eye["box"][0])  # type: ignore[index]
    width, height = int(rgba.shape[1]), int(rgba.shape[0])
    return {
        "file": path.relative_to(REPO).as_posix(),
        "canvas": [width, height],
        "bbox": [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())],
        "eyes": eyes,
        "rimLineY": rim,
    }


def main() -> None:
    meta = {path.stem: measure(path) for path in sorted(POSES.glob("*.png"))}
    meta["stand"] = measure(STAND)
    out = POSES / "meta.json"
    out.write_text(
        json.dumps(meta, indent=1, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    for name, item in meta.items():
        print(name, item["bbox"], len(item["eyes"]), "eyes")  # type: ignore[arg-type]


if __name__ == "__main__":
    main()
