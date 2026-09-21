import Foundation

/// 하루 경계 시각(기본 새벽 4시) 기준의 하루 키.
/// `design/prototype.html`의 `dayKey`/`keyShift` 동작을 옮긴 것이다.
///
/// 경계 시각은 설정에서 바뀔 수 있으므로 기록에 저장하지 않고 매번 계산한다.
/// 저장해 두면 사용자가 경계를 바꾼 순간 과거 기록의 날짜가 어긋난다.
struct DayKey: Hashable, Comparable, Codable, CustomStringConvertible, Sendable {
    let year: Int
    let month: Int
    let day: Int

    var rawValue: String { String(format: "%04d-%02d-%02d", year, month, day) }
    var description: String { rawValue }

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// 경계 시각만큼 뒤로 민 뒤 달력 날짜를 읽는다.
    /// 경계가 4시면 03:59는 전날, 04:00은 당일이다.
    init(at date: Date, boundaryHour: Int, calendar: Calendar = .current) {
        let shifted = date.addingTimeInterval(-Double(boundaryHour) * 3600)
        let parts = calendar.dateComponents([.year, .month, .day], from: shifted)
        self.init(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0)
    }

    /// 정오를 기준으로 날짜를 옮긴다. 서머타임이 있는 지역에서 자정 기준이 하루를 건너뛰는 걸 피한다.
    func shifted(by days: Int, calendar: Calendar = .current) -> DayKey {
        let noon = DateComponents(year: year, month: month, day: day, hour: 12)
        guard let base = calendar.date(from: noon),
              let moved = calendar.date(byAdding: .day, value: days, to: base)
        else {
            assertionFailure("달력으로 환원되지 않는 DayKey: \(rawValue)")
            return self
        }
        let parts = calendar.dateComponents([.year, .month, .day], from: moved)
        return DayKey(year: parts.year ?? year, month: parts.month ?? month, day: parts.day ?? day)
    }

    static func < (lhs: DayKey, rhs: DayKey) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

/// 하루 기준(§3). 무료 사용자도 설정에서 바꿀 수 있다.
struct DailyLimits: Equatable, Sendable {
    let sugarG: Double
    let caffeineMg: Double

    static let `default` = DailyLimits(sugarG: 50, caffeineMg: 400)
}

/// 기록 한 건이 하루 합계에 더하는 양.
///
/// **이미 수량이 곱해진 총량이다.** 기록 시점에 `serving 값 × 수량`으로 스냅샷하므로
/// 합계에서 수량을 다시 곱하면 이중 계산이 된다(`design/prototype.html:348`).
///
/// nil은 0이 아니라 "브랜드 미공개"다. 합계에는 0으로 더하되 표시는 "미공개"로 남긴다
/// (SPEC §9.2, `data/SCHEMA.md`).
struct Consumption: Equatable, Sendable {
    let sugarG: Double?
    let caffeineMg: Double?
}

/// 하루치 합계와 남은 양. 컵 높이(§4.1)와 먹이기 적립(§4.7)이 이 값을 읽는다.
struct DayTotals: Equatable, Sendable {
    let sugarG: Double
    let caffeineMg: Double
    let leftSugarG: Double
    let leftCaffeineMg: Double
    let overSugarG: Double
    let overCaffeineMg: Double
}

enum DayMath {
    /// 남은 양 = `max(0, 하루 기준 − 그날 합계)`, 넘긴 양 = `max(0, 합계 − 기준)` (SPEC §2.2).
    static func totals(_ consumptions: [Consumption], limits: DailyLimits) -> DayTotals {
        var sugar = 0.0
        var caffeine = 0.0
        for item in consumptions {
            sugar += item.sugarG ?? 0
            caffeine += item.caffeineMg ?? 0
        }
        return DayTotals(
            sugarG: sugar,
            caffeineMg: caffeine,
            leftSugarG: max(0, limits.sugarG - sugar),
            leftCaffeineMg: max(0, limits.caffeineMg - caffeine),
            overSugarG: max(0, sugar - limits.sugarG),
            overCaffeineMg: max(0, caffeine - limits.caffeineMg)
        )
    }
}
