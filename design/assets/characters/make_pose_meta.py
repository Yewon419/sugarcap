"""Measure character pose art for the motion prototype and, later, SwiftUI.

For every pose PNG this records the opaque bounding box, the eye blobs (small
pure-white components, used to draw blinking lids) and the body colour next to
each eye (the lid colour). Coordinates are canvas pixels of the source PNG.

    python design/assets/characters/make_pose_meta.py

Writes <character>/poses/meta.json for every character.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage  # type: ignore[import-untyped]  # scipy ships no stubs here

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[2]
STAND = REPO / "SugarCap/Resources/Shared.xcassets/character-roshu.imageset/roshu.png"

WHITE_MIN = 240
OPAQUE_MIN = 250


@dataclass(frozen=True)
class Character:
    poses: Path
    # Eye blobs larger than this share of the opaque area are not eyes.
    eye_max_area_ratio: float
    extra: dict[str, Path] = field(default_factory=dict)
    # A pose with a transparent line where the cup rim goes (drawn by hand, measured once).
    rim_line_y: dict[str, int] = field(default_factory=dict)
    # A pose whose white limb bands or half-hidden nose read as eyes: only blobs inside
    # this box (x0, y0, x1, y1, measured once) count.
    eye_region: dict[str, tuple[int, int, int, int]] = field(default_factory=dict)


CHARACTERS = {
    "roshu": Character(
        ROOT / "roshu" / "poses",
        eye_max_area_ratio=0.004,
        extra={"stand": STAND},
        rim_line_y={"in-cup": 1100},
        eye_region={"hug-strawberry": (1435, 1100, 1500, 1200)},
    ),
    # Kain's eyes are a white ring round a black pupil, about 2.4% of the body.
    "kain": Character(ROOT / "kain" / "poses", eye_max_area_ratio=0.03),
}


def measure(path: Path, character: Character) -> dict[str, object]:
    rgba = np.array(Image.open(path).convert("RGBA")).astype(int)
    opaque = rgba[..., 3] > 128
    ys, xs = np.nonzero(opaque)
    white = opaque & (rgba[..., :3].min(-1) > WHITE_MIN)
    labels, count = ndimage.label(white)
    max_area = opaque.sum() * character.eye_max_area_ratio
    rim = character.rim_line_y.get(path.stem)
    region = character.eye_region.get(path.stem)
    eyes: list[dict[str, object]] = []
    for index in range(1, count + 1):
        ey, ex = np.nonzero(labels == index)
        if len(ey) < 100 or len(ey) > max_area:
            continue
        if rim is not None and ey.max() > rim:
            continue  # highlights on the submerged body, not eyes
        x0, y0, x1, y1 = int(ex.min()), int(ey.min()), int(ex.max()), int(ey.max())
        if region is not None and not (
            region[0] <= x0 and region[1] <= y0 and x1 <= region[2] and y1 <= region[3]
        ):
            continue
        # Lid colour from the body left of the eye, or right of it when the eye sits at the left edge.
        sample_x = max(x0 - (x1 - x0) // 2, 0)
        if rgba[(y0 + y1) // 2, sample_x, 3] < OPAQUE_MIN:
            sample_x = min(x1 + (x1 - x0) // 2, rgba.shape[1] - 1)
        lid = rgba[(y0 + y1) // 2, sample_x]
        if lid[3] < OPAQUE_MIN:
            raise ValueError(f"no body next to eye {x0, y0, x1, y1} in {path}")
        eyes.append(
            {
                "box": [x0, y0, x1, y1],
                "lid": "#" + "".join(f"{int(v):02X}" for v in lid[:3]),
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
    for name, character in CHARACTERS.items():
        meta = {
            path.stem: measure(path, character)
            for path in sorted(character.poses.glob("*.png"))
        }
        for pose, path in character.extra.items():
            meta[pose] = measure(path, character)
        out = character.poses / "meta.json"
        out.write_text(
            json.dumps(meta, indent=1, ensure_ascii=False) + "\n", encoding="utf-8"
        )
        for pose, item in meta.items():
            print(name, pose, item["bbox"], len(item["eyes"]), "eyes")  # type: ignore[arg-type]


if __name__ == "__main__":
    main()
