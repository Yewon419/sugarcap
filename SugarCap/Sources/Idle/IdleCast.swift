import CoreGraphics
import Foundation

/// 대기 자세 이름. 프로토타입(`design/proto/characters.html`)의 이름과 같다.
/// 로슈 = in-cup·watch·walk·slump, 카인 = rim-stand·rim-sit·swim·walk·floor-sit.
enum IdlePose: String, CaseIterable, Sendable {
    case inCup = "in-cup"
    case watch
    case walk
    case slump
    case rimStand = "rim-stand"
    case rimSit = "rim-sit"
    case swim
    case floorSit = "floor-sit"
}

/// 자세 하나의 규칙. `art`는 그림 이름(카인 가장자리 뒤 앉기·바닥 앉기는 `sit` 그림을 같이 쓴다).
struct IdlePoseRule: Sendable {
    let art: String
    /// 좌우반전(목업에서 앉은 카인은 오른쪽을 본다).
    var mirror = false
    var minStep: Int?
    var maxStep: Int?
    /// 커피 속 헤엄은 반쯤 비친다(대표님 지시).
    var opacity: Double = 1
    /// 팔다리가 도는 방향(CSS 각도 부호). 0이면 양쪽, 1·-1이면 그쪽으로만(반대쪽 끝이 몸 안으로 숨는 방향).
    /// 없는 팔다리는 돌지 않는다.
    var limbDirection: [String: Double] = [:]
    /// 잔 유리에 비친 모습. 없으면 안 비친다.
    var reflection: IdleReflection?
    /// 바닥 그림자. 가장자리 위 자세와 헤엄은 없다.
    var shadow: IdleShadow?

    func allows(step: Int) -> Bool {
        if let maxStep, step > maxStep { return false }
        if let minStep, step < minStep { return false }
        return true
    }
}

/// 유리 반사 자리(프로토타입 `REFLECTS.poses`). 캐릭터 가운데에서 잔 가운데 쪽으로 거리의 `toward`만큼 당기고
/// 위로 `up`(393×852 화면 pt) 올린다. `mirror`는 캐릭터별 기본값(`IdleReflectionLook.mirror`)을 덮는다.
struct IdleReflection: Sendable {
    let toward: Double
    var up: Double = 0
    var mirror: Bool?
}

/// 반사 모양(프로토타입 `REFLECTS.look`). 로슈는 몸통만 몸 색 한 가지로(`tint`), 카인은 다리까지 색 그대로.
/// `squeeze`는 가로 눌림.
struct IdleReflectionLook: Sendable {
    let tint: String?
    let mirror: Bool
    let squeeze: Double
    let opacity: Double
}

/// 바닥 그림자(프로토타입 `SHADOWS`). 크기·자리는 그림 폭 비율. 넓고 옅은 그늘 하나 + 접지.
/// `feet`면 접지를 발마다 두고(로슈 걷기), 아니면 몸 밑에 하나. 그늘은 빛 반대쪽(오른쪽 뒤)으로 밀리고 좌우반전을 따르지 않는다.
struct IdleShadow: Sendable {
    let w: Double
    let h: Double
    let dx: Double
    let dy: Double
    var feet = false
}

/// 걷기: 오른쪽 끝(from) ↔ 왼쪽 끝(to)을 오가고 끝에서 쉰다(사진 폭 비율). 속도·보폭은 393×852 화면 pt.
struct IdleGait: Sendable {
    let from: Double
    let to: Double
    let speed: Double
    let pause: Double
    let stride: Double
}

/// 캐릭터 하나의 대기 자세 설정(프로토타입 `CHARS`). 잔 가장자리·음료 윗면은 단계마다 사진이 달라 따로 쟀다.
struct IdleCast: Sendable {
    let character: String
    /// 사진 높이 비율. 잔 바닥.
    let bottom: Double
    /// 단계 → (뒤 가장자리, 앞 가장자리) 사진 높이 비율(가운데 열).
    let rim: [Int: (back: Double, front: Double)]
    /// 단계 → 음료 윗면(카인은 얼음 밑 진한 커피가 시작하는 선).
    let liquid: [Int: Double]
    /// 단계 → 잔 가운데 x(사진 폭 비율). 누끼 알파에서 잔 옆선 가운데를 평균했다(프로토타입 `measureGlass`와 같은 방법).
    let axis: [Int: Double]
    let reflectionLook: IdleReflectionLook
    /// 캔버스 픽셀 → pt 배율 = 사진 높이 × 이 값.
    let scalePerPhotoHeight: Double
    /// 눈꺼풀을 눈보다 얼마나 크게 덮을지(눈 크기 비율).
    let lidPad: Double
    /// 0%일 때 자세.
    let zero: IdlePose
    let poses: [IdlePose: IdlePoseRule]
    let gait: IdleGait

