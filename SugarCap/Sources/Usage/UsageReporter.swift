import CryptoKit
import Foundation
import OSLog

/// TelemetryDeck 앱 ID. 공개 리포라 코드에 두지 않고 CI 시크릿 → 빌드 설정 → Info.plist로 받는다.
/// 시크릿 없이 만든 빌드(로컬·포크)는 값이 비어 아무것도 보내지 않는다.
struct UsageConfig: Equatable, Sendable {
    static let namespace = "com.windgarden"
    static let infoKey = "TelemetryDeckAppID"

    let appID: String

    static func bundled(_ bundle: Bundle) -> UsageConfig? {
        guard let raw = bundle.object(forInfoDictionaryKey: infoKey) as? String, UUID(uuidString: raw) != nil else {
            return nil
        }
        return UsageConfig(appID: raw)
    }

    var ingestURL: URL {
        URL(string: "https://nom.telemetrydeck.com/v2/namespace/\(Self.namespace)/")!
    }
}

/// TelemetryDeck Ingest API v2 본문 한 건. SDK를 쓰지 않고 필드를 직접 고른다(SPEC §9.10).
/// SDK는 모든 신호에 기기 정보·세션·재방문 통계를 붙여 음료 통계를 이어 버린다.
struct IngestSignal: Codable, Equatable, Sendable {
    let receivedAt: String
    let appID: String
    let clientUser: String
    let sessionID: String?
    let type: String
    let payload: [String: String]
    let isTestMode: String

    /// 퍼널: 설치 ID 해시 + 실행 세션, 시각 그대로.
    /// 음료 통계: 건마다 새 무작위 사용자 값, 세션 없음, 시각은 그날 0시(UTC)로 내려 퍼널 이벤트와 시각으로도 못 잇게 한다.
    static func make(
        events: [UsageEvent], appID: String, installUser: String, isTestMode: Bool, technical: [String: String]
    ) -> [IngestSignal] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!

        return events.map { event in
            let payload = technical.merging(event.parameters) { _, eventValue in eventValue }
            switch event.scope {
            case .install:
                return IngestSignal(
                    receivedAt: formatter.string(from: event.createdAt), appID: appID, clientUser: installUser,
                    sessionID: event.sessionID?.uuidString, type: event.type, payload: payload,
                    isTestMode: isTestMode ? "true" : "false")
            case .anonymous:
                return IngestSignal(
                    receivedAt: formatter.string(from: utc.startOfDay(for: event.createdAt)), appID: appID,
                    clientUser: sha256Hex(UUID().uuidString), sessionID: nil, type: event.type, payload: payload,
                    isTestMode: isTestMode ? "true" : "false")
            }
        }
    }

    static func sha256Hex(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// 동의서 제3조 4호의 기술 정보 전부. 여기 없는 기기 정보는 보내지 않는다.
    static func technicalPayload(bundle: Bundle, locale: Locale, process: ProcessInfo) -> [String: String] {
        let os = process.operatingSystemVersion
        return [
            "appVersion": bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            "systemVersion": "\(os.majorVersion).\(os.minorVersion)",
            "language": locale.language.languageCode?.identifier ?? "unknown",
            "region": locale.region?.identifier ?? "unknown",
        ]
    }
}

/// 이용 기록의 진입점(SPEC §9.10). 기록은 늘 대기열 파일에 먼저 쌓고, 동의한 뒤에만 보낸다.
@MainActor
final class UsageReporter {
    enum FlushResult: Equatable {
        case notAllowed
        case notConfigured
        case busy
        case empty
        case sent(Int)
    }

    private static let logger = Logger(subsystem: "com.sugarcap.app", category: "usage")
    private static let attempts = 3

    private let defaults: UserDefaults
    private let queue: UsageQueue
    private let config: UsageConfig?
    /// 퍼널 이벤트를 실행 단위로 묶는다. 저장하지 않아 앱을 다시 켜면 바뀐다.
    private let sessionID = UUID()
    private var isFlushing = false

    init(defaults: UserDefaults, queue: UsageQueue, config: UsageConfig?) {
        self.defaults = defaults
        self.queue = queue
        self.config = config
    }

    var consent: UsageConsent {
        UsageConsent.load(from: defaults)
    }

    /// 거절했으면 버린다. 아직 안 물었으면 쌓기만 하고, 동의했으면 쌓은 뒤 보낸다.
    func record(type: String, scope: UsageEvent.Scope, parameters: [String: String]) throws {
        let current = consent
        guard current != .declined else { return }
        let event = UsageEvent(
            id: UUID(), type: type, scope: scope, parameters: parameters, createdAt: Date(),
            sessionID: scope == .install ? sessionID : nil)
        try queue.save(try queue.load() + [event])
        if current == .granted {
            Task { await flushLogged() }
        }
    }

    /// 동의. 동의 전에 쌓인 기록을 바로 보낸다.
    func grant() async throws -> FlushResult {
        UsageConsent.store(granted: true, in: defaults)
        return try await flush()
    }

    /// 거절·철회. 그 뒤로 쌓지 않고, 안 보낸 기록도 지운다.
    func decline() throws {
        UsageConsent.store(granted: false, in: defaults)
        try queue.delete()
    }

    func flush() async throws -> FlushResult {
        guard consent == .granted else { return .notAllowed }
        guard let config else { return .notConfigured }
        guard !isFlushing else { return .busy }
        isFlushing = true
        defer { isFlushing = false }

        let pending = try queue.load()
        guard !pending.isEmpty else { return .empty }
        let installUser = IngestSignal.sha256Hex(try InstallID.current().uuidString)
        let isTestMode = await TestBuild.isActive()
        let technical = IngestSignal.technicalPayload(bundle: .main, locale: .current, process: .processInfo)

        // 두 흐름을 같은 요청에 섞지 않는다.
        var sent = 0
        for scope in [UsageEvent.Scope.install, .anonymous] {
            let batch = pending.filter { $0.scope == scope }
            guard !batch.isEmpty else { continue }
            let signals = IngestSignal.make(
                events: batch, appID: config.appID, installUser: installUser, isTestMode: isTestMode,
                technical: technical)
            try await post(signals, to: config.ingestURL)
            sent += batch.count
            // 보내는 사이 철회했으면 지운 파일을 되살리지 않는다.
            guard consent == .granted else { return .sent(sent) }
            let sentIDs = Set(batch.map(\.id))
            try queue.save(try queue.load().filter { !sentIDs.contains($0.id) })
        }
        return .sent(sent)
    }

    private func flushLogged() async {
        do {
            _ = try await flush()
        } catch {
            Self.logger.error("이용 기록 전송 실패, 대기열에 남김: \(String(describing: error), privacy: .public)")
        }
    }

    private func post(_ signals: [IngestSignal], to url: URL) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(signals)

        var lastError = UsageError.transport(url: url.absoluteString, signalCount: signals.count, underlying: "not attempted")
        for attempt in 1...Self.attempts {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if (200...299).contains(status) {
                    return
                }
                lastError = .ingest(
                    url: url.absoluteString, signalCount: signals.count, status: status,
                    body: String(data: data, encoding: .utf8) ?? "<\(data.count) bytes>")
            } catch {
                lastError = .transport(url: url.absoluteString, signalCount: signals.count, underlying: String(describing: error))
            }
            Self.logger.error("이용 기록 전송 \(attempt)/\(Self.attempts)회 실패: \(lastError.description, privacy: .public)")
            if attempt < Self.attempts {
                try await Task.sleep(for: .seconds(attempt))
            }
        }
        throw lastError
    }
}
