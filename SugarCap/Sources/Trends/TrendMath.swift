import Foundation

/// 추이 한 칸(하루 또는 한 주).
struct TrendPoint: Identifiable, Equatable, Sendable {
    /// 그 칸의 시작 날. 주 보기에서는 그 주의 첫날이다.
    let day: DayKey
    let sugarG: Double
    let caffeineMg: Double

    var id: String { day.rawValue }

    func value(_ side: CupSide) -> Double {
        switch side {
        case .sugar: return sugarG
        case .caffeine: return caffeineMg
        }
    }
}

/// 추이 계산(SPEC §4.3). 순수 함수만 둔다. 미공개 값은 0으로 더한다(§9.2).
enum TrendMath {
    /// 오늘까지 최근 `days`일의 하루 합계. 기록이 없는 날도 0으로 채워 자리를 남긴다.
    static func daily(
        entries: [Entry], boundaryHour: Int, today: DayKey, days: Int, calendar: Calendar = .current
    ) -> [TrendPoint] {
        let totals = dailyTotals(entries: entries, boundaryHour: boundaryHour, calendar: calendar)
        return (0..<days).reversed().map { offset in
            let day = today.shifted(by: -offset, calendar: calendar)
            let total = totals[day] ?? (sugarG: 0, caffeineMg: 0)
            return TrendPoint(day: day, sugarG: total.sugarG, caffeineMg: total.caffeineMg)
        }
    }

    /// 오늘이 든 주까지 최근 `weeks`주의 **하루 평균**. 합계를 쓰면 진행 중인 주가 낮아 보인다.
    static func weekly(
        entries: [Entry], boundaryHour: Int, today: DayKey, weeks: Int, calendar: Calendar = .current
    ) -> [TrendPoint] {
        let totals = dailyTotals(entries: entries, boundaryHour: boundaryHour, calendar: calendar)
        return (0..<weeks).reversed().map { offset in
            let start = today.shifted(by: -(offset * 7 + 6), calendar: calendar)
            var sugar = 0.0
            var caffeine = 0.0
            for day in 0..<7 {
                let key = start.shifted(by: day, calendar: calendar)
                let total = totals[key] ?? (sugarG: 0, caffeineMg: 0)
                sugar += total.sugarG
                caffeine += total.caffeineMg
            }
            return TrendPoint(day: start, sugarG: sugar / 7, caffeineMg: caffeine / 7)
        }
    }

    /// 최근 7일 합계가 그 앞 7일 대비 몇 % 달라졌는지. 앞 7일이 0이면 비교하지 않는다.
    static func changeVersusPreviousWeek(
        entries: [Entry], boundaryHour: Int, today: DayKey, side: CupSide,
        calendar: Calendar = .current
    ) -> Double? {
        let points = daily(
            entries: entries, boundaryHour: boundaryHour, today: today, days: 14, calendar: calendar
        )
        guard points.count == 14 else { return nil }
        let previous = points.prefix(7).reduce(0) { $0 + $1.value(side) }
        let current = points.suffix(7).reduce(0) { $0 + $1.value(side) }
        guard previous > 0 else { return nil }
        return (current - previous) / previous * 100
    }

    private static func dailyTotals(
        entries: [Entry], boundaryHour: Int, calendar: Calendar
    ) -> [DayKey: (sugarG: Double, caffeineMg: Double)] {
        var totals: [DayKey: (sugarG: Double, caffeineMg: Double)] = [:]
        for entry in entries {
            let key = entry.dayKey(boundaryHour: boundaryHour, calendar: calendar)
            let current = totals[key] ?? (sugarG: 0, caffeineMg: 0)
            totals[key] = (
                sugarG: current.sugarG + (entry.sugarG ?? 0),
                caffeineMg: current.caffeineMg + (entry.caffeineMg ?? 0)
            )
        }
        return totals
    }
}

