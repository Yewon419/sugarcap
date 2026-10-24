"""Export the idle-pose rig (split parts + pose meta) into the iOS app bundle.

Parts are downscaled for the phone: a 2500 px canvas draws at about 130 pt,
so 0.2x still leaves a little over @3x. Frames and pivots stay in original
canvas pixels; the app draws each downscaled image stretched to its frame.

    python design/assets/characters/export_ios.py

Writes SugarCap/Resources/Idle.xcassets/idle-<character>-<art>-<part>.imageset
and SugarCap/Resources/idle-rig.json. The previous Idle.xcassets is replaced.
Pose definitions (<character>/poses.json: placement, motion, unlock stage) are
merged into SugarCap/Resources/idle-poses.json. The arts exported are the ones
poses.json names plus EXTRA_ARTS, so a new pose needs no change here.
"""

from __future__ import annotations

import json
import shutil
from pathlib import Path
from typing import NotRequired, TypedDict

from PIL import Image

ROOT = Path(__file__).resolve().parent
APP = ROOT.parents[2] / "SugarCap" / "Resources"
CATALOG = APP / "Idle.xcassets"
RIG = APP / "idle-rig.json"
POSES = APP / "idle-poses.json"
SCALE = 0.2

CHARACTER_IDS = ["roshu", "kain"]
# Arts the app draws that no idle pose uses. Roshu "stand" is the front-facing character art
# (feeding summary, intro); "gift-carry" walks a present onto Today (SPEC 4.9).
EXTRA_ARTS: dict[str, list[str]] = {
    "roshu": ["stand", "gift-carry"],
    "kain": ["gift-carry"],
}
# Arts whose canvas is not 2500 px. Roshu "stand" is 935x1024 and draws at 150 pt.
ART_SCALE: dict[str, float] = {"stand": 0.5}
# The pose canvases draw the character at different sizes, and the app draws every art of a
# character at one px->pt scale, so Today grew and shrank with the random pose. Each art's rig
# coordinates are multiplied by this factor so all poses match the smallest unoccluded one
# (roshu "wave", kain "swim"; 2026-10-24). Factor = sqrt(reference area / art area) of the
# character's own pixels (items filtered by color). Roshu hug-strawberry is already smaller and is
# left alone; roshu gift-carry is mostly hidden by the box, so it takes the walk factor.
ART_NORM: dict[str, dict[str, float]] = {
    "roshu": {
        "in-cup": 0.870,
        "watch": 0.857,
        "walk": 0.891,
        "slump": 0.796,
        "doze-lean": 0.796,
        "gift-carry": 0.891,
    },
    "kain": {
        "rim-stand": 0.989,
        "sit": 0.915,
        "walk": 0.964,
        "doze-one-leg": 0.998,
        "lie": 0.937,
        "gift-carry": 0.977,
    },
}


def scaled(values: list[float], k: float) -> list[float]:
    return [round(v * k, 1) for v in values]


class Eye(TypedDict):
    box: list[float]
    lid: str


class Part(TypedDict):
    name: str
    z: str
    frame: list[float]
    pivot: list[float]


class Art(TypedDict):
    canvas: list[float]
    bbox: list[float]
    rimLineY: float | None
    eyes: list[Eye]
    body: list[float]
    parts: list[Part]


def asset_name(character: str, art: str, part: str) -> str:
    return f"idle-{character}-{art}-{part}"


def write_imageset(name: str, source: Path, scale: float) -> None:
    folder = CATALOG / f"{name}.imageset"
    folder.mkdir(parents=True)
    with Image.open(source) as image:
        rgba = image.convert("RGBA")
        size = (max(1, round(rgba.width * scale)), max(1, round(rgba.height * scale)))
        rgba.resize(size, Image.Resampling.LANCZOS).save(
            folder / "part.png", optimize=True
        )
    contents = {
        "images": [{"filename": "part.png", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
    }
    (folder / "Contents.json").write_text(
        json.dumps(contents, indent=2) + "\n", encoding="utf-8"
    )


def arts_for(character: str, book: PoseBook) -> list[str]:
    used = dict.fromkeys(pose["art"] for pose in book["poses"].values())
    return [*used, *(a for a in EXTRA_ARTS.get(character, []) if a not in used)]


def export_character(character: str, arts: list[str]) -> dict[str, Art]:
    meta = json.loads(
        (ROOT / character / "poses" / "meta.json").read_text(encoding="utf-8")
    )
    parts = json.loads(
        (ROOT / character / "parts" / "parts.json").read_text(encoding="utf-8")
    )
    out: dict[str, Art] = {}
    for art in arts:
        if art not in meta or art not in parts:
            raise KeyError(
                f"{character}/{art}: missing from poses/meta.json or parts/parts.json"
                " (run import_layers.py for layered art)"
            )
        pose_meta = meta[art]
        rig = parts[art]
        folder = ROOT / character / "parts" / art
        scale = ART_SCALE.get(art, SCALE)
        write_imageset(asset_name(character, art, "body"), folder / "body.png", scale)
        for part in rig["parts"]:
            write_imageset(
                asset_name(character, art, part["name"]),
                folder / f"{part['name']}.png",
                scale,
            )
        k = ART_NORM[character].get(art, 1.0)
        rim_line = pose_meta["rimLineY"]
        out[art] = Art(
            canvas=scaled(pose_meta["canvas"], k),
            bbox=scaled(pose_meta["bbox"], k),
            rimLineY=None if rim_line is None else round(rim_line * k, 1),
            eyes=[
                Eye(box=scaled(e["box"], k), lid=e["lid"]) for e in pose_meta["eyes"]
            ],
            body=scaled(rig["body"], k),
            parts=[
                Part(
                    name=p["name"],
                    z=p["z"],
                    frame=scaled(p["frame"], k),
                    pivot=scaled(p["pivot"], k),
                )
                for p in rig["parts"]
            ],
        )
    return out


class PoseSpec(TypedDict):
    art: str
    # "from" is canvas px (beak tip), so it takes the art's ART_NORM factor.
    bubbles: NotRequired[dict[str, object]]


class PoseBook(TypedDict):
    zero: str
    poses: dict[str, PoseSpec]


def load_poses(character: str) -> PoseBook:
    book: PoseBook = json.loads(
        (ROOT / character / "poses.json").read_text(encoding="utf-8")
    )
    if book["zero"] not in book["poses"]:
        raise KeyError(f"{character}: zero pose {book['zero']!r} is not defined")
    return book


def main() -> None:
    if CATALOG.exists():
        shutil.rmtree(CATALOG)
    CATALOG.mkdir(parents=True)
    (CATALOG / "Contents.json").write_text(
        json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n",
        encoding="utf-8",
    )
    poses = {character: load_poses(character) for character in CHARACTER_IDS}
    for character, book in poses.items():
        for pose in book["poses"].values():
            bubbles = pose.get("bubbles")
            if bubbles is None:
                continue
            start = bubbles["from"]
            if not isinstance(start, list):
                raise TypeError(
                    f"{character}/{pose['art']}: bubbles.from must be [x, y]"
                )
            bubbles["from"] = scaled(start, ART_NORM[character].get(pose["art"], 1.0))
    rig = {
        character: export_character(character, arts_for(character, poses[character]))
        for character in CHARACTER_IDS
    }
    RIG.write_text(
        json.dumps(rig, indent=1, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    POSES.write_text(
        json.dumps(poses, indent=1, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    count = sum(1 for _ in CATALOG.glob("*.imageset"))
    print(f"{count} images -> {CATALOG}")
    print(f"rig -> {RIG}")
    print(f"poses -> {POSES}")


if __name__ == "__main__":
    main()
