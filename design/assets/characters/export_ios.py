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
from typing import TypedDict

from PIL import Image

ROOT = Path(__file__).resolve().parent
APP = ROOT.parents[2] / "SugarCap" / "Resources"
CATALOG = APP / "Idle.xcassets"
RIG = APP / "idle-rig.json"
POSES = APP / "idle-poses.json"
SCALE = 0.2

CHARACTER_IDS = ["roshu", "kain"]
# Arts the app draws that no idle pose uses. Roshu "stand" is the front-facing character art
# (feeding summary, intro).
EXTRA_ARTS: dict[str, list[str]] = {"roshu": ["stand"]}
# Arts whose canvas is not 2500 px. Roshu "stand" is 935x1024 and draws at 150 pt.
ART_SCALE: dict[str, float] = {"stand": 0.5}


class Eye(TypedDict):
    box: list[int]
    lid: str


class Part(TypedDict):
    name: str
    z: str
    frame: list[int]
    pivot: list[int]


class Art(TypedDict):
    canvas: list[int]
    bbox: list[int]
    rimLineY: int | None
    eyes: list[Eye]
    body: list[int]
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
        out[art] = Art(
            canvas=pose_meta["canvas"],
            bbox=pose_meta["bbox"],
            rimLineY=pose_meta["rimLineY"],
            eyes=pose_meta["eyes"],
            body=rig["body"],
            parts=rig["parts"],
        )
    return out


class PoseSpec(TypedDict):
    art: str


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
