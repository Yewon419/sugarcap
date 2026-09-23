import SwiftData
import XCTest

@testable import SugarCap

private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> DayKey {
    DayKey(year: year, month: month, day: dayOfMonth)
}

final class ReductionMathTests: XCTestCase {
    /// 당 50 g → 30 g, 8주. 주당 2.5 g이라 5 g 단위로는 두 주에 한 칸씩 내려간다.
    func testWeeklyLimitSequenceForSugar() {
        let limits = (0...8).map {
            ReductionMath.weeklyLimit(start: 50, target: 30, weeks: 8, achievedWeeks: $0, step: 5)
        }
        XCTAssertEqual(limits, [50, 45, 45, 40, 40, 35, 35, 30, 30])
    }

    func testWeeklyLimitNeverGoesBelowTarget() {
        let limit = ReductionMath.weeklyLimit(
            start: 400, target: 200, weeks: 4, achievedWeeks: 99, step: 25
        )
        XCTAssertEqual(limit, 200)
    }

    func testWeeklyLimitForCaffeine() {
        XCTAssertEqual(
            ReductionMath.weeklyLimit(start: 400, target: 200, weeks: 4, achievedWeeks: 1, step: 25),
            350
        )
    }

    func testInvalidPlanFallsBackToTarget() {
        XCTAssertEqual(
            ReductionMath.weeklyLimit(start: 30, target: 50, weeks: 4, achievedWeeks: 0, step: 5), 50
        )
        XCTAssertEqual(
            ReductionMath.weeklyLimit(start: 50, target: 30, weeks: 0, achievedWeeks: 0, step: 5), 30
        )
    }

    func testWeekIsAchievedWithFiveDaysWithinLimit() {
        // 5일 이내 + 2일 초과 → 달성
        XCTAssertTrue(ReductionMath.isWeekAchieved(dailyTotals: [10, 10, 10, 10, 10, 90, 90], limit: 50))
        // 4일만 이내 → 미달
        XCTAssertFalse(ReductionMath.isWeekAchieved(dailyTotals: [10, 10, 10, 10, 90, 90, 90], limit: 50))
        // 기준과 같은 값은 이내로 센다
        XCTAssertTrue(ReductionMath.isWeekAchieved(dailyTotals: Array(repeating: 50, count: 7), limit: 50))
        // 기록이 없는 날(0)도 이내
        XCTAssertTrue(ReductionMath.isWeekAchieved(dailyTotals: Array(repeating: 0, count: 7), limit: 50))
    }

    func testElapsedWeeksCountsOnlyFinishedWeeks() {
        let start = day(2026, 9, 1)
        XCTAssertEqual(ReductionMath.elapsedWeeks(from: start, to: day(2026, 9, 1)), 0)
        XCTAssertEqual(ReductionMath.elapsedWeeks(from: start, to: day(2026, 9, 7)), 0)
        XCTAssertEqual(ReductionMath.elapsedWeeks(from: start, to: day(2026, 9, 8)), 1)
        XCTAssertEqual(ReductionMath.elapsedWeeks(from: start, to: day(2026, 9, 22)), 3)
    }

    /// 미달한 주는 기준을 유지하고, 계획 기간만 늘어난다(SPEC §9.5).
    func testMissedWeekHoldsTheLimit() {
        let weekTotals: [[Double]] = [
            Array(repeating: 10, count: 7),  // 1주차 달성
            Array(repeating: 90, count: 7),  // 2주차 미달
            Array(repeating: 10, count: 7),  // 3주차 달성
        ]
        let state = ReductionAdvance.advance(
            state: ReductionState(achievedWeeks: 0, evaluatedWeeks: 0),
            elapsedWeeks: 3, start: 50, target: 30, weeks: 8, step: 5,
            totalsForWeek: { weekTotals[$0] }
        )
        XCTAssertEqual(state, ReductionState(achievedWeeks: 2, evaluatedWeeks: 3))
        XCTAssertEqual(
            ReductionMath.weeklyLimit(
                start: 50, target: 30, weeks: 8, achievedWeeks: state.achievedWeeks, step: 5
            ),
            45,
            "3주 중 2주 달성 → 2칸이 아니라 2주치만 내려간다"
        )
    }

