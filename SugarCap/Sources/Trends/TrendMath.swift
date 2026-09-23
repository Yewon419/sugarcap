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
