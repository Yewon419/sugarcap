import Foundation
import OSLog
import SwiftData

/// 거래 계산(SPEC §4.10). 전부 순수 함수다. 잔액은 저장하지 않고 늘 여기서 계산한다.
enum TradeMath {
    /// 거래 행 하나의 상태. `TradeOffer`에서 뽑아 넘긴다.
    struct Record: Equatable, Sendable {
        let itemID: String
        let price: Int
        let accepted: Bool?
        var nextOfferAt: Date? = nil
    }

    static let firstPrice = 2
    static let laterPrice = 5
    /// 거절 뒤 다음 제안까지(일).
    static let afterRefusalDays: ClosedRange<Double> = 3 ... 4
    /// 수락 뒤 다음 제안까지(일, 대표님 2026-10-24 "2-4주 뒤").
    static let afterAcceptanceDays: ClosedRange<Double> = 14 ... 28

    /// 병뚜껑 잔액 = 열어 본 병뚜껑 선물 수 − 수락한 거래 가격 합. 음수면 기록이 어긋난 것이라 호출 쪽이 제안을 멈춘다.
    static func balance(openedCaps: Int, trades: [Record]) -> Int {
        openedCaps - trades.filter { $0.accepted == true }.reduce(0) { $0 + $1.price }
    }

    /// 다음 제안 가격. 수락한 거래가 하나도 없으면 첫 거래 값(거절만 했어도 그대로).
    static func price(trades: [Record]) -> Int {
        trades.contains { $0.accepted == true } ? laterPrice : firstPrice
    }

    /// 가진 잔 = 수락한 거래의 상품.
    static func ownedSets(trades: [Record]) -> Set<String> {
        Set(trades.filter { $0.accepted == true }.map(\.itemID))
    }

    /// 다음 제안 시각. `roll`은 0..<1 무작위 값이고 그 사이 아무 시각이 된다.
    static func nextOfferAt(decidedAt: Date, accepted: Bool, roll: Double) -> Date {
        let range = accepted ? afterAcceptanceDays : afterRefusalDays
        let days = range.lowerBound + (range.upperBound - range.lowerBound) * min(max(roll, 0), 1)
        return decidedAt.addingTimeInterval(days * 86_400)
    }

    /// 지금 들고 올 상품(§4.10 "제안이 오는 조건"). nil이면 제안하지 않는다.
    /// - `trades`: 제안 순서대로. 아직 안 정한 제안이 있으면 그걸 먼저 끝낸다.
    /// - `balance`: 잔액(음수면 기록이 어긋난 것이라 멈춘다).
    /// - `sides`: 기록하는 면. `busy`: 그중 안 연 상자·단계 상승이 있는 면(선물이 먼저라 그 면 상품은 지금 안 온다).
    /// - `capDays`: 열어 본 병뚜껑 선물의 연 날, 오래된 것부터. 첫 제안은 잔액이 첫 가격에 닿은 다음 날부터 온다.
    /// - `roll`: 0..<1 무작위 값.
    /// 첫 제안은 무작위가 아니라 목록 앞의 상품(튜토리얼, `TradeCatalog.tutorialItem`)이고, 그 면이 바쁘면 기다린다.
    static func offerItem(
        trades: [Record], balance: Int, sides: [CupSide], busy: Set<CupSide> = [], capDays: [DayKey], today: DayKey,
        now: Date, roll: Double, catalog: [TradeItem] = TradeCatalog.items
    ) -> TradeItem? {
        guard !trades.contains(where: { $0.accepted == nil }), balance >= 0 else { return nil }
        let cost = price(trades: trades)
        guard balance >= cost else { return nil }
        if let last = trades.last(where: { $0.accepted != nil }) {
            guard let next = last.nextOfferAt, now >= next else { return nil }
        } else {
            guard capDays.count >= cost, capDays[cost - 1] < today else { return nil }
        }
        if trades.isEmpty {
            guard let first = catalog.first(where: { sides.contains($0.side) }), !busy.contains(first.side) else { return nil }
            return first
        }
        let owned = ownedSets(trades: trades)
        var candidates = catalog.filter { sides.contains($0.side) && !busy.contains($0.side) && !owned.contains($0.id) }
        if let refused = trades.last(where: { $0.accepted == false })?.itemID, candidates.count > 1 {
            candidates.removeAll { $0.id == refused }
        }
        guard !candidates.isEmpty else { return nil }
        let index = min(Int(min(max(roll, 0), 1) * Double(candidates.count)), candidates.count - 1)
        return candidates[index]
    }
}

extension TradeOffer {
    var record: TradeMath.Record {
        TradeMath.Record(itemID: itemID, price: price, accepted: accepted, nextOfferAt: nextOfferAt)
    }
}

/// 병뚜껑 잔액(보관함·설정·추이가 같은 값을 보인다).
enum CapBalance {
    private static let logger = Logger(subsystem: "com.sugarcap.app", category: "trade")