    func testAdvanceIsIdempotentForAlreadyEvaluatedWeeks() {
        let state = ReductionAdvance.advance(
            state: ReductionState(achievedWeeks: 2, evaluatedWeeks: 3),
            elapsedWeeks: 3, start: 50, target: 30, weeks: 8, step: 5,
            totalsForWeek: { _ in XCTFail("이미 판정한 주를 다시 본다"); return [] }
        )
        XCTAssertEqual(state, ReductionState(achievedWeeks: 2, evaluatedWeeks: 3))
    }
}

@MainActor
final class ReductionStoreTests: XCTestCase {
    /// 컨테이너를 테스트가 붙잡고 있어야 한다. 지역 변수로 두면 해제되면서 컨텍스트가 리셋되고
    /// 모델 인스턴스가 "destroyed by ModelContext.reset"으로 죽는다.
    private var container: ModelContainer?

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Entry.self, AppSettings.self, DaySettlement.self, Affinity.self, ReductionGoal.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        self.container = container
        return container.mainContext
    }

    private func entry(_ sugar: Double, at date: Date, in context: ModelContext) {
        context.insert(
            Entry(
                servingID: nil, quantity: 1, loggedAt: date, sugarG: sugar, caffeineMg: nil,
                drinkName: "테스트", brandName: "직접 입력", sizeLabel: ""
            )
        )
    }

    /// 첫 주를 달성하면 다음 주 하루 기준이 내려가고, 그 값이 설정에 반영된다.
    func testAchievedWeekLowersTheDailyLimit() throws {
        let context = try makeContext()
        let settings = AppSettings()
        context.insert(settings)

        let calendar = Calendar.current
        let start = DayKey(year: 2026, month: 9, day: 1)
        let goal = try ReductionStore.start(
            side: .sugar, target: 30, weeks: 8, settings: settings, today: start, in: context
        )
        XCTAssertEqual(goal.startLimit, 50)

        // 1주차 7일 모두 10 g → 달성.
        var entries: [Entry] = []
        for offset in 0..<7 {
            let key = start.shifted(by: offset)
            let date = calendar.date(
                from: DateComponents(year: key.year, month: key.month, day: key.day, hour: 12)
            )!
            entry(10, at: date, in: context)
        }
        entries = try context.fetch(FetchDescriptor<Entry>())

        ReductionStore.advance(
            goal, entries: entries, boundaryHour: 4, today: start.shifted(by: 8), settings: settings,
            in: context
        )

        XCTAssertEqual(goal.achievedWeeks, 1)
        XCTAssertEqual(settings.sugarLimitG, 45, "달성한 주 수만큼 내려간 기준이 설정에 쓰인다")
    }

    /// 목표치에 닿으면 계획을 끝내고 목표치를 하루 기준으로 남긴다.
    func testGoalFinishesAtTarget() throws {
        let context = try makeContext()
        let settings = AppSettings()
        context.insert(settings)

        let start = DayKey(year: 2026, month: 9, day: 1)
        let goal = try ReductionStore.start(
            side: .sugar, target: 45, weeks: 1, settings: settings, today: start, in: context
        )
        // 기록 0건 = 7일 모두 기준 이내 → 1주 만에 목표 도달.
        ReductionStore.advance(
            goal, entries: [], boundaryHour: 4, today: start.shifted(by: 8), settings: settings,
            in: context
        )

        XCTAssertEqual(settings.sugarLimitG, 45)
        XCTAssertTrue(try ReductionStore.goals(in: context).isEmpty, "도달하면 계획을 끝낸다")
    }

    func testStopKeepsTheCurrentLimit() throws {
        let context = try makeContext()
        let settings = AppSettings()
        context.insert(settings)
        settings.sugarLimitG = 45

        _ = try ReductionStore.start(
            side: .sugar, target: 30, weeks: 8, settings: settings,
            today: DayKey(year: 2026, month: 9, day: 1), in: context
        )
        try ReductionStore.stop(side: .sugar, in: context)

        XCTAssertTrue(try ReductionStore.goals(in: context).isEmpty)
        XCTAssertEqual(settings.sugarLimitG, 45, "그만둬도 지금까지 내려온 기준은 그대로 둔다")
    }
}

