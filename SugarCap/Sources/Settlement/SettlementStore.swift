import Foundation
import SwiftData

/// 먹이기 한 번의 결과. 캐릭터 하나당 1개.
struct FeedResult: Equatable, Sendable {
    let side: CupSide
    let left: Double
    let levelBefore: Int
    let levelAfter: Int

    var leveledUp: Bool { levelAfter > levelBefore }
}

/// 정산 행·호감도 행을 읽고 쓴다(SPEC §4.7). 계산은 `SettlementMath`의 순수 함수에 맡긴다.
/// 저장(`save`)은 호출한 화면이 한 번에 한다.
@MainActor
enum SettlementStore {
    static func row(for day: DayKey, in context: ModelContext) throws -> DaySettlement {
        let key = day.rawValue
        let existing = try context.fetch(
            FetchDescriptor<DaySettlement>(predicate: #Predicate { $0.day == key })
        )
        if let first = existing.first {
            return first
        }
        let created = DaySettlement(day: day)
        context.insert(created)
        return created
    }

    static func records(in context: ModelContext) throws -> [SettlementRecord] {
        try context.fetch(FetchDescriptor<DaySettlement>()).compactMap { row in
            guard let day = row.dayKey else { return nil }
            return SettlementRecord(day: day, isClosed: row.isClosed, isFinalized: row.finalizedAt != nil)
        }
    }

    /// 오늘 마감. 연출용 값만 남기고 적립은 하루 경계가 지난 뒤 `finalize`에서 한다.
    static func close(_ row: DaySettlement, totals: DayTotals, now: Date) {
        row.closedAt = now
        row.sugarLeftAtCloseG = totals.leftSugarG
        row.caffeineLeftAtCloseMg = totals.leftCaffeineMg
    }

    /// 하루가 끝난 날을 최종 값으로 확정하고 적립한다. 이미 확정된 행은 건드리지 않는다.
    static func finalize(
        _ row: DaySettlement,
        entries: [Entry],
        limits: DailyLimits,
        boundaryHour: Int,
        now: Date,
        in context: ModelContext
    ) throws -> [FeedResult] {
        guard row.finalizedAt == nil, let day = row.dayKey else { return [] }
        let consumptions = entries
            .filter { $0.dayKey(boundaryHour: boundaryHour) == day }
            .map(\.consumption)
        let totals = DayMath.totals(consumptions, limits: limits)

        row.finalSugarLeftG = totals.leftSugarG
        row.finalCaffeineLeftMg = totals.leftCaffeineMg
        row.finalizedAt = now

        return try CupSide.allCases.map { side in
            try credit(side, left: side.remaining(totals), limit: side.limit(limits), in: context)
        }
    }

    /// 어제 미마감 → 먹이기. 하루가 이미 끝났으니 마감과 확정을 한 번에 한다.
    static func feedPastDay(
        _ day: DayKey,
        entries: [Entry],
        limits: DailyLimits,
        boundaryHour: Int,
        now: Date,
        in context: ModelContext
    ) throws -> [FeedResult] {
        let row = try row(for: day, in: context)
        let consumptions = entries
            .filter { $0.dayKey(boundaryHour: boundaryHour) == day }
            .map(\.consumption)
        close(row, totals: DayMath.totals(consumptions, limits: limits), now: now)
        return try finalize(
            row, entries: entries, limits: limits, boundaryHour: boundaryHour, now: now, in: context
        )
    }

    /// "마셨어요" — 적립 없이 닫고 다시 묻지 않는다(§4.7).
    static func dismissPastDay(_ day: DayKey, now: Date, in context: ModelContext) throws {
        let row = try row(for: day, in: context)
        row.finalizedAt = now
    }

    private static func credit(
        _ side: CupSide, left: Double, limit: Double, in context: ModelContext
    ) throws -> FeedResult {
        let affinity = try affinity(for: side, in: context)
        let before = affinity.level
        affinity.points += AffinityMath.points(left: left, limit: limit)
        return FeedResult(side: side, left: left, levelBefore: before, levelAfter: affinity.level)
    }

    static func affinity(for side: CupSide, in context: ModelContext) throws -> Affinity {
        let id = side.characterID
        let existing = try context.fetch(
            FetchDescriptor<Affinity>(predicate: #Predicate { $0.character == id })
        )
        if let first = existing.first {
            return first
        }
        let created = Affinity(character: id)
        context.insert(created)
        return created
    }
}
