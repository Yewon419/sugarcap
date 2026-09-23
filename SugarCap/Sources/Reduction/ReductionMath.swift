import Foundation

/// 감소 목표 계산(SPEC §9.5). 순수 함수만 둔다.
///
/// 주당 낮추는 폭 = (시작 기준 − 목표) / 주 수. 그 주의 하루 기준은 **달성한 주 수**만큼만 내려간다.
/// 미달한 주는 기준을 유지하므로 계획 기간이 그만큼 늘어난다.
enum ReductionMath {
    /// 한 주를 달성으로 치는 최소 일수(7일 중).
    static let requiredDays = 5

    static func weeklyLimit(
        start: Double, target: Double, weeks: Int, achievedWeeks: Int, step: Double
    ) -> Double {
        guard weeks > 0, start > target, step > 0 else { return target }
        let perWeek = (start - target) / Double(weeks)
        let raw = start - perWeek * Double(achievedWeeks)
        return min(start, max(target, roundToStep(raw, step: step)))
    }

    /// 반올림 단위에 맞춘다. **정확히 중간이면 목표 쪽(아래)으로 내린다.**
    /// 위로 올리면 주당 폭이 단위의 절반일 때(50 g → 30 g, 8주 = 2.5 g) 달성해도 기준이 그대로여서
    /// 계획이 멈춘 것처럼 보인다.
    static func roundToStep(_ value: Double, step: Double) -> Double {
        guard step > 0 else { return value }
        return (value / step + 0.5 - 1e-9).rounded(.down) * step
    }

    /// 그 주 7일 중 기준 이하인 날이 5일 이상이면 달성.
    /// **기록이 없는 날은 0으로 들어와 기준 이하로 센다**(자기 보고 앱, SPEC §9.3).
    static func isWeekAchieved(dailyTotals: [Double], limit: Double) -> Bool {
        dailyTotals.filter { $0 <= limit + 1e-9 }.count >= requiredDays
    }

    /// 목표 시작일부터 오늘까지 **끝난** 주의 수. 진행 중인 주는 세지 않는다.
    static func elapsedWeeks(from start: DayKey, to today: DayKey, calendar: Calendar = .current) -> Int {
        max(0, start.days(until: today, calendar: calendar) / 7)
    }
}

/// 판정이 어디까지 끝났는지. `evaluatedWeeks`는 판정한 주 수, `achievedWeeks`는 그중 달성한 주 수다.
struct ReductionState: Equatable, Sendable {
    var achievedWeeks: Int
    var evaluatedWeeks: Int
}

enum ReductionAdvance {
    /// 끝난 주를 차례로 판정한다. 각 주의 기준은 그 시점까지 달성한 주 수로 계산한다.
    /// - Parameter totalsForWeek: 0-based 주차 → 그 주 7일의 하루 합계.
    static func advance(
        state: ReductionState,
        elapsedWeeks: Int,
        start: Double,
        target: Double,
        weeks: Int,
        step: Double,
        totalsForWeek: (Int) -> [Double]
    ) -> ReductionState {
        var state = state
        while state.evaluatedWeeks < elapsedWeeks {
            let limit = ReductionMath.weeklyLimit(
                start: start, target: target, weeks: weeks,
                achievedWeeks: state.achievedWeeks, step: step
            )
            if ReductionMath.isWeekAchieved(
                dailyTotals: totalsForWeek(state.evaluatedWeeks), limit: limit
            ) {
                state.achievedWeeks += 1
            }
            state.evaluatedWeeks += 1
        }
        return state
    }
}