    func rule(_ pose: IdlePose) -> IdlePoseRule? { poses[pose] }

    func allows(_ pose: IdlePose, step: Int) -> Bool {
        if step == 0 { return pose == zero }
        return poses[pose]?.allows(step: step) ?? false
    }

    /// 앱을 열 때마다 허용된 자세 중 하나를 뽑는다. 0%면 늘 `zero`.
    func pick<G: RandomNumberGenerator>(step: Int, using generator: inout G) -> IdlePose {
        if step == 0 { return zero }
        let pool = IdlePose.allCases.filter { allows($0, step: step) }
        return pool.randomElement(using: &generator) ?? zero
    }

    func rimLine(step: Int) -> (back: Double, front: Double) {
        rim[step] ?? rim[100] ?? (0.27, 0.33)
    }

    func liquidTop(step: Int) -> Double {
        liquid[step] ?? bottom
    }

    func glassAxis(step: Int) -> Double {
        axis[step] ?? 0.497
    }
}

extension CupSide {
    var idleCast: IdleCast {
        switch self {
        case .sugar: return .roshu
        case .caffeine: return .kain
        }
    }
}

extension IdleCast {
    /// 로슈 · 딸기라떼. 배율은 목업에서 잰 값의 0.9배(대표님 2026-09-29).
    /// 0%면 철푸덕(30% 이하에서도 뽑힌다). 컵 안 가장자리 매달리기는 50% 이하일 때만.
    static let roshu = IdleCast(
        character: "roshu",
        bottom: 0.885,
        rim: [
            0: (0.2626, 0.3280), 30: (0.2605, 0.3247), 50: (0.2614, 0.3247),
            80: (0.2581, 0.3235), 100: (0.2686, 0.3268),
        ],
        liquid: [0: 0.80, 30: 0.557, 50: 0.4466, 80: 0.3511, 100: 0.3397],
        axis: [0: 0.4975, 30: 0.4973, 50: 0.4973, 80: 0.4935, 100: 0.4944],
        // 대표님 레퍼런스(2026-09-29): 몸통만 있는 매끈한 윤곽, 크기 그대로.
        reflectionLook: IdleReflectionLook(tint: "#D5D7DD", mirror: false, squeeze: 1, opacity: 0.42),
        scalePerPhotoHeight: 7.96e-5 * 0.9,
        lidPad: 0.35,
        zero: .slump,
        poses: [
            .inCup: IdlePoseRule(art: "in-cup", minStep: 1, maxStep: 50, limbDirection: ["foot_left": -1, "foot_right": 1]),
            .watch: IdlePoseRule(
                art: "watch", minStep: 1, limbDirection: ["foot_left": -1, "foot_right": 1, "arm": -1],
                reflection: IdleReflection(toward: 0.43), shadow: IdleShadow(w: 0.8, h: 0.24, dx: 0.2, dy: -0.05)
            ),
            .walk: IdlePoseRule(
                art: "walk", minStep: 1,
                limbDirection: ["flipper_front": 0, "foot_back": -1, "foot_front": 1, "flipper_side": 0],
                reflection: IdleReflection(toward: 0.12, up: 16),
                shadow: IdleShadow(w: 0.9, h: 0.24, dx: 0.2, dy: -0.05, feet: true)
            ),
            // 철푸덕은 몸이 바닥에 닿아 그늘을 밀지 않고 몸 바로 밑에 좁게.
            .slump: IdlePoseRule(
                art: "slump", maxStep: 30, limbDirection: ["foot_left": 1, "foot_right": -1],
                reflection: IdleReflection(toward: 0.1, up: 5), shadow: IdleShadow(w: 0.92, h: 0.1, dx: 0.03, dy: -0.025)
            ),
        ],
        gait: IdleGait(from: 0.74, to: 0.28, speed: 20, pause: 1.6, stride: 10)
    )

