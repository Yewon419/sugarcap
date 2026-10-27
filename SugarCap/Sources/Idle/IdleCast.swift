import CoreGraphics
import Foundation

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
    /// 숨 쉬듯 올라오는 기포(카인 헤엄). 없으면 안 나온다.
    var bubbles: IdleBubbles?
    /// 잔 뒤 멀리 물러나 있기(`IdleAway`). 있으면 누를 수 없고, 앱을 다시 켤 때까지 다른 자세로 안 바뀐다.
    var away: IdleAway?

    func allows(step: Int) -> Bool {
        if let maxStep, step > maxStep { return false }
        if let minStep, step < minStep { return false }
        return true
    }
}

/// 유리 반사 자리(프로토타입 `REFLECTS.poses`). 캐릭터 가운데에서 잔 가운데 쪽으로 거리의 `toward`만큼 당기고
/// 위로 `up`(393×852 화면 pt) 올린다. `mirror`는 캐릭터별 기본값(`IdleReflectionLook.mirror`)을 덮는다.
struct IdleReflection: Sendable, Equatable {
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
struct IdleShadow: Sendable, Equatable {
    let w: Double
    let h: Double
    let dx: Double
    let dy: Double
    var feet = false
}

/// 잔 뒤 멀리 삐져 있는 자세(대표님 2026-10-27 "뒤쪽에 가서 짜져있는것", "건드려지지도 않게 앱 껐다켜야만 위치 바꾸도록").
/// 크기는 걷기 그림 키(서 있는 키)의 `scale`배. 멀어 보이게 몸 색을 벽 색 쪽으로 `fade`만큼 덮는다. 반투명이 아니라
/// 불투명한 색이라 테마가 바뀌어도 뒤 벽지가 비치지 않는다(대표님 2026-10-27 "반투명 말고 배경색을 씌워서").
/// 잔 누끼로 지워 잔 뒤에 선다.
struct IdleAway: Sendable, Equatable {
    let scale: Double
    let fade: Double
}

/// 숨 쉬듯 나오는 흰 기포 점(프로토타입 `bubblesAt`). `every`초마다 `count`개를 `gap`초 간격으로 내보낸다.
/// 나오는 자리는 그 순간 그림 속 `from`(캔버스 픽셀, 부리 끝)이 있던 화면 위 자리이고, 나온 뒤엔 몸을 따라가지 않고
/// `life`초 동안 `rise`(393×852 화면 pt)만큼 곧게 올라가며 살짝 흔들리다 사라진다. `size`는 첫 기포 반지름(pt).
struct IdleBubbles: Sendable, Equatable {
    let from: CGPoint
    let every: Double
    let count: Int
    let gap: Double
    let life: Double
    let rise: Double
    let size: Double
}

/// 기포 한 개의 한 시각 모습.
struct IdleBubble: Sendable, Equatable {
    let center: CGPoint
    let radius: Double
    let alpha: Double
}

/// 걷기: 오른쪽 끝(from) ↔ 왼쪽 끝(to)을 오가고 끝에서 쉰다(사진 폭 비율). 속도·보폭은 393×852 화면 pt.
struct IdleGait: Sendable {
    let from: Double
    let to: Double
    let speed: Double
    let pause: Double
    let stride: Double
}

/// 잔 세트 하나의 치수(SPEC §4.10). 잔 가장자리·음료 윗면은 단계마다 사진이 달라 따로 쟀다.
/// 대기 자세는 캐릭터 것이 아니라 지금 그 면에 그린 잔의 치수에 선다.
struct CupSetGeometry: Sendable {
    /// 사진 높이 비율. 잔 바닥.
    let bottom: Double
    /// 단계 → (뒤 가장자리, 앞 가장자리) 사진 높이 비율(가운데 열).
    let rim: [Int: (back: Double, front: Double)]
    /// 단계 → 음료 윗면(카인은 잠긴 얼음이 끝나고 진한 커피만 남는 선. 헤엄 자리 x 범위에서 밝기 90 경계로 쟀다, 2026-10-07).
    let liquid: [Int: Double]
    /// 단계 → 잔 가운데 x(사진 폭 비율). 누끼 알파에서 잔 옆선 가운데를 평균했다(프로토타입 `measureGlass`와 같은 방법).
    let axis: [Int: Double]

