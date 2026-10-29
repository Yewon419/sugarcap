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

    // MARK: - 월 통계(MonthDigest)

    private func drink(
        _ day: Int, hour: Int = 10, name: String, brand: String = "이디야커피", quantity: Int = 1,
        sugar: Double?, caffeine: Double? = 0
    ) -> Entry {
        Entry(
            servingID: nil, quantity: quantity, loggedAt: date(2026, 10, day, hour: hour), sugarG: sugar,
            caffeineMg: caffeine, drinkName: name, brandName: brand, sizeLabel: ""
        )
    }

    private func digest(_ entries: [Entry], side: CupSide = .sugar, limit: Double = 50) -> MonthDigest {
        MonthDigest.make(
            entries: entries, boundaryHour: 4, year: 2026, month: 10, today: today, side: side, limit: limit,
            earliest: DayKey(year: 2026, month: 7, day: 3), calendar: calendar
        )
    }

    func testDigestTopGroupsSizesAndSkipsDrinksWithoutThatValue() {
        let entries = [
            drink(1, name: "딸기 라떼", quantity: 2, sugar: 60),
            drink(2, name: "딸기 라떼", sugar: 38),
            drink(2, name: "딸기 라떼", brand: "메가MGC커피", sugar: 40),
            drink(3, name: "아메리카노", sugar: 0, caffeine: 200),
            drink(3, name: "바나나맛 우유", brand: "편의점", sugar: nil, caffeine: nil),
        ]
        let sugar = digest(entries)
        XCTAssertEqual(sugar.top.map(\.name), ["딸기 라떼", "딸기 라떼"], "브랜드가 다르면 다른 음료, 당 0·미공개는 순위 밖")
        XCTAssertEqual(sugar.top.first?.brand, "이디야커피")
        XCTAssertEqual(sugar.top.first?.cups, 3, "잔 수는 수량을 센다")
        XCTAssertEqual(sugar.top.first?.amount, 98)
        XCTAssertEqual(sugar.total, 138)
        let caffeine = digest(entries, side: .caffeine)
        XCTAssertEqual(caffeine.top.map(\.name), ["아메리카노"])
    }

    func testDigestSlotsFoldLateNightIntoEveningAndCountAfterTwo() {
        let entries = [
            drink(5, hour: 9, name: "a", sugar: 10),
            drink(5, hour: 12, name: "b", sugar: 20),
            drink(5, hour: 15, name: "c", sugar: 30),
            drink(5, hour: 20, name: "d", sugar: 40),
            // 10월 6일 새벽 2시 = 경계(4시) 전이라 5일 밤.
            drink(6, hour: 2, name: "e", sugar: 5),
        ]
        let made = digest(entries)
        XCTAssertEqual(made.slots, [10, 20, 30, 45])
        XCTAssertEqual(made.late, 75, "오후 2시 이후 + 새벽")
    }

    func testDigestWeekdaysNeedTwoDaysAndLeaveTodayOut() {
        // 2026-10-06·13·27은 화요일, 27일이 오늘. 10월 1일은 목요일.
        let entries = [
            drink(6, name: "a", sugar: 10),
            drink(13, name: "a", sugar: 20),
            drink(27, name: "a", sugar: 100),
            drink(1, name: "a", sugar: 30),
        ]
        let made = digest(entries)
        XCTAssertEqual(made.weekdays.count, 7)
        XCTAssertEqual(made.weekdays[2], 15, "화요일 = 6·13일 평균, 오늘은 안 끝나서 뺀다")
        XCTAssertNil(made.weekdays[4], "목요일은 하루뿐이라 비운다")
    }

    func testDigestKeptDaysCountClosedDaysWithinLimit() {
        let entries = [
            drink(1, name: "a", sugar: 50),
            drink(2, name: "a", sugar: 51),
            drink(3, name: "a", sugar: 0, caffeine: 100),
            drink(27, name: "a", sugar: 10),
        ]
        let made = digest(entries)
        XCTAssertEqual(made.closedDays, 3, "오늘은 안 끝나서 뺀다")
        XCTAssertEqual(made.keptDays, 2, "기준과 같으면 안이다")
    }

    func testDigestRecentCoversSixMonthsAndBlanksBeforeFirstRecord() {
        let entries = [
            Entry(
                servingID: nil, quantity: 1, loggedAt: date(2026, 8, 10), sugarG: 30, caffeineMg: 0,
                drinkName: "a", brandName: "", sizeLabel: ""
            ),
            drink(1, name: "a", sugar: 20),
        ]
        let made = digest(entries)
        XCTAssertEqual(made.recent.map(\.month.month), [5, 6, 7, 8, 9, 10])
        XCTAssertNil(made.recent[0].average, "첫 기록 달(7월) 전")
        XCTAssertNil(made.recent[2].average, "7월은 열렸지만 기록이 없다")
        XCTAssertEqual(made.recent[3].average, 30)
        XCTAssertEqual(made.recent[5].average, 10, "이번 달 = 1일 20 + 오늘 0")
    }
}
