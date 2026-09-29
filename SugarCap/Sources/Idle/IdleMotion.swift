import CoreGraphics
import Foundation

/// 한 시각의 자세 변형(프로토타입 `motion()` 반환값).
/// 전체(dx, dy, rot, flip) · 몸 층(bodyDy, sx, sy) · 팔다리 각도(limbs, 크기만. 방향은 규칙의 limbDirection)
/// · 팔다리 이동(shift, pt). 길이 값은 이미 화면 배율(`IdlePhoto.unit`)을 곱한 pt다.
struct IdleFrame: Sendable, Equatable {
    var dx: Double = 0
    var dy: Double = 0
    var rot: Double = 0
    var flip: Double = 1
    var bodyDy: Double = 0
    var sx: Double = 1
    var sy: Double = 1
    var limbs: [String: Double] = [:]
    var shift: [String: CGVector] = [:]
}

/// 자세마다의 동작. 전부 시각 t(초)의 순수 함수다(프로토타입 `roshuMotion`·`kainMotion`).
enum IdleMotion {
    static let tau = Double.pi * 2

    /// 자세 기준점(그림 bbox 아래 가운데, 로슈 in-cup만 가장자리 선)이 놓일 화면 위 자리.
    /// 카인 자리는 목업에서 잔 가운데로부터 가장자리 폭 단위로 잰 거리다(가장자리 폭 = 사진 폭의 .477, 가운데 .498).
    static func place(_ pose: IdlePose, cast: IdleCast, step: Int, photo: IdlePhoto, art: IdleArt, scale: Double) -> CGPoint {
        let rim = cast.rimLine(step: step)
        let kainX: (Double) -> Double = { 0.498 + $0 * 0.477 }
        switch (cast.character, pose) {
        case ("roshu", .inCup): return photo.point(0.49, rim.front)
        case ("roshu", .watch): return photo.point(0.25, cast.bottom - 0.005)
        case ("roshu", .slump): return photo.point(0.4, cast.bottom + 0.02)
        case ("roshu", .walk): return photo.point(0.5, cast.bottom + 0.012)
        // 발바닥이 앞 가장자리 선 위.
        case (_, .rimStand): return photo.point(kainX(-0.01), rim.front)
        // 엉덩이가 뒤 가장자리 선 위, 가운데서 오른쪽으로 가장자리 폭 .23.
        case (_, .rimSit): return photo.point(kainX(0.23), rim.back)
        // 잔 왼쪽 바깥 냅킨 위. 목업에서 잔 바닥보다 가장자리 폭의 .088만큼 뒤(위)에 앉았다.
        case (_, .floorSit): return photo.point(kainX(-0.63), cast.bottom - 0.024)
        // 얼음 밑 진한 커피 한가운데(커피 윗선~잔 안쪽 바닥 .852의 55% 깊이)에 그림 가운데가 오게 기준점(발끝)을 내린다.
        case (_, .swim):
            let top = cast.liquidTop(step: step)
            let mid = photo.point(kainX(-0.05), top + (0.852 - top) * 0.55)
            let half: Double = Double(art.bbox.height) / 2 * scale
            return CGPoint(x: Double(mid.x), y: Double(mid.y) + half)
        default: return photo.point(0.5, cast.bottom + 0.014)
        }
    }

    static func frame(_ pose: IdlePose, cast: IdleCast, rule: IdlePoseRule, t: Double, photo: IdlePhoto, walkBaseX: Double) -> IdleFrame {
        var frame = cast.character == "roshu"
            ? roshu(pose, t: t, cast: cast, photo: photo, walkBaseX: walkBaseX)
            : kain(pose, t: t, cast: cast, photo: photo, walkBaseX: walkBaseX)
        // 좌우반전 자세는 flip에 곱해 그림·그림자·반사가 한 값을 쓴다.
        if rule.mirror { frame.flip = -frame.flip }
        return frame
    }

    // MARK: 로슈