/// 캐주얼 추이(2026-09-26 HTML 프로토타입 확정) 주 요약: 컵 선반 7칸 + "기준 안에서 마신 날" + "준 양".
struct WeekSummary: Equatable, Sendable {
    /// 오래된 날이 먼저, 오늘(또는 기준 끝 날)이 마지막.
    let days: [TrendPoint]
    let limit: Double
    let side: CupSide

    /// 하루 기준 이하로 마신 날 수(기록 없는 날도 0이라 포함).
    var withinDays: Int { days.filter { $0.value(side) <= limit }.count }
    var dailyAverage: Double { days.isEmpty ? 0 : days.reduce(0) { $0 + $1.value(side) } / Double(days.count) }
    /// 날마다 남긴 양의 합 = 캐릭터에게 준 양.
    var given: Double { days.reduce(0) { $0 + max(0, limit - $1.value(side)) } }
    /// 5일 이상이면 "사이가 쑥쑥 가까워지는 중"(감소 목표의 주 달성 기준과 같은 5일).
    var isGoodWeek: Bool { withinDays >= 5 }

    static func make(
        entries: [Entry], boundaryHour: Int, today: DayKey, side: CupSide, limit: Double, weeksAgo: Int = 0,
        calendar: Calendar = .current
    ) -> WeekSummary {
        let end = today.shifted(by: -7 * weeksAgo, calendar: calendar)
        let days = TrendMath.daily(entries: entries, boundaryHour: boundaryHour, today: end, days: 7, calendar: calendar)
        return WeekSummary(days: days, limit: limit, side: side)
    }
}

/// 월 방울 달력(Pro). 이번 달 1일부터 말일까지, 날마다 남긴 만큼 방울이 커진다.
struct DropCalendar: Equatable, Sendable {
    struct Cell: Equatable, Sendable, Identifiable {
        let day: DayKey
        /// 그날 마신 양. 오늘 이후는 nil.
        let used: Double?
        var id: String { day.rawValue }
    }

    let cells: [Cell]
    /// 1일이 무슨 요일인지(일=0). 달력 앞 빈칸 수.
    let leadingBlanks: Int
    let limit: Double

    func left(_ cell: Cell) -> Double? { cell.used.map { max(0, limit - $0) } }

    private var elapsed: [Cell] { cells.filter { $0.used != nil } }
    var elapsedDays: Int { elapsed.count }
    var withinDays: Int { elapsed.filter { ($0.used ?? 0) <= limit }.count }
    var given: Double { elapsed.reduce(0) { $0 + (left($1) ?? 0) } }

    /// 방울 크기(pt). 남긴 게 없으면 0(점만 찍는다).
    static func dropSize(left: Double, limit: Double) -> Double {
        guard left > 0, limit > 0 else { return 0 }
        return (12 + 26 * min(1, left / limit)).rounded()
    }

    static func make(
        entries: [Entry], boundaryHour: Int, today: DayKey, side: CupSide, limit: Double, calendar: Calendar = .current
    ) -> DropCalendar {
        let first = DayKey(year: today.year, month: today.month, day: 1)
        let nextMonth = today.month == 12
            ? DayKey(year: today.year + 1, month: 1, day: 1)
            : DayKey(year: today.year, month: today.month + 1, day: 1)
        let count = first.days(until: nextMonth, calendar: calendar)
        let daily = TrendMath.daily(entries: entries, boundaryHour: boundaryHour, today: today, days: today.day, calendar: calendar)
        let used = Dictionary(uniqueKeysWithValues: daily.map { ($0.day, $0.value(side)) })
        let cells = (0..<count).map { offset -> Cell in
            let day = first.shifted(by: offset, calendar: calendar)
            return Cell(day: day, used: day > today ? nil : (used[day] ?? 0))
        }
        return DropCalendar(cells: cells, leadingBlanks: first.weekday(calendar: calendar) - 1, limit: limit)
    }
}

extension DayKey {
    /// 1 = 일요일 … 7 = 토요일(`Calendar` 규칙).
    func weekday(calendar: Calendar = .current) -> Int {
        let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
        return calendar.component(.weekday, from: date)
    }
}
