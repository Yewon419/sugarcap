import XCTest

@testable import SugarCap

/// SPEC §9.10 1단계. 앱과 같은 UserDefaults·대기열을 건드리지 않게 따로 만든 저장소를 쓴다.
@MainActor
final class UsageReporterTests: XCTestCase {
    private struct Storage {
        let suiteName: String
        let defaults: UserDefaults
        let queue: UsageQueue

        func remove() throws {
            defaults.removePersistentDomain(forName: suiteName)
            try queue.delete()
        }
    }

    private func makeStorage() throws -> Storage {
        let suiteName = "usage-tests-\(UUID().uuidString)"
        let queue = UsageQueue(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(suiteName, isDirectory: true).appendingPathComponent("queue.json"))
        return Storage(suiteName: suiteName, defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)), queue: queue)
    }

    func testBeforeConsentEventsStayOnDevice() async throws {
        let storage = try makeStorage()
        defer { try? storage.remove() }
        let queue = storage.queue
        // 설정이 있어도(실제 앱 ID) 동의 전에는 네트워크를 타지 않는다.
        let reporter = UsageReporter(defaults: storage.defaults, queue: queue, config: UsageConfig.bundled(.main))
        XCTAssertEqual(reporter.consent, .undecided)

        try reporter.record(type: "onboarding_completed", scope: .install, parameters: [:])
        try reporter.record(type: "day_bundle", scope: .anonymous, parameters: ["weekday": "3"])

        let queued = try queue.load()
        XCTAssertEqual(queued.map(\.type), ["onboarding_completed", "day_bundle"])
        XCTAssertNotNil(queued[0].sessionID)
        XCTAssertNil(queued[1].sessionID)
        let result = try await reporter.flush()
        XCTAssertEqual(result, .notAllowed)
        XCTAssertEqual(try queue.load().count, 2)
    }

    func testDeclineDeletesQueueAndDropsLaterEvents() throws {
        let storage = try makeStorage()
        defer { try? storage.remove() }
        let queue = storage.queue
        let reporter = UsageReporter(defaults: storage.defaults, queue: queue, config: nil)
        try reporter.record(type: "onboarding_completed", scope: .install, parameters: [:])
        XCTAssertTrue(FileManager.default.fileExists(atPath: queue.fileURL.path))

        try reporter.decline()
        XCTAssertEqual(reporter.consent, .declined)
        XCTAssertFalse(FileManager.default.fileExists(atPath: queue.fileURL.path))

        try reporter.record(type: "first_entry_logged", scope: .install, parameters: [:])
        XCTAssertFalse(FileManager.default.fileExists(atPath: queue.fileURL.path))
    }

    func testGrantWithoutAppIDSendsNothingAndKeepsQueue() async throws {
        let storage = try makeStorage()
        defer { try? storage.remove() }
        let queue = storage.queue
        let reporter = UsageReporter(defaults: storage.defaults, queue: queue, config: nil)
        try reporter.record(type: "onboarding_completed", scope: .install, parameters: [:])
        let result = try await reporter.grant()
        XCTAssertEqual(result, .notConfigured)
        XCTAssertEqual(try queue.load().count, 1)
    }

    /// 실제 TelemetryDeck으로 테스트 모드 신호를 보낸다(목 없음). CI가 시크릿으로 앱 ID를 넣은 빌드에서만 돈다.
    func testGrantSendsQueuedEventsToTelemetryDeck() async throws {
        let config = try XCTUnwrap(
            UsageConfig.bundled(.main), "TelemetryDeckAppID가 비어 있다. CI 테스트 단계에 시크릿이 들어갔는지 본다.")
        let storage = try makeStorage()
        defer { try? storage.remove() }
        let queue = storage.queue
        let reporter = UsageReporter(defaults: storage.defaults, queue: queue, config: config)
        try reporter.record(type: "ci_probe_install", scope: .install, parameters: ["source": "UsageTests"])
        try reporter.record(type: "ci_probe_anonymous", scope: .anonymous, parameters: ["source": "UsageTests"])

        let result = try await reporter.grant()
        XCTAssertEqual(result, .sent(2))
        XCTAssertEqual(try queue.load(), [])
    }

    func testFirstEntryIsLoggedOnceWithDaysSinceInstall() throws {
        let storage = try makeStorage()
        defer { try? storage.remove() }
        let reporter = UsageReporter(defaults: storage.defaults, queue: storage.queue, config: nil)
        let now = Date()
        let today = DayKey(at: now, boundaryHour: 4)
        reporter.noteInstallDay(
            records: [
                SettlementRecord(day: today.shifted(by: -1), isClosed: true, isFinalized: true),
                SettlementRecord(day: today.shifted(by: -3), isClosed: true, isFinalized: true),
            ],
            boundaryHour: 4)

        reporter.logEntry(path: .favorite, place: .today, brandID: nil, now: now)
        reporter.logEntry(path: .brandMenu, place: .feeding, brandID: "starbucks", now: now)

        let queued = try storage.queue.load()
        XCTAssertEqual(queued.map(\.type), ["entry_logged", "first_entry_logged", "entry_logged"])
        XCTAssertTrue(queued.allSatisfy { $0.scope == .install && $0.sessionID != nil })
        XCTAssertEqual(queued[0].parameters, ["path": "favorite", "place": "today"])
        XCTAssertEqual(queued[1].parameters, ["daysSinceInstall": "3"])
        XCTAssertEqual(queued[2].parameters, ["path": "brandMenu", "place": "feeding", "brandID": "starbucks"])
    }

    func testInstallWithEarlierEntriesSkipsFirstEntry() throws {
        let storage = try makeStorage()
        defer { try? storage.remove() }
        let reporter = UsageReporter(defaults: storage.defaults, queue: storage.queue, config: nil)
        reporter.noteExistingEntries(count: 0)
        reporter.noteExistingEntries(count: 12)

        reporter.logEntry(path: .search, place: .today, brandID: "ediya", now: Date())

        XCTAssertEqual(try storage.queue.load().map(\.type), ["entry_logged"])
    }
}

