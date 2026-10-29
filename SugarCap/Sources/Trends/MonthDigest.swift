import Foundation

/// 월 달력 아래 통계(2026-10-28 대표님, 프로토 `design/proto/trends-month-stats.html`, Pro). 면마다 따로, 순수 계산만 둔다.
/// 많이 준 음료 TOP 3 · 시간대 · 요일별 하루 평균 · 하루 기준 안에서 끝낸 날 · 최근 6개월 하루 평균.
struct MonthDigest: Equatable, Sendable {
    struct Drink: Equatable, Sendable {
        let name: String
        let brand: String
        let cups: Int
        let amount: Double
    }

    /// 시간대. 하루 경계 전 새벽 기록은 저녁으로 센다(그날 밤의 연장).
    enum Slot: Int, CaseIterable, Sendable {
        case morning, lunch, afternoon, evening

        /// 경계 시각 기준으로 편 시(새벽 2시 = 26시)에서 고른다.
        static func of(hour: Int, boundaryHour: Int) -> Slot {
            let stretched = hour < boundaryHour ? hour + 24 : hour
            switch stretched {
            case ..<11: return .morning
            case ..<14: return .lunch
            case ..<18: return .afternoon
            default: return .evening
            }
        }
    }

    struct Recent: Equatable, Sendable {
        /// 그 달 1일.
        let month: DayKey
        /// 기록한 날 하루 평균(달력 "지난달보다 %"와 같은 정의). 첫 기록 달 전이면 nil.
        let average: Double?
    }

    /// 요일 막대를 세우는 최소 기록 일수. 한 달이면 요일마다 표본이 4~5일뿐이라 하루짜리는 비운다.
    static let minDaysPerWeekday = 2
    /// 오후 2시 이후 카페인(카페인 면 한 줄).
    static let lateHour = 14

    /// 이 달 먹은 양의 합(오늘 포함).
    let total: Double
    let top: [Drink]
    /// `Slot` 순서대로 먹은 양.
    let slots: [Double]
    /// 오후 2시 이후(새벽 포함) 먹은 양.
    let late: Double
    /// 일요일부터 7칸. 기록한 지난날이 `minDaysPerWeekday` 미만이면 nil. 오늘은 안 끝나서 뺀다.
    let weekdays: [Double?]
    /// 기록한 지난날 중 하루 기준 안(이하)에서 끝난 날. 기준은 지금 기준이다(지난 기준은 저장하지 않는다).
    let keptDays: Int
    let closedDays: Int
    /// 보는 달까지 6달, 오래된 달부터.
    let recent: [Recent]

    static func make(
        entries: [Entry], boundaryHour: Int, year: Int, month: Int, today: DayKey, side: CupSide, limit: Double,
        earliest: DayKey, calendar: Calendar = .current
    ) -> MonthDigest {
        let mine = entries.filter { entry in
            let key = entry.dayKey(boundaryHour: boundaryHour, calendar: calendar)
            return key.year == year && key.month == month
        }
        let value: (Entry) -> Double? = { side == .sugar ? $0.sugarG : $0.caffeineMg }

        var slots = Array(repeating: 0.0, count: Slot.allCases.count)
        var late = 0.0
        var groups: [String: Drink] = [:]
        for entry in mine {
            let amount = value(entry) ?? 0
            let hour = calendar.component(.hour, from: entry.loggedAt)
            slots[Slot.of(hour: hour, boundaryHour: boundaryHour).rawValue] += amount
            if hour >= lateHour || hour < boundaryHour { late += amount }
            // 그 면 값이 0이거나 미공개인 음료는 순위에서 뺀다. 사이즈는 합친다.
            guard amount > 0 else { continue }
            let key = entry.brandName + "\u{1F}" + entry.drinkName
            let old = groups[key]
            groups[key] = Drink(
                name: entry.drinkName, brand: entry.brandName, cups: (old?.cups ?? 0) + entry.quantity,
                amount: (old?.amount ?? 0) + amount
            )
        }
        let top = groups.values
            .sorted { lhs, rhs in
                if lhs.amount != rhs.amount { return lhs.amount > rhs.amount }
                if lhs.cups != rhs.cups { return lhs.cups > rhs.cups }
                return lhs.name < rhs.name
            }
            .prefix(3)

        let page = MonthPage.make(
            entries: entries, boundaryHour: boundaryHour, year: year, month: month, today: today, side: side,
            calendar: calendar
        )
        let closed = page.cells.filter { !$0.isToday }.compactMap { cell in cell.used.map { (cell.day, $0) } }
        var byWeekday = Array(repeating: [Double](), count: 7)
        for (day, used) in closed {
            byWeekday[day.weekday(calendar: calendar) - 1].append(used)
        }
        let weekdays = byWeekday.map { values -> Double? in
            values.count >= minDaysPerWeekday ? values.reduce(0, +) / Double(values.count) : nil
        }

        let shown = DayKey(year: year, month: month, day: 1)
        let firstMonth = DayKey(year: earliest.year, month: earliest.month, day: 1)
        let recent = (0..<6).reversed().map { back -> Recent in
            let start = MonthTrendsView.shift(shown, by: -back)
            guard start >= firstMonth else { return Recent(month: start, average: nil) }
            let average = MonthPage.make(
                entries: entries, boundaryHour: boundaryHour, year: start.year, month: start.month, today: today,
                side: side, calendar: calendar
            ).dailyAverage
            return Recent(month: start, average: average)
        }

        return MonthDigest(
            total: slots.reduce(0, +),
            top: Array(top),
            slots: slots,
            late: late,
            weekdays: weekdays,
            keptDays: closed.filter { $0.1 <= limit }.count,
            closedDays: closed.count,
            recent: recent
        )
    }
}