@MainActor
final class TrendMathTests: XCTestCase {
    private var container: ModelContainer?

    private func makeEntries(_ values: [(day: Int, sugar: Double, caffeine: Double?)]) throws -> [Entry] {
        let container = try ModelContainer(
            for: Entry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        self.container = container
        let context = container.mainContext
        let calendar = Calendar.current
        for value in values {
            let date = calendar.date(
                from: DateComponents(year: 2026, month: 9, day: value.day, hour: 12)
            )!
            context.insert(
                Entry(
                    servingID: nil, quantity: 1, loggedAt: date, sugarG: value.sugar,
                    caffeineMg: value.caffeine, drinkName: "테스트", brandName: "직접 입력", sizeLabel: ""
                )
            )
        }
        return try context.fetch(FetchDescriptor<Entry>())
    }

    func testDailyFillsEmptyDaysWithZero() throws {
        let entries = try makeEntries([(day: 22, sugar: 20, caffeine: 100)])
        let points = TrendMath.daily(
            entries: entries, boundaryHour: 4, today: day(2026, 9, 22), days: 7
        )

        XCTAssertEqual(points.count, 7)
        XCTAssertEqual(points.first?.day, day(2026, 9, 16))
        XCTAssertEqual(points.last?.day, day(2026, 9, 22), "마지막 칸이 오늘")
        XCTAssertEqual(points.last?.sugarG, 20)
        XCTAssertEqual(points.dropLast().map(\.sugarG), Array(repeating: 0, count: 6))
    }

    func testMissingValuesCountAsZero() throws {
        let entries = try makeEntries([(day: 22, sugar: 30, caffeine: nil)])
        let points = TrendMath.daily(
            entries: entries, boundaryHour: 4, today: day(2026, 9, 22), days: 1
        )
        XCTAssertEqual(points.first?.caffeineMg, 0, "미공개는 0으로 더한다(§9.2)")
    }

    func testWeeklyUsesDailyAverage() throws {
        let entries = try makeEntries([
            (day: 21, sugar: 70, caffeine: 0), (day: 22, sugar: 70, caffeine: 0),
        ])
        let points = TrendMath.weekly(
            entries: entries, boundaryHour: 4, today: day(2026, 9, 22), weeks: 2
        )
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points.last?.sugarG, 20, "140 / 7일")
        XCTAssertEqual(points.first?.sugarG, 0)
    }

    func testChangeVersusPreviousWeek() throws {
        let entries = try makeEntries([
            (day: 10, sugar: 100, caffeine: 0),  // 앞 7일
            (day: 20, sugar: 50, caffeine: 0),  // 최근 7일
        ])
        let change = TrendMath.changeVersusPreviousWeek(
            entries: entries, boundaryHour: 4, today: day(2026, 9, 22), side: .sugar
        )
        XCTAssertEqual(change ?? 0, -50, accuracy: 0.001)
    }

    func testChangeIsNilWithoutPreviousWeek() throws {
        let entries = try makeEntries([(day: 22, sugar: 50, caffeine: 0)])
        XCTAssertNil(
            TrendMath.changeVersusPreviousWeek(
                entries: entries, boundaryHour: 4, today: day(2026, 9, 22), side: .sugar
            )
        )
    }
}