    /// 세트 id → 치수. 모르는 세트면 nil.
    static func of(_ setID: String) -> CupSetGeometry? {
        switch setID {
        case "strawberry-latte": return .strawberryLatte
        case "iced-americano": return .icedAmericano
        // 아메리카노 사진에서 음료만 바꾼 편집본이라 잔 자리·누끼가 같다.
        case "cafe-latte": return .icedAmericano
        case "choco-frappe": return .chocoFrappe
        default: return nil
        }
    }

    /// 이 잔에서 뽑지 않는 대기 자세. 음료가 불투명하면 음료 속 헤엄(`swim`·앞모습 `swim-front`)이 안 비쳐 뺀다(대표님 2026-10-25, 카페라떼).
    static func hiddenPoses(_ setID: String) -> Set<String> {
        setID == "cafe-latte" ? ["swim", "swim-front"] : []
    }
}

/// 캐릭터 하나의 대기 자세 설정(프로토타입 `CHARS`). 잔 치수(`cup`)는 그 면에 그린 잔 세트 것으로 갈아 끼운다.
struct IdleCast: Sendable {
    let character: String
    var cup: CupSetGeometry
    let reflectionLook: IdleReflectionLook
    /// 캔버스 픽셀 → pt 배율 = 사진 높이 × 이 값.
    let scalePerPhotoHeight: Double
    /// 눈꺼풀을 눈보다 얼마나 크게 덮을지(눈 크기 비율).
    let lidPad: Double
    let gait: IdleGait

    /// 자세 묶음(`IdlePoseBook`). 번들을 못 읽었으면 nil이고 캐릭터가 안 보인다.
    var poseSet: IdlePoseSet? { IdlePoseBook.sets[character] }

    /// 사진 높이 비율. 잔 바닥.
    var bottom: Double { cup.bottom }

    func rimLine(step: Int) -> (back: Double, front: Double) {
        cup.rim[step] ?? cup.rim[100] ?? (0.27, 0.33)
    }

    func liquidTop(step: Int) -> Double {
        cup.liquid[step] ?? bottom
    }

    func glassAxis(step: Int) -> Double {
        cup.axis[step] ?? 0.497
    }
}

extension CupSide {
    /// 이 면 캐릭터를 지금 고른 잔(`cupSetID`)의 치수에 세운다.
    var idleCast: IdleCast {
        var cast: IdleCast
        switch self {
        case .sugar: cast = .roshu
        case .caffeine: cast = .kain
        }
        if let cup = CupSetGeometry.of(cupSetID) {
            cast.cup = cup
        }
        return cast
    }
}

extension CupSetGeometry {
    /// 딸기 라떼(로슈 기본 잔).
    static let strawberryLatte = CupSetGeometry(
        bottom: 0.885,
        rim: [
            0: (0.2626, 0.3280), 30: (0.2605, 0.3247), 50: (0.2614, 0.3247),
            80: (0.2581, 0.3235), 100: (0.2686, 0.3268),
        ],
        liquid: [0: 0.80, 30: 0.557, 50: 0.4466, 80: 0.3511, 100: 0.3397],
        axis: [0: 0.4975, 30: 0.4973, 50: 0.4973, 80: 0.4935, 100: 0.4944]
    )

    /// 아이스 아메리카노(카인 기본 잔).
    static let icedAmericano = CupSetGeometry(
        bottom: 0.876,
        rim: [
            0: (0.2629, 0.3283), 30: (0.2629, 0.3271), 50: (0.2641, 0.3259),
            80: (0.2629, 0.3271), 100: (0.2683, 0.3265),
        ],
        liquid: [0: 0.87, 30: 0.782, 50: 0.668, 80: 0.568, 100: 0.537],
        axis: [0: 0.4974, 30: 0.4974, 50: 0.4971, 80: 0.4973, 100: 0.4953]
    )

