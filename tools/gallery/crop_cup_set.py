"""컵 세트 원본(2048²)을 9:16(937×1666)으로 자른다.

아메리카노 세트는 단계별로 배율·오프셋이 다르게 잘려 있다(컵 윤곽 정렬, SPEC §9-10).
새 세트는 아메리카노 각 단계 원본을 편집해 만들어 픽셀이 정렬돼 있으므로,
아메리카노 원본→9x16 변환을 복원한 표(`transforms.json`)를 그대로 적용하면 같은 자리에 컵이 온다.

    python tools/gallery/crop_cup_set.py design/assets/cups/strawberry-latte design/assets/cups/transforms.json
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image

WIDTH, HEIGHT = 937, 1666
STEPS = [0, 10, 20, 30, 40, 50, 70, 80, 100]


def crop(source: Path, scale: float, dx: int, dy: int) -> Image.Image:
    image = Image.open(source).convert("RGB")
    if scale != 1.0:
        image = image.resize((round(image.width * scale), round(image.height * scale)), Image.LANCZOS)
    return image.crop((dx, dy, dx + WIDTH, dy + HEIGHT))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("set_dir", type=Path)
    parser.add_argument("transforms", type=Path)
    args = parser.parse_args()

    transforms = json.loads(args.transforms.read_text(encoding="utf-8"))
    out_dir = args.set_dir / "9x16"
    out_dir.mkdir(exist_ok=True)
    for step in STEPS:
        spec = transforms[str(step)]
        result = crop(args.set_dir / "original" / f"{step}.png", spec["scale"], spec["dx"], spec["dy"])
        if result.size != (WIDTH, HEIGHT):
            raise SystemExit(f"{step}: crop size {result.size} != {(WIDTH, HEIGHT)}")
        result.save(out_dir / f"{step}.png", optimize=True)
        print(step, spec)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