    private static func roshu(_ pose: IdlePose, t: Double, cast: IdleCast, photo: IdlePhoto, walkBaseX: Double) -> IdleFrame {
        let u = photo.unit
        var f = IdleFrame()
        switch pose {
        case .inCup:
            // 음료에 떠 있다: 그림의 가장자리 틈이 컵 가장자리에서 벗어나지 않게 위아래로는 안 움직이고,
            // 틈 가운데를 축으로 아주 살짝만 기운다. 물속에서 발장구.
            f.rot = 0.6 * sin(tau * t / 3.4)
            let k = sin(tau * t / 1.3)
            f.limbs["foot_left"] = 12 * max(0, k)
            f.limbs["foot_right"] = 12 * max(0, -k)
        case .watch:
            // 5.5초마다 까치발로 들여다본다: 몸만 올라가고 발은 바닥에 남는다. 컵 잡은 팔로 몸을 끌어올린다.
            let v = positiveRemainder(t, 5.5)
            let ramp: Double = v < 0.6 ? v / 0.6 : (v < 1.8 ? 1 : 1 - (v - 1.8) / 0.6)
            let e = smooth(ramp)
            f.bodyDy = -2.2 * e * u
            f.limbs["arm"] = 6 * e
        case .walk:
            let w = walk(t: t, gait: cast.gait, photo: photo)
            f.dx = w.x - walkBaseX
            f.flip = w.facingLeft ? 1 : -1
            if w.moving {
                // 몸은 흔들지 않고 다리로 걷는다: 한 발씩 들어 앞으로 내딛고, 딛은 발은 뒤로 밀린다.
                let c = positiveRemainder(w.phase / 2, 1)
                for (foot, phase) in [("foot_back", c), ("foot_front", positiveRemainder(c + 0.5, 1))] {
                    let g = footStep(phase)
                    f.limbs[foot] = g.rot
                    f.shift[foot] = CGVector(dx: g.x * u, dy: -g.lift * u)
                }
                // 팔은 반대쪽 다리와 같이 앞뒤로: 앞 지느러미는 어깨를 축으로 +가 앞(바깥), 옆 지느러미는 반대 박자.
                let swing = cos(tau * c)
                f.limbs["flipper_front"] = 12 * swing
                f.limbs["flipper_side"] = -8 * swing
            } else {
                f.limbs["flipper_side"] = 3 * sin(tau * t / 3.0)
            }
        case .slump:
            // 7초마다 한숨: 부풀었다가 푹 꺼지고, 끝에 왼발이 한 번 까딱.
            let v = positiveRemainder(t, 7)
            if v > 4.5, v < 6.5 {
                let k = (v - 4.5) / 2
                let puff: Double = k < 0.45 ? sin(Double.pi * min(k / 0.45, 1)) : 0
                let sag: Double = k >= 0.45 ? sin(Double.pi * (k - 0.45) / 0.55) : 0
                f.sy = 1 + 0.035 * puff - 0.05 * sag
                f.sx = 1 - 0.015 * puff + 0.03 * sag
            }
            f.limbs["foot_left"] = 7 * bump(v - 6.3, 0.6)
        default:
            break
        }
        return f
    }

    // MARK: 카인

    private static func kain(_ pose: IdlePose, t: Double, cast: IdleCast, photo: IdlePhoto, walkBaseX: Double) -> IdleFrame {
        let u = photo.unit
        var f = IdleFrame()
        switch pose {
        case .walk:
            // 뒤뚱 걷기: 두 다리가 엉덩이를 축으로 엇갈려 흔들리고(+가 앞), 앞으로 가는 다리는 살짝 든다.
            // 몸은 딛는 다리 쪽으로 조금 기운다.
            let w = walk(t: t, gait: cast.gait, photo: photo)
            f.dx = w.x - walkBaseX
            f.flip = w.facingLeft ? 1 : -1
            if w.moving {
                let c = positiveRemainder(w.phase / 2, 1)
                let k = sin(tau * c)
                let lift = cos(tau * c)
                f.limbs["leg_near"] = 8 * k
                f.limbs["leg_far"] = -8 * k
                f.shift["leg_near"] = CGVector(dx: 0, dy: -0.7 * max(0, lift) * u)
                f.shift["leg_far"] = CGVector(dx: 0, dy: -0.7 * max(0, -lift) * u)
                f.rot = 1.5 * k
            }
        case .rimStand:
            // 가장자리에서 균형 잡기: 발밑을 축으로 아주 느리게 흔들리고, 6.5초마다 오른발을 두 번 까딱.
            f.rot = 0.8 * sin(tau * t / 3.6)
            let v = positiveRemainder(t, 6.5)
            f.limbs["leg_right"] = -7 * (bump(v - 4.6, 0.35) + bump(v - 5.05, 0.35))
        case .rimSit, .floorSit:
            // 앉아서 숨쉬기(바닥 기준으로 부풀었다 가라앉음). 가장자리 뒤에서는 8초마다 고개 갸웃.
            let k = sin(tau * t / 3.2)
            f.sy = 1 + 0.012 * k
            f.sx = 1 - 0.006 * k
            if pose == .rimSit { f.rot = -4 * bump(positiveRemainder(t, 8) - 5.5, 1.4) }
        case .swim:
            // 커피 속에서 제자리 헤엄: 천천히 좌우로 떠다니며 오르내리고, 두 다리로 번갈아 발차기.
            f.dx = 6 * sin(tau * t / 7) * u
            f.dy = 2.2 * sin(tau * t / 3.1) * u
            f.rot = 3 * sin(tau * t / 3.1 + 1.2)
            let k = sin(tau * t / 0.9)
            f.limbs["leg_near"] = 10 * k
            f.limbs["leg_far"] = -10 * k
        default:
            break
        }
        return f
    }

