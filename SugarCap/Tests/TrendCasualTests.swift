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
}
