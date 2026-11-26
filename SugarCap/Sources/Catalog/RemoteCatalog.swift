import Foundation
import OSLog

enum RemoteCatalogError: Error, Sendable, CustomStringConvertible {
    case http(url: String, status: Int, body: String)
    case transport(url: String, underlying: String)
    case missingBuiltAt(String)

    var description: String {
        switch self {
        case .http(let url, let status, let body): "\(url) -> \(status): \(body)"
        case .transport(let url, let underlying): "\(url) 전송 실패: \(underlying)"
        case .missingBuiltAt(let name): "\(name) 앞부분에서 built_at을 못 찾음"
        }
    }
}

/// 나라별 원격 조회 기록. `builtAt`은 저장한 캐시 파일의 값이다.
/// 캐시는 Caches에 있어 시스템이 지울 수 있으므로, 파일이 없으면 ETag를 보내지 않고 다시 받는다.
struct RemoteCatalogRecord: Codable, Equatable, Sendable {
    var etag: String
    var builtAt: String
    var saved: Bool
    var checkedAt: Date
}

enum RemoteCatalogOutcome: Equatable, Sendable {
    case skipped
    case notModified
    case notNewer(builtAt: String)
    case saved(builtAt: String)
}

/// 원격 카탈로그(SPEC §2.3). `catalog-live` 브랜치의 `data/*.json`을 받아 번들보다 새로우면 캐시에 둔다.
/// 받은 파일은 다음 실행(또는 메뉴 국가 전환)부터 쓴다. 보고 있는 메뉴 목록이 도중에 바뀌지 않게.
struct RemoteCatalog: Sendable {
    let baseURL: URL
    let cacheDirectory: URL
    /// 테스트가 실제 설정을 건드리지 않도록 UserDefaults 키 앞에 붙인다.
    let keyPrefix: String

    static let live = RemoteCatalog(
        baseURL: URL(string: "https://raw.githubusercontent.com/Yewon419/sugarcap/catalog-live/data/")!,
        cacheDirectory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RemoteCatalog", isDirectory: true),
        keyPrefix: "remoteCatalog"
    )

    static let checkInterval: TimeInterval = 6 * 3600

    /// Debug 빌드는 받지 않는다. CI UI 테스트·스크린샷이 늘 번들 카탈로그로 돌게.
    static var refreshesOnForeground: Bool {
        #if DEBUG
        false
        #else
        true
        #endif
    }
    static let logger = Logger(subsystem: "com.sugarcap.app", category: "catalog")
    private static let attempts = 2

    func cacheURL(_ country: MenuCountry) -> URL {
        cacheDirectory.appendingPathComponent("\(country.catalogResourceName).\(CatalogStore.resourceExtension)")
    }

    func record(_ country: MenuCountry) -> RemoteCatalogRecord? {
        guard let data = UserDefaults.standard.data(forKey: key(country)) else { return nil }
        do {
            return try JSONDecoder().decode(RemoteCatalogRecord.self, from: data)
        } catch {
            Self.logger.error("원격 카탈로그 기록을 못 읽어 버림(\(country.rawValue, privacy: .public)): \(String(describing: error), privacy: .public)")
            UserDefaults.standard.removeObject(forKey: key(country))
            return nil
        }
    }

    /// 번들과 캐시 중 새 쪽. 번들 쪽은 파일 앞부분의 `built_at`만 읽는다(한국 카탈로그를 두 번 디코딩하지 않게).
    /// 캐시가 깨졌으면 기록째 지워 다음 조회에서 다시 받는다. 앱 업데이트로 번들이 따라잡았으면 파일만 지운다.
    func loadNewest(_ country: MenuCountry, from bundle: Bundle = .main) throws -> Catalog {
        let file = cacheURL(country)
        let hasFile = FileManager.default.fileExists(atPath: file.path)
        if let record = record(country), record.saved, hasFile {
            let bundled = try CatalogStore.bundledBuiltAt(country, from: bundle)
            if Self.isNewer(record.builtAt, than: bundled) {
                do {
                    return try CatalogStore.load(from: Data(contentsOf: file))
                } catch {
                    Self.logger.error("캐시 카탈로그가 깨져 번들로 돌아감(\(country.rawValue, privacy: .public)): \(String(describing: error), privacy: .public)")
                    removeFile(file)
                    UserDefaults.standard.removeObject(forKey: key(country))
                }
            } else {
                Self.logger.info("번들(\(bundled, privacy: .public))이 캐시(\(record.builtAt, privacy: .public))를 따라잡아 캐시를 지움")
                removeFile(file)
                save(RemoteCatalogRecord(etag: record.etag, builtAt: record.builtAt, saved: false, checkedAt: record.checkedAt), country)
            }
        }
        return try CatalogStore.loadBundled(country, from: bundle)
    }

