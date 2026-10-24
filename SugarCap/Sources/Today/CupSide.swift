import Foundation

/// 컵 한 면. 당은 로슈, 카페인은 카인이 맡는다(SPEC §2.2·§9.3).
/// 오늘 화면은 당으로 시작하고 좌우 스와이프로 카페인으로 넘어간다(§4.1).
enum CupSide: String, CaseIterable, Identifiable, Sendable {
    case sugar
    case caffeine

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sugar: return String(localized: "당")
        case .caffeine: return String(localized: "카페인")
        }
    }

    var unit: String {
        switch self {
        case .sugar: return "g"
        case .caffeine: return "mg"
        }
    }

    /// 화면에 쓰는 이름. 별명을 붙였으면 별명(SPEC §4.9 2026-10-11).
    var characterName: String {
        Nickname.stored(characterID) ?? defaultCharacterName
    }

    /// 원래 이름(로슈 · 카인).
    var defaultCharacterName: String {
        switch self {
        case .sugar: return String(localized: "로슈")
        case .caffeine: return String(localized: "카인")
        }
    }

    /// 받침에 맞춘 "와/과" (로슈와, 카인과). 별명이면 별명 끝 글자로 고른다.
    var characterNameWithGwa: String {
        if let nickname = Nickname.stored(characterID) {
            return Nickname.usesJosa ? Josa.withGwa(nickname) : nickname
        }
        switch self {
        case .sugar: return String(localized: "로슈와")
        case .caffeine: return String(localized: "카인과")
        }
    }

    /// 받침에 맞춘 "가/이" (로슈가, 카인이). 별명이면 별명 끝 글자로 고른다.
    var characterNameWithIga: String {
        if let nickname = Nickname.stored(characterID) {
            return Nickname.usesJosa ? Josa.withIga(nickname) : nickname
        }
        switch self {
        case .sugar: return String(localized: "로슈가")
        case .caffeine: return String(localized: "카인이")
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
    /// 거래로 산 잔을 쓰는 중이면 그 잔의 방울(§4.10).
    var dropAsset: String {
        if let item = TradeCatalog.item(cupSetID) { return item.dropAsset }
        switch self {
        case .sugar: return "drop-sugar"
        case .caffeine: return "drop-caffeine"
        }
    }

    /// 이 면에 그리는 컵 세트(SPEC §9-10·§4.10). 보관함에서 고른 잔(`cupSetKey`)이 이 면 상품이면 그 잔, 아니면 기본 잔.
    /// 가진 잔인지는 고를 때(보관함)와 앱 시작 때(`CupSetChoice.dropUnowned`) 본다.
    var cupSetID: String {
        if let chosen = UserDefaults.standard.string(forKey: cupSetKey), TradeCatalog.item(chosen)?.side == self {
            return chosen
        }
        return defaultCupSetID
    }

    /// 기본 잔. 당 컵은 단 음료, 카페인 컵은 커피.
    var defaultCupSetID: String {
        switch self {
        case .sugar: return "strawberry-latte"
        case .caffeine: return "iced-americano"
        }
    }

    /// 기본 잔 이름(보관함 "잔" 칸).
    var defaultCupSetName: String {
        switch self {
        case .sugar: return String(localized: "딸기 라떼")
        case .caffeine: return String(localized: "아이스 아메리카노")
        }
    }

    /// 고른 잔을 두는 기기 설정 키(Debug `-cupSet.sugar choco-frappe`).
    var cupSetKey: String { "cupSet.\(rawValue)" }

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

    /// 설정 "기록할 것"에서 켠 면(순서는 당 → 카페인). 둘 다 꺼졌으면 둘 다(빈 화면 방지).
    static func tracked(sugar: Bool, caffeine: Bool) -> [CupSide] {
        let sides = allCases.filter { $0 == .sugar ? sugar : caffeine }
        return sides.isEmpty ? allCases : sides
    }

    /// 보고 있던 면이 꺼졌으면 켜진 첫 면으로 옮긴다.
    static func visible(_ side: CupSide, in tracked: [CupSide]) -> CupSide {
        tracked.contains(side) ? side : tracked.first ?? side
    }

    /// 이 정도 카페인이면 카페인 음료로 본다. 에스프레소 한 샷 안팎.
    static let caffeineDrinkMinMg: Double = 50

    /// 카페인 음료라도 당(g)이 카페인(mg)의 이만큼 이상이면 당 음료로 본다.
    static let sugarPerCaffeineMin: Double = 0.75

    /// 음료 한 잔이 주로 어느 쪽 음료인지. 목록 수치와 메뉴 패널이 이 면을 크게 보여 준다.
    /// 카페인이 기준 이상이거나, 당이 0인데 카페인이 있으면 카페인 음료. 나머지는 당 음료다.
    /// 하루 기준 대비 비율로 가르면 같은 바닐라라떼가 HOT은 당·ICED는 카페인으로 갈려서 카페인 절대량으로 정했다
    /// (2026-10-04, 아이스카페라떼가 우유 당 때문에 당 음료로 뜨던 문제).
    /// 다만 카페인이 기준을 넘어도 당이 카페인 mg의 0.75배(g) 이상이면 당 음료다(빌드 272 대표님, 딸기 아사이 레모네이드
    /// 당 62 g·카페인 73 mg). 카탈로그에서 넘어가는 건 단 차·쉐이크·에이드 16종이고 커피·라떼는 그대로 카페인이다.
    /// 이름에 "흑당"이 들어간 메뉴는 카페인과 상관없이 당 음료다(대표님 2026-10-06, 흑당 카페라떼).
    static func primary(name: String, sugarG: Double?, caffeineMg: Double?) -> CupSide {
        if name.contains("흑당") { return .sugar }
        guard let caffeineMg, caffeineMg > 0 else { return .sugar }
        if caffeineMg >= caffeineDrinkMinMg {
            return (sugarG ?? 0) >= caffeineMg * sugarPerCaffeineMin ? .sugar : .caffeine
        }
        return (sugarG ?? 0) > 0 ? .sugar : .caffeine
    }
}
