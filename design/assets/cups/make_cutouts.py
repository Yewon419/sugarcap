# 컵 누끼(rembg u2net) + 식탁 배경(빈 컵 사진에서 컵을 지움).
# 2026-09-27 대표님 베타 피드백: 추이 선반은 컵 전체로, 오늘 화면은 식탁 위에서 음료를 미는 것처럼.
# 원본 사진은 cups/<세트>/9x16. 결과는 cups/cutouts에 쓰고, 앱 번들 cutout-*.imageset(추이 선반·영향 미리보기)에 복사한다.
# 오늘 탭·먹이기는 원본 사진(cup-*)을 그대로 쓴다(대표님 2026-09-27). plate.png(식탁 배경)는 지금 앱에서 안 쓴다.
# 캔버스(937×1666)는 원본 그대로 둔다. 배경 위에 같은 자리로 얹으면 원래 사진과 같아 보인다.
import os

import cv2
import numpy as np
from PIL import Image
from rembg import new_session, remove

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "cutouts")
STEPS = [0, 10, 20, 30, 40, 50, 70, 80, 100]


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    session = new_session("u2net")
    for set_id in ["strawberry-latte", "iced-americano"]:
        union = None
        for step in STEPS:
            src = Image.open(os.path.join(HERE, set_id, "9x16", f"{step}.png")).convert("RGB")
            pixels = np.array(remove(src, session=session))
            alpha = pixels[:, :, 3]
            alpha[alpha < 24] = 0  # 반투명 찌꺼기(냅킨 가장자리 등)는 지운다
            pixels[:, :, 3] = alpha
            Image.fromarray(pixels).save(os.path.join(OUT, f"cutout-{set_id}-{step}.png"), optimize=True)
            ys, xs = np.nonzero(alpha > 128)
            box = (xs.min(), ys.min(), xs.max(), ys.max())
            union = box if union is None else (
                min(union[0], box[0]), min(union[1], box[1]), max(union[2], box[2]), max(union[3], box[3])
            )
            if set_id == "strawberry-latte" and step == 0:
                # 빈 컵 사진에서 컵 자리를 지워 식탁 배경을 만든다(두 세트가 같은 벽·식탁·냅킨이다).
                mask = cv2.dilate((alpha > 8).astype(np.uint8) * 255, np.ones((31, 31), np.uint8))
                bgr = cv2.cvtColor(np.array(src), cv2.COLOR_RGB2BGR)
                cv2.imwrite(os.path.join(OUT, "plate.png"), cv2.inpaint(bgr, mask, 21, cv2.INPAINT_TELEA))
        # 앱의 CupCrop이 이 값(두 세트 합집합)으로 잔만 잘라 보여 준다.
        print(set_id, "union bbox", tuple(int(v) for v in union))


if __name__ == "__main__":
    main()
