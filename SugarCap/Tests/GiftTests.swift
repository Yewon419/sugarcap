import Foundation
import SwiftData
import XCTest

@testable import SugarCap

/// 선물(SPEC §4.9) 판정과 저장. 첫 보상(추이 열림)·기준 지킨 주·마음 결제 유도.
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

    // MARK: 상자 내용(2026-10-11)

    func testBoxOutcomeOdds() {
        XCTAssertEqual(GiftMath.outcome(roll: 0.84, isPro: false, itemsLeft: true), .heart)
        XCTAssertEqual(GiftMath.outcome(roll: 0.85, isPro: false, itemsLeft: true), .cap, "무료 15%는 병뚜껑, 물건 없음")
        XCTAssertEqual(GiftMath.outcome(roll: 0.39, isPro: true, itemsLeft: true), .heart)
        XCTAssertEqual(GiftMath.outcome(roll: 0.45, isPro: true, itemsLeft: true), .item)
        XCTAssertEqual(GiftMath.outcome(roll: 0.45, isPro: true, itemsLeft: false), .cap, "물건을 다 모으면 병뚜껑")
        XCTAssertEqual(GiftMath.outcome(roll: 0.5, isPro: true, itemsLeft: true), .cap)
        let rolls = (0 ..< 1000).map { Double($0) / 1000 }
        XCTAssertEqual(rolls.filter { GiftMath.outcome(roll: $0, isPro: false, itemsLeft: true) == .heart }.count, 850)
        XCTAssertEqual(rolls.filter { GiftMath.outcome(roll: $0, isPro: true, itemsLeft: true) == .heart }.count, 400)
        XCTAssertEqual(rolls.filter { GiftMath.outcome(roll: $0, isPro: true, itemsLeft: true) == .item }.count, 100)
    }

    @MainActor
    func testRevealDecidesContentOnceForBoxesOnly() throws {
        let gift = GiftEvent(kind: .weekKept, side: .caffeine, createdAt: Date())
        GiftStore.reveal(gift, isPro: false, takenItems: [], roll: 0.9)
        XCTAssertTrue(gift.isCap)
        GiftStore.reveal(gift, isPro: false, takenItems: [], roll: 0.1)
        XCTAssertTrue(gift.isCap, "한 번 정한 내용은 바뀌지 않는다")
        GiftStore.open(gift, now: Date())
        XCTAssertTrue(gift.isCap, "열어도 그대로")

        let item = GiftEvent(kind: .goalReached, side: .sugar, createdAt: Date())
        GiftStore.reveal(item, isPro: true, takenItems: [], roll: 0.45)
        XCTAssertTrue(Self.roshuItems.contains(item.payload ?? ""), "로슈가 들고 온 옛 상자는 로슈 물건")
        let kainBox = GiftEvent(kind: .goalReached, side: .caffeine, createdAt: Date())
        GiftStore.reveal(kainBox, isPro: true, takenItems: [], roll: 0.45)
        XCTAssertEqual(kainBox.payload, GiftContent.item("coffee-bean"), "카인이 들고 온 상자엔 카인 물건만 든다")
        let kainLast = GiftEvent(kind: .goalReached, side: .caffeine, createdAt: Date())
        GiftStore.reveal(kainLast, isPro: true, takenItems: ["coffee-bean"], roll: 0.45)
        XCTAssertTrue(kainLast.isCap, "카인 물건을 다 모으면 로슈 물건 대신 병뚜껑")

        let stage = GiftEvent(kind: .levelUp, side: .sugar, level: 4, createdAt: Date())
        GiftStore.reveal(stage, isPro: true, takenItems: [], roll: 0.1)
        XCTAssertNil(stage.payload, "단계 상승은 상자가 아니다")
    }

    func testJosaFollowsTheLastSyllable() {
        XCTAssertEqual(Josa.withGwa("토토"), "토토와")
        XCTAssertEqual(Josa.withGwa("몽실"), "몽실과")
        XCTAssertEqual(Josa.withIga("몽실"), "몽실이")
        XCTAssertEqual(Josa.withIga("코코"), "코코가")
        XCTAssertEqual(Josa.withIga("ㅋ"), "ㅋ이")
        XCTAssertEqual(Josa.withGwa("R2"), "R2와")
        XCTAssertEqual(Josa.withGwa("No7"), "No7과")
        XCTAssertEqual(Josa.withGwa("Coco"), "Coco와")
    }

    func testNicknameTrimsLimitsAndClears() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "NicknameTests"))
        defaults.removePersistentDomain(forName: "NicknameTests")
        XCTAssertNil(Nickname.stored("roshu", in: defaults))
        Nickname.save("  몽실몽실몽실몽실몽실 ", for: "roshu", in: defaults)
        XCTAssertEqual(Nickname.stored("roshu", in: defaults), "몽실몽실몽실몽실", "앞뒤 빈칸을 자르고 8자까지")
        Nickname.save("   ", for: "roshu", in: defaults)
        XCTAssertNil(Nickname.stored("roshu", in: defaults), "비우면 원래 이름")
    }

    // MARK: 기준 지킨 주

    private let gregorian = Calendar(identifier: .gregorian)

    /// 2026-10-05(월) ~ 10-11(일). `over`로 날마다 넘긴 양을 바꾼다.
    private func week(sugarOver: [Double?] = Array(repeating: 0, count: 7), caffeineOver: Double? = 0) -> [GiftMath.ClosedDay] {
        sugarOver.enumerated().map { offset, over in
            GiftMath.ClosedDay(day: DayKey(year: 2026, month: 10, day: 5 + offset), sugarOver: over, caffeineOver: caffeineOver)
        }
    }

    func testWeekKeptOnlyOnSundayWithAllSevenDaysWithinLimits() {
        let sunday = DayKey(year: 2026, month: 10, day: 11)
        let saturday = DayKey(year: 2026, month: 10, day: 10)
        XCTAssertEqual(GiftMath.weekStart(of: sunday, calendar: gregorian), DayKey(year: 2026, month: 10, day: 5))
        XCTAssertEqual(GiftMath.weekStart(of: DayKey(year: 2026, month: 10, day: 5), calendar: gregorian), DayKey(year: 2026, month: 10, day: 5))
        XCTAssertTrue(GiftMath.grantsWeekKept(closed: sunday, days: week(), sides: [.sugar, .caffeine], gifts: [], calendar: gregorian))
        XCTAssertFalse(GiftMath.grantsWeekKept(closed: saturday, days: week(), sides: [.sugar, .caffeine], gifts: [], calendar: gregorian), "일요일 마감에만 준다")
        XCTAssertFalse(
            GiftMath.grantsWeekKept(closed: sunday, days: Array(week().dropFirst()), sides: [.sugar, .caffeine], gifts: [], calendar: gregorian),
            "월요일을 마감 안 했거나 주 중간에 시작한 주는 해당 없음"
        )
        var oneOver: [Double?] = Array(repeating: 0, count: 7)
        oneOver[3] = 2
        XCTAssertFalse(GiftMath.grantsWeekKept(closed: sunday, days: week(sugarOver: oneOver), sides: [.sugar, .caffeine], gifts: [], calendar: gregorian), "하루라도 넘기면 안 된다")
        var unknown: [Double?] = Array(repeating: 0, count: 7)
        unknown[0] = nil
        XCTAssertFalse(GiftMath.grantsWeekKept(closed: sunday, days: week(sugarOver: unknown), sides: [.sugar], gifts: [], calendar: gregorian), "마감 값이 없는 날(필드 전 마감)은 못 지킨 걸로")
    }

    func testWeekKeptJudgesOnlyTrackedSidesAndOncePerWeek() {
        let sunday = DayKey(year: 2026, month: 10, day: 11)
        let caffeineOver = week(caffeineOver: 30)
        XCTAssertFalse(GiftMath.grantsWeekKept(closed: sunday, days: caffeineOver, sides: [.sugar, .caffeine], gifts: [], calendar: gregorian), "둘 다 지켜야 한다")
        XCTAssertTrue(GiftMath.grantsWeekKept(closed: sunday, days: caffeineOver, sides: [.sugar], gifts: [], calendar: gregorian), "카페인을 끈 사용자는 당만 본다")
        let given = [GiftMath.Record(kind: .weekKept, isOpened: true, week: DayKey(year: 2026, month: 10, day: 5))]
        XCTAssertFalse(GiftMath.grantsWeekKept(closed: sunday, days: week(), sides: [.sugar], gifts: given, calendar: gregorian), "같은 주에 두 번 안 준다")
        XCTAssertFalse(GiftMath.grantsWeekKept(closed: sunday, days: week(), sides: [], gifts: [], calendar: gregorian))
    }

    func testProOfferStartsFromTheSecondHeartForFreeUsers() {
        XCTAssertFalse(GiftMath.offersPro(heartsBefore: 0, isPro: false), "첫 마음은 그냥 웃고 넘어간다")
        XCTAssertTrue(GiftMath.offersPro(heartsBefore: 1, isPro: false))
        XCTAssertFalse(GiftMath.offersPro(heartsBefore: 3, isPro: true), "Pro에겐 결제 유도 없음")
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
    func testClosingAKeptSundayGrantsOneHeartGift() throws {
        let container = try ModelContainer(
            for: GiftEvent.self, DaySettlement.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let now = Date()
        let kept = DayTotals(sugarG: 10, caffeineMg: 100, leftSugarG: 40, leftCaffeineMg: 300, overSugarG: 0, overCaffeineMg: 0)
        for offset in 0 ..< 7 {
            let row = try SettlementStore.row(for: DayKey(year: 2026, month: 10, day: 5 + offset), in: context)
            SettlementStore.close(row, totals: kept, now: now)
        }
        let sunday = DayKey(year: 2026, month: 10, day: 11)

        let both: [CupSide] = [.sugar, .caffeine]
        XCTAssertTrue(try GiftStore.grantWeekKept(closed: sunday, sides: both, isPro: false, now: now, in: context, roll: 0.1))
        XCTAssertFalse(
            try GiftStore.grantWeekKept(closed: sunday, sides: both, isPro: false, now: now, in: context, roll: 0.1), "한 주에 한 번"
        )
        let gift = try XCTUnwrap(try GiftStore.pending(in: context).first)
        XCTAssertEqual(gift.giftKind, .weekKept)
        XCTAssertTrue(gift.isHeart, "내용은 상자가 생길 때 정해진다")
        GiftStore.open(gift, now: now)
        XCTAssertTrue(gift.isHeart, "열어도 그대로")
    }

    /// Pro 축하 선물: 기록하는 면 주인의 고정 물건을 한 번만. 고를 게 없으면 넣지 않고 나중에 다시 본다(대표님 2026-10-12).
    @MainActor
    func testProWelcomeGivesTheOwnersFixedItemOnce() throws {
        let container = try ModelContainer(for: GiftEvent.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let now = Date()

        XCTAssertTrue(try GiftStore.grantProWelcome(sides: [.sugar], now: now, in: context))
        XCTAssertFalse(try GiftStore.grantProWelcome(sides: [.sugar, .caffeine], now: now, in: context), "한 번만")
        let gift = try XCTUnwrap(try GiftStore.pending(in: context).first)
        XCTAssertEqual(gift.giftKind, .proWelcome)
        XCTAssertEqual(gift.payload, GiftContent.item("strawberry"))
        XCTAssertEqual(gift.cupSide, .sugar, "딸기는 로슈가 들고 온다")
        XCTAssertEqual(GiftStore.content(owners: [.sugar], isPro: true, taken: try GiftStore.takenItems(in: context), roll: 0.45).payload,
                       GiftContent.item("sugar-cube"), "축하 선물로 받은 딸기는 상자에서 다시 안 나온다")

        // 당을 끄고 카페인만 기록하면 카인이 커피콩을 들고 온다(대표님 2026-10-27).
        let caffeineContainer = try ModelContainer(for: GiftEvent.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let caffeineOnly = caffeineContainer.mainContext
        XCTAssertTrue(try GiftStore.grantProWelcome(sides: [.caffeine], now: now, in: caffeineOnly))
        let bean = try XCTUnwrap(try GiftStore.pending(in: caffeineOnly).first)
        XCTAssertEqual(bean.payload, GiftContent.item("coffee-bean"))
        XCTAssertEqual(bean.cupSide, .caffeine, "커피콩은 카인이 들고 온다")
    }

    private static let roshuItems: Set<String> = [GiftContent.item("strawberry"), GiftContent.item("sugar-cube")]

    /// 물건이 나오면 그 주인이 들고 온다. 기록하지 않는 면의 물건, 이미 상자에 든 물건은 안 나온다(대표님 2026-10-11).
    @MainActor
    func testItemBoxIsCarriedByItsOwner() throws {
        let container = try ModelContainer(for: GiftEvent.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let now = Date()

        let berry = GiftStore.content(owners: [.sugar], isPro: true, taken: [], roll: 0.45)
        XCTAssertTrue(Self.roshuItems.contains(berry.payload))
        XCTAssertEqual(berry.owner, .sugar, "딸기·각설탕은 로슈가 들고 온다")
        let bean = GiftStore.content(owners: [.caffeine], isPro: true, taken: [], roll: 0.45)
        XCTAssertEqual(bean.payload, GiftContent.item("coffee-bean"), "카페인만 기록하면 딸기는 안 나온다")
        XCTAssertEqual(bean.owner, .caffeine)

        try GiftStore.grantGoalReached(side: .caffeine, isPro: true, now: now, in: context, roll: 0.45)
        XCTAssertEqual(try XCTUnwrap(try GiftStore.pending(in: context).last).payload, GiftContent.item("coffee-bean"),
                       "카페인 목표 상자엔 카인 물건만 든다")
        try GiftStore.grantGoalReached(side: .sugar, isPro: true, now: now.addingTimeInterval(1), in: context, roll: 0.45)
        let first = try XCTUnwrap(try GiftStore.pending(in: context).last)
        XCTAssertTrue(Self.roshuItems.contains(first.payload ?? ""))
        XCTAssertEqual(first.cupSide, .sugar)
        try GiftStore.grantGoalReached(side: .sugar, isPro: true, now: now.addingTimeInterval(2), in: context, roll: 0.45)
        let second = try XCTUnwrap(try GiftStore.pending(in: context).last)
        XCTAssertEqual(Set([first.payload, second.payload].compactMap { $0 }), Self.roshuItems, "로슈 물건 둘이 한 번씩")
        try GiftStore.grantGoalReached(side: .sugar, isPro: true, now: now.addingTimeInterval(3), in: context, roll: 0.45)
        XCTAssertTrue(try XCTUnwrap(try GiftStore.pending(in: context).last).isCap, "안 연 상자에 든 물건은 다시 안 나온다")
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

    /// 단계가 오른 캐릭터마다 단계 상승 무대 하나(상자 아님, SPEC §4.9 결정 4). 열어도 마음이 들지 않는다.
    @MainActor
    func testLevelUpsAreQueuedOnlyForRaisedSides() throws {
        let container = try ModelContainer(
            for: GiftEvent.self, DaySettlement.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let credited = [
            FeedResult(side: .sugar, left: 50, levelBefore: 2, levelAfter: 3),
            FeedResult(side: .caffeine, left: 400, levelBefore: 2, levelAfter: 2),
        ]

        XCTAssertEqual(GiftStore.queueLevelUps(credited: credited, now: Date(), in: context), 1)
        let pending = try GiftStore.pending(in: context)
        XCTAssertEqual(pending.map(\.giftKind), [.levelUp])
        XCTAssertEqual(pending.first?.cupSide, .sugar)
        XCTAssertEqual(pending.first?.level, 3)

        let stage = try XCTUnwrap(pending.first)
        GiftStore.open(stage, now: Date())
        XCTAssertTrue(stage.isOpened)
        XCTAssertFalse(stage.isHeart, "단계 상승은 마음을 세지 않는다")
        XCTAssertFalse(GiftMath.isTrendsUnlocked(gifts: try GiftStore.records(in: context)))
    }
}
