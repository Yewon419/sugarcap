import Foundation
import SwiftData

/// 감소 목표를 만들고, 끝난 주를 판정하고, 그 결과를 하루 기준에 반영한다(SPEC §9.5).
/// 계산은 `ReductionMath`·`ReductionAdvance`의 순수 함수가 한다.
@MainActor
enum ReductionStore {
    static func goals(in context: ModelContext) throws -> [ReductionGoal] {
        try context.fetch(FetchDescriptor<ReductionGoal>())
    }

    static func goal(for side: CupSide, in context: ModelContext) throws -> ReductionGoal? {
        let id = side.rawValue
        return try context.fetch(
            FetchDescriptor<ReductionGoal>(predicate: #Predicate { $0.side == id })
        ).first
    }

    /// 지금 하루 기준에서 목표치까지 내려가는 계획을 만든다. 같은 면의 기존 계획은 갈아 끼운다.
    @discardableResult
    static func start(
        side: CupSide, target: Double, weeks: Int, settings: AppSettings, today: DayKey,
        in context: ModelContext
    ) throws -> ReductionGoal {
        if let existing = try goal(for: side, in: context) {
            context.delete(existing)
        }
        let goal = ReductionGoal(
            side: side, startDay: today, startLimit: side.limit(settings.limits), target: target,
            weeks: weeks
        )
        context.insert(goal)
        return goal
    }

    /// 계획만 멈춘다. 지금까지 내려온 하루 기준은 그대로 둔다.
    static func stop(side: CupSide, in context: ModelContext) throws {
        if let goal = try goal(for: side, in: context) {
            context.delete(goal)
        }
    }

    /// 끝난 주를 전부 판정하고 이번 주 하루 기준을 설정에 쓴다.
    /// 목표치에 닿으면 계획을 끝내고 목표치를 하루 기준으로 남긴다.
    static func advance(
        _ goal: ReductionGoal,
        entries: [Entry],
        boundaryHour: Int,
        today: DayKey,
        settings: AppSettings,
        calendar: Calendar = .current,
        in context: ModelContext
    ) {
        guard let side = goal.cupSide, let startDay = goal.startDayKey else { return }
        let step = side.reductionStep

        goal.state = ReductionAdvance.advance(
            state: goal.state,
            elapsedWeeks: ReductionMath.elapsedWeeks(from: startDay, to: today, calendar: calendar),
            start: goal.startLimit,
            target: goal.target,
            weeks: goal.weeks,
            step: step,
            totalsForWeek: { week in
                weekTotals(
                    side: side, entries: entries, from: startDay, week: week,
                    boundaryHour: boundaryHour, calendar: calendar
                )
            }
        )

        let limit = goal.currentLimit(step: step)
        settings.setLimit(limit, for: side)
        if limit <= goal.target {
            context.delete(goal)
        }
    }

    /// 목표 시작일 기준 `week`번째 주(0-based) 7일의 하루 합계. 기록이 없는 날은 0이다.
    private static func weekTotals(
        side: CupSide, entries: [Entry], from startDay: DayKey, week: Int, boundaryHour: Int,
        calendar: Calendar
    ) -> [Double] {
        (0..<7).map { offset in
            let day = startDay.shifted(by: week * 7 + offset, calendar: calendar)
            return entries
                .filter { $0.dayKey(boundaryHour: boundaryHour, calendar: calendar) == day }
                .reduce(0) { sum, entry in
                    switch side {
                    case .sugar: return sum + (entry.sugarG ?? 0)
                    case .caffeine: return sum + (entry.caffeineMg ?? 0)
                    }
                }
        }
    }
}
