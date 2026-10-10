"""Cut the lid off the gift box in a gift-carry art so the app can open it (SPEC 4.9).

The lid is the top 10% of the box square plus the bow above it. It becomes its own
part (lid.png) hinged at the square's bottom-left corner of the cut. Where the lid was,
the box gets a flat dark interior so the opened box shows its inside instead of a hole.

The closed box is kept as _<layer>_closed.png (the importer skips "_" files) and is the
input on every run, so the script can be run again after the art changes.

    python design/assets/characters/split_gift_lid.py <character>

Then run import_layers.py <character> gift-carry and export_ios.py.
"""

from __future__ import annotations

import argparse
import json
import shutil
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent
ART = "gift-carry"
# Keep the interior inside the box outline so the lid's soft edge never sits on it.
INSET = 6
LID_SHARE = 0.10


@dataclass(frozen=True)
class Box:
    layer: str
    # Box square [x0, y0, x1, y1] in canvas px, bow excluded.
    square: tuple[int, int, int, int]
    interior: tuple[int, int, int]


BOXES: dict[str, Box] = {
    # Roshu's box is painted into body.png; Kain's is its own back layer.
    "roshu": Box("body", (522, 706, 1632, 1747), (150, 120, 40)),
    "kain": Box("box", (324, 1504, 1261, 2437), (70, 120, 80)),
}


def lid_cut(square: tuple[int, int, int, int]) -> int:
    _, y0, _, y1 = square
    return y0 + round((y1 - y0) * LID_SHARE)


def split(closed: np.ndarray, box: Box) -> tuple[np.ndarray, np.ndarray]:
    """Return (box layer without the lid, lid layer), both full canvas."""
    x0, y0, x1, _ = box.square
    cut = lid_cut(box.square)
    lid = np.zeros_like(closed)
    lid[:cut] = closed[:cut]
    rest = closed.copy()
    rest[:cut] = 0
    rest[y0 + INSET : cut, x0 + INSET : x1 - INSET] = (*box.interior, 255)
    return rest, lid


def main() -> None:
    parser = argparse.ArgumentParser(description=(__doc__ or "").split("\n", 1)[0])
    parser.add_argument("character", choices=sorted(BOXES))
    character: str = parser.parse_args().character
    box = BOXES[character]
    source = ROOT / character / "layers" / ART
    closed_path = source / f"_{box.layer}_closed.png"
    if not closed_path.exists():
        shutil.copyfile(source / f"{box.layer}.png", closed_path)
    with Image.open(closed_path) as image:
        closed = np.asarray(image.convert("RGBA")).copy()

    rest, lid = split(closed, box)
    Image.fromarray(rest, "RGBA").save(source / f"{box.layer}.png", optimize=True)
    Image.fromarray(lid, "RGBA").save(source / "lid.png", optimize=True)

    rig_path = source / "rig.json"
    rig = json.loads(rig_path.read_text(encoding="utf-8"))
    rig.setdefault("pivots", {})["lid"] = [box.square[0], lid_cut(box.square)]
    # The lid sits on the box: in front of the body when the box is (Roshu holds it),
    # behind it when the box is a back layer (Kain sits in front of his).
    front: list[str] = rig.setdefault("front", [])
    in_front = box.layer == "body" or box.layer in front
    if in_front and "lid" not in front:
        front.append("lid")
    if not in_front and "lid" in front:
        front.remove("lid")
    rig_path.write_text(json.dumps(rig, ensure_ascii=False) + "\n", encoding="utf-8")
    print(
        f"{character}: lid cut at y={lid_cut(box.square)}, hinge {rig['pivots']['lid']}"
    )


if __name__ == "__main__":
    main()
