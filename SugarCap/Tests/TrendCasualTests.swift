import XCTest

@testable import SugarCap

/// 캐주얼 추이(주 컵 선반·월~일 주) 계산. 서울 달력 고정(CI 러너는 UTC).
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

    // MARK: - 월~일 주(2026-10-27)

    func testWeekStartIsMonday() {
        XCTAssertEqual(today.weekStart(calendar: calendar), DayKey(year: 2026, month: 9, day: 21), "9월 26일은 토요일")
        XCTAssertEqual(
            DayKey(year: 2026, month: 9, day: 27).weekStart(calendar: calendar), DayKey(year: 2026, month: 9, day: 21),
            "일요일은 앞 월요일의 주"
        )
        XCTAssertEqual(DayKey(year: 2026, month: 9, day: 21).weekStart(calendar: calendar), DayKey(year: 2026, month: 9, day: 21))
    }

    func testCalendarWeekRunsMondayToSundayAndLeavesTheFutureEmpty() {
        let entries = [entry(25, sugar: 20), entry(22, sugar: 70)]
        let table = TrendTable.calendarWeek(
            entries: entries, boundaryHour: 4, today: today, start: DayKey(year: 2026, month: 9, day: 21), side: .sugar,
            limit: 50, calendar: calendar
        )
        XCTAssertEqual(table.cups.map(\.day.day), [21, 22, 23, 24, 25, 26, 27])
        XCTAssertEqual(table.cups.map(\.recorded), [false, true, false, false, true, true, false])
        XCTAssertEqual(table.cups.map(\.isFuture), [false, false, false, false, false, false, true])
        XCTAssertEqual(table.total, 30 + 0 + 50, accuracy: 1e-9, "25일 30 + 넘긴 22일 0 + 오늘 50")
        XCTAssertEqual(table.nowIndex, 5)
        XCTAssertEqual(table.last, DayKey(year: 2026, month: 9, day: 27))
    }

    func testCalendarWeekChangeComparesTheSameDaysOfLastWeek() {
        XCTAssertNil(TrendTable.calendarWeekChange(
            entries: [entry(25, sugar: 20), entry(20, sugar: 10)], boundaryHour: 4, today: today, side: .sugar,
            limit: 50, calendar: calendar
        ), "지난주 일요일(20일) 기록은 이맘때 밖이라 비교 기록이 없다")
        let change = TrendTable.calendarWeekChange(
            entries: [entry(25, sugar: 20), entry(15, sugar: 10), entry(20, sugar: 0)], boundaryHour: 4, today: today,
            side: .sugar, limit: 50, calendar: calendar
        )
        XCTAssertEqual(change ?? 0, (30 + 50) - 40, accuracy: 1e-9, "지난주 월~토 중 기록은 15일 하나")
    }
}
