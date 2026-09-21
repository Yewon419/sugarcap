import XCTest

@testable import SugarCap

/// 고정 달력. `.current`를 쓰면 CI 러너(UTC)와 로컬(KST)에서 결과가 갈린다.
private func seoulCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .gmt
    return calendar
}

private func seoulDate(
    _ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0
) -> Date {
    let calendar = seoulCalendar()
    let components = DateComponents(
        year: year, month: month, day: day, hour: hour, minute: minute
    )
    guard let date = calendar.date(from: components) else {
        preconditionFailure("테스트 날짜를 만들 수 없음: \(year)-\(month)-\(day) \(hour):\(minute)")
    }
    return date
}

final class DayKeyTests: XCTestCase {
    private let calendar = seoulCalendar()

    func testBoundaryHourSplitsTheDayAtFourAM() {
        // 경계 4시: 03:59는 아직 전날, 04:00부터 당일.
        let justBefore = DayKey(
            at: seoulDate(2026, 9, 21, 3, 59), boundaryHour: 4, calendar: calendar
        )
        let justAfter = DayKey(
            at: seoulDate(2026, 9, 21, 4, 0), boundaryHour: 4, calendar: calendar
        )

        XCTAssertEqual(justBefore.rawValue, "2026-09-20")
        XCTAssertEqual(justAfter.rawValue, "2026-09-21")
    }

    func testLateNightBeforeMidnightStaysOnTheSameDay() {
        let beforeMidnight = DayKey(
            at: seoulDate(2026, 9, 21, 23, 30), boundaryHour: 4, calendar: calendar
        )
        XCTAssertEqual(beforeMidnight.rawValue, "2026-09-21")
    }

    func testZeroBoundaryMatchesCalendarDate() {
        let key = DayKey(
            at: seoulDate(2026, 9, 21, 0, 1), boundaryHour: 0, calendar: calendar
        )
        XCTAssertEqual(key.rawValue, "2026-09-21")
    }

    func testRawValueIsZeroPadded() {
        XCTAssertEqual(DayKey(year: 2026, month: 1, day: 5).rawValue, "2026-01-05")
    }

    func testShiftCrossesMonthAndYearBoundaries() {
        let endOfYear = DayKey(year: 2026, month: 12, day: 31)
        XCTAssertEqual(endOfYear.shifted(by: 1, calendar: calendar).rawValue, "2027-01-01")

        let firstOfMonth = DayKey(year: 2026, month: 3, day: 1)
        XCTAssertEqual(firstOfMonth.shifted(by: -1, calendar: calendar).rawValue, "2026-02-28")
    }

    func testShiftRoundTripsToItself() {
        let key = DayKey(year: 2026, month: 9, day: 21)
        let roundTrip = key.shifted(by: 7, calendar: calendar)
            .shifted(by: -7, calendar: calendar)
        XCTAssertEqual(roundTrip, key)
    }

    func testOrderingIsChronological() {
        let keys = [
            DayKey(year: 2026, month: 1, day: 2),
            DayKey(year: 2025, month: 12, day: 31),
            DayKey(year: 2026, month: 1, day: 10),
        ].sorted()

        XCTAssertEqual(keys.map(\.rawValue), ["2025-12-31", "2026-01-02", "2026-01-10"])
    }
}

final class DayTotalsTests: XCTestCase {
    private let limits = DailyLimits(sugarG: 50, caffeineMg: 400)

    func testEmptyDayLeavesTheFullLimit() {
        let totals = DayMath.totals([], limits: limits)

        XCTAssertEqual(totals.sugarG, 0)
        XCTAssertEqual(totals.leftSugarG, 50)
        XCTAssertEqual(totals.leftCaffeineMg, 400)
        XCTAssertEqual(totals.overSugarG, 0)
    }

    func testMissingValuesAddZeroButDoNotDropTheEntry() {
        // SPEC §9.2: 미공개는 0이 아니다. 합계에만 0으로 더하고 행은 남는다.
        let totals = DayMath.totals(
            [
                Consumption(sugarG: 20, caffeineMg: nil),
                Consumption(sugarG: nil, caffeineMg: 150),
            ],
            limits: limits
        )

        XCTAssertEqual(totals.sugarG, 20)
        XCTAssertEqual(totals.caffeineMg, 150)
        XCTAssertEqual(totals.leftSugarG, 30)
        XCTAssertEqual(totals.leftCaffeineMg, 250)
    }

    func testLeftIsClampedAtZeroAndOverflowIsReported() {
        let totals = DayMath.totals(
            [Consumption(sugarG: 62, caffeineMg: 410)], limits: limits
        )

        XCTAssertEqual(totals.leftSugarG, 0)
        XCTAssertEqual(totals.leftCaffeineMg, 0)
        XCTAssertEqual(totals.overSugarG, 12, accuracy: 1e-9)
        XCTAssertEqual(totals.overCaffeineMg, 10, accuracy: 1e-9)
    }

    func testExactlyAtTheLimitIsNotOverflow() {
        let totals = DayMath.totals(
            [Consumption(sugarG: 50, caffeineMg: 400)], limits: limits
        )

        XCTAssertEqual(totals.leftSugarG, 0)
        XCTAssertEqual(totals.overSugarG, 0)
        XCTAssertEqual(totals.overCaffeineMg, 0)
    }

    func testQuantityIsNotMultipliedAgain() {
        // 기록 시점에 수량을 곱해 스냅샷한다(prototype.html:348).
        // 2잔짜리 기록 하나는 이미 곱해진 값 그대로 더해져야 한다.
        let twoCups = Consumption(sugarG: 11 * 2, caffeineMg: 75 * 2)
        let totals = DayMath.totals([twoCups], limits: limits)

        XCTAssertEqual(totals.sugarG, 22)
        XCTAssertEqual(totals.caffeineMg, 150)
    }
}
