import CoreGraphics
import Foundation
import OSLog

/// 자세 정의 한 개(`design/assets/characters/<캐릭터>/poses.json` → `export_ios.py` → 번들 `idle-poses.json`).
/// 자세 = 그림 + 놓일 자리 + 움직임 + 해금 단계. 새 자세는 코드를 고치지 않고 poses.json에 더한다.
struct IdlePoseSpec: Sendable {
    let rule: IdlePoseRule
    /// 이 자세가 풀리는 사이 단계(SPEC §9.8). 0%일 때 자세는 해금과 상관없이 쓴다.
    let unlock: Int
    let place: IdlePlace
    /// 회전·반전 중심을 그림 속 가장자리 틈(`rimLineY`)에 둔다(로슈 컵 안). 아니면 그림 발밑.
    let pivotOnRim: Bool
    let motion: IdleMotionSpec
}

/// 자세 기준점(그림 bbox 아래 가운데, `pivotOnRim`이면 가장자리 틈)이 놓일 사진 위 자리.
struct IdlePlace: Sendable, Equatable {
    enum Horizontal: Sendable, Equatable {
        /// 사진 폭 비율.
        case photo(Double)
        /// 잔 가운데로부터 가장자리 폭 단위(가장자리 폭 = 사진 폭의 .477, 가운데 .498. 카인 목업에서 잰 값).
        case rim(Double)
    }

    enum Vertical: String, Sendable, Equatable, Decodable {
        /// 잔 바닥(`IdleCast.bottom`).
        case bottom
        /// 앞·뒤 가장자리 선(단계마다 다르다).
        case rimFront, rimBack
        /// 음료 윗면 ~ 잔 안쪽 바닥(`floor`) 사이 `depth` 깊이.
        case liquid
    }

    static let rimMid = 0.498
    static let rimWidth = 0.477

    let x: Horizontal
    let y: Vertical
    /// 사진 높이 비율만큼 아래(+)로.
    var dy: Double = 0
    var floor: Double = 0
    var depth: Double = 0
    /// 그림 가운데가 그 자리에 오게 기준점(발끝)을 그림 높이 절반만큼 내린다.
    var centered = false

    var photoX: Double {
        switch x {
        case .photo(let value): return value
        case .rim(let value): return Self.rimMid + value * Self.rimWidth
        }
    }
}

enum IdleMotionSpec: Sendable {
    /// 시각 t의 파형들을 더한다.
    case channels([IdleChannel])
    /// 잔 밑을 오가는 걷기. 다리 이름이 정해져 있다(`IdleWalkStyle`).
    case walk(IdleWalkStyle)
}

/// 걷기 모양. step = 로슈(foot_back·foot_front를 들어 내딛고 flipper_front·flipper_side를 흔든다),
/// waddle = 카인(leg_near·leg_far를 엇갈려 흔들고 몸을 기울인다).
enum IdleWalkStyle: String, Sendable, Decodable {
    case step, waddle
}

/// 움직임 한 줄: 대상(`to`)에 `amp × 파형(t)`을 더한다. 길이 대상(dx·dy·bodyDy)은 393×852 화면 pt라
/// 화면 배율(`IdlePhoto.unit`)을 곱한다. sx·sy는 1에, 나머지는 0에 더한다.
struct IdleChannel: Sendable, Equatable {
    enum Target: Sendable, Equatable {
        case dx, dy, rot, bodyDy, sx, sy
        case limb(String)
    }

    enum Rectify: String, Sendable, Equatable, Decodable {
        /// 양수 쪽만(음수는 0).
        case pos
        /// 음수 쪽만 뒤집어(양수는 0).
        case neg
    }

    enum Shape: Sendable, Equatable {
        /// sin(2π·t/period + phase).
        case wave(period: Double, phase: Double, rectify: Rectify?)
        /// period마다: rise초 동안 0→1, hold초 유지, fall초 동안 1→0(smoothstep).
        case plateau(period: Double, rise: Double, hold: Double, fall: Double)
        /// period 안 at초부터 length초 동안 0→1→0 한 번(sin²).
        case bump(period: Double, at: Double, length: Double)
        /// period 안 at초부터 length초 동안 0→1→0 한 번(sin 반 주기).
        case arch(period: Double, at: Double, length: Double)
    }

    let target: Target
    let amp: Double
    let shape: Shape

    func value(at t: Double) -> Double {
        switch shape {
        case let .wave(period, phase, rectify):
            let k = sin(IdleMotion.tau * t / period + phase)
            switch rectify {
            case nil: return amp * k
            case .pos: return amp * max(0, k)
            case .neg: return amp * max(0, -k)
            }
        case let .plateau(period, rise, hold, fall):
            let v = IdleMotion.positiveRemainder(t, period)
            let ramp: Double = v < rise ? v / rise : (v < rise + hold ? 1 : 1 - (v - rise - hold) / fall)
            return amp * IdleMotion.smooth(ramp)
        case let .bump(period, at, length):
            return amp * IdleMotion.bump(IdleMotion.positiveRemainder(t, period) - at, length)
        case let .arch(period, at, length):
            let u = IdleMotion.positiveRemainder(t, period) - at
            guard u >= 0, u <= length else { return 0 }
            return amp * sin(Double.pi * u / length)
        }
    }
}