    /// 초코 프라페(거래 상품, 2026-10-24). 가장자리는 9x16 사진 가운데 열에서 눈으로, 가운데는 누끼 옆선 평균으로 쟀다.
    /// 바닥은 누끼 바닥(.817)에 딸기 라떼의 누끼 바닥 ↔ `bottom` 차이(+.009)를 더했다. 100%는 크림이 입구 뒤를 가려 80% 값을 쓴다.
    /// 음료 윗면은 가운데 띠에서 갈색이 60% 넘는 첫 줄, 0%는 유리 안쪽 바닥.
    static let chocoFrappe = CupSetGeometry(
        bottom: 0.826,
        rim: [
            0: (0.2713, 0.3007), 30: (0.2719, 0.3007), 50: (0.2689, 0.3147),
            80: (0.2659, 0.3103), 100: (0.2659, 0.3115),
        ],
        liquid: [0: 0.75, 30: 0.6687, 50: 0.5522, 80: 0.419, 100: 0.3577],
        axis: [0: 0.4971, 30: 0.4971, 50: 0.4926, 80: 0.4937, 100: 0.496]
    )
}

extension IdleCast {
    /// 로슈. 배율은 목업에서 잰 값의 0.9배(대표님 2026-09-29). 자세는 `roshu/poses.json`.
    static let roshu = IdleCast(
        character: "roshu",
        cup: .strawberryLatte,
        // 대표님 레퍼런스(2026-09-29): 몸통만 있는 매끈한 윤곽, 크기 그대로.
        reflectionLook: IdleReflectionLook(tint: "#D5D7DD", mirror: false, squeeze: 1, opacity: 0.42),
        scalePerPhotoHeight: 7.96e-5 * 0.9,
        lidPad: 0.35,
        gait: IdleGait(from: 0.74, to: 0.28, speed: 20, pause: 1.6, stride: 10)
    )

    /// 카인. 배율은 목업의 앉기·헤엄 크기(잔 가장자리 폭 대비)의 1.3배(대표님 2026-09-29).
    /// 자세는 `kain/poses.json`.
    static let kain = IdleCast(
        character: "kain",
        cup: .icedAmericano,
        // 대표님 목업(2026-09-29): 그림 전체가 색 그대로 옅게, 좌우반전(부리가 캐릭터 쪽), 가로만 .45배.
        reflectionLook: IdleReflectionLook(tint: nil, mirror: true, squeeze: 0.45, opacity: 0.45),
        scalePerPhotoHeight: 0.0818 * 1.3 / 1666,
        // 카인 눈은 흰 고리라 눈꺼풀을 넉넉히 키우면 몸 밖으로 삐져나온다.
        lidPad: 0.04,
        gait: IdleGait(from: 0.74, to: 0.28, speed: 14, pause: 2.2, stride: 6)
    )
}

/// 컵 사진 틀(`CupView`와 같은 계산). 크기는 `CupView`의 사진 칸(화면 높이 84%)이고, 사진은 칸 아래에 붙여
/// 가운데 정렬로 채운다(937×1666). `unit`은 393×852 화면 기준으로 잰 pt 값(속도·흔들림 폭)을 이 화면에 맞추는 배율이다.
struct IdlePhoto: Sendable {
    let left: Double
    let top: Double
    let width: Double
    let height: Double

    static let canvas = CGSize(width: 937, height: 1666)
    /// 프로토타입 화면(393×852)의 사진 높이.
    static let referenceHeight = 852 * 0.84

    init(slot size: CGSize) {
        let scale = max(Double(size.width) / Self.canvas.width, Double(size.height) / Self.canvas.height)
        width = Self.canvas.width * scale
        height = Self.canvas.height * scale
        top = Double(size.height) - height
        left = (Double(size.width) - width) / 2
    }

    var unit: Double { height / Self.referenceHeight }

    var rect: CGRect { CGRect(x: left, y: top, width: width, height: height) }

    func point(_ nx: Double, _ ny: Double) -> CGPoint {
        CGPoint(x: left + nx * width, y: top + ny * height)
    }
}