    /// 앱이 앞으로 올 때 부른다. `checkInterval` 안에 확인했으면 건너뛴다. 실패는 던지고, 기록은 성공했을 때만 바꾼다.
    func refresh(_ country: MenuCountry, from bundle: Bundle = .main, now: Date = Date()) async throws -> RemoteCatalogOutcome {
        let prior = record(country)
        if let prior, now.timeIntervalSince(prior.checkedAt) < Self.checkInterval { return .skipped }

        let file = cacheURL(country)
        let hasCache = prior?.saved == true && FileManager.default.fileExists(atPath: file.path)
        let sendTag = prior.flatMap { $0.saved && !hasCache ? nil : $0.etag }.flatMap { $0.isEmpty ? nil : $0 }
        let url = baseURL.appendingPathComponent(file.lastPathComponent)

        guard let fetched = try await Self.fetch(url, etag: sendTag) else {
            if var kept = prior {
                kept.checkedAt = now
                save(kept, country)
            }
            return .notModified
        }
        let (data, etag) = fetched

        // 못 읽는 파일(이 앱보다 새 스키마 등)도 ETag와 확인 시각은 남긴다. 앱이 앞으로 올 때마다 다시 받지 않게.
        let catalog: Catalog
        do {
            catalog = try CatalogStore.load(from: data)
        } catch {
            save(
                RemoteCatalogRecord(
                    etag: etag ?? "", builtAt: hasCache ? prior?.builtAt ?? "" : "", saved: hasCache, checkedAt: now),
                country)
            throw error
        }
        let bundled = try CatalogStore.bundledBuiltAt(country, from: bundle)
        let cached = hasCache ? prior?.builtAt : nil
        let base = cached.flatMap { Self.isNewer($0, than: bundled) ? $0 : nil } ?? bundled

        if Self.isNewer(catalog.builtAt, than: base) {
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            save(RemoteCatalogRecord(etag: etag ?? "", builtAt: catalog.builtAt, saved: true, checkedAt: now), country)
            Self.logger.info("원격 카탈로그 저장(\(country.rawValue, privacy: .public)): \(catalog.builtAt, privacy: .public), 다음 실행부터 씀")
            return .saved(builtAt: catalog.builtAt)
        }
        save(
            RemoteCatalogRecord(
                etag: etag ?? "", builtAt: hasCache ? prior?.builtAt ?? catalog.builtAt : catalog.builtAt,
                saved: hasCache, checkedAt: now),
            country)
        return .notNewer(builtAt: catalog.builtAt)
    }

    static func isNewer(_ lhs: String, than rhs: String) -> Bool {
        let formatter = ISO8601DateFormatter()
        guard let left = formatter.date(from: lhs) else { return false }
        guard let right = formatter.date(from: rhs) else { return true }
        return left > right
    }

    private func key(_ country: MenuCountry) -> String { "\(keyPrefix).\(country.rawValue)" }

    private func save(_ record: RemoteCatalogRecord, _ country: MenuCountry) {
        do {
            UserDefaults.standard.set(try JSONEncoder().encode(record), forKey: key(country))
        } catch {
            Self.logger.error("원격 카탈로그 기록 저장 실패: \(String(describing: error), privacy: .public)")
        }
    }

    private func removeFile(_ url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Self.logger.error("캐시 카탈로그 삭제 실패 \(url.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    /// 304면 nil. `UpdateSource.fetch`와 같은 재시도·로그.
    private static func fetch(_ url: URL, etag: String?) async throws -> (Data, String?)? {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        var lastError = RemoteCatalogError.transport(url: url.absoluteString, underlying: "not attempted")
        for attempt in 1...attempts {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let http = response as? HTTPURLResponse
                let status = http?.statusCode ?? 0
                if status == 304 { return nil }
                if (200...299).contains(status) { return (data, http?.value(forHTTPHeaderField: "ETag")) }
                lastError = .http(
                    url: url.absoluteString, status: status,
                    body: String(data: data.prefix(500), encoding: .utf8) ?? "<\(data.count) bytes>")
            } catch {
                lastError = .transport(url: url.absoluteString, underlying: String(describing: error))
            }
            logger.error("원격 카탈로그 조회 \(attempt)/\(attempts)회 실패: \(lastError.description, privacy: .public)")
            if attempt < attempts {
                try await Task.sleep(for: .seconds(attempt))
            }
        }
        throw lastError
    }
}