    /// 카인 · 아이스 아메리카노. 배율은 목업의 앉기·헤엄 크기(잔 가장자리 폭 대비)의 1.3배(대표님 2026-09-29).
    /// 0%면 바닥에 앉기. 헤엄은 커피가 30% 이상 남았을 때만, 나머지는 1% 이상 어디서나.
    static let kain = IdleCast(
        character: "kain",
        bottom: 0.876,
        rim: [
            0: (0.2629, 0.3283), 30: (0.2629, 0.3271), 50: (0.2641, 0.3259),
            80: (0.2629, 0.3271), 100: (0.2683, 0.3265),
        ],
        liquid: [0: 0.87, 30: 0.7071, 50: 0.5366, 80: 0.4274, 100: 0.3962],
        axis: [0: 0.4974, 30: 0.4974, 50: 0.4971, 80: 0.4973, 100: 0.4953],
        // 대표님 목업(2026-09-29): 그림 전체가 색 그대로 옅게, 좌우반전(부리가 캐릭터 쪽), 가로만 .45배.
        reflectionLook: IdleReflectionLook(tint: nil, mirror: true, squeeze: 0.45, opacity: 0.45),
        scalePerPhotoHeight: 0.0818 * 1.3 / 1666,
        // 카인 눈은 흰 고리라 눈꺼풀을 넉넉히 키우면 몸 밖으로 삐져나온다.
        lidPad: 0.04,
        zero: .floorSit,
        poses: [
            .rimStand: IdlePoseRule(art: "rim-stand", minStep: 1, limbDirection: ["leg_left": 0, "leg_right": 0]),
            .rimSit: IdlePoseRule(art: "sit", mirror: true, minStep: 1),
            .swim: IdlePoseRule(art: "swim", minStep: 30, opacity: 0.6, limbDirection: ["leg_far": 0, "leg_near": 0]),
            // 걷기 반사는 뒤집지 않는다(대표님: 뒤집으면 반대로 걷는 것처럼 보임). 위로 올리면 눌린 반사가 머리 위로 삐져나온다.
            .walk: IdlePoseRule(
                art: "walk", minStep: 1, limbDirection: ["leg_far": 0, "leg_near": 0],
                reflection: IdleReflection(toward: 0.49, mirror: false), shadow: IdleShadow(w: 0.7, h: 0.2, dx: 0.15, dy: -0.04)
            ),
            .floorSit: IdlePoseRule(
                art: "sit", mirror: true,
                reflection: IdleReflection(toward: 0.49), shadow: IdleShadow(w: 0.92, h: 0.12, dx: 0.04, dy: -0.03)
            ),
        ],
        gait: IdleGait(from: 0.74, to: 0.28, speed: 14, pause: 2.2, stride: 6)
    )
}

/// 컵 사진 틀(`CupView`와 같은 계산): 높이 84%, 아래에서 8% 올림, 가운데 정렬로 채우기(937×1666).
/// `unit`은 393×852 화면 기준으로 잰 pt 값(속도·흔들림 폭)을 이 화면에 맞추는 배율이다.
struct IdlePhoto: Sendable {
    let left: Double
    let top: Double
    let width: Double
    let height: Double

    static let canvas = CGSize(width: 937, height: 1666)
    /// 프로토타입 화면(393×852)의 사진 높이.
    static let referenceHeight = 852 * 0.84

    init(size: CGSize) {
        let slotHeight = Double(size.height) * Double(CupView.heightRatio)
        let scale = max(Double(size.width) / Self.canvas.width, slotHeight / Self.canvas.height)
        width = Self.canvas.width * scale
        height = Self.canvas.height * scale
        let bottom = Double(size.height) * (1 - Double(CupView.liftRatio))
        top = bottom - height
        left = (Double(size.width) - width) / 2
    }

    var unit: Double { height / Self.referenceHeight }

    var rect: CGRect { CGRect(x: left, y: top, width: width, height: height) }

    func point(_ nx: Double, _ ny: Double) -> CGPoint {
        CGPoint(x: left + nx * width, y: top + ny * height)
    }
}
