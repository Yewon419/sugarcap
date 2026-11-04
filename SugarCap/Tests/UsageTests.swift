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
