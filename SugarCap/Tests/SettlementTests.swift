import SwiftData
import XCTest

@testable import SugarCap

/// 고정 달력. `.current`를 쓰면 CI 러너(UTC)와 로컬(KST)에서 결과가 갈린다.
private func seoulCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .gmt
    return calendar
}

private func date(
    _ calendar: Calendar, _ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0
) -> Date {
    let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
    guard let date = calendar.date(from: components) else {
        preconditionFailure("테스트 날짜를 만들 수 없음: \(year)-\(month)-\(day) \(hour):\(minute)")
    }
    return date
}

final class AffinityMathTests: XCTestCase {
    func testPointsRangeFromOneToTen() {
        XCTAssertEqual(AffinityMath.points(left: 50, limit: 50), 10)
        XCTAssertEqual(AffinityMath.points(left: 0, limit: 50), 1, "기준을 넘긴 날도 먹이면 1점")
        // 25/50 × 9 = 4.5 → 5 (반올림)
        XCTAssertEqual(AffinityMath.points(left: 25, limit: 50), 6)
        // 20/50 × 9 = 3.6 → 4
        XCTAssertEqual(AffinityMath.points(left: 20, limit: 50), 5)
    }

    func testPointsClampRatio() {
        XCTAssertEqual(AffinityMath.points(left: 80, limit: 50), 10)
        XCTAssertEqual(AffinityMath.points(left: -5, limit: 50), 1)
        XCTAssertEqual(AffinityMath.points(left: 10, limit: 0), 1)
    }

    func testLevelThresholds() {
        let expected = [0, 30, 90, 180, 300, 450, 630, 840, 1080, 1350]
        XCTAssertEqual((1...10).map { AffinityMath.threshold(level: $0) }, expected)

        XCTAssertEqual(AffinityMath.level(points: 0), 1)
        XCTAssertEqual(AffinityMath.level(points: 29), 1)
        XCTAssertEqual(AffinityMath.level(points: 30), 2)
        XCTAssertEqual(AffinityMath.level(points: 89), 2)
        XCTAssertEqual(AffinityMath.level(points: 90), 3)
        XCTAssertEqual(AffinityMath.level(points: 1350), 10)
        XCTAssertEqual(AffinityMath.level(points: 99_999), 10, "10단계가 끝")
    }
}

final class CloseWindowTests: XCTestCase {
    private let calendar = seoulCalendar()

    private func isOpen(_ hour: Int, _ minute: Int = 0) -> Bool {
        CloseWindow.isOpen(
            at: date(calendar, 2026, 9, 22, hour, minute),
            closeFromHour: 20, boundaryHour: 4, calendar: calendar
        )
    }

    func testOpensAtCloseHourAndStaysOpenUntilBoundary() {
        XCTAssertFalse(isOpen(19, 59), "마감 가능 시각 전")
        XCTAssertTrue(isOpen(20, 0))
        XCTAssertTrue(isOpen(23, 59))
        XCTAssertTrue(isOpen(0, 30), "자정 넘어도 경계 전이면 같은 하루")
        XCTAssertTrue(isOpen(3, 59))
        XCTAssertFalse(isOpen(4, 0), "경계 시각부터는 새 하루")
        XCTAssertFalse(isOpen(12, 0))
    }
}

final class SettlementPlannerTests: XCTestCase {
    private let today = DayKey(year: 2026, month: 9, day: 22)
    private var yesterday: DayKey { today.shifted(by: -1) }

    private func record(_ day: DayKey, closed: Bool = false, finalized: Bool = false) -> SettlementRecord {
        SettlementRecord(day: day, isClosed: closed, isFinalized: finalized)
    }

    func testFirstDayAsksNothing() {
        let plan = SettlementPlanner.plan(today: today, records: [record(today)])
        XCTAssertEqual(plan, SettlementPlan(finalize: [], prompt: nil), "설치 전 날은 묻지 않는다")
    }

    func testClosedYesterdayIsFinalizedWithoutPrompt() {
        let plan = SettlementPlanner.plan(
            today: today, records: [record(yesterday, closed: true), record(today)]
        )
        XCTAssertEqual(plan, SettlementPlan(finalize: [yesterday], prompt: nil))
    }

    func testOpenedButUnclosedYesterdayOffersFeeding() {
        let plan = SettlementPlanner.plan(today: today, records: [record(yesterday), record(today)])
        XCTAssertEqual(plan.prompt, .feedYesterday(yesterday))
        XCTAssertEqual(plan.finalize, [])
    }

