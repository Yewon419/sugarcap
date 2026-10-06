import XCTest

@testable import SugarCap

/// 캐주얼 추이(주 컵 선반·월 방울 달력) 계산. 서울 달력 고정(CI 러너는 UTC).
final class TrendCasualTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .gmt
        return calendar
    }

    private func entry(_ day: Int, sugar: Double) -> Entry {
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: 10)) ?? Date()
        return Entry(
            servingID: nil, quantity: 1, loggedAt: date, sugarG: sugar, caffeineMg: 0,
            drinkName: "테스트", brandName: "", sizeLabel: ""
        )
    }

    private let today = DayKey(year: 2026, month: 9, day: 26)

    func testWeekCountsDaysWithinLimitAndWhatWasGiven() {
        let entries = [entry(26, sugar: 60), entry(25, sugar: 20)]
        let week = WeekSummary.make(
            entries: entries, boundaryHour: 4, today: today, side: .sugar, limit: 50, calendar: calendar
        )
        XCTAssertEqual(week.days.map(\.day.day), [20, 21, 22, 23, 24, 25, 26])
        XCTAssertEqual(week.withinDays, 6, "기준을 넘긴 26일만 빠진다")
        XCTAssertEqual(week.given, 5 * 50 + 30, accuracy: 1e-9, "넘긴 날은 0을 준다")
        XCTAssertEqual(week.dailyAverage, 80.0 / 7, accuracy: 1e-9)
        XCTAssertTrue(week.isGoodWeek)
    }

    func testPreviousWeekShiftsBySevenDays() {
        let week = WeekSummary.make(
            entries: [], boundaryHour: 4, today: today, side: .sugar, limit: 50, weeksAgo: 1, calendar: calendar
        )
        XCTAssertEqual(week.days.first?.day, DayKey(year: 2026, month: 9, day: 13))
        XCTAssertEqual(week.days.last?.day, DayKey(year: 2026, month: 9, day: 19))
    }

    func testDropCalendarCoversTheMonthAndStopsAtToday() {
        let entries = [entry(26, sugar: 60), entry(25, sugar: 20)]
        let month = DropCalendar.make(
            entries: entries, boundaryHour: 4, today: today, side: .sugar, limit: 50, calendar: calendar
        )
        XCTAssertEqual(month.cells.count, 30)
        XCTAssertEqual(month.leadingBlanks, 2, "2026년 9월 1일은 화요일")
        XCTAssertEqual(month.elapsedDays, 26)
        XCTAssertEqual(month.withinDays, 25)
        XCTAssertEqual(month.given, 24 * 50 + 30, accuracy: 1e-9)
        XCTAssertNil(month.cells.last?.used, "오늘 이후는 비운다")
    }

    func testDecemberRollsOverToNextYear() {
        let month = DropCalendar.make(
            entries: [], boundaryHour: 4, today: DayKey(year: 2026, month: 12, day: 3), side: .sugar, limit: 50,
            calendar: calendar
        )
        XCTAssertEqual(month.cells.count, 31)
    }

    func testDropGrowsWithWhatWasLeft() {
        XCTAssertEqual(DropCalendar.dropSize(left: 50, limit: 50), 38)
        XCTAssertEqual(DropCalendar.dropSize(left: 25, limit: 50), 25)
        XCTAssertEqual(DropCalendar.dropSize(left: 0, limit: 50), 0)
    }
    // MARK: - 식탁 위 일주일(2026-10-06)

    func testTableWeekCountsOnlyRecordedDaysAndToday() {
        let entries = [entry(25, sugar: 20), entry(23, sugar: 70)]
        let table = TrendTable.week(
            entries: entries, boundaryHour: 4, today: today, side: .sugar, limit: 50, calendar: calendar
        )
        XCTAssertEqual(table.cups.map(\.day.day), [20, 21, 22, 23, 24, 25, 26])
        XCTAssertEqual(table.cups.map(\.recorded), [false, false, false, true, false, true, true])
        XCTAssertEqual(table.total, 30 + 0 + 50, accuracy: 1e-9, "25일 30 + 넘긴 23일 0 + 오늘 50, 기록 없는 날은 안 센다")
        XCTAssertEqual(table.nowIndex, 6)
        XCTAssertEqual(table.first, DayKey(year: 2026, month: 9, day: 20))
        XCTAssertEqual(table.last, today)
    }

    func testTableWeekChangeNeedsLastWeekRecords() {
        XCTAssertNil(TrendTable.weekChange(
            entries: [entry(25, sugar: 20)], boundaryHour: 4, today: today, side: .sugar, limit: 50, calendar: calendar
        ))
        let change = TrendTable.weekChange(
            entries: [entry(25, sugar: 20), entry(18, sugar: 10)], boundaryHour: 4, today: today, side: .sugar,
            limit: 50, calendar: calendar
        )
        XCTAssertEqual(change ?? 0, (30 + 50) - 40, accuracy: 1e-9)
    }

    func testTableMonthAveragesEachCalendarRow() {
        let entries = [entry(1, sugar: 10), entry(2, sugar: 30), entry(25, sugar: 60)]
        let table = TrendTable.month(
            entries: entries, boundaryHour: 4, today: today, side: .sugar, limit: 50, calendar: calendar
        )
        XCTAssertEqual(table.cups.map(\.day.day), [1, 6, 13, 20, 27], "9월 1일은 화요일, 일요일마다 새 줄")
        XCTAssertEqual(table.cups[0].used, 20, accuracy: 1e-9, "1·2일만 센다")
        XCTAssertEqual(table.cups.map(\.recorded), [true, false, false, true, false])
        XCTAssertEqual(table.cups[3].used, 30, accuracy: 1e-9, "25일 60과 오늘 0의 평균")
        XCTAssertTrue(table.cups[4].isFuture)
        XCTAssertEqual(table.nowIndex, 3)
        XCTAssertEqual(table.total, 40 + 20 + 0 + 50, accuracy: 1e-9)
    }
}