final class UsageEventsTests: XCTestCase {
    func testDraftsCarryOnlyListedParameters() {
        XCTAssertEqual(
            UsageEvents.onboardingCompleted(reelSkipped: true, limits: DailyLimits(sugarG: 50, caffeineMg: 400)),
            UsageEventDraft(
                type: "onboarding_completed",
                parameters: ["reelSkipped": "true", "sugarLimitBand": "50", "caffeineLimitBand": "400"]))
        XCTAssertEqual(
            UsageEvents.dayClosed(.drank), UsageEventDraft(type: "day_closed", parameters: ["kind": "drank"]))
        XCTAssertEqual(
            UsageEvents.tradeOffer(itemID: "matcha", accepted: false),
            UsageEventDraft(type: "trade_offer", parameters: ["itemID": "matcha", "accepted": "false"]))
        XCTAssertEqual(
            UsageEvents.firstEntryLogged(daysSinceInstall: 0),
            UsageEventDraft(type: "first_entry_logged", parameters: ["daysSinceInstall": "0"]))
    }

    func testPaywallSendsPlanNameAndOriginOfLockedFeature() {
        XCTAssertEqual(
            UsageEvents.paywallShown(
                origin: PaywallOrigin(.reductionGoal), planID: ProProduct.yearly, result: .trialStarted),
            UsageEventDraft(
                type: "paywall_shown",
                parameters: ["origin": "reductionGoal", "plan": "yearly", "result": "trialStarted"]))
        XCTAssertEqual(
            UsageEvents.paywallShown(origin: .trialAfterTrade, planID: ProProduct.lifetime, result: .closed)
                .parameters["plan"],
            "lifetime")
    }

    func testGoalReminderWidgetDrafts() {
        XCTAssertEqual(
            UsageEvents.goalStarted(side: .caffeine, weeks: 4, startLimit: 400, target: 250),
            UsageEventDraft(
                type: "goal_started",
                parameters: ["side": "caffeine", "weeks": "4", "startLimitBand": "400", "targetBand": "200"]))
        XCTAssertEqual(
            UsageEvents.goalStarted(side: .sugar, weeks: 3, startLimit: 50, target: 30).parameters["targetBand"], "25")
        XCTAssertEqual(
            UsageEvents.goalStopped(side: .sugar, achievedWeeks: 1, evaluatedWeeks: 2),
            UsageEventDraft(
                type: "goal_stopped", parameters: ["side": "sugar", "achievedWeeks": "1", "evaluatedWeeks": "2"]))
        XCTAssertEqual(
            UsageEvents.goalReached(side: .sugar, weeks: 3),
            UsageEventDraft(type: "goal_reached", parameters: ["side": "sugar", "weeks": "3"]))
        XCTAssertEqual(
            UsageEvents.reminderAnswered(place: .prompt, result: .notNow),
            UsageEventDraft(type: "reminder_answered", parameters: ["place": "prompt", "result": "notNow"]))
        XCTAssertEqual(
            UsageEvents.widgetState(count: 0),
            UsageEventDraft(type: "widget_state", parameters: ["installed": "false", "count": "0"]))
    }
}

final class IngestSignalTests: XCTestCase {
    private let technical = ["appVersion": "1.0.1", "systemVersion": "26.0", "language": "ko", "region": "KR"]

