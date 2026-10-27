import Foundation
import SwiftData
import XCTest

@testable import SugarCap

/// 거래(SPEC §4.10) 계산과 잔 선택.
final class TradeTests: XCTestCase {
    private typealias Record = TradeMath.Record

    func testBalanceSubtractsOnlyAcceptedPrices() {
        let trades = [
            Record(itemID: "choco-frappe", price: 2, accepted: true),
            Record(itemID: "choco-frappe", price: 2, accepted: false),
            Record(itemID: "choco-frappe", price: 5, accepted: nil),
        ]
        XCTAssertEqual(TradeMath.balance(openedCaps: 6, trades: trades), 4)
        XCTAssertEqual(TradeMath.balance(openedCaps: 1, trades: trades), -1, "음수는 그대로 돌려줘 호출 쪽이 오류로 본다")
    }

    func testPriceIsTwoUntilFirstAcceptance() {
        XCTAssertEqual(TradeMath.price(trades: []), 2)
        XCTAssertEqual(TradeMath.price(trades: [Record(itemID: "choco-frappe", price: 2, accepted: false)]), 2, "거절만 했으면 2")
        XCTAssertEqual(TradeMath.price(trades: [Record(itemID: "choco-frappe", price: 2, accepted: true)]), 5)
    }

    func testOwnedSetsAreAcceptedItems() {
        let trades = [
            Record(itemID: "choco-frappe", price: 2, accepted: false),
            Record(itemID: "x", price: 5, accepted: nil),
        ]
        XCTAssertEqual(TradeMath.ownedSets(trades: trades), [])
        XCTAssertEqual(TradeMath.ownedSets(trades: trades + [Record(itemID: "choco-frappe", price: 2, accepted: true)]), ["choco-frappe"])
    }

