"""Prepare the face side of the watch pose for its reflection in the cup glass.

The watch pose is drawn from behind, clinging to the cup and looking in, so the glass reflects its
face. `watch-front.png` (drawn by hand) is that pose seen from the front. Mirrored left to right it
lines up exactly with the back view, which is the orientation the reflection samples in.

    python design/assets/characters/make_watch_face.py
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent
FRONT = ROOT / "roshu" / "poses" / "watch-front.png"
BACK = ROOT / "roshu" / "poses" / "watch.png"
OUT = ROOT / "roshu" / "parts" / "watch" / "face.png"
MIN_OVERLAP = 0.98


def main() -> None:
    front = Image.open(FRONT).convert("RGBA").transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    back = Image.open(BACK).convert("RGBA")
    if front.size != back.size:
        raise ValueError(f"canvas mismatch: front {front.size}, back {back.size}")
    a = np.asarray(front)[..., 3] > 128
    b = np.asarray(back)[..., 3] > 128
    overlap = float((a & b).sum() / (a | b).sum())
    if overlap < MIN_OVERLAP:
        raise ValueError(
            f"mirrored front does not match the back silhouette: IoU {overlap:.3f}"
        )
    OUT.parent.mkdir(parents=True, exist_ok=True)
    front.save(OUT, optimize=True)
    print(OUT.relative_to(ROOT), front.size, f"IoU {overlap:.4f}")


if __name__ == "__main__":
    main()
