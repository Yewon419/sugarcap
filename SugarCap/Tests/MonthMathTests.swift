import XCTest

@testable import SugarCap

/// 월 추이 달력·합계·보관함 계산. 서울 달력 고정(CI 러너는 UTC).
final class MonthMathTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .gmt
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? Date()
    }

    private func entry(_ month: Int, _ day: Int, sugar: Double, caffeine: Double = 0) -> Entry {
        Entry(
            servingID: nil, quantity: 1, loggedAt: date(2026, month, day), sugarG: sugar, caffeineMg: caffeine,
            drinkName: "테스트", brandName: "", sizeLabel: ""
        )
    }

    private let today = DayKey(year: 2026, month: 10, day: 27)

    func testStepSplitsByRatioOfLimit() {
        XCTAssertEqual(MonthPage.step(used: 0, limit: 25), 0)
        XCTAssertEqual(MonthPage.step(used: 5, limit: 25), 30)
        XCTAssertEqual(MonthPage.step(used: 12, limit: 25), 50)
        XCTAssertEqual(MonthPage.step(used: 20, limit: 25), 80)
        XCTAssertEqual(MonthPage.step(used: 25, limit: 25), 100, "기준을 채우면 가득")
        XCTAssertEqual(MonthPage.step(used: 40, limit: 25), 100)
    }

    func testPageLeavesUnloggedPastDaysEmptyAndTodayAtZero() {
        let entries = [entry(10, 3, sugar: 10), entry(10, 3, sugar: 5), entry(9, 30, sugar: 99)]
        let page = MonthPage.make(
            entries: entries, boundaryHour: 4, year: 2026, month: 10, today: today, side: .sugar, calendar: calendar
        )
        XCTAssertEqual(page.cells.count, 31)
        XCTAssertEqual(page.leadingBlanks, 4, "2026년 10월 1일은 목요일")
        XCTAssertEqual(page.cells[2].used, 15, "같은 날 기록은 더한다")
        XCTAssertNil(page.cells[3].used, "기록 없는 지난날은 비운다(안 적었을 수도 있다)")
        XCTAssertEqual(page.cells[26].used, 0, "오늘은 기록이 없어도 0")
        XCTAssertTrue(page.cells[26].isToday)
        XCTAssertTrue(page.cells[27].isFuture)
        XCTAssertNil(page.cells[27].used)
        XCTAssertEqual(page.eaten, 15, "다른 달 기록은 섞이지 않는다")
        XCTAssertEqual(page.dailyAverage ?? -1, 7.5, accuracy: 1e-9, "3일(15)과 오늘(0)의 평균")
    }

    func testThingsConvertEatenToCubesAndShots() {
        XCTAssertEqual(MonthStats.things(eaten: 122 * 4 + 1, side: .sugar), 122)
        XCTAssertEqual(MonthStats.things(eaten: 75 * 3, side: .caffeine), 3)
    }

    func testChangeComparesSameDaysOfLastMonthWhileMonthIsLive() {
        // 9월: 1~27일 하루 10씩, 28일에 1000(이맘때 이후라 비교에서 빠져야 한다).
        var entries = (1...27).map { entry(9, $0, sugar: 10) }
        entries.append(entry(9, 28, sugar: 1000))
        // 10월: 1~27일 하루 8씩(오늘 포함).
        entries += (1...27).map { entry(10, $0, sugar: 8) }
        let change = MonthStats.change(
            entries: entries, boundaryHour: 4, year: 2026, month: 10, today: today, side: .sugar, calendar: calendar
        )
        XCTAssertEqual(change, -20)
    }

    func testChangeUsesWholeMonthsForPastMonthsAndCrossesTheYear() {
        let jan = Entry(
            servingID: nil, quantity: 1, loggedAt: date(2026, 1, 10), sugarG: 30, caffeineMg: 0,
            drinkName: "테스트", brandName: "", sizeLabel: ""
        )
        let dec = Entry(
            servingID: nil, quantity: 1, loggedAt: date(2025, 12, 31), sugarG: 20, caffeineMg: 0,
            drinkName: "테스트", brandName: "", sizeLabel: ""
        )
        let change = MonthStats.change(
            entries: [jan, dec], boundaryHour: 4, year: 2026, month: 1, today: today, side: .sugar, calendar: calendar
        )
        XCTAssertEqual(change, 50, "1월 하루 평균 30, 지난해 12월 20")
        XCTAssertNil(
            MonthStats.change(
                entries: [jan], boundaryHour: 4, year: 2026, month: 1, today: today, side: .sugar, calendar: calendar
            ),
            "지난달 기록이 없으면 비교하지 않는다"
        )
    }

    func testInventoryCountsHeartsOpenedThisYearUpToTheMonth() {
        func heart(opened: Date?, side: CupSide = .sugar) -> GiftEvent {
            GiftEvent(kind: .weekKept, side: side, payload: GiftContent.heart, createdAt: date(2025, 12, 31), openedAt: opened)
        }
        let gifts = [
            heart(opened: date(2026, 1, 2)),
            heart(opened: date(2026, 3, 5)),
            heart(opened: date(2026, 11, 1)),
            heart(opened: date(2025, 12, 31)),
            heart(opened: nil),
            heart(opened: date(2026, 2, 1), side: .caffeine),
        ]
        let march = MonthInventory.make(
            gifts: gifts, capBalance: 4, side: .sugar, year: 2026, month: 3, boundaryHour: 4, calendar: calendar
        )
        XCTAssertEqual(march.hearts, 2, "받은 날(작년)이 아니라 연 날로 센다. 안 연 것·다른 면·이후 달은 빠진다")
        XCTAssertEqual(march.caps, 4)
        let lastYear = MonthInventory.make(
            gifts: gifts, capBalance: 4, side: .sugar, year: 2025, month: 12, boundaryHour: 4, calendar: calendar
        )
        XCTAssertEqual(lastYear.hearts, 1, "지난해로 가면 그해 마음이 다시 보인다")
    }

    func testInventoryKeepsEveryOpenedItemOfTheOwner() {
        let gifts = [
            GiftEvent(kind: .goalReached, side: .sugar, payload: GiftContent.item("sugar-cube"), createdAt: date(2026, 5, 1), openedAt: date(2026, 5, 2)),
            GiftEvent(kind: .proWelcome, side: .sugar, payload: GiftContent.item("strawberry"), createdAt: date(2025, 3, 1), openedAt: date(2025, 3, 1)),
            GiftEvent(kind: .goalReached, side: .sugar, payload: GiftContent.item("cinnamon-stick"), createdAt: date(2026, 5, 1), openedAt: date(2026, 5, 3)),
            GiftEvent(kind: .goalReached, side: .caffeine, payload: GiftContent.item("coffee-bean"), createdAt: date(2026, 5, 1), openedAt: nil),
        ]
        let sugar = MonthInventory.make(
            gifts: gifts, capBalance: 0, side: .sugar, year: 2026, month: 1, boundaryHour: 4, calendar: calendar
        )
        XCTAssertEqual(sugar.items, ["strawberry", "sugar-cube"], "연 순서, 주인 것만, 보는 달과 상관없이 전부")
        let caffeine = MonthInventory.make(
            gifts: gifts, capBalance: 0, side: .caffeine, year: 2026, month: 10, boundaryHour: 4, calendar: calendar
        )
        XCTAssertEqual(caffeine.items, [], "안 연 상자는 아직 없다")
    }

    func testShakerKeysStayTheSameAcrossMonthsSoOnlyTheDifferenceMoves() {
        let march = ShakerGift.list(MonthInventory(hearts: 2, caps: 1, items: ["strawberry"]))
        XCTAssertEqual(march.map(\.key), ["item:strawberry:1", "cap:0", "heart:0", "heart:1"], "물건 → 병뚜껑 → 마음")
        let april = ShakerGift.list(MonthInventory(hearts: 3, caps: 1, items: ["strawberry"]))
        XCTAssertEqual(Set(april.map(\.key)).subtracting(march.map(\.key)), ["heart:2"], "달이 바뀌면 새 마음만 더해진다")
    }
}
