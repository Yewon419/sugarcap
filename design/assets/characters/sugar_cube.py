"""Measure a cube drawn as three face layers so the app can tilt it by computation.

Roshu's sugar-cube pose (roshu/layers/sugar-cube/) has the cube's three visible faces as
separate layers: cube_top.png, cube_left.png, cube_right.png. Each face is a
parallelogram. Its four corners are found from the alpha outline and all twelve corners
are fitted, by least squares, to one cube under parallel projection:

    screen(x, y, z) = origin + x * ex + y * ey + z * ez      (x, y, z in 0..1)

origin is the front-bottom corner, ey points up, ex runs to the left-back corner and ez
to the right-back corner. The left face is the plane z = 0, the right face x = 0 and the
top y = 1. Turning the cube is a 3D rotation of the unit cube followed by the same
projection, so every face moves by one affine transform (exact for parallel projection)
and the faces are drawn from the art unchanged when the cube is at rest.

import_layers.py calls measure() when rig.json has "cube"; the result goes into the art's
parts.json entry. Run alone to print the fit:

    python design/assets/characters/sugar_cube.py
"""

from __future__ import annotations

from pathlib import Path
from typing import TypedDict

import cv2
import numpy as np
from numpy.typing import NDArray
from PIL import Image

ROOT = Path(__file__).resolve().parent
ALPHA = 128
Corner = tuple[int, int, int]
# Unit-cube corner of each outline vertex, walked clockwise on screen from the topmost one.
FACE_CORNERS: dict[str, list[Corner]] = {
    "cube_top": [(1, 1, 1), (0, 1, 1), (0, 1, 0), (1, 1, 0)],
    "cube_left": [(1, 1, 0), (0, 1, 0), (0, 0, 0), (1, 0, 0)],
    "cube_right": [(0, 1, 1), (0, 0, 1), (0, 0, 0), (0, 1, 0)],
}
# Corner at u = v = 0, the u axis and the v axis of each face, in cube units.
FACE_SPAN: dict[str, tuple[Corner, Corner, Corner]] = {
    "cube_top": ((0, 1, 0), (1, 0, 0), (0, 0, 1)),
    "cube_left": ((0, 0, 0), (1, 0, 0), (0, 1, 0)),
    "cube_right": ((0, 0, 0), (0, 0, 1), (0, 1, 0)),
}
FACE_NORMAL: dict[str, Corner] = {
    "cube_top": (0, 1, 0),
    "cube_left": (0, 0, -1),
    "cube_right": (-1, 0, 0),
}
# Back to front: the sides under the top, as the art is stacked.
FACE_ORDER = ["cube_right", "cube_left", "cube_top"]

Points = NDArray[np.float64]


class CubeFace(TypedDict):
    name: str
    span: list[list[int]]
    normal: list[int]


class CubeEntry(TypedDict):
    origin: list[float]
    ex: list[float]
    ey: list[float]
    ez: list[float]
    faces: list[CubeFace]
    # Where the standing part touches the top face, as (x, z) on the top (y = 1).
    stand: list[float]
    # Share of the cube's tilt the character leans back against (0 = rides it rigidly).
    lean: float


def alpha_of(path: Path) -> NDArray[np.uint8]:
    with Image.open(path) as image:
        return np.asarray(image.convert("RGBA"))[..., 3]


def outline(path: Path) -> Points:
    mask = (alpha_of(path) > ALPHA).astype(np.uint8)
    contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    if not contours:
        raise ValueError(f"{path.name} has no opaque pixels")
    hull = cv2.convexHull(max(contours, key=cv2.contourArea))
    quad = cv2.approxPolyDP(hull, 0.02 * cv2.arcLength(hull, True), True).reshape(-1, 2)
    if len(quad) != 4:
        raise ValueError(f"{path.name} outline has {len(quad)} corners, expected 4")
    start = int(np.argmin(quad[:, 1]))
    ordered = np.roll(quad, -start, axis=0).astype(np.float64)
    edge1 = ordered[1] - ordered[0]
    edge2 = ordered[2] - ordered[1]
    if edge1[0] * edge2[1] - edge1[1] * edge2[0] < 0:
        ordered = np.vstack([ordered[0], ordered[:0:-1]])
    return ordered


def fit(observed: dict[str, Points]) -> tuple[Points, Points]:
    """Least squares for origin, ex, ey, ez (rows of a 4x2 matrix) from all face corners."""
    rows: list[list[float]] = []
    targets: list[Points] = []
    for face, points in observed.items():
        for corner, point in zip(FACE_CORNERS[face], points, strict=True):
            rows.append([1.0, float(corner[0]), float(corner[1]), float(corner[2])])
            targets.append(point)
    design = np.array(rows)
    target = np.array(targets)
    solution, *_ = np.linalg.lstsq(design, target, rcond=None)
    return solution, target - design @ solution


def contact(path: Path) -> Points:
    """Bottom middle of a part: the mean x of its lowest opaque row."""
    ys, xs = np.nonzero(alpha_of(path) > ALPHA)
    if len(ys) == 0:
        raise ValueError(f"{path.name} has no opaque pixels")
    bottom = ys.max()
    return np.array([float(xs[ys >= bottom - 2].mean()), float(bottom)])


def measure(source: Path, stand: str, lean: float) -> CubeEntry:
    observed = {face: outline(source / f"{face}.png") for face in FACE_CORNERS}
    basis, residual = fit(observed)
    error = np.hypot(residual[:, 0], residual[:, 1])
    if error.max() > 40:
        raise ValueError(
            f"cube faces do not fit one cube (corner error up to {error.max():.0f} px)"
        )
    origin, ex, ey, ez = (basis[i] for i in range(4))
    # Point on the top face under the standing part: origin + ey + x * ex + z * ez.
    target = contact(source / f"{stand}.png") - origin - ey
    x, z = np.linalg.solve(np.column_stack([ex, ez]), target)
    return CubeEntry(
        origin=[round(float(v), 2) for v in origin],
        ex=[round(float(v), 2) for v in ex],
        ey=[round(float(v), 2) for v in ey],
        ez=[round(float(v), 2) for v in ez],
        faces=[
            CubeFace(
                name=face,
                span=[list(c) for c in FACE_SPAN[face]],
                normal=list(FACE_NORMAL[face]),
            )
            for face in FACE_ORDER
        ],
        stand=[round(float(x), 4), round(float(z), 4)],
        lean=lean,
    )


def main() -> None:
    source = ROOT / "roshu" / "layers" / "sugar-cube"
    observed = {face: outline(source / f"{face}.png") for face in FACE_CORNERS}
    _, residual = fit(observed)
    error = np.hypot(residual[:, 0], residual[:, 1])
    print(f"corner error px: mean {error.mean():.1f}, max {error.max():.1f}")
    print(measure(source, "foot_stand", 0.5))


if __name__ == "__main__":
    main()
