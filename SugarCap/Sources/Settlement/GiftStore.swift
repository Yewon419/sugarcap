import Foundation
import SwiftData

/// 선물 행을 읽고 쓴다(SPEC §4.9). 판정은 `GiftMath`. 저장(`save`)은 호출한 화면이 한 번에 한다.
@MainActor
enum GiftStore {
    static func all(in context: ModelContext) throws -> [GiftEvent] {
        try context.fetch(FetchDescriptor<GiftEvent>(sortBy: [SortDescriptor(\.createdAt)]))
    }

    static func records(in context: ModelContext) throws -> [GiftMath.Record] {
        try all(in: context).compactMap { gift in
            guard let kind = gift.giftKind else { return nil }
            return GiftMath.Record(kind: kind, isOpened: gift.isOpened, week: gift.week.flatMap(DayKey.init(rawValue:)))
        }
    }

    /// 아직 안 연 선물. 오래된 것부터.
    static func pending(in context: ModelContext) throws -> [GiftEvent] {
        try all(in: context).filter { !$0.isOpened }
    }

    /// 선물이 생기기 전부터 쓰던 기기면 열린 첫 보상을 소급해 넣는다(추이가 갑자기 잠기지 않게).
    /// 이번 실행에서 적립하기 전에 부른다. 넣었으면 참.
    static func adoptExistingProgress(records: [SettlementRecord], now: Date, in context: ModelContext) throws -> Bool {
        guard GiftMath.adoptsExistingProgress(records: records, gifts: try self.records(in: context)) else { return false }
        context.insert(GiftEvent(kind: .trendsUnlock, side: .sugar, createdAt: now, openedAt: now))
        return true
    }

    /// 첫 적립 뒤 첫 보상(추이 열림). 로슈가 가져온다. 넣었으면 참.
    static func grantFirstReward(credited: [FeedResult], now: Date, in context: ModelContext) throws -> Bool {
        guard GiftMath.grantsFirstReward(credited: !credited.isEmpty, gifts: try records(in: context)) else { return false }
        context.insert(GiftEvent(kind: .trendsUnlock, side: .sugar, createdAt: now))
        return true
    }

    /// `closed`를 마감한 직후. 기준 지킨 주면 선물을 넣는다. 둘 다 지킨 거라 누가 가져올지는 `sides` 중 무작위. 넣었으면 참.
    static func grantWeekKept(closed: DayKey, sides: [CupSide], now: Date, in context: ModelContext) throws -> Bool {
        let days = try context.fetch(FetchDescriptor<DaySettlement>()).compactMap { row -> GiftMath.ClosedDay? in
            guard row.isClosed, let day = row.dayKey else { return nil }
            return GiftMath.ClosedDay(day: day, sugarOver: row.sugarOverAtCloseG, caffeineOver: row.caffeineOverAtCloseMg)
        }
        guard GiftMath.grantsWeekKept(closed: closed, days: days, sides: sides, gifts: try records(in: context)),
              let side = sides.randomElement()
        else { return false }
        context.insert(GiftEvent(kind: .weekKept, side: side, week: GiftMath.weekStart(of: closed), createdAt: now))
        return true
    }

    /// 연 것으로 저장한다. 주·목표 선물은 이때 내용이 정해진다(지금은 마음뿐).
    static func open(_ gift: GiftEvent, now: Date) {
        gift.openedAt = now
        switch gift.giftKind {
        case .weekKept, .goalReached: gift.payload = GiftContent.heart
        case .trendsUnlock, .levelUp, nil: break
        }
    }
}
