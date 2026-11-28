import Foundation
import SwiftData
import XCTest

@testable import SugarCap

/// 2주 스탬프판(대표님 2026-11-05). 배치는 seed로 고정, 마감마다 한 칸, 14칸은 안 가진 잔 세트 또는 병뚜껑 3개.
/// 다 차면 다음 판이 이어진다(2026-11-27).
final class StampTests: XCTestCase {
    func testLayoutHasOneOrTwoCapsAndIsStablePerSeed() {
        for board in 1 ... 3 {
            var counts = Set<Int>()
            for seed in UInt64(0) ..< 200 {
                let layout = StampMath.layout(seed: seed, board: board)
                XCTAssertEqual(layout.count, 13)
                let caps = layout.filter { $0 == .cap }.count
                XCTAssertTrue((1 ... 2).contains(caps), "판 \(board) seed \(seed): 병뚜껑 \(caps)개")
                XCTAssertEqual(layout, StampMath.layout(seed: seed, board: board), "같은 seed·판은 같은 배치")
                counts.insert(caps)
            }
            XCTAssertEqual(counts, [1, 2], "판 \(board): 1개·2개가 둘 다 나와야 한다")
        }
        for seed in UInt64(0) ..< 200 {
            XCTAssertEqual(StampMath.layout(seed: seed, board: 1)[StampMath.earlyBirdCell - 1], .heart, "seed \(seed): 첫 판 7칸은 늘 마음")
        }
    }

    /// 첫 판 배치는 판 반복 전 공식 그대로여야 한다. 바뀌면 이미 찍은 칸의 내용이 달라진다.
    func testFirstBoardLayoutIsUnchanged() {
        func legacy(seed: UInt64) -> [StampMath.Prize] {
            var generator = SeededGenerator(state: seed)
            let caps = generator.next() % 2 == 0 ? 1 : 2
            var prizes = (0 ..< StampMath.cells - 2).map { $0 < caps ? StampMath.Prize.cap : StampMath.Prize.heart }
            prizes.shuffle(using: &generator)
            prizes.insert(.heart, at: StampMath.earlyBirdCell - 1)
            return prizes
        }
        for seed in UInt64(0) ..< 200 {
            XCTAssertEqual(StampMath.layout(seed: seed, board: 1), legacy(seed: seed), "seed \(seed)")
        }
        XCTAssertEqual(StampMath.layout(seed: UInt64.max, board: 1), legacy(seed: UInt64.max))
    }

    /// 판마다 배치가 다르고, 둘째 판부터는 7칸에도 병뚜껑이 올 수 있다(대표님 2026-11-27 "일반칸").
    func testLaterBoardsShuffleAgainAndCellSevenIsOrdinary() {
        let seeds = UInt64(0) ..< 200
        let differing = seeds.filter { StampMath.layout(seed: $0, board: 1) != StampMath.layout(seed: $0, board: 2) }
        XCTAssertGreaterThan(differing.count, 150, "판 2가 판 1을 따라가면 안 된다")
        let differingLater = seeds.filter { StampMath.layout(seed: $0, board: 2) != StampMath.layout(seed: $0, board: 3) }
        XCTAssertGreaterThan(differingLater.count, 150)
        XCTAssertTrue(
            seeds.contains { StampMath.layout(seed: $0, board: 2)[StampMath.earlyBirdCell - 1] == .cap },
            "둘째 판 7칸도 병뚜껑이 나와야 한다"
        )
    }

    func testCellNumbersContinueAcrossBoards() {
        XCTAssertEqual(StampMath.stamped(cellNumbers: []), 0)
        XCTAssertEqual(StampMath.stamped(cellNumbers: [1, 2, 14, 14, 14]), 14)
        XCTAssertEqual(StampMath.stamped(cellNumbers: [7, 14, 15]), 15)
        for (cell, board, inBoard) in [(1, 1, 1), (14, 1, 14), (15, 2, 1), (21, 2, 7), (28, 2, 14), (29, 3, 1)] {
            XCTAssertEqual(StampMath.board(of: cell), board, "칸 \(cell)")
            XCTAssertEqual(StampMath.cellInBoard(cell), inBoard, "칸 \(cell)")
        }
    }

