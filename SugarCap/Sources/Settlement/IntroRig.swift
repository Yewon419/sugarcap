import SwiftUI

/// 소개 무대의 리그 캐릭터(시안 `intro-v2.html`과 같은 조각·축·방향). 단위는 무대 픽셀.
enum IntroRig {
    struct Figure {
        let painter: RigPainter
        let base: CGPoint
        let frame: IdleFrame
        let squash: Double
        let blink: Double
    }

    /// 로슈 걷기 그림 높이(무대 px). 정면 그림도 같은 높이로 맞춘다(캔버스 크기가 달라서).
    private static let roshuHeight = 400.0
    private static let roshuPx = CupSide.sugar.idleCast.scalePerPhotoHeight
    private static let kainPx = CupSide.caffeine.idleCast.scalePerPhotoHeight

    /// 무대 배율 = 로슈 높이 400 기준. 카인은 오늘 화면 배율 비(× 0.891)를 따른다.
    private static let roshuScale: Double = scale(fitting: "walk", of: "roshu")
    private static let kainScale: Double = roshuScale * kainPx / roshuPx
    /// 오늘 화면 대비 무대 배율(걷기 발 들기·내딛기 pt를 키울 때 쓴다).
    private static let stageK: Double = roshuScale / (IdlePhoto.referenceHeight * roshuPx)
    /// RigPainter의 눌림(세로 8%)을 로슈 시안 값(세로 7%)으로 맞춘다.
    static let roshuSquash = 0.875

    // 로슈 앞 지느러미는 몸 안쪽(-)으로만 돈다. 바깥으로 젖히면 자른 선이 드러난다(무대 400px에서 눈에 띔).
    static let roshuWalkArt = RigPainter(
        character: "roshu", art: "walk", scale: roshuScale, lidPad: 0.35,
        limbDirection: ["flipper_front": -1, "foot_back": -1, "foot_front": 1, "flipper_side": 0]
    )
    static let roshuStandArt = RigPainter(
        character: "roshu", art: "stand", scale: scale(fitting: "stand", of: "roshu"), lidPad: 0.35,
        limbDirection: ["arm_left": 0, "arm_right": 0, "foot_left": 0, "foot_right": 0]
    )
    /// 선물 상자를 들고 오는 로슈(SPEC §4.9). 정면 그림이라 팔은 상자를 받친 채 고정, 발만 걷는다.
    /// 뚜껑(`lid`)은 왼쪽 아래 경첩으로 열린다(`split_gift_lid.py`).
    static let roshuGiftArt = RigPainter(
        character: "roshu", art: "gift-carry", scale: scale(fitting: "gift-carry", of: "roshu"), lidPad: 0.35,
        limbDirection: ["arm_left": 0, "arm_right": 0, "foot_left": 0, "foot_right": 0, "lid": 0]
    )
    static let kainWalkArt = RigPainter(
        character: "kain", art: "walk", scale: kainScale, lidPad: 0.04, limbDirection: ["leg_far": 0, "leg_near": 0]
    )
    static let kainStandArt = RigPainter(
        character: "kain", art: "rim-stand", scale: kainScale, lidPad: 0.04, limbDirection: ["leg_left": 0, "leg_right": 0]
    )
    /// 선물 상자 옆에 앉은 카인(SPEC §4.9). 상자는 몸 뒤 별도 부위(고정), 뚜껑은 왼쪽 아래 경첩으로 열린다. 그림은 왼쪽을 본다.
    static let kainGiftArt = RigPainter(
        character: "kain", art: "gift-carry", scale: kainScale, lidPad: 0.04,
        limbDirection: ["box": 0, "leg_near": 0, "leg_far": 0, "lid": 0]
    )

    private static func scale(fitting art: String, of character: String) -> Double {
        guard let height = IdleRig.arts[character]?[art]?.bbox.height, height > 0 else { return 0 }
        return roshuHeight / Double(height)
    }