    // MARK: 걷기

    struct WalkState: Equatable {
        let x: Double
        let facingLeft: Bool
        let moving: Bool
        let phase: Double
    }

    /// 오른쪽 끝 → 왼쪽 끝 → 쉬기 → 오른쪽 끝 → 쉬기. 두 캐릭터 그림 다 왼쪽을 본다.
    static func walk(t: Double, gait: IdleGait, photo: IdlePhoto) -> WalkState {
        let speed = gait.speed * photo.unit
        let dist = (gait.from - gait.to) * photo.width
        let duration = dist / speed
        let cycle = 2 * (duration + gait.pause)
        let v = positiveRemainder(t, cycle)
        let (d, facingLeft, moving): (Double, Bool, Bool) =
            if v < duration {
                (v * speed, true, true)
            } else if v < duration + gait.pause {
                (dist, true, false)
            } else if v < 2 * duration + gait.pause {
                (dist - (v - duration - gait.pause) * speed, false, true)
            } else {
                (0, false, false)
            }
        let x = photo.left + gait.from * photo.width - d
        let travelled = v < duration ? d : dist * 2 - d
        let phase = moving ? travelled / (gait.stride * photo.unit) : 0
        return WalkState(x: x, facingLeft: facingLeft, moving: moving, phase: phase)
    }

    /// 한 발의 한 주기(u 0~1). 앞 절반은 들어서 앞으로(그림 기준 -x) 내딛기, 뒤 절반은 바닥을 딛고 뒤로 밀리기.
    /// 반환 x·lift는 393×852 화면 pt.
    static let stepReach = 1.5
    static let stepLift = 1.6
    static let stepRot = 8.0

    static func footStep(_ u: Double) -> (x: Double, lift: Double, rot: Double) {
        if u < 0.5 {
            let v = u / 0.5
            let arc = sin(Double.pi * v)
            return (stepReach - 2 * stepReach * smooth(v), stepLift * arc, stepRot * arc)
        }
        return (-stepReach + 2 * stepReach * (u - 0.5) / 0.5, 0, 0)
    }

    // MARK: 눈 깜빡임

    /// 눈꺼풀 닫힘 정도(0 열림 ~ 1 닫힘). 4초 칸마다 한 번, 칸 안 1~2.5초 사이 어딘가에서 깜빡인다
    /// (간격 2.5~5.5초). 다섯 번에 한 번꼴로 두 번 깜빡인다. 닫힘 0.07초·열림 0.1초.
    /// 프로토타입은 난수 상태를 들고 다녔는데, 앱은 시각과 씨앗만으로 정해지게 바꿨다(스크린샷 재현).
    static func blink(t: Double, seed: UInt64) -> Double {
        guard t >= 0 else { return 0 }
        let slot = floor(t / 4)
        let start = slot * 4 + 1 + 1.5 * unitHash(UInt64(slot) &* 2 &+ 1, seed: seed)
        let isDouble = unitHash(UInt64(slot) &* 2 &+ 2, seed: seed) < 0.2
        let d = t - start
        return max(blinkOnce(d), isDouble ? blinkOnce(d - 0.22) : 0)
    }

    private static func blinkOnce(_ x: Double) -> Double {
        if x < 0 { return 0 }
        if x < 0.07 { return x / 0.07 }
        if x < 0.17 { return 1 - (x - 0.07) / 0.1 }
        return 0
    }

    /// splitmix64 → [0, 1).
    static func unitHash(_ value: UInt64, seed: UInt64) -> Double {
        var z = value &+ seed &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(UInt64(1) << 53)
    }

    // MARK: 곡선

    static func smooth(_ x: Double) -> Double {
        let c = min(max(x, 0), 1)
        return c * c * (3 - 2 * c)
    }

    /// 0→1→0 한 번(길이 len초). 시작 전·끝난 뒤는 0.
    static func bump(_ u: Double, _ length: Double) -> Double {
        if u < 0 || u > length { return 0 }
        let s = sin(Double.pi * u / length)
        return s * s
    }

    static func positiveRemainder(_ value: Double, _ modulus: Double) -> Double {
        let r = value.truncatingRemainder(dividingBy: modulus)
        return r < 0 ? r + modulus : r
    }
}
