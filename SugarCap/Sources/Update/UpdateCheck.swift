import Foundation
import Observation
import OSLog

/// 업데이트 안내(대표님 2026-11-22 "중요한 업데이트 사항이 있으면 무조건 업데이트를 해야 앱을 쓸 수 있게").
/// 스토어 최신 버전은 App Store 공개 조회로, 최소 버전은 리포 `update.json`(main)으로 읽는다. 서버가 없어서다(§1).
/// 새 버전이 있으면 오늘 화면 왼쪽 위에 닫을 수 없는 안내를 띄우고, 최소 버전보다 낮으면 앱 전체를 막는다.
struct AppVersion: Comparable, Sendable, CustomStringConvertible {
    let parts: [Int]

    init?(_ text: String) {
        let pieces = text.trimmingCharacters(in: .whitespaces).split(separator: ".", omittingEmptySubsequences: false)
        let parts = pieces.compactMap { Int($0) }.filter { $0 >= 0 }
        guard !parts.isEmpty, parts.count == pieces.count else { return nil }
        self.parts = parts
    }

    var description: String { parts.map(String.init).joined(separator: ".") }

    /// 빠진 자리는 0으로 본다("1.1" == "1.1.0").
    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.parts.count, rhs.parts.count)
        for i in 0..<count {
            let l = i < lhs.parts.count ? lhs.parts[i] : 0
            let r = i < rhs.parts.count ? rhs.parts[i] : 0
            if l != r { return l < r }
        }
        return false
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool { !(lhs < rhs) && !(rhs < lhs) }
}

enum UpdateState: String, Equatable {
    case none
    /// 새 버전이 스토어에 있다. 왼쪽 위 안내만.
    case available
    /// 최소 버전보다 낮다. 업데이트 전엔 앱을 못 쓴다.
    case required
}

enum UpdateMath {
    /// 최소 버전을 넘는 버전이 스토어에 실제로 올라와 있을 때만 막는다. 최소 버전을 먼저 올려도 업데이트할 길 없이 갇히지 않게.
    static func state(installed: AppVersion, store: AppVersion?, minimum: AppVersion?) -> UpdateState {
        guard let store, installed < store else { return .none }
        if let minimum, installed < minimum, !(store < minimum) { return .required }
        return .available
    }
}

/// `update.json` 형식. 최소 버전을 올릴 때는 이 파일만 main에 커밋한다(앱 빌드와 무관).
struct UpdatePolicy: Decodable, Sendable {
    let minimumVersion: String
}

struct StoreLookup: Decodable, Sendable {
    struct Result: Decodable, Sendable { let version: String }
    let results: [Result]
}

enum UpdateCheckError: Error, Sendable, CustomStringConvertible {
    case http(url: String, status: Int, body: String)
    case transport(url: String, underlying: String)
    case badVersion(url: String, value: String)

    var description: String {
        switch self {
        case .http(let url, let status, let body): "\(url) -> \(status): \(body)"
        case .transport(let url, let underlying): "\(url) 전송 실패: \(underlying)"
        case .badVersion(let url, let value): "\(url) 버전을 못 읽음: \(value)"
        }
    }
}

/// 스토어·`update.json` 조회. 메인 액터 밖에서 돈다.
enum UpdateSource {
    static let appStoreID = "6814832068"
    static let appStoreURL = URL(string: "https://apps.apple.com/app/id\(appStoreID)")!
    static let policyURL = URL(string: "https://raw.githubusercontent.com/Yewon419/sugarcap/main/update.json")!
    static let logger = Logger(subsystem: "com.sugarcap.app", category: "update")
    private static let attempts = 2

    /// 그 나라 스토어에 앱이 없으면 nil.
    static func storeVersion(region: Locale.Region?) async throws -> AppVersion? {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        components.queryItems = [URLQueryItem(name: "id", value: appStoreID)]
            + (region.map { [URLQueryItem(name: "country", value: $0.identifier.lowercased())] } ?? [])
        let url = components.url!
        let lookup = try JSONDecoder().decode(StoreLookup.self, from: try await fetch(url))
        guard let raw = lookup.results.first?.version else { return nil }
        guard let version = AppVersion(raw) else { throw UpdateCheckError.badVersion(url: url.absoluteString, value: raw) }
        return version
    }

    static func minimumVersion() async throws -> AppVersion {
        let policy = try JSONDecoder().decode(UpdatePolicy.self, from: try await fetch(policyURL))
        guard let version = AppVersion(policy.minimumVersion) else {
            throw UpdateCheckError.badVersion(url: policyURL.absoluteString, value: policy.minimumVersion)
        }
        return version
    }

    private static func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        var lastError = UpdateCheckError.transport(url: url.absoluteString, underlying: "not attempted")
        for attempt in 1...attempts {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if (200...299).contains(status) { return data }
                lastError = .http(
                    url: url.absoluteString, status: status,
                    body: String(data: data, encoding: .utf8) ?? "<\(data.count) bytes>")
            } catch {
                lastError = .transport(url: url.absoluteString, underlying: String(describing: error))
            }
            logger.error("업데이트 조회 \(attempt)/\(attempts)회 실패: \(lastError.description, privacy: .public)")
            if attempt < attempts {
                try await Task.sleep(for: .seconds(attempt))
            }
        }
        throw lastError
    }
}

@Observable
@MainActor
final class UpdateStore {
    private(set) var state: UpdateState = .none
    /// 스크린샷용 고정 상태면 조회하지 않는다.
    private var isFixed = false

    init() {}

    init(fixed: UpdateState) {
        state = fixed
        isFixed = true
    }

    /// Debug 빌드는 조회하지 않는다. 최소 버전을 올리는 순간 CI UI 테스트가 강제 화면에 막히지 않게.
    /// CI 스크린샷은 `-screenshotUpdate available|required`로 상태를 고정한다.
    static func make() -> UpdateStore {
        #if DEBUG
        let fixed = UserDefaults.standard.string(forKey: "screenshotUpdate").flatMap(UpdateState.init(rawValue:)) ?? .none
        return UpdateStore(fixed: fixed)
        #else
        return UpdateStore()
        #endif
    }

    /// 앱이 앞으로 올 때마다 부른다. 조회가 실패하면 지난 상태를 그대로 두고 로그만 남긴다(오프라인 사용자를 막지 않는다).
    func refresh() async {
        guard !isFixed else { return }
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            let installed = AppVersion(raw)
        else {
            UpdateSource.logger.error("설치 버전을 못 읽어 업데이트 확인을 건너뜀")
            return
        }
        let region = Locale.current.region
        do {
            async let store = UpdateSource.storeVersion(region: region)
            async let minimum = UpdateSource.minimumVersion()
            let next = UpdateMath.state(installed: installed, store: try await store, minimum: try await minimum)
            if next != state {
                UpdateSource.logger.info("업데이트 상태 \(self.state.rawValue, privacy: .public) -> \(next.rawValue, privacy: .public)")
            }
            state = next
        } catch {
            UpdateSource.logger.error("업데이트 확인 실패, 상태 유지: \(String(describing: error), privacy: .public)")
        }
    }
}