    func testNextOfferWindow() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let day = 86_400.0
        XCTAssertEqual(TradeMath.nextOfferAt(decidedAt: now, accepted: false, roll: 0).timeIntervalSince(now), 3 * day)
        XCTAssertEqual(TradeMath.nextOfferAt(decidedAt: now, accepted: false, roll: 1).timeIntervalSince(now), 4 * day)
        XCTAssertEqual(TradeMath.nextOfferAt(decidedAt: now, accepted: true, roll: 0).timeIntervalSince(now), 14 * day)
        XCTAssertEqual(TradeMath.nextOfferAt(decidedAt: now, accepted: true, roll: 1).timeIntervalSince(now), 28 * day)
    }

    /// 산 잔은 주인 면에만 쓴다. 다른 면 키에 넣어도 기본 잔으로 그린다.
    func testCupSetChoiceOnlyOnOwnerSide() {
        let defaults = UserDefaults.standard
        let saved = CupSide.allCases.map { defaults.object(forKey: $0.cupSetKey) }
        defer {
            for (side, value) in zip(CupSide.allCases, saved) {
                defaults.set(value, forKey: side.cupSetKey)
            }
        }
        CupSetChoice.select("choco-frappe", for: .sugar)
        XCTAssertEqual(CupSide.sugar.cupSetID, "choco-frappe")
        XCTAssertEqual(CupSide.sugar.dropAsset, "drop-choco-frappe")
        XCTAssertEqual(CupSide.sugar.idleCast.bottom, CupSetGeometry.chocoFrappe.bottom)

        defaults.set("choco-frappe", forKey: CupSide.caffeine.cupSetKey)
        XCTAssertEqual(CupSide.caffeine.cupSetID, "iced-americano")

        CupSetChoice.select("cafe-latte", for: .caffeine)
        XCTAssertEqual(CupSide.caffeine.cupSetID, "cafe-latte")
        XCTAssertEqual(CupSide.caffeine.dropAsset, "drop-cafe-latte")
        XCTAssertEqual(CupSide.caffeine.idleCast.bottom, CupSetGeometry.icedAmericano.bottom, "아메리카노와 같은 잔")
        XCTAssertEqual(CupSetGeometry.hiddenPoses("cafe-latte"), ["swim", "swim-front"], "불투명한 라떼 속에선 헤엄 안 함")
        XCTAssertEqual(CupSetGeometry.hiddenPoses("iced-americano"), [])

        CupSetChoice.dropUnowned(owned: [])
        XCTAssertEqual(CupSide.caffeine.cupSetID, "iced-americano")
        XCTAssertEqual(CupSide.sugar.cupSetID, "strawberry-latte")
        XCTAssertEqual(CupSide.sugar.dropAsset, "drop-sugar")
        XCTAssertEqual(CupSide.sugar.idleCast.bottom, CupSetGeometry.strawberryLatte.bottom)
    }

    func testOfferRowsLiveInTheSharedSchema() throws {
        let container = try ModelContainer(
            for: SharedStore.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let offer = TradeOffer(itemID: "choco-frappe", side: .sugar, price: 2, offeredAt: .now)
        offer.accepted = true
        context.insert(offer)
        try context.save()
        let rows = try context.fetch(FetchDescriptor<TradeOffer>())
        XCTAssertEqual(rows.map(\.record), [Record(itemID: "choco-frappe", price: 2, accepted: true)])
        XCTAssertEqual(rows.first?.cupSide, .sugar)
    }

    // MARK: 제안(Phase 2)

    private static let start = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 21)) ?? .now
    private static let both: [CupSide] = [.sugar, .caffeine]
    private static let kept = DayTotals(
        sugarG: 10, caffeineMg: 100, leftSugarG: 40, leftCaffeineMg: 300, overSugarG: 0, overCaffeineMg: 0
    )

    private static func at(_ days: Double) -> Date { start.addingTimeInterval(days * 86_400) }
    private static func day(_ date: Date) -> DayKey { DayKey(at: date, boundaryHour: 4) }

    @MainActor
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: SharedStore.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @MainActor
    private func close(days: Range<Int>, sides: [CupSide] = both, in context: ModelContext) throws -> [Bool] {
        try days.map { offset in
            let date = Self.at(Double(offset))
            let row = try SettlementStore.row(for: Self.day(date), in: context)
            SettlementStore.close(row, totals: Self.kept, now: date)
            return try GiftStore.grantStarterCap(sides: sides, now: date, in: context)
        }
    }

    @MainActor
    private func offer(at date: Date, sides: [CupSide] = both, roll: Double = 0, in context: ModelContext) throws -> TradeOffer? {
        try TradeStore.offerIfDue(sides: sides, today: Self.day(date), boundaryHour: 4, now: date, roll: roll, in: context)
    }

    /// 튜토리얼 흐름(§4.10 초반 보상 고정): 2·3번째 마감 뒤 카인이 병뚜껑 상자 → 3번째 상자를 연 다음 날 카인의 카페라떼 →
    /// 거절하면 3~4일 뒤 남은 상품(초코 프라페)이 같은 가격으로 → 수락하면 잔액이 줄고 다음은 2~4주 뒤 5개 → 다 사면 멈춤.
    @MainActor
    func testStarterCapsLeadToTheFirstOfferTheNextDay() throws {
        let context = try makeContext()

        XCTAssertEqual(try close(days: 0 ..< 4, in: context), [false, true, true, false], "2·3번째 마감에만")
        let caps = try GiftStore.pending(in: context).filter { $0.giftKind == .starterCap }
        XCTAssertEqual(caps.count, 2)
        XCTAssertTrue(caps.allSatisfy { $0.isCap && $0.cupSide == .caffeine }, "늘 병뚜껑, 첫 거래 상품 주인 카인이 가져온다")

        XCTAssertNil(try offer(at: Self.at(3), in: context), "상자를 안 열었으면 제안 없음")
        for gift in caps { GiftStore.open(gift, now: Self.at(2)) }
        XCTAssertEqual(try TradeStore.balance(in: context), 2)
        XCTAssertNil(try offer(at: Self.at(2.05), in: context), "잔액이 2가 된 날에는 안 온다")

        let first = try XCTUnwrap(try offer(at: Self.at(3), roll: 0.99, in: context), "다음 날 첫 제안")
        XCTAssertEqual(first.itemID, "cafe-latte", "첫 제안은 무작위가 아니라 카페라떼")
        XCTAssertEqual(first.cupSide, .caffeine)
        XCTAssertEqual(first.price, TradeMath.firstPrice)
        XCTAssertNil(try offer(at: Self.at(3), in: context), "안 정한 제안은 하나만")

        TradeStore.refuse(first, now: Self.at(3), roll: 0.5)
        let retry = try XCTUnwrap(first.nextOfferAt)
        XCTAssertEqual(retry.timeIntervalSince(Self.at(3)) / 86_400, 3.5, accuracy: 0.001, "거절하면 3~4일 뒤")
        XCTAssertNil(try offer(at: Self.at(6), in: context), "거절 뒤 3일 안엔 안 온다")

        let second = try XCTUnwrap(try offer(at: retry, in: context))
        XCTAssertEqual(second.itemID, "choco-frappe", "직전에 거절한 라떼는 빠진다")
        XCTAssertEqual(second.price, TradeMath.firstPrice, "거절만 했으면 여전히 2")

        try TradeStore.accept(second, now: retry, roll: 1, in: context)
        XCTAssertEqual(try TradeStore.balance(in: context), 0, "수락하면 잔액이 준다")
        let after = try XCTUnwrap(second.nextOfferAt)
        XCTAssertEqual(after.timeIntervalSince(retry) / 86_400, 28, accuracy: 0.001, "수락하면 2~4주 뒤")
        XCTAssertEqual(TradeMath.ownedSets(trades: try TradeStore.offers(in: context).map(\.record)), ["choco-frappe"])

        for _ in 0 ..< 5 {
            context.insert(GiftEvent(kind: .weekKept, side: .caffeine, payload: GiftContent.cap, createdAt: after, openedAt: after))
        }
        let third = try XCTUnwrap(try offer(at: after.addingTimeInterval(86_400), in: context))
        XCTAssertEqual(third.itemID, "cafe-latte", "남은 건 라떼뿐")
        XCTAssertEqual(third.price, TradeMath.laterPrice, "첫 거래 뒤로는 5")
        try TradeStore.accept(third, now: after.addingTimeInterval(86_400), roll: 0, in: context)
        XCTAssertEqual(try TradeStore.balance(in: context), 0)

        for _ in 0 ..< 5 {
            context.insert(GiftEvent(kind: .weekKept, side: .sugar, payload: GiftContent.cap, createdAt: after, openedAt: after))
        }
        XCTAssertNil(try offer(at: after.addingTimeInterval(30 * 86_400), in: context), "다 사면 제안이 멈춘다")
    }

    /// 카페인 면을 끈 사용자는 로슈가 병뚜껑을 가져오고 첫 제안도 로슈의 초코 프라페다.
    @MainActor
    func testSugarOnlyGetsRoshuAndFrappe() throws {
        let context = try makeContext()
        XCTAssertEqual(try close(days: 0 ..< 3, sides: [.sugar], in: context), [false, true, true])
        let caps = try GiftStore.pending(in: context)
        XCTAssertTrue(caps.allSatisfy { $0.cupSide == .sugar }, "카페인 면이 꺼졌으면 로슈가 가져온다")
        for gift in caps { GiftStore.open(gift, now: Self.at(2)) }
        let first = try XCTUnwrap(try offer(at: Self.at(3), sides: [.sugar], in: context))
        XCTAssertEqual(first.itemID, "choco-frappe")
        XCTAssertEqual(first.cupSide, .sugar)
    }

    /// 업데이트 전에 이미 여러 번 마감한 기기: 다음 마감부터 하나씩, 두 개까지.
    @MainActor
    func testLongTimeUsersGetOneStarterCapPerCloseUpToTwo() throws {
        let context = try makeContext()
        for offset in 0 ..< 10 {
            let row = try SettlementStore.row(for: Self.day(Self.at(Double(offset))), in: context)
            SettlementStore.close(row, totals: Self.kept, now: Self.at(Double(offset)))
        }
        let granted = try (0 ..< 3).map { _ in try GiftStore.grantStarterCap(sides: Self.both, now: Self.at(10), in: context) }
        XCTAssertEqual(granted, [true, true, false])
    }

    /// 그 면에 안 연 선물이 있으면 선물이 먼저다. 첫 제안은 카인 차례라 로슈 상품으로 바꾸지 않고 기다린다.
    /// 잔액이 모자라면 수락이 거절된다.
    @MainActor
    func testGiftsComeFirstAndShortBalanceCannotAccept() throws {
        let context = try makeContext()
        for _ in 0 ..< 2 {
            context.insert(GiftEvent(kind: .weekKept, side: .sugar, payload: GiftContent.cap, createdAt: Self.at(0), openedAt: Self.at(0)))
        }
        let heart = GiftEvent(kind: .weekKept, side: .caffeine, payload: GiftContent.heart, createdAt: Self.at(1))
        context.insert(heart)
        XCTAssertNil(try offer(at: Self.at(2), in: context), "카인이 안 연 선물을 들고 있으면 로슈가 비어 있어도 제안 없음")
        GiftStore.open(heart, now: Self.at(2))
        let offered = try XCTUnwrap(try offer(at: Self.at(2), in: context), "선물을 열고 나면 온다")
        XCTAssertEqual(offered.itemID, "cafe-latte")
        context.delete(offered)
        try context.save()

        let pending = TradeOffer(itemID: "choco-frappe", side: .sugar, price: 5, offeredAt: Self.at(2))
        context.insert(pending)
        XCTAssertThrowsError(try TradeStore.accept(pending, now: Self.at(2), roll: 0, in: context), "잔액 2로 5개짜리는 못 산다")
        XCTAssertNil(pending.accepted, "실패하면 그대로 둔다")
    }

    /// 살 수 있는 상품 중 무작위. 직전에 거절한 상품은 다른 상품이 있으면 뺀다.
    func testOfferSkipsTheLastRefusedItemWhenThereIsAnother() {
        let catalog = [TradeItem(id: "a", side: .sugar), TradeItem(id: "b", side: .sugar), TradeItem(id: "c", side: .caffeine)]
        let refused = [Record(itemID: "a", price: 2, accepted: false, nextOfferAt: Self.at(0))]
        let today = Self.day(Self.at(1))
        for roll in [0.0, 0.5, 0.99] {
            let item = TradeMath.offerItem(
                trades: refused, balance: 2, sides: [.sugar], capDays: [], today: today, now: Self.at(1), roll: roll,
                catalog: catalog
            )
            XCTAssertEqual(item?.id, "b", "거절한 a·꺼진 면의 c는 빠진다(roll \(roll))")
        }
        XCTAssertNil(
            TradeMath.offerItem(
                trades: refused, balance: -1, sides: [.sugar], capDays: [], today: today, now: Self.at(1), roll: 0,
                catalog: catalog
            ),
            "잔액이 음수면 멈춘다"
        )
    }
}