    private func event(_ type: String, _ scope: UsageEvent.Scope, at date: Date) -> UsageEvent {
        UsageEvent(
            id: UUID(), type: type, scope: scope, parameters: ["k": "v"], createdAt: date,
            sessionID: scope == .install ? UUID() : nil)
    }

    func testAnonymousSignalsCannotBeJoined() throws {
        let afternoon = Date(timeIntervalSince1970: 1_762_264_800)  // 2025-11-04 14:00 UTC
        let signals = IngestSignal.make(
            events: [event("day_bundle", .anonymous, at: afternoon), event("day_bundle", .anonymous, at: afternoon)],
            appID: "app", installUser: "install-hash", isTestMode: true, technical: technical)

        XCTAssertNotEqual(signals[0].clientUser, signals[1].clientUser)
        XCTAssertFalse(signals.contains { $0.clientUser == "install-hash" })
        XCTAssertEqual(signals[0].receivedAt, "2025-11-04T00:00:00+0000")
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(signals), encoding: .utf8))
        XCTAssertFalse(json.contains("sessionID"))
    }

    func testInstallSignalsKeepUserSessionAndTime() {
        let afternoon = Date(timeIntervalSince1970: 1_762_264_800)
        let source = event("onboarding_completed", .install, at: afternoon)
        let signal = IngestSignal.make(
            events: [source], appID: "app", installUser: "install-hash", isTestMode: false, technical: technical)[0]

        XCTAssertEqual(signal.clientUser, "install-hash")
        XCTAssertEqual(signal.sessionID, source.sessionID?.uuidString)
        XCTAssertEqual(signal.receivedAt, "2025-11-04T14:00:00+0000")
        XCTAssertEqual(signal.isTestMode, "false")
        XCTAssertEqual(signal.payload["k"], "v")
        XCTAssertEqual(signal.payload["region"], "KR")
    }

    /// 동의서 제3조 4호에 적은 것만 붙는다.
    func testTechnicalPayloadListsOnlyConsentedFields() {
        let payload = IngestSignal.technicalPayload(
            bundle: .main, locale: Locale(identifier: "ko_KR"), process: .processInfo)
        XCTAssertEqual(Set(payload.keys), ["appVersion", "systemVersion", "language", "region"])
        XCTAssertEqual(payload["language"], "ko")
        XCTAssertEqual(payload["region"], "KR")
    }

    func testSHA256HexMatchesKnownVector() {
        XCTAssertEqual(
            IngestSignal.sha256Hex("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}

final class InstallIDTests: XCTestCase {
    func testInstallIDIsStable() throws {
        XCTAssertEqual(try InstallID.current(), try InstallID.current())
    }
}

/// 음료 통계 하루 묶음(SPEC §9.10). 서울 달력 고정(CI 러너는 UTC).
final class DayBundleTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .gmt
        return calendar
    }

    private let today = DayKey(year: 2026, month: 10, day: 27)
    private let settings = DayBundle.Settings(
        menuCountry: .kr, sides: [.sugar, .caffeine], limits: DailyLimits(sugarG: 50, caffeineMg: 400), boundaryHour: 4)

    private func day(_ day: Int) -> DayKey {
        DayKey(year: 2026, month: 10, day: day)
    }

    private func record(_ day: Int, finalized: Bool) -> SettlementRecord {
        SettlementRecord(day: self.day(day), isClosed: finalized, isFinalized: finalized)
    }

    private func entry(_ day: Int, hour: Int = 10, serving: String?, quantity: Int = 1, sugar: Double, caffeine: Double = 0)
        -> Entry
    {
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour)) ?? Date()
        return Entry(
            servingID: serving, quantity: quantity, loggedAt: date, sugarG: sugar, caffeineMg: caffeine,
            drinkName: "테스트", brandName: "", sizeLabel: "")
    }

    func testFirstRunOnlyPlacesWatermark() {
        let plan = DayBundle.plan(
            records: [record(20, finalized: true), record(26, finalized: true)], today: today, watermark: nil, recent: [])
        XCTAssertEqual(plan, DayBundle.Plan(days: [], watermark: day(25), recent: []))
    }

    func testFinalizedDaysGoAtOnceOthersWaitTwoDays() {
        let records = [
            record(22, finalized: false),  // 워터마크 이전: 이미 처리
            record(24, finalized: false),  // 이틀 지남: 확정 안 돼도 보낸다
            record(25, finalized: false),  // 이틀 지남
            record(26, finalized: false),  // 어제, 확정 안 됨: 기다린다
            record(27, finalized: false),  // 오늘
        ]
        let plan = DayBundle.plan(records: records, today: today, watermark: day(23), recent: [])
        XCTAssertEqual(plan.days, [day(24), day(25)])
        XCTAssertEqual(plan.watermark, day(25))

        let finalizedYesterday = DayBundle.plan(
            records: [record(26, finalized: true)], today: today, watermark: day(25), recent: [])
        XCTAssertEqual(finalizedYesterday.days, [day(26)])
        XCTAssertEqual(finalizedYesterday.recent, [day(26)])

        // 다음 날: 26일은 이미 보냈고, 워터마크가 지나가면 기억에서 뺀다.
        let nextDay = DayBundle.plan(
            records: [record(26, finalized: true), record(27, finalized: true)], today: day(28), watermark: day(25),
            recent: [day(26)])
        XCTAssertEqual(nextDay.days, [day(27)])
        XCTAssertEqual(nextDay.watermark, day(26))
        XCTAssertEqual(nextDay.recent, [day(27)])
    }

    func testParametersDropManualDetailsAndBandLimits() throws {
        let entries = [
            entry(20, hour: 15, serving: "starbucks-latte-tall", quantity: 2, sugar: 20, caffeine: 150),
            entry(20, hour: 9, serving: "mega-americano", sugar: 0, caffeine: 200),
            entry(20, hour: 21, serving: nil, quantity: 3, sugar: 40),
            entry(21, serving: "other-day", sugar: 5),
        ]
        let params = try DayBundle.parameters(day: day(20), entries: entries, settings: settings, calendar: calendar)

        XCTAssertEqual(params["weekday"], "3")
        XCTAssertEqual(params["menuCountry"], "kr")
        XCTAssertEqual(params["sides"], "sugar,caffeine")
        XCTAssertEqual(params["sugarLimitBand"], "50")
        XCTAssertEqual(params["caffeineLimitBand"], "400")
        XCTAssertEqual(params["keptSugar"], "false")  // 20 + 40(직접 입력) = 60 > 50
        XCTAssertEqual(params["keptCaffeine"], "true")  // 350 ≤ 400
        XCTAssertEqual(params["manualCups"], "3")
        XCTAssertEqual(
            params["cups"],
            #"[{"hour":9,"quantity":1,"servingID":"mega-americano"},{"hour":15,"quantity":2,"servingID":"starbucks-latte-tall"}]"#
        )
        XCTAssertFalse(params.values.contains { $0.contains("테스트") })
        XCTAssertEqual(DayBundle.band(37, width: 25), 25)
        XCTAssertEqual(DayBundle.band(250, width: 100), 200)
    }

    /// 앱 월 통계의 "기준 안에서 끝낸 날"과 같은 답을 내야 한다.
    func testKeptFlagsMatchMonthDigest() throws {
        let entries = [
            entry(20, serving: "a", sugar: 30),
            entry(21, serving: "b", sugar: 60),
            entry(22, serving: "c", sugar: 50),
            entry(23, serving: nil, sugar: 70),
            entry(27, serving: "today", sugar: 10),
        ]
        let digest = MonthDigest.make(
            entries: entries, boundaryHour: 4, year: 2026, month: 10, today: today, side: .sugar, limit: 50,
            earliest: day(1), calendar: calendar)
        let bundled = try [20, 21, 22, 23].map {
            try DayBundle.parameters(day: day($0), entries: entries, settings: settings, calendar: calendar)
        }
        XCTAssertEqual(bundled.filter { $0["keptSugar"] == "true" }.count, digest.keptDays)
        XCTAssertEqual(digest.keptDays, 2)
    }

    @MainActor
    func testReporterQueuesEachDayOnce() async throws {
        let suiteName = "day-bundle-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let queue = UsageQueue(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(suiteName, isDirectory: true).appendingPathComponent("queue.json"))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? queue.delete()
        }
        let reporter = UsageReporter(defaults: defaults, queue: queue, config: nil)
        let entries = [entry(25, serving: "a", sugar: 10), entry(26, serving: "b", sugar: 20)]

        try reporter.recordDayBundles(
            records: [record(25, finalized: false)], entries: entries, today: day(27), settings: settings,
            calendar: calendar)
        XCTAssertEqual(try queue.load(), [])

        let records = [record(25, finalized: false), record(26, finalized: false), record(27, finalized: true)]
        for _ in 0..<2 {
            try reporter.recordDayBundles(
                records: records, entries: entries, today: day(28), settings: settings, calendar: calendar)
        }
        let queued = try queue.load()
        XCTAssertEqual(queued.map(\.type), ["day_bundle", "day_bundle"])
        XCTAssertTrue(queued.allSatisfy { $0.scope == .anonymous && $0.sessionID == nil })
        XCTAssertEqual(queued.map { $0.parameters["weekday"] }, ["2", "3"])
    }
}
