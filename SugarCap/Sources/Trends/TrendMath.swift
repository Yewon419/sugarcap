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

extension DayKey {
    /// 1 = 일요일 … 7 = 토요일(`Calendar` 규칙).
    func weekday(calendar: Calendar = .current) -> Int {
        let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
        return calendar.component(.weekday, from: date)
    }

    /// 그날이 든 주의 월요일. 추이 주 보기는 월~일 주다(2026-10-27 대표님 "정확히는 그 주").
    func weekStart(calendar: Calendar = .current) -> DayKey {
        shifted(by: -((weekday(calendar: calendar) + 5) % 7), calendar: calendar)
    }
}

/// 추이 "식탁 위 일주일"(2026-10-06 이식, 프로토 `design/proto/screens-trends-table.js`)의 잔 한 칸.
/// 한 칸 = 하루.
struct TableCup: Identifiable, Equatable, Sendable {
    /// 그 칸의 첫날. 주 보기에서는 그날이다.
    let day: DayKey
    let used: Double
    /// 기록한 날이나 오늘이 하나라도 들었는지. 기록 없는 지난날은 "남겼다"고 셀 수 없다(안 적었을 수도 있다).
    let recorded: Bool
    let isFuture: Bool
    /// 오늘 칸. 캐릭터가 이 잔 뒤에 선다(없으면 마지막 잔).
    let isNow: Bool

    var id: String { day.rawValue }
}

struct TrendTable: Equatable, Sendable {
    let cups: [TableCup]
    /// 큰 숫자: 기록한 날과 오늘 남긴 양의 합.
    let total: Double
    let first: DayKey
    let last: DayKey

    var nowIndex: Int { cups.firstIndex(where: \.isNow) ?? max(0, cups.count - 1) }

    /// 오늘로 끝나는 7일. `weeksAgo`만큼 앞 주로 옮긴다. 주 지킴 축하(`WeekKeptCelebration`)가 쓴다.
    static func week(
        entries: [Entry], boundaryHour: Int, today: DayKey, side: CupSide, limit: Double, weeksAgo: Int = 0,
        calendar: Calendar = .current
    ) -> TrendTable {
        let recordedDays = recordedDays(entries: entries, boundaryHour: boundaryHour, calendar: calendar)
        let end = today.shifted(by: -7 * weeksAgo, calendar: calendar)
        let days = TrendMath.daily(entries: entries, boundaryHour: boundaryHour, today: end, days: 7, calendar: calendar)
        let cups = days.map { point in
            TableCup(
                day: point.day, used: point.value(side),
                recorded: recordedDays.contains(point.day) || point.day == today,
                isFuture: false, isNow: point.day == today
            )
        }
        let total = cups.filter(\.recorded).reduce(0) { $0 + max(0, limit - $1.used) }
        return TrendTable(cups: cups, total: total, first: days.first?.day ?? end, last: end)
    }

    /// `start`(월요일)부터 일요일까지 한 주. 오늘 이후 날은 비운다(기록 없음, `isFuture`).
    static func calendarWeek(
        entries: [Entry], boundaryHour: Int, today: DayKey, start: DayKey, side: CupSide, limit: Double,
        calendar: Calendar = .current
    ) -> TrendTable {
        let recordedDays = recordedDays(entries: entries, boundaryHour: boundaryHour, calendar: calendar)
        let end = start.shifted(by: 6, calendar: calendar)
        let days = TrendMath.daily(entries: entries, boundaryHour: boundaryHour, today: end, days: 7, calendar: calendar)
        let cups = days.map { point in
            let isFuture = point.day > today
            return TableCup(
                day: point.day, used: isFuture ? 0 : point.value(side),
                recorded: !isFuture && (recordedDays.contains(point.day) || point.day == today),
                isFuture: isFuture, isNow: point.day == today
            )
        }
        let total = cups.filter(\.recorded).reduce(0) { $0 + max(0, limit - $1.used) }
        return TrendTable(cups: cups, total: total, first: start, last: end)
    }

    /// 이번 주와 지난주 **같은 요일까지** 남긴 양의 차이(끝줄 한 줄). 이번 주는 아직 안 끝났으니 월 비교와 같은 규칙이다.
    /// 지난주 그 기간에 기록이 없으면 비교하지 않는다.
    static func calendarWeekChange(
        entries: [Entry], boundaryHour: Int, today: DayKey, side: CupSide, limit: Double,
        calendar: Calendar = .current
    ) -> Double? {
        let start = today.weekStart(calendar: calendar)
        let elapsed = start.days(until: today, calendar: calendar) + 1
        let previous = calendarWeek(
            entries: entries, boundaryHour: boundaryHour, today: today, start: start.shifted(by: -7, calendar: calendar),
            side: side, limit: limit, calendar: calendar
        ).cups.prefix(elapsed).filter(\.recorded)
        guard !previous.isEmpty else { return nil }
        let current = calendarWeek(
            entries: entries, boundaryHour: boundaryHour, today: today, start: start, side: side, limit: limit,
            calendar: calendar
        )
        return current.total - previous.reduce(0) { $0 + max(0, limit - $1.used) }
    }

    private static func recordedDays(entries: [Entry], boundaryHour: Int, calendar: Calendar) -> Set<DayKey> {
        Set(entries.map { $0.dayKey(boundaryHour: boundaryHour, calendar: calendar) })
    }
}
