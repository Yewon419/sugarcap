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
    /// 바꿔 끼우는 조각(`IdleArt.Part.isOverlay`)별 값. 0.5 이상이면 보인다.
    var show: [String: Double] = [:]

    func shows(_ part: String) -> Bool { (show[part] ?? 0) >= 0.5 }
}

/// 대기 동작 공용 함수. 전부 시각 t(초)의 순수 함수다. 자세별 움직임은 `IdlePoseBook`(poses.json).
enum IdleMotion {
    static let tau = Double.pi * 2

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

    /// 눌렀을 때 움찔하는 정도(0 ~ 1). 0.06초 만에 움츠렸다가 0.3초에 걸쳐 풀린다.
    static func flinch(age: Double) -> Double {
        if age < 0 || age >= flinchDuration { return 0 }
        if age < 0.06 { return age / 0.06 }
        let release = 1 - (age - 0.06) / (flinchDuration - 0.06)
        return release * release
    }

    static let flinchDuration = 0.36

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