    /// Debug `-screenshotCaps <n>`이면 그 값.
    static func current(gifts: [GiftEvent], trades: [TradeOffer]) -> Int {
        #if DEBUG
        if UserDefaults.standard.object(forKey: "screenshotCaps") != nil {
            return UserDefaults.standard.integer(forKey: "screenshotCaps")
        }
        #endif
        let opened = gifts.filter { $0.isCap && $0.isOpened }.count
        let value = TradeMath.balance(openedCaps: opened, trades: trades.map(\.record))
        if value < 0 {
            logger.error("병뚜껑 잔액이 음수: opened=\(opened) trades=\(trades.count)")
        }
        return max(value, 0)
    }
}

/// 면마다 고른 잔(UserDefaults `cupSet.<면>`). 그리는 쪽은 `CupSide.cupSetID`가 읽는다.
enum CupSetChoice {
    static func select(_ setID: String, for side: CupSide) {
        if setID == side.defaultCupSetID {
            UserDefaults.standard.removeObject(forKey: side.cupSetKey)
        } else {
            UserDefaults.standard.set(setID, forKey: side.cupSetKey)
        }
    }

    /// 가진 잔이 아닌 선택을 지운다(앱 시작 때). 그 면은 기본 잔으로 돌아간다.
    static func dropUnowned(owned: Set<String>) {
        for side in CupSide.allCases {
            guard let chosen = UserDefaults.standard.string(forKey: side.cupSetKey), !owned.contains(chosen) else {
                continue
            }
            UserDefaults.standard.removeObject(forKey: side.cupSetKey)
        }
    }
}

/// 거래 행을 쓴다(§4.10). 저장(`save`)은 호출한 화면이 한다.
@MainActor
enum TradeStore {
    enum Failure: Error, CustomStringConvertible {
        case notEnoughCaps(balance: Int, price: Int, itemID: String)

        var description: String {
            switch self {
            case let .notEnoughCaps(balance, price, itemID):
                return "병뚜껑 부족: item=\(itemID) price=\(price) balance=\(balance)"
            }
        }
    }

    private static let logger = Logger(subsystem: "com.sugarcap.app", category: "trade")

    static func offers(in context: ModelContext) throws -> [TradeOffer] {
        try context.fetch(FetchDescriptor<TradeOffer>(sortBy: [SortDescriptor(\.offeredAt)]))
    }

    /// 실제 잔액(Debug 덮어쓰기 없음, 음수 그대로).
    static func balance(in context: ModelContext) throws -> Int {
        let caps = try GiftStore.all(in: context).filter { $0.isCap && $0.isOpened }.count
        return TradeMath.balance(openedCaps: caps, trades: try offers(in: context).map(\.record))
    }

    /// 지금 제안이 올 때면 제안 행을 넣는다(§4.10). `sides`는 기록하는 면이고, 안 연 선물·단계 상승이 있는 면은 뺀다.
    /// 오늘 화면이 다른 연출 없이 자리 잡았을 때 부른다. 넣은 제안.
    static func offerIfDue(
        sides: [CupSide], today: DayKey, boundaryHour: Int, now: Date, roll: Double, in context: ModelContext
    ) throws -> TradeOffer? {
        let gifts = try GiftStore.all(in: context)
        let busy = Set(gifts.filter { !$0.isOpened }.compactMap(\.cupSide))
        let records = try offers(in: context).map(\.record)
        let capDays = gifts.filter(\.isCap).compactMap(\.openedAt).sorted().map { DayKey(at: $0, boundaryHour: boundaryHour) }
        let balance = TradeMath.balance(openedCaps: capDays.count, trades: records)
        if balance < 0 {
            logger.error("병뚜껑 잔액이 음수라 제안을 멈춤: caps=\(capDays.count) trades=\(records.count)")
        }
        guard let item = TradeMath.offerItem(
            trades: records, balance: balance, sides: sides, busy: busy, capDays: capDays, today: today, now: now,
            roll: roll
        ) else { return nil }
        let offer = TradeOffer(itemID: item.id, side: item.side, price: TradeMath.price(trades: records), offeredAt: now)
        context.insert(offer)
        logger.info("거래 제안: item=\(item.id, privacy: .public) price=\(offer.price) balance=\(balance)")
        return offer
    }

    /// 바꾸기. 잔액이 모자라면 바꾸지 않고 던진다.
    static func accept(_ offer: TradeOffer, now: Date, roll: Double, in context: ModelContext) throws {
        let balance = try balance(in: context)
        guard balance >= offer.price else {
            throw Failure.notEnoughCaps(balance: balance, price: offer.price, itemID: offer.itemID)
        }
        decide(offer, accepted: true, now: now, roll: roll)
        logger.info("거래 수락: item=\(offer.itemID, privacy: .public) price=\(offer.price) balance=\(balance - offer.price)")
    }

    /// 다음에.
    static func refuse(_ offer: TradeOffer, now: Date, roll: Double) {
        decide(offer, accepted: false, now: now, roll: roll)
        logger.info("거래 거절: item=\(offer.itemID, privacy: .public)")
    }

    /// 다음 제안 시각은 이때 한 번 정해 저장한다.
    private static func decide(_ offer: TradeOffer, accepted: Bool, now: Date, roll: Double) {
        offer.accepted = accepted
        offer.decidedAt = now
        offer.nextOfferAt = TradeMath.nextOfferAt(decidedAt: now, accepted: accepted, roll: roll)
    }
}
