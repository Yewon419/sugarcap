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

        CupSetChoice.dropUnowned(owned: [])
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
}
