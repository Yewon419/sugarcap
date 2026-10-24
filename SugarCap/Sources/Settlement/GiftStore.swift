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

    /// `closed`를 마감한 직후. 기준 지킨 주면 선물을 넣는다. 내용은 이때 정한다(대표님 2026-10-11).
    /// 물건이면 그 주인이, 아니면 `sides` 중 무작위가 가져온다. 넣었으면 참.
    static func grantWeekKept(
        closed: DayKey, sides: [CupSide], isPro: Bool, now: Date, in context: ModelContext,
        roll: Double = Double.random(in: 0 ..< 1)
    ) throws -> Bool {
        let days = try context.fetch(FetchDescriptor<DaySettlement>()).compactMap { row -> GiftMath.ClosedDay? in
            guard row.isClosed, let day = row.dayKey else { return nil }
            return GiftMath.ClosedDay(day: day, sugarOver: row.sugarOverAtCloseG, caffeineOver: row.caffeineOverAtCloseMg)
        }
        guard GiftMath.grantsWeekKept(closed: closed, days: days, sides: sides, gifts: try records(in: context)),
              let fallback = sides.randomElement()
        else { return false }
        let picked = Self.content(owners: sides, isPro: isPro, taken: try takenItems(in: context), roll: roll)
        context.insert(GiftEvent(
            kind: .weekKept, side: picked.owner ?? fallback, payload: picked.payload,
            week: GiftMath.weekStart(of: closed), createdAt: now
        ))
        return true
    }

    /// 마감(오늘 마감·어젯밤 먹이기)을 저장한 직후. 튜토리얼 상자 차례면 병뚜껑 1개 상자를 넣는다(§4.10).
    /// 첫 상품 주인(로슈)이 가져오고, 당 면을 껐으면 카인이 가져온다. 넣었으면 참.
    static func grantStarterCap(sides: [CupSide], now: Date, in context: ModelContext) throws -> Bool {
        let closedDays = try context.fetch(FetchDescriptor<DaySettlement>()).filter(\.isClosed).count
        guard GiftMath.grantsStarterCap(closedDays: closedDays, gifts: try records(in: context)) else { return false }
        let carrier: CupSide = sides.contains(.sugar) ? .sugar : .caffeine
        context.insert(GiftEvent(kind: .starterCap, side: carrier, payload: GiftContent.cap, createdAt: now))
        return true
    }

    /// 적립으로 단계가 오른 캐릭터마다 단계 상승 이벤트를 넣는다(§4.9 결정 4). 상자가 아니라 오늘 화면의 무대 연출로 보이고,
    /// 다 보면 연 것으로 저장한다. 넣은 개수.
    static func queueLevelUps(credited: [FeedResult], now: Date, in context: ModelContext) -> Int {
        let raised = credited.filter(\.leveledUp)
        for result in raised {
            context.insert(GiftEvent(kind: .levelUp, side: result.side, level: result.levelAfter, createdAt: now))
        }
        return raised.count
    }

    /// 감소 목표를 끝까지 해냈을 때. 그 면 캐릭터가 가져오고, 물건은 그 캐릭터 것만 나온다. 내용은 이때 정한다.
    static func grantGoalReached(
        side: CupSide, isPro: Bool, now: Date, in context: ModelContext, roll: Double = Double.random(in: 0 ..< 1)
    ) throws {
        let picked = Self.content(owners: [side], isPro: isPro, taken: try takenItems(in: context), roll: roll)
        context.insert(GiftEvent(kind: .goalReached, side: side, payload: picked.payload, createdAt: now))
    }

    /// Pro를 처음 산 뒤 한 번. 기록하는 면 주인의 고정 물건 중 하나를 그 주인이 들고 온다.
    /// 고를 물건이 없으면(카페인만 기록, 카인 것 아직 없음) 넣지 않고 다음에 다시 본다. 넣었으면 참.
    static func grantProWelcome(sides: [CupSide], now: Date, in context: ModelContext) throws -> Bool {
        guard try !all(in: context).contains(where: { $0.giftKind == .proWelcome }),
              let pick = GiftContent.welcome.filter({ sides.contains($0.owner) }).randomElement()
        else { return false }
        context.insert(GiftEvent(kind: .proWelcome, side: pick.owner, payload: GiftContent.item(pick.id), createdAt: now))
        return true
    }

    /// 상자 내용(`GiftContent`)과, 물건이면 그 주인. 물건은 `owners`의 것 중 아직 안 나온 것 하나.
    static func content(owners: [CupSide], isPro: Bool, taken: Set<String>, roll: Double) -> (payload: String, owner: CupSide?) {
        let left = GiftContent.items.filter { owners.contains($0.owner) && !taken.contains($0.id) }
        switch GiftMath.outcome(roll: roll, isPro: isPro, itemsLeft: !left.isEmpty) {
        case .heart: return (GiftContent.heart, nil)
        case .cap: return (GiftContent.cap, nil)
        case .item:
            guard let item = left.randomElement() else { return (GiftContent.cap, nil) }
            return (GiftContent.item(item.id), item.owner)
        }
    }

    /// 이미 상자에 든 물건 id(열었든 안 열었든). 같은 물건이 두 번 나오지 않게.
    static func takenItems(in context: ModelContext) throws -> Set<String> {
        GiftContent.takenItems(in: try all(in: context))
    }

    /// 내용 없이 만들어진 옛 상자(2026-10-11 전)를 눌렀을 때 내용을 정한다(주·목표 선물만, 이미 정했으면 그대로).
    /// 이미 들고 온 캐릭터는 못 바꾸니 물건은 그 캐릭터 것만.
    static func reveal(_ gift: GiftEvent, isPro: Bool, takenItems: Set<String>, roll: Double) {
        guard gift.payload == nil, let side = gift.cupSide else { return }
        switch gift.giftKind {
        case .weekKept, .goalReached:
            gift.payload = content(owners: [side], isPro: isPro, taken: takenItems, roll: roll).payload
        case .trendsUnlock, .levelUp, .proWelcome, .starterCap, nil: break
        }
    }

    /// 연 것으로 저장한다. 내용을 안 정한 채 열린 주·목표 선물은 마음.
    static func open(_ gift: GiftEvent, now: Date) {
        gift.openedAt = now
        switch gift.giftKind {
        case .weekKept, .goalReached: if gift.payload == nil { gift.payload = GiftContent.heart }
        case .trendsUnlock, .levelUp, .proWelcome, .starterCap, nil: break
        }
    }
}
