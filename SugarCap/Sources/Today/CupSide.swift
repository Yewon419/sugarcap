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

    /// 받침에 맞춘 "와/과" (로슈와, 카인과).
    var characterNameWithGwa: String {
        switch self {
        case .sugar: return "로슈와"
        case .caffeine: return "카인과"
        }
    }

    /// 받침에 맞춘 "가/이" (로슈가, 카인이).
    var characterNameWithIga: String {
        switch self {
        case .sugar: return "로슈가"
        case .caffeine: return "카인이"
        }
    }

    /// `Affinity.character` 저장 값(SPEC §2.2 `kain|roshu`).
    var characterID: String {
        switch self {
        case .sugar: return "roshu"
        case .caffeine: return "kain"
        }
    }

    var characterAsset: String {
        switch self {
        case .sugar: return "character-roshu"
        case .caffeine: return "character-kain"
        }
    }

    /// 먹이기·소개에 쓰는 음료 방울 사진(`design/assets/drops`, 힉스필드 Seedream 5.0 lite로 만든 둥근 방울).
    var dropAsset: String {
        switch self {
        case .sugar: return "drop-sugar"
        case .caffeine: return "drop-caffeine"
        }
    }

    /// 이 면에 그리는 컵 세트(SPEC §9-10). 당 컵은 단 음료, 카페인 컵은 커피.
    /// 세트 선택(§9-9 커스터마이징)이 생기기 전까지는 면마다 고정이다.
    var cupSetID: String {
        switch self {
        case .sugar: return "strawberry-latte"
        case .caffeine: return "iced-americano"
        }
    }

    /// 감소 목표가 하루 기준을 낮출 때 쓰는 반올림 단위(SPEC §9.5).
    var reductionStep: Double {
        switch self {
        case .sugar: return 5
        case .caffeine: return 25
        }
    }

    func limit(_ limits: DailyLimits) -> Double {
        switch self {
        case .sugar: return limits.sugarG
        case .caffeine: return limits.caffeineMg
        }
    }

    func used(_ totals: DayTotals) -> Double {
        switch self {
        case .sugar: return totals.sugarG
        case .caffeine: return totals.caffeineMg
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

    var other: CupSide {
        switch self {
        case .sugar: return .caffeine
        case .caffeine: return .sugar
        }
    }

    /// 이 정도 카페인이면 카페인 음료로 본다. 에스프레소 한 샷 안팎.
    static let caffeineDrinkMinMg: Double = 50

    /// 음료 한 잔이 주로 어느 쪽 음료인지. 목록 수치와 메뉴 패널이 이 면을 크게 보여 준다.
    /// 카페인이 기준 이상이거나, 당이 0인데 카페인이 있으면 카페인 음료. 나머지는 당 음료다.
    /// 하루 기준 대비 비율로 가르면 같은 바닐라라떼가 HOT은 당·ICED는 카페인으로 갈려서 카페인 절대량으로 정했다
    /// (2026-10-04, 아이스카페라떼가 우유 당 때문에 당 음료로 뜨던 문제).
    static func primary(sugarG: Double?, caffeineMg: Double?) -> CupSide {
        guard let caffeineMg, caffeineMg > 0 else { return .sugar }
        if caffeineMg >= caffeineDrinkMinMg { return .caffeine }
        return (sugarG ?? 0) > 0 ? .sugar : .caffeine
    }
}