    @MainActor
    func testEachCloseStampsTheNextCellAndCellFourteenGivesAnUnownedSet() throws {
        let container = try ModelContainer(
            for: GiftEvent.self, TradeOffer.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let seed: UInt64 = 7
        let layout = StampMath.layout(seed: seed, board: 1)

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
    }

    /// 14칸 다음 마감은 둘째 판 1칸(15). 둘째 판도 배치대로 주고, 28칸 룰렛은 첫 판에서 받은 잔을 뺀다.
    @MainActor
    func testSecondBoardStartsAfterFourteenAndSkipsSetsWonOnTheFirst() throws {
        let container = try ModelContainer(
            for: GiftEvent.self, TradeOffer.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let seed: UInt64 = 11
        for _ in 1 ... StampMath.cells {
            _ = try GiftStore.grantStamp(sides: CupSide.allCases, seed: seed, now: .now, in: context) { $0.last }
        }
        let firstWon = GiftContent.wonSets(in: try GiftStore.all(in: context))
        XCTAssertEqual(firstWon.count, 1)

        let layout = StampMath.layout(seed: seed, board: 2)
        for expected in 15 ... 27 {
            XCTAssertEqual(try GiftStore.grantStamp(sides: CupSide.allCases, seed: seed, now: .now, in: context), expected)
        }
        let second = try GiftStore.all(in: context).filter { $0.giftKind == .stamp && ($0.level ?? 0) > StampMath.cells }
        XCTAssertEqual(second.count, 13)
        for gift in second {
            let cell = try XCTUnwrap(gift.level)
            XCTAssertEqual(gift.isCap, layout[StampMath.cellInBoard(cell) - 1] == .cap, "칸 \(cell) 내용이 둘째 판 배치와 다름")
        }

        var offered: [String] = []
        let cell = try GiftStore.grantStamp(sides: CupSide.allCases, seed: seed, now: .now, in: context) { candidates in
            offered = candidates.map(\.id)
            return candidates.first
        }
        XCTAssertEqual(cell, 2 * StampMath.cells)
        XCTAssertTrue(offered.allSatisfy { !firstWon.contains($0) }, "첫 판에서 받은 잔은 둘째 판 룰렛에 없다")
        XCTAssertEqual(offered.count, TradeCatalog.items.count - 1)
        XCTAssertEqual(GiftContent.wonSets(in: try GiftStore.all(in: context)).count, 2)
        XCTAssertEqual(try GiftStore.grantStamp(sides: CupSide.allCases, seed: seed, now: .now, in: context), 29, "셋째 판으로 이어진다")
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

        // 7칸을 찍은 뒤 둘째 판 7칸(21)까지 지나서 판정이 왔다(소급). 잔은 첫 판 7칸에만 붙는다.
        for _ in StampMath.earlyBirdCell ... 21 {
            _ = try GiftStore.grantStamp(sides: [.sugar], seed: 3, now: .now, in: context)
        }
        XCTAssertTrue(try GiftStore.grantEarlyBird(now: .now, in: context))
        XCTAssertFalse(try GiftStore.grantEarlyBird(now: .now, in: context), "두 번 주지 않는다")

        let gifts = try GiftStore.all(in: context)
        let perkIDs = Set(TradeCatalog.perks.map(\.id))
        XCTAssertEqual(GiftContent.wonSets(in: gifts).intersection(perkIDs), ["glass-soda", "glass-beans"], "당만 기록해도 두 잔 다")
        let perkRows = gifts.filter { row in perkIDs.contains { GiftContent.set($0) == row.payload } }
        XCTAssertEqual(perkRows.count, 2)
        XCTAssertTrue(perkRows.allSatisfy { $0.level == StampMath.earlyBirdCell && $0.isOpened })
        XCTAssertEqual(gifts.first { $0.payload == GiftContent.set("glass-beans") }?.cupSide, .caffeine, "원두는 카인이 준다")
        XCTAssertEqual(StampMath.stamped(cellNumbers: gifts.compactMap(\.level)), 21, "찍은 칸 수는 그대로")

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

    /// 룰렛 시간표(대표님 2026-11-21 시안): 당첨 칸에 앉고, 끝에 다음 방울이 반쯤 올라와도 칸이 넘어가지 않는다.
    func testRouletteLandsOnStopWithoutTickingPastIt() {
        let stop = 17
        XCTAssertEqual(RouletteMotion.reel(at: 0, stop: stop), 0)
        XCTAssertEqual(RouletteMotion.reel(at: RouletteMotion.landAt, stop: stop), Double(stop), accuracy: 1e-9)
        XCTAssertEqual(RouletteMotion.cell(at: RouletteMotion.reel(at: RouletteMotion.doubtAt - 0.01, stop: stop)), stop - 1)
        var t = RouletteMotion.doubtAt
        while t <= RouletteMotion.landAt {
            let position = RouletteMotion.reel(at: t, stop: stop)
            XCTAssertLessThan(position, Double(stop) + 0.5, "t \(t): 다음 칸으로 넘어가면 안 된다")
            XCTAssertGreaterThan(position, Double(stop) - 1.5, "t \(t)")
            t += 0.01
        }
        XCTAssertEqual(RouletteMotion.pop(at: 0).scale, 1, accuracy: 1e-9)
        XCTAssertEqual(RouletteMotion.pop(at: RouletteMotion.popGrow + 0.1).scale, 1.6, accuracy: 1e-9)
        XCTAssertEqual(RouletteMotion.pop(at: RouletteMotion.popEnd).scale, 1, accuracy: 1e-9)
    }
}
