import Foundation
import SwiftData
import XCTest

@testable import SugarCap

/// 2주 스탬프판(대표님 2026-11-05). 배치는 seed로 고정, 마감마다 한 칸, 14칸은 안 가진 잔 세트 또는 병뚜껑 3개.
final class StampTests: XCTestCase {
    func testLayoutHasOneOrTwoCapsAndIsStablePerSeed() {
        var counts = Set<Int>()
        for seed in UInt64(0) ..< 200 {
            let layout = StampMath.layout(seed: seed)
            XCTAssertEqual(layout.count, 13)
            let caps = layout.filter { $0 == .cap }.count
            XCTAssertTrue((1 ... 2).contains(caps), "seed \(seed): 병뚜껑 \(caps)개")
            XCTAssertEqual(layout, StampMath.layout(seed: seed), "같은 seed는 같은 배치")
            XCTAssertEqual(layout[StampMath.earlyBirdCell - 1], .heart, "seed \(seed): 얼리버드 칸은 늘 마음")
            counts.insert(caps)
        }
        XCTAssertEqual(counts, [1, 2], "1개·2개가 둘 다 나와야 한다")
    }

    func testNextCellStopsAfterFourteen() {
        XCTAssertEqual(StampMath.nextCell(stamped: 0), 1)
        XCTAssertEqual(StampMath.nextCell(stamped: 13), 14)
        XCTAssertNil(StampMath.nextCell(stamped: 14))
        XCTAssertEqual(StampMath.stamped(cellNumbers: [1, 2, 14, 14, 14]), 14)
    }

