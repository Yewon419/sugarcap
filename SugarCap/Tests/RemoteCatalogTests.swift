import XCTest

@testable import SugarCap

/// 원격 카탈로그(SPEC §2.3). 목 없이 실제 번들 카탈로그와 실제 raw 주소를 쓴다.
/// 캐시 폴더와 UserDefaults 키는 테스트마다 따로 둬 앱 설정을 건드리지 않는다.
final class RemoteCatalogTests: XCTestCase {
    private var bundle: Bundle { Bundle(for: Self.self) }
    private var remote: RemoteCatalog!

    override func setUpWithError() throws {
        let id = UUID().uuidString
        remote = RemoteCatalog(
            baseURL: URL(string: "https://raw.githubusercontent.com/Yewon419/sugarcap/main/data/")!,
            cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("RemoteCatalogTests-\(id)"),
            keyPrefix: "remoteCatalogTests.\(id)"
        )
    }

    override func tearDownWithError() throws {
        for country in MenuCountry.allCases {
            UserDefaults.standard.removeObject(forKey: "\(remote.keyPrefix).\(country.rawValue)")
        }
        if FileManager.default.fileExists(atPath: remote.cacheDirectory.path) {
            try FileManager.default.removeItem(at: remote.cacheDirectory)
        }
    }

    /// 앞부분만 읽은 `built_at`이 통째로 디코딩한 값과 같아야 번들·캐시 비교가 맞는다.
    func testBundledBuiltAtMatchesFullDecode() throws {
        for country in MenuCountry.allCases {
            let full = try CatalogStore.loadBundled(country, from: bundle)
            XCTAssertEqual(try CatalogStore.bundledBuiltAt(country, from: bundle), full.builtAt, country.rawValue)
        }
    }

    func testNewerCacheWinsAndStaleCacheIsDropped() throws {
        let bundled = try CatalogStore.bundledBuiltAt(.tw, from: bundle)
        let later = "2099-01-01T00:00:00+00:00"
        try writeCache(.tw, builtAt: later)

        XCTAssertEqual(try remote.loadNewest(.tw, from: bundle).builtAt, later, "번들보다 새 캐시를 안 씀")

        try writeCache(.tw, builtAt: "2000-01-01T00:00:00+00:00")
        XCTAssertEqual(try remote.loadNewest(.tw, from: bundle).builtAt, bundled, "번들보다 오래된 캐시를 씀")
        XCTAssertFalse(FileManager.default.fileExists(atPath: remote.cacheURL(.tw).path), "따라잡힌 캐시가 남음")
        XCTAssertEqual(remote.record(.tw)?.saved, false)
    }

    func testBrokenCacheFallsBackToBundleAndForgetsRecord() throws {
        let bundled = try CatalogStore.bundledBuiltAt(.tw, from: bundle)
        try FileManager.default.createDirectory(at: remote.cacheDirectory, withIntermediateDirectories: true)
        try Data("{\"schema_version\": 3".utf8).write(to: remote.cacheURL(.tw))
        try saveRecord(.tw, builtAt: "2099-01-01T00:00:00+00:00")

        XCTAssertEqual(try remote.loadNewest(.tw, from: bundle).builtAt, bundled)
        XCTAssertNil(remote.record(.tw), "깨진 캐시의 기록이 남아 ETag로 다시 받기를 막음")
        XCTAssertFalse(FileManager.default.fileExists(atPath: remote.cacheURL(.tw).path))
    }

    /// 실제 raw 조회: 처음엔 받고, 6시간 뒤엔 ETag로 304, 그 사이엔 건너뛴다.
    /// 연결 실패만 건너뛴다(`UpdateCheckTests.testStoreLookupReturnsVersion`과 같은 이유). HTTP·형식 오류는 실패다.
    func testRefreshDownloadsThenGetsNotModified() async throws {
        let start = Date()
        let first: RemoteCatalogOutcome
        do {
            first = try await remote.refresh(.tw, from: bundle, now: start)
        } catch RemoteCatalogError.transport(let url, let underlying) {
            throw XCTSkip("raw 연결 실패로 건너뜀: \(url) \(underlying)")
        }
        switch first {
        case .saved, .notNewer: break
        default: XCTFail("첫 조회가 받지 않음: \(first)")
        }
        XCTAssertFalse(remote.record(.tw)?.etag.isEmpty ?? true, "ETag를 못 받음")

        let soon = try await remote.refresh(.tw, from: bundle, now: start.addingTimeInterval(3600))
        XCTAssertEqual(soon, .skipped)

        let later: RemoteCatalogOutcome
        do {
            later = try await remote.refresh(.tw, from: bundle, now: start.addingTimeInterval(7 * 3600))
        } catch RemoteCatalogError.transport(let url, let underlying) {
            throw XCTSkip("raw 연결 실패로 건너뜀: \(url) \(underlying)")
        }
        XCTAssertEqual(later, .notModified, "같은 파일을 다시 받음")
    }

    private func writeCache(_ country: MenuCountry, builtAt: String) throws {
        let url = try XCTUnwrap(bundle.url(forResource: country.catalogResourceName, withExtension: "json"))
        let text = try String(contentsOf: url, encoding: .utf8)
        let bumped = text.replacingOccurrences(
            of: #""built_at"\s*:\s*"[^"]+""#, with: "\"built_at\": \"\(builtAt)\"", options: .regularExpression)
        try FileManager.default.createDirectory(at: remote.cacheDirectory, withIntermediateDirectories: true)
        try Data(bumped.utf8).write(to: remote.cacheURL(country))
        try saveRecord(country, builtAt: builtAt)
    }

    private func saveRecord(_ country: MenuCountry, builtAt: String) throws {
        let record = RemoteCatalogRecord(etag: "test", builtAt: builtAt, saved: true, checkedAt: Date())
        UserDefaults.standard.set(try JSONEncoder().encode(record), forKey: "\(remote.keyPrefix).\(country.rawValue)")
    }
}
