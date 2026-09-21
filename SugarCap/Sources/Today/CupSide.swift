import Foundation

/// 컵 한 면. 당은 로슈, 카페인은 카인이 맡는다(SPEC §2.2·§9.3).
/// 오늘 화면은 당으로 시작하고 좌우 스와이프로 카페인으로 넘어간다(§4.1).
enum CupSide: String, CaseIterable, Identifiable, Sendable {
    case sugar
    case caffeine

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sugar: return "당"
        case .caffeine: return "카페인"
        }
    }

    var unit: String {
        switch self {
        case .sugar: return "g"
        case .caffeine: return "mg"
        }
    }

    var characterName: String {
        switch self {
        case .sugar: return "로슈"
        case .caffeine: return "카인"
        }
    }

    var characterAsset: String {
        switch self {
        case .sugar: return "character-roshu"
        case .caffeine: return "character-kain"
        }
    }

    func limit(_ limits: DailyLimits) -> Double {
        switch self {
        case .sugar: return limits.sugarG
        case .caffeine: return limits.caffeineMg
        }
    }

    func remaining(_ totals: DayTotals) -> Double {
        switch self {
        case .sugar: return totals.leftSugarG
        case .caffeine: return totals.leftCaffeineMg
        }
    }

    func overflow(_ totals: DayTotals) -> Double {
        switch self {
        case .sugar: return totals.overSugarG
        case .caffeine: return totals.overCaffeineMg
        }
    }
}