    @MainActor
    func testEachCloseStampsTheNextCellAndCellFourteenGivesAnUnownedSet() throws {
        let container = try ModelContainer(
            for: GiftEvent.self, TradeOffer.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let seed: UInt64 = 7
        let layout = StampMath.layout(seed: seed)

        // 카페라떼는 이미 거래로 샀다.
        let bought = TradeOffer(itemID: "cafe-latte", side: .caffeine, price: 2, offeredAt: .now)
        bought.accepted = true
        context.insert(bought)

        for expected in 1 ... 13 {
            XCTAssertEqual(try GiftStore.grantStamp(sides: CupSide.allCases, seed: seed, now: .now, in: context), expected)
        }
        let early = try GiftStore.all(in: context).filter { $0.giftKind == .stamp }
        XCTAssertEqual(early.count, 13)
        XCTAssertTrue(early.allSatisfy(\.isOpened), "스탬프는 상자 없이 연 채로 들어간다")
        for gift in early {
            let cell = try XCTUnwrap(gift.level)
            XCTAssertEqual(gift.isCap, layout[cell - 1] == .cap, "칸 \(cell) 내용이 배치와 다름")
        }

        var offered: [String] = []
        let cell = try GiftStore.grantStamp(sides: CupSide.allCases, seed: seed, now: .now, in: context) { candidates in
            offered = candidates.map(\.id)
            return candidates.last
        }
        XCTAssertEqual(cell, 14)
        XCTAssertFalse(offered.contains("cafe-latte"), "가진 잔은 룰렛에 없다")
        XCTAssertEqual(offered.count, TradeCatalog.items.count - 1)
        let won = GiftContent.wonSets(in: try GiftStore.all(in: context))
        XCTAssertEqual(won, ["grape"])
        XCTAssertNil(try GiftStore.grantStamp(sides: CupSide.allCases, seed: seed, now: .now, in: context), "다 찍으면 더 안 준다")
    }

    @MainActor
    func testCellFourteenGivesThreeCapsWhenEverySetIsOwned() throws {
        let container = try ModelContainer(
            for: GiftEvent.self, TradeOffer.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        for cell in 1 ... 13 {
            context.insert(GiftEvent(kind: .stamp, side: .sugar, level: cell, payload: GiftContent.heart, createdAt: .now, openedAt: .now))
        }
        // 당만 기록: 로슈 잔(초코 프라페·망고·청포도)만 후보인데 다 가졌다.
        for id in ["choco-frappe", "mango", "grape"] {
            let offer = TradeOffer(itemID: id, side: .sugar, price: 5, offeredAt: .now)
            offer.accepted = true
            context.insert(offer)
        }
        XCTAssertEqual(try GiftStore.grantStamp(sides: [.sugar], seed: 1, now: .now, in: context), 14)
        let last = try GiftStore.all(in: context).filter { $0.giftKind == .stamp && $0.level == 14 }
        XCTAssertEqual(last.count, StampMath.finalCaps)
        XCTAssertTrue(last.allSatisfy(\.isCap))
        XCTAssertEqual(try TradeStore.balance(in: context), 3 - 15, "스탬프 병뚜껑도 잔액에 들어간다")
    }

    /// 얼리버드 선물(2026 특전): 7칸을 찍어야 받고, 늦게 판정돼도 소급해 받고, 두 번 받지 않는다. 14칸 룰렛에는 안 나온다.
    @MainActor
    func testEarlyBirdGivesBothGlassSetsOnceFromCellSeven() throws {
        let container = try ModelContainer(
            for: GiftEvent.self, TradeOffer.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        for _ in 1 ..< StampMath.earlyBirdCell {
            _ = try GiftStore.grantStamp(sides: [.sugar], seed: 3, now: .now, in: context)
        }
        XCTAssertFalse(try GiftStore.grantEarlyBird(now: .now, in: context), "6칸까지는 안 준다")

        // 7칸을 찍은 뒤 몇 칸 더 지나서 판정이 왔다(소급).
        for _ in StampMath.earlyBirdCell ... 9 {
            _ = try GiftStore.grantStamp(sides: [.sugar], seed: 3, now: .now, in: context)
        }
        XCTAssertTrue(try GiftStore.grantEarlyBird(now: .now, in: context))
        XCTAssertFalse(try GiftStore.grantEarlyBird(now: .now, in: context), "두 번 주지 않는다")

        let gifts = try GiftStore.all(in: context)
        XCTAssertEqual(GiftContent.wonSets(in: gifts), ["glass-soda", "glass-beans"], "당만 기록해도 두 잔 다")
        let perkRows = gifts.filter { $0.payload?.hasPrefix(GiftContent.setPrefix) == true }
        XCTAssertTrue(perkRows.allSatisfy { $0.level == StampMath.earlyBirdCell && $0.isOpened })
        XCTAssertEqual(gifts.first { $0.payload == GiftContent.set("glass-beans") }?.cupSide, .caffeine, "원두는 카인이 준다")
        XCTAssertEqual(StampMath.stamped(cellNumbers: gifts.compactMap(\.level)), 9, "찍은 칸 수는 그대로")

        let candidates = StampMath.finalCandidates(
            catalog: TradeCatalog.items, sides: CupSide.allCases, owned: GiftContent.wonSets(in: gifts)
        )
        XCTAssertFalse(candidates.contains { $0.id.hasPrefix("glass-") }, "특전 잔은 14칸 룰렛에 없다")
    }

    func testEarlyBirdYearIsKoreanTime() throws {
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        func at(_ text: String) throws -> Date {
            let formatter = ISO8601DateFormatter()
            formatter.timeZone = utc
            return try XCTUnwrap(formatter.date(from: text))
        }
        XCTAssertTrue(EarlyBird.isEarly(firstDownload: try at("2025-12-31T15:30:00Z")), "한국 2026-01-01 00:30")
        XCTAssertFalse(EarlyBird.isEarly(firstDownload: try at("2025-12-31T14:59:00Z")), "한국 2025-12-31 23:59")
        XCTAssertTrue(EarlyBird.isEarly(firstDownload: try at("2026-12-31T14:59:00Z")), "한국 2026-12-31 23:59")
        XCTAssertFalse(EarlyBird.isEarly(firstDownload: try at("2026-12-31T15:00:00Z")), "한국 2027-01-01 00:00")
    }

    func testEarlyBirdUsesTheStoredVerdict() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "EarlyBirdTests"))
        defaults.removePersistentDomain(forName: "EarlyBirdTests")
        defer { defaults.removePersistentDomain(forName: "EarlyBirdTests") }
        XCTAssertNil(EarlyBird.known(defaults))
        defaults.set(false, forKey: EarlyBird.key)
        XCTAssertEqual(EarlyBird.known(defaults), false)
        let resolved = await EarlyBird.resolve(defaults)
        XCTAssertEqual(resolved, false, "저장된 판정이 있으면 영수증을 다시 읽지 않는다")
    }
}