    func testMissingYesterdayAsksNoDrinkWhenInstalledEarlier() {
        let twoDaysAgo = today.shifted(by: -2)
        let plan = SettlementPlanner.plan(
            today: today, records: [record(twoDaysAgo, closed: true, finalized: true), record(today)]
        )
        XCTAssertEqual(plan.prompt, .askNoDrink(yesterday))
    }

    func testAnsweredYesterdayIsNotAskedAgain() {
        // "마셨어요" = 마감 없이 확정만.
        let plan = SettlementPlanner.plan(
            today: today, records: [record(yesterday, finalized: true), record(today)]
        )
        XCTAssertNil(plan.prompt)
        XCTAssertEqual(plan.finalize, [])
    }

    func testOnlyYesterdayIsOfferedButOlderClosedDaysStillFinalize() {
        let threeDaysAgo = today.shifted(by: -3)
        let fourDaysAgo = today.shifted(by: -4)
        let plan = SettlementPlanner.plan(
            today: today,
            records: [record(fourDaysAgo), record(threeDaysAgo, closed: true), record(today)]
        )
        // 4일 전 미마감은 묻지 않고, 3일 전 마감분은 확정한다. 어제는 앱을 안 열었다.
        XCTAssertEqual(plan.finalize, [threeDaysAgo])
        XCTAssertEqual(plan.prompt, .askNoDrink(yesterday))
    }

    func testTodayIsNeverFinalized() {
        let plan = SettlementPlanner.plan(today: today, records: [record(today, closed: true)])
        XCTAssertEqual(plan.finalize, [])
    }
}

final class DayKeyRawValueTests: XCTestCase {
    func testRoundTrip() {
        let key = DayKey(year: 2026, month: 1, day: 5)
        XCTAssertEqual(DayKey(rawValue: key.rawValue), key)
        XCTAssertNil(DayKey(rawValue: "2026-01"))
        XCTAssertNil(DayKey(rawValue: "abc"))
    }
}

/// 하루 경계 전후 정산 시나리오(SPEC §8 Phase 2 게이트). 실제 SwiftData 컨테이너(인메모리)로 돈다.
///
/// `Entry.dayKey`가 기기 달력(`.current`)을 쓰므로 여기서도 `.current`로 시각을 만든다.
/// 경계 4시, 당 기준 50 g, 카페인 기준 400 mg.
@MainActor
private struct Harness {
    let container: ModelContainer
    let calendar = Calendar.current
    let limits = DailyLimits.default
    let boundaryHour = 4

    var context: ModelContext { container.mainContext }