/// 캐릭터 하나의 자세 묶음.
struct IdlePoseSet: Sendable {
    /// 0%일 때 자세.
    let zero: String
    let poses: [String: IdlePoseSpec]

    /// 남은 양 조건과 해금(`unlock` ≤ 풀린 단계)을 둘 다 맞아야 한다. 0%면 `zero`만, 해금과 상관없다.
    func allows(_ pose: String, step: Int, unlockedLevel: Int) -> Bool {
        if step == 0 { return pose == zero }
        guard let spec = poses[pose] else { return false }
        return spec.unlock <= unlockedLevel && spec.rule.allows(step: step)
    }

    /// 앱을 열 때마다 허용된 자세 중 하나를 뽑는다. 0%면 늘 `zero`.
    func pick<G: RandomNumberGenerator>(step: Int, unlockedLevel: Int, using generator: inout G) -> String {
        if step == 0 { return zero }
        let pool = poses.keys.sorted().filter { allows($0, step: step, unlockedLevel: unlockedLevel) }
        return pool.randomElement(using: &generator) ?? zero
    }
}

enum IdlePoseBook {
    /// 캐릭터 id("roshu", "kain") → 자세 묶음. 읽기에 실패하면 비어 있고 캐릭터가 안 보인다(오류는 로그).
    static let sets: [String: IdlePoseSet] = load(bundle: .main)

    private static let logger = Logger(subsystem: "com.sugarcap.app", category: "idle")

    enum BookError: Error, Equatable {
        case unknownZero(character: String, pose: String)
        case badTarget(pose: String, target: String)
        case badShape(pose: String, shape: String)
        case badPlace(pose: String)
    }

    static func load(bundle: Bundle) -> [String: IdlePoseSet] {
        guard let url = bundle.url(forResource: "idle-poses", withExtension: "json") else {
            logger.error("idle-poses.json이 번들에 없음")
            return [:]
        }
        do {
            return try decode(Data(contentsOf: url))
        } catch {
            logger.error("idle-poses.json 읽기 실패: \(String(describing: error), privacy: .public)")
            return [:]
        }
    }

    static func decode(_ data: Data) throws -> [String: IdlePoseSet] {
        let raw = try JSONDecoder().decode([String: RawSet].self, from: data)
        var sets: [String: IdlePoseSet] = [:]
        for (character, set) in raw {
            guard set.poses[set.zero] != nil else { throw BookError.unknownZero(character: character, pose: set.zero) }
            var poses: [String: IdlePoseSpec] = [:]
            for (name, pose) in set.poses {
                poses[name] = try pose.spec(name: name)
            }
            sets[character] = IdlePoseSet(zero: set.zero, poses: poses)
        }
        return sets
    }

    // MARK: JSON 모양

    private struct RawSet: Decodable {
        let zero: String
        let poses: [String: RawPose]
    }

    private struct RawPlace: Decodable {
        let x: Double?
        let xRim: Double?
        let y: IdlePlace.Vertical
        let dy: Double?
        let floor: Double?
        let depth: Double?
        let centered: Bool?
    }

    private struct RawReflection: Decodable {
        let toward: Double
        let up: Double?
        let mirror: Bool?
    }

    private struct RawShadow: Decodable {
        let w: Double
        let h: Double
        let dx: Double
        let dy: Double
        let feet: Bool?
    }

    private struct RawChannel: Decodable {
        let to: String
        let shape: String
        let amp: Double
        let period: Double
        let phase: Double?
        let rectify: IdleChannel.Rectify?
        let rise: Double?
        let hold: Double?
        let fall: Double?
        let at: Double?
        let length: Double?
    }

    private struct RawPose: Decodable {
        let art: String
        let mirror: Bool?
        let unlock: Int
        let minStep: Int?
        let maxStep: Int?
        let opacity: Double?
        let pivot: String?
        let place: RawPlace
        let limbDirection: [String: Double]?
        let reflection: RawReflection?
        let shadow: RawShadow?
        let motion: [RawChannel]?
        let walk: IdleWalkStyle?

        func spec(name: String) throws -> IdlePoseSpec {
            var rule = IdlePoseRule(art: art, mirror: mirror ?? false, minStep: minStep, maxStep: maxStep)
            if let opacity { rule.opacity = opacity }
            rule.limbDirection = limbDirection ?? [:]
            rule.reflection = reflection.map { IdleReflection(toward: $0.toward, up: $0.up ?? 0, mirror: $0.mirror) }
            rule.shadow = shadow.map { IdleShadow(w: $0.w, h: $0.h, dx: $0.dx, dy: $0.dy, feet: $0.feet ?? false) }

            let motionSpec: IdleMotionSpec
            if let walk {
                motionSpec = .walk(walk)
            } else {
                motionSpec = .channels(try (motion ?? []).map { try channel($0, pose: name) })
            }
            return IdlePoseSpec(
                rule: rule, unlock: unlock, place: try placeSpec(name: name),
                pivotOnRim: pivot == "rimLine", motion: motionSpec
            )
        }