    /// 입장 걷기: a→b를 감속으로 가고, 걸음 위상은 지나온 거리로 잰다. 끝 0.14초 동안 다리를 모은다.
    static func entrance(_ t: Double, _ a: Double, _ b: Double, from x0: Double, to x1: Double)
        -> (x: Double, travelled: Double, moving: Double) {
        let x = Motion.lerp(x0, x1, Motion.seg(t, a, b, Ease.power2Out))
        let moving: Double = t > b ? 0 : (t < a ? 1 : 1 - Motion.seg(t, b - 0.14, b))
        return (x, abs(x - x0), moving)
    }

    /// 한 발의 한 주기. 옆으로 미는 폭은 오늘 화면 배율 그대로, 발 들기만 `liftBoost`배.
    private static func footStep(_ c: Double, liftBoost: Double) -> (x: Double, lift: Double, rot: Double) {
        let reach = 1.5, lift = 1.6, rot = 8.0
        if c < 0.5 {
            let v = c / 0.5
            let arc = sin(Double.pi * v)
            return ((reach - 2 * reach * RigMotion.smooth(v)) * stageK, lift * arc * stageK * liftBoost, rot * arc * 1.4)
        }
        return ((-reach + 2 * reach * (c - 0.5) / 0.5) * stageK, 0, 0)
    }

    /// 로슈 걷기: 다리로 걷고 지느러미는 반대 박자, 몸이 발 박자에 맞춰 살짝 들썩인다. `moving`으로 멈출 때 다리를 모은다.
    static func roshuWalk(_ m: inout IdleFrame, travelled: Double, moving: Double) {
        let c = RigMotion.remainder(travelled / 125 / 2, 1)
        for (foot, phase) in [("foot_back", c), ("foot_front", RigMotion.remainder(c + 0.5, 1))] {
            let g = footStep(phase, liftBoost: 2.2)
            m.limbs[foot] = g.rot * moving
            m.shift[foot] = CGVector(dx: g.x * moving, dy: -g.lift * moving)
        }
        let swing = cos(2 * Double.pi * c) * moving
        m.limbs["flipper_front"] = 6 * swing
        m.limbs["flipper_side"] = -12 * swing
        m.bodyDy = -6 * abs(sin(2 * Double.pi * c)) * moving
    }

    /// 선물 들고 걷기: 걷기와 같은 발 박자(그림만 정면 `gift-carry`). 팔은 상자를 받친 채 두고 몸이 발 박자에 들썩인다.
    static func roshuGiftWalk(_ m: inout IdleFrame, travelled: Double, moving: Double) {
        let c = RigMotion.remainder(travelled / 125 / 2, 1)
        for (foot, phase) in [("foot_left", c), ("foot_right", RigMotion.remainder(c + 0.5, 1))] {
            let g = footStep(phase, liftBoost: 2.2)
            m.limbs[foot] = g.rot * moving
            m.shift[foot] = CGVector(dx: g.x * moving, dy: -g.lift * moving)
        }
        m.bodyDy = -6 * abs(sin(2 * Double.pi * c)) * moving
    }

    /// 카인 뒤뚱 걷기: 다리가 엉덩이를 축으로 엇갈리고 몸이 딛는 쪽으로 기운다.
    static func kainWalk(_ m: inout IdleFrame, travelled: Double, moving: Double) {
        let c = RigMotion.remainder(travelled / 95 / 2, 1)
        let k = sin(2 * Double.pi * c)
        let lift = cos(2 * Double.pi * c)
        let raise: Double = 2.1 * stageK * moving
        m.limbs["leg_near"] = 16 * k * moving
        m.limbs["leg_far"] = -16 * k * moving
        m.shift["leg_near"] = CGVector(dx: 0, dy: -raise * max(0, lift))
        m.shift["leg_far"] = CGVector(dx: 0, dy: -raise * max(0, -lift))
        m.rot += 4 * k * moving
    }
}