    init() throws {
        container = try ModelContainer(
            for: Entry.self, AppSettings.self, DaySettlement.self, Affinity.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    func at(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        date(calendar, 2026, month, day, hour, minute)
    }

    func log(sugar: Double, caffeine: Double?, at loggedAt: Date) -> Entry {
        let entry = Entry(
            servingID: nil, quantity: 1, loggedAt: loggedAt, sugarG: sugar, caffeineMg: caffeine,
            drinkName: "테스트", brandName: "직접 입력", sizeLabel: ""
        )
        context.insert(entry)
        return entry
    }

    func points(_ side: CupSide) throws -> Int {
        let id = side.characterID
        let rows = try context.fetch(FetchDescriptor<Affinity>(predicate: #Predicate { $0.character == id }))
        return rows.first?.points ?? 0
    }

    func feedPastDay(_ day: DayKey, entries: [Entry], now: Date) throws -> [FeedResult] {
        try SettlementStore.feedPastDay(
            day, entries: entries, limits: limits, boundaryHour: boundaryHour, now: now, in: context
        )
    }
}

@MainActor
final class SettlementScenarioTests: XCTestCase {
    func testDrinkAfterCloseBeforeBoundaryShrinksTheFinalValue() throws {
        let h = try Harness()
        let day = DayKey(year: 2026, month: 9, day: 21)
        var entries = [h.log(sugar: 20, caffeine: 150, at: h.at(9, 21, 14))]

        // 23:00 마감: 남은 당 30, 카페인 250.
        let row = try SettlementStore.row(for: day, in: h.context)
        let atClose = DayMath.totals(entries.map(\.consumption), limits: h.limits)
        SettlementStore.close(row, totals: atClose, now: h.at(9, 21, 23))
        XCTAssertEqual(row.sugarLeftAtCloseG, 30)

        // 마감 뒤 01:30(달력상 다음 날, 경계 전) 당 10 g → 21일 몫.
        entries.append(h.log(sugar: 10, caffeine: nil, at: h.at(9, 22, 1, 30)))
        // 04:05(경계 뒤) 기록은 22일 몫이라 빠지지 않는다.
        entries.append(h.log(sugar: 40, caffeine: 300, at: h.at(9, 22, 4, 5)))

        // 22일 04:10 첫 실행 → 계획은 21일 확정.
        let now = h.at(9, 22, 4, 10)
        let today = DayKey(at: now, boundaryHour: h.boundaryHour, calendar: h.calendar)
        _ = try SettlementStore.row(for: today, in: h.context)
        let plan = SettlementPlanner.plan(today: today, records: try SettlementStore.records(in: h.context))
        XCTAssertEqual(plan.finalize, [day])
        XCTAssertNil(plan.prompt)

        let results = try SettlementStore.finalize(
            row, entries: entries, limits: h.limits, boundaryHour: h.boundaryHour, now: now, in: h.context
        )

        XCTAssertEqual(row.finalSugarLeftG, 20, "마감 뒤 경계 전 기록은 그날 몫으로 빠진다")
        XCTAssertEqual(row.finalCaffeineLeftMg, 250, "카페인 미공개 기록은 카인 컵을 줄이지 않는다")
        XCTAssertTrue(row.shrankAfterClose)
        // 당 20/50 → 1 + round(3.6) = 5, 카페인 250/400 → 1 + round(5.625) = 7
        XCTAssertEqual(try h.points(.sugar), 5)
        XCTAssertEqual(try h.points(.caffeine), 7)
        XCTAssertEqual(results.map(\.side), [.sugar, .caffeine])

        // 다시 확정해도 두 번 적립되지 않는다.
        _ = try SettlementStore.finalize(
            row, entries: entries, limits: h.limits, boundaryHour: h.boundaryHour, now: now, in: h.context
        )
        XCTAssertEqual(try h.points(.sugar), 5)
    }

    func testFeedingUnclosedYesterdayCreditsFinalValueOnce() throws {
        let h = try Harness()
        let yesterday = DayKey(year: 2026, month: 9, day: 21)
        let entries = [h.log(sugar: 60, caffeine: 100, at: h.at(9, 21, 15))]

        let results = try h.feedPastDay(yesterday, entries: entries, now: h.at(9, 22, 9))

        // 당 초과 → 1점, 카페인 300/400 → 1 + round(6.75) = 8
        XCTAssertEqual(try h.points(.sugar), 1)
        XCTAssertEqual(try h.points(.caffeine), 8)
        XCTAssertEqual(results.first { $0.side == .sugar }?.left, 0)

        let records = try SettlementStore.records(in: h.context)
        XCTAssertEqual(records, [SettlementRecord(day: yesterday, isClosed: true, isFinalized: true)])
    }

    func testNoDrinkAnswerFeedsFullCups() throws {
        let h = try Harness()
        _ = try h.feedPastDay(DayKey(year: 2026, month: 9, day: 21), entries: [], now: h.at(9, 22, 9))
        XCTAssertEqual(try h.points(.sugar), 10)
        XCTAssertEqual(try h.points(.caffeine), 10)
    }

    func testDrankAnswerClosesWithoutCredit() throws {
        let h = try Harness()
        let yesterday = DayKey(year: 2026, month: 9, day: 21)
        let today = yesterday.shifted(by: 1)
        try SettlementStore.dismissPastDay(yesterday, now: h.at(9, 22, 9), in: h.context)
        _ = try SettlementStore.row(for: today, in: h.context)

        XCTAssertEqual(try h.points(.sugar), 0)
        let plan = SettlementPlanner.plan(today: today, records: try SettlementStore.records(in: h.context))
        XCTAssertNil(plan.prompt, "마셨어요 뒤에는 다시 묻지 않는다")
    }

    func testLevelUpIsReported() throws {
        let h = try Harness()
        // 3일 연속 가득 → 30점 → Lv2.
        var last: [FeedResult] = []
        for offset in 0..<3 {
            last = try h.feedPastDay(DayKey(year: 2026, month: 9, day: 10 + offset), entries: [], now: Date())
        }
        XCTAssertEqual(try h.points(.sugar), 30)
        XCTAssertEqual(last.first { $0.side == .sugar }?.leveledUp, true)
        XCTAssertEqual(last.first { $0.side == .sugar }?.levelAfter, 2)
    }
}
