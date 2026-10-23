# 오늘 화면 컵 사진의 좌우 날개(대표님 베타 피드백 2026-10-23 "냅킨 겹치는 게 거슬려서 원본처럼 좌우를 넓게").
# 9x16 크롭과 같은 변환(transforms.json)으로 원본(2048²)을 키운 뒤 좌우로 WING px씩 더 넓게 자른다.
# 가운데 937폭은 9x16과 같은 자리라, 앱은 이 사진을 원래 사진 밑에 깔아 넘길 때 옆 장과 겹치는 부분만 보인다.
# 100%는 align_100.py가 "80" 변환으로 9x16을 만들었으니 같은 변환을 쓴다.
import json
import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(HERE, "..", "..", "..", "SugarCap", "Resources", "Assets.xcassets")
SETS = ["iced-americano", "strawberry-latte"]
STEPS = [0, 30, 50, 80, 100]
WING = 300
CONTENTS = '{\n  "images": [\n    {\n      "filename": "%s",\n      "idiom": "universal"\n    }\n  ],\n  "info": {\n    "author": "xcode",\n    "version": 1\n  }\n}\n'


def main() -> None:
    transforms = json.load(open(os.path.join(HERE, "transforms.json")))
    for set_id in SETS:
        for step in STEPS:
            t = transforms["80" if step == 100 else str(step)]
            original = Image.open(os.path.join(HERE, set_id, "original", f"{step}.png")).convert("RGB")
            side = round(2048 * t["scale"])
            big = original.resize((side, side), Image.LANCZOS)
            left, top = t["dx"] - WING, t["dy"]
            assert left >= 0 and t["dx"] + 937 + WING <= side, (set_id, step)
            wide = big.crop((left, top, t["dx"] + 937 + WING, top + 1666))
            folder = os.path.join(ASSETS, f"cupwide-{set_id}-{step}.imageset")
            os.makedirs(folder, exist_ok=True)
            name = f"{step}.jpg"
            wide.save(os.path.join(folder, name), quality=88)
            with open(os.path.join(folder, "Contents.json"), "w", newline="\n") as f:
                f.write(CONTENTS % name)
            print(set_id, step, wide.size)


if __name__ == "__main__":
    main()
