import Foundation

/// 오늘 화면에서 캐릭터를 연달아 너무 많이 누르면 나오는 반응(대표님 2026-10-12).
/// 연타 판정은 호감도 화면과 같은 `PokeMath.combo`(0.6초 안에 이어 5번). 반응은 그중 하나를 무작위로 고른다.
enum IdleFuss: String, CaseIterable, Sendable {
    /// 좌우로 부르르 떤다.
    case shiver
    /// 부르르 떨고 다른 대기 자세로 옮긴다. 구경꾼은 자리가 정해져 있어 안 나온다.
    case dodge
    /// 아무 말 없이 잠깐 멈춰 이쪽을 본다(숨·깜빡임까지 멈춤).
    case stare
    /// 머리 위로 하트가 떠오른다. 호감도가 높을 때만.
    case heart
}

enum IdleFussMath {
    /// 하트가 나오는 호감도 단계. 호감도 화면에서 애교를 부리기 시작하는 단계와 같다(`PokeMath.reaction`).
    static let fondLevel = 7
    static let shiverLength = 0.5
    static let stareLength = 1.8
    static let heartLength = 1.3
    /// 부르르 떠는 폭(그림 폭 대비).
    static let shiverWidth = 0.05

    static func options(canDodge: Bool, level: Int) -> [IdleFuss] {
        IdleFuss.allCases.filter { fuss in
            switch fuss {
            case .shiver, .stare: true
            case .dodge: canDodge
            case .heart: level >= fondLevel
            }
        }
    }

    static func length(_ fuss: IdleFuss) -> Double {
        switch fuss {
        case .shiver, .dodge: shiverLength
        case .stare: stareLength
        case .heart: heartLength
        }
    }

    /// 부르르: 가로 밀림(-1 ~ 1, 그림 폭 × `shiverWidth`). 초당 12번 떨며 끝으로 갈수록 잦아든다.
    static func shiver(age: Double) -> Double {
        guard age >= 0, age < shiverLength else { return 0 }
        let fade = 1 - age / shiverLength
        return sin(2 * Double.pi * 12 * age) * fade
    }

    /// 하트: 크기(0 ~ 약 1.1), 떠오른 높이(하트 크기 대비), 불투명도. 끝났으면 nil.
    static func heart(age: Double) -> (scale: Double, rise: Double, alpha: Double)? {
        guard age >= 0, age < heartLength else { return nil }
        let pop = min(1, age / 0.22)
        let scale = Ease.backOut(pop)
        let rise = 0.6 * Ease.power2Out(age / heartLength)
        let fadeFrom = heartLength * 0.65
        let alpha = age < fadeFrom ? 1 : 1 - (age - fadeFrom) / (heartLength - fadeFrom)
        return (scale, rise, alpha)
    }
}

/// 멈춰 보기(`IdleFuss.stare`) 동안 대기 자세 시계를 세우고, 끝나면 멈춘 만큼 늦춰 이어 간다(튀지 않게).
/// 시각은 전부 자세를 뽑은 뒤 초(`IdleCharacterLayer`의 `t`).
struct IdleStare: Equatable, Sendable {
    /// 지난 멈춤들로 밀린 시간.
    private(set) var lag: Double = 0
    /// 마지막 멈춤을 시작한 시각.
    private(set) var from: Double?

    func isStaring(at t: Double) -> Bool {
        guard let from else { return false }
        return t >= from && t < from + IdleFussMath.stareLength
    }

    /// 자세 움직임에 쓸 시각.
    func time(_ t: Double) -> Double {
        guard let from, t >= from else { return t - lag }
        return t < from + IdleFussMath.stareLength ? from - lag : t - lag - IdleFussMath.stareLength
    }

    /// t에 멈추기 시작한다. 이미 멈춰 있으면 그대로 둔다.
    mutating func begin(at t: Double) {
        if isStaring(at: t) { return }
        if let from, t >= from + IdleFussMath.stareLength { lag += IdleFussMath.stareLength }
        from = t
    }
}

/// 캐릭터 하나의 연타 세기와 지금 반응. 시각은 자세를 뽑은 뒤 초.
struct IdleFussState: Equatable, Sendable {
    var combo = 0
    var lastTap: Date?
    var fuss: IdleFuss?
    var startedAt: Double?
    var stare = IdleStare()

    init() {}

    init(fuss: IdleFuss, startedAt: Double) {
        self.fuss = fuss
        self.startedAt = startedAt
    }

    func isActive(at t: Double) -> Bool {
        guard let fuss, let startedAt else { return false }
        return t >= startedAt && t < startedAt + IdleFussMath.length(fuss)
    }

    /// 누름 하나를 센다. 연타가 `PokeMath.comboCount`에 닿고 반응 중이 아니면 `options`에서 하나를 골라 시작한다.
    func poked(now: Date, t: Double, options: [IdleFuss]) -> IdleFussState {
        var next = self
        next.combo = PokeMath.combo(previous: combo, lastTap: lastTap, now: now)
        next.lastTap = now
        guard next.combo >= PokeMath.comboCount, !isActive(at: t), let fuss = options.randomElement() else { return next }
        next.fuss = fuss
        next.startedAt = t
        if fuss == .stare { next.stare.begin(at: t) }
        return next
    }

    /// 부르르 밀림(-1 ~ 1).
    func jitter(t: Double) -> Double {
        guard fuss == .shiver || fuss == .dodge, let startedAt else { return 0 }
        return IdleFussMath.shiver(age: t - startedAt)
    }

    func heart(t: Double) -> (scale: Double, rise: Double, alpha: Double)? {
        guard fuss == .heart, let startedAt else { return nil }
        return IdleFussMath.heart(age: t - startedAt)
    }
}