        private func placeSpec(name: String) throws -> IdlePlace {
            let x: IdlePlace.Horizontal
            switch (place.x, place.xRim) {
            case (let value?, nil): x = .photo(value)
            case (nil, let value?): x = .rim(value)
            default: throw BookError.badPlace(pose: name)
            }
            if place.y == .liquid, place.floor == nil || place.depth == nil { throw BookError.badPlace(pose: name) }
            return IdlePlace(
                x: x, y: place.y, dy: place.dy ?? 0, floor: place.floor ?? 0, depth: place.depth ?? 0,
                centered: place.centered ?? false
            )
        }

        private func channel(_ raw: RawChannel, pose: String) throws -> IdleChannel {
            let target: IdleChannel.Target
            switch raw.to {
            case "dx": target = .dx
            case "dy": target = .dy
            case "rot": target = .rot
            case "bodyDy": target = .bodyDy
            case "sx": target = .sx
            case "sy": target = .sy
            default:
                guard raw.to.hasPrefix("limb."), raw.to.count > 5 else {
                    throw BookError.badTarget(pose: pose, target: raw.to)
                }
                target = .limb(String(raw.to.dropFirst(5)))
            }
            let shape: IdleChannel.Shape
            switch (raw.shape, raw.rise, raw.hold, raw.fall, raw.at, raw.length) {
            case ("wave", _, _, _, _, _):
                shape = .wave(period: raw.period, phase: raw.phase ?? 0, rectify: raw.rectify)
            case ("plateau", let rise?, let hold?, let fall?, _, _):
                shape = .plateau(period: raw.period, rise: rise, hold: hold, fall: fall)
            case ("bump", _, _, _, let at?, let length?):
                shape = .bump(period: raw.period, at: at, length: length)
            case ("arch", _, _, _, let at?, let length?):
                shape = .arch(period: raw.period, at: at, length: length)
            default:
                throw BookError.badShape(pose: pose, shape: raw.shape)
            }
            return IdleChannel(target: target, amp: raw.amp, shape: shape)
        }
    }
}

extension IdleMotion {
    /// 자세 정의대로 기준점이 놓일 화면 위 자리.
    static func place(_ spec: IdlePoseSpec, cast: IdleCast, step: Int, photo: IdlePhoto, art: IdleArt, scale: Double) -> CGPoint {
        let place = spec.place
        let x = place.photoX
        let rim = cast.rimLine(step: step)
        switch place.y {
        case .bottom: return photo.point(x, cast.bottom + place.dy)
        case .rimFront: return photo.point(x, rim.front + place.dy)
        case .rimBack: return photo.point(x, rim.back + place.dy)
        case .liquid:
            let top = cast.liquidTop(step: step)
            let mid = photo.point(x, top + (place.floor - top) * place.depth)
            let half: Double = place.centered ? Double(art.bbox.height) / 2 * scale : 0
            return CGPoint(x: Double(mid.x), y: Double(mid.y) + half)
        }
    }

    /// 자세 정의대로 시각 t의 변형.
    static func frame(_ spec: IdlePoseSpec, cast: IdleCast, t: Double, photo: IdlePhoto, walkBaseX: Double) -> IdleFrame {
        var f: IdleFrame
        switch spec.motion {
        case .walk(let style):
            f = walkFrame(style, t: t, cast: cast, photo: photo, walkBaseX: walkBaseX)
        case .channels(let channels):
            f = IdleFrame()
            let u = photo.unit
            for channel in channels {
                let v = channel.value(at: t)
                switch channel.target {
                case .dx: f.dx += v * u
                case .dy: f.dy += v * u
                case .bodyDy: f.bodyDy += v * u
                case .rot: f.rot += v
                case .sx: f.sx += v
                case .sy: f.sy += v
                case .limb(let name): f.limbs[name, default: 0] += v
                }
            }
        }
        if spec.rule.mirror { f.flip = -f.flip }
        return f
    }

    private static func walkFrame(_ style: IdleWalkStyle, t: Double, cast: IdleCast, photo: IdlePhoto, walkBaseX: Double) -> IdleFrame {
        let u = photo.unit
        var f = IdleFrame()
        let w = walk(t: t, gait: cast.gait, photo: photo)
        f.dx = w.x - walkBaseX
        f.flip = w.facingLeft ? 1 : -1
        switch style {
        case .step:
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
        case .waddle:
            // 뒤뚱 걷기: 두 다리가 엉덩이를 축으로 엇갈려 흔들리고(+가 앞), 앞으로 가는 다리는 살짝 든다.
            // 몸은 딛는 다리 쪽으로 조금 기운다.
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
        }
        return f
    }
}
