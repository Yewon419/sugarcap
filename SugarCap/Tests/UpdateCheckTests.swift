import XCTest

@testable import SugarCap

final class UpdateCheckTests: XCTestCase {
    private func v(_ text: String) -> AppVersion { AppVersion(text)! }

    func testVersionCompare() {
        XCTAssertLessThan(v("1.1.2"), v("1.1.3"))
        XCTAssertLessThan(v("1.1.9"), v("1.1.10"), "자리별 숫자로 비교한다(문자열 아님)")
        XCTAssertLessThan(v("1.1"), v("1.1.1"))
        XCTAssertEqual(v("1.1"), v("1.1.0"))
        XCTAssertNil(AppVersion(""))
        XCTAssertNil(AppVersion("1..2"))
        XCTAssertNil(AppVersion("1.1b"))
    }

    func testState() {
        XCTAssertEqual(UpdateMath.state(installed: v("1.1.3"), store: v("1.1.3"), minimum: v("1.1.3")), .none)
        XCTAssertEqual(UpdateMath.state(installed: v("1.1.4"), store: v("1.1.3"), minimum: v("1.1.3")), .none, "심사 중·TestFlight 빌드")
        XCTAssertEqual(UpdateMath.state(installed: v("1.1.3"), store: v("1.1.4"), minimum: v("1.1.3")), .available)
        XCTAssertEqual(UpdateMath.state(installed: v("1.1.3"), store: v("1.1.4"), minimum: v("1.1.4")), .required)
        XCTAssertEqual(UpdateMath.state(installed: v("1.1.3"), store: v("1.1.5"), minimum: v("1.1.4")), .required)
        XCTAssertEqual(
            UpdateMath.state(installed: v("1.1.3"), store: v("1.1.4"), minimum: v("1.1.5")), .available,
            "최소 버전이 스토어에 아직 없으면 막지 않는다")
        XCTAssertEqual(UpdateMath.state(installed: v("1.1.3"), store: nil, minimum: v("1.1.5")), .none, "그 나라 스토어에 없음")
        XCTAssertEqual(UpdateMath.state(installed: v("1.1.3"), store: v("1.1.4"), minimum: nil), .available)
    }

    /// 리포 루트 `update.json`(앱이 main에서 읽는 파일)이 앱이 읽는 형식인지 본다. 시뮬레이터는 맥 파일을 그대로 읽는다.
    func testRepoPolicyFileDecodes() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("update.json")
        let policy = try JSONDecoder().decode(UpdatePolicy.self, from: Data(contentsOf: url))
        XCTAssertNotNil(AppVersion(policy.minimumVersion), "minimumVersion을 못 읽음: \(policy.minimumVersion)")
    }

    /// 실제 App Store 조회. 출시된 앱이라 한국 스토어에 버전이 있다.
    /// CI 러너에서 연결이 시간 초과로 끊기는 일이 잦아(2026-11-22 세 번 연속, 로컬에선 0.35초에 200) 연결 실패만 건너뛴다.
    /// HTTP 오류·응답 형식 오류는 그대로 실패다.
    func testStoreLookupReturnsVersion() async throws {
        let version: AppVersion?
        do {
            version = try await UpdateSource.storeVersion(region: Locale.Region("KR"))
        } catch UpdateCheckError.transport(let url, let underlying) {
            throw XCTSkip("App Store 연결 실패로 건너뜀: \(url) \(underlying)")
        }
        let found = try XCTUnwrap(version, "한국 스토어 조회에 앱이 없음")
        XCTAssertFalse(found < AppVersion("1.1.2")!, "스토어 버전이 이미 나간 1.1.2보다 낮음: \(found)")
    }
}
