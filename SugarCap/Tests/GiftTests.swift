import Foundation
import SwiftData
import XCTest

@testable import SugarCap

/// 선물(SPEC §4.9) 판정과 저장. Phase 1 = 첫 보상(추이 열림).
final class GiftTests: XCTestCase {
    // MARK: 순수 판정

    func testFirstRewardComesOnceAfterFirstCredit() {
        XCTAssertFalse(GiftMath.grantsFirstReward(credited: false, gifts: []), "적립 전에는 안 온다")
        XCTAssertTrue(GiftMath.grantsFirstReward(credited: true, gifts: []))
        let given = [GiftMath.Record(kind: .trendsUnlock, isOpened: false)]
        XCTAssertFalse(GiftMath.grantsFirstReward(credited: true, gifts: given), "한 번 준 뒤엔 안 준다(안 열었어도)")
    }

    func testTrendsUnlockOnlyAfterOpeningTheFirstReward() {
        XCTAssertFalse(GiftMath.isTrendsUnlocked(gifts: []))
        XCTAssertFalse(GiftMath.isTrendsUnlocked(gifts: [.init(kind: .trendsUnlock, isOpened: false)]), "들고 서 있는 동안은 잠김")
        XCTAssertTrue(GiftMath.isTrendsUnlocked(gifts: [.init(kind: .trendsUnlock, isOpened: true)]))
        XCTAssertFalse(GiftMath.isTrendsUnlocked(gifts: [.init(kind: .levelUp, isOpened: true)]), "다른 선물은 추이를 안 연다")
    }

    func testExistingDevicesAreNotLockedOut() {
        let credited = SettlementRecord(day: DayKey(year: 2026, month: 10, day: 1), isClosed: true, isFinalized: true)
        let dismissed = SettlementRecord(day: DayKey(year: 2026, month: 10, day: 2), isClosed: false, isFinalized: true)
        let open = SettlementRecord(day: DayKey(year: 2026, month: 10, day: 3), isClosed: false, isFinalized: false)
        XCTAssertTrue(GiftMath.adoptsExistingProgress(records: [credited], gifts: []))
        XCTAssertFalse(GiftMath.adoptsExistingProgress(records: [dismissed, open], gifts: []), "'마셨어요'·오늘 행만 있으면 새 기기")
        XCTAssertFalse(GiftMath.adoptsExistingProgress(records: [credited], gifts: [.init(kind: .trendsUnlock, isOpened: false)]), "이미 선물이 있으면 소급 안 함")
    }

    // MARK: 저장

    @MainActor
    func testGrantThenOpenUnlocksTrendsAndNeverRepeats() throws {
        let container = try ModelContainer(
            for: GiftEvent.self, DaySettlement.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let now = Date()
        let credited = [FeedResult(side: .sugar, left: 50, levelBefore: 1, levelAfter: 1)]

        XCTAssertTrue(try GiftStore.grantFirstReward(credited: credited, now: now, in: context))
        XCTAssertFalse(try GiftStore.grantFirstReward(credited: credited, now: now, in: context), "두 번째 적립엔 안 준다")
        XCTAssertFalse(GiftMath.isTrendsUnlocked(gifts: try GiftStore.records(in: context)))

        let pending = try GiftStore.pending(in: context)
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.giftKind, .trendsUnlock)
        XCTAssertEqual(pending.first?.cupSide, .sugar, "첫 보상은 로슈가 가져온다")

        GiftStore.open(try XCTUnwrap(pending.first), now: now)
        XCTAssertTrue(try GiftStore.pending(in: context).isEmpty)
        XCTAssertTrue(GiftMath.isTrendsUnlocked(gifts: try GiftStore.records(in: context)))
    }

    @MainActor
    func testAdoptingExistingProgressInsertsAnOpenedReward() throws {
        let container = try ModelContainer(
            for: GiftEvent.self, DaySettlement.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let records = [SettlementRecord(day: DayKey(year: 2026, month: 10, day: 1), isClosed: true, isFinalized: true)]

        XCTAssertTrue(try GiftStore.adoptExistingProgress(records: records, now: Date(), in: context))
        XCTAssertTrue(try GiftStore.pending(in: context).isEmpty, "소급분은 열린 채로 들어간다(들고 오지 않는다)")
        XCTAssertTrue(GiftMath.isTrendsUnlocked(gifts: try GiftStore.records(in: context)))
        XCTAssertFalse(try GiftStore.adoptExistingProgress(records: records, now: Date(), in: context), "한 번만")
        XCTAssertFalse(
            try GiftStore.grantFirstReward(credited: [FeedResult(side: .sugar, left: 0, levelBefore: 1, levelAfter: 1)], now: Date(), in: context),
            "소급한 기기엔 첫 보상을 다시 안 준다"
        )
    }
}
