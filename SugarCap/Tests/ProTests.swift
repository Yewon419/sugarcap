import XCTest

@testable import SugarCap

final class ProEntitlementTests: XCTestCase {
    func testAnyProProductUnlocksPro() {
        XCTAssertTrue(ProEntitlement.isPro(productIDs: [ProProduct.yearly]))
        XCTAssertTrue(ProEntitlement.isPro(productIDs: [ProProduct.lifetime]))
        XCTAssertTrue(ProEntitlement.isPro(productIDs: [ProProduct.yearly, ProProduct.lifetime]))
    }

    func testUnknownProductDoesNotUnlockPro() {
        XCTAssertFalse(ProEntitlement.isPro(productIDs: ["com.sugarcap.app.something"]))
        XCTAssertFalse(ProEntitlement.isPro(productIDs: []))
    }

    func testProductIDsMatchTheStoreListing() {
        // App Store Connect에 등록할 id와 같아야 한다. 바꾸면 이미 산 사람의 권한이 끊긴다.
        XCTAssertEqual(ProProduct.yearly, "com.sugarcap.app.pro.yearly")
        XCTAssertEqual(ProProduct.lifetime, "com.sugarcap.app.pro.lifetime")
        XCTAssertEqual(ProProduct.order, [ProProduct.yearly, ProProduct.lifetime])
        XCTAssertEqual(ProProduct.all, Set(ProProduct.order))
    }
}

final class ProFeatureTests: XCTestCase {
    func testEveryListedFeatureIsLockedForFreeAndOpenForPro() {
        for feature in ProFeature.allCases {
            XCTAssertTrue(feature.isLocked(isPro: false), "\(feature.rawValue)가 무료에 열려 있다")
            XCTAssertFalse(feature.isLocked(isPro: true))
        }
    }

    /// SPEC §6의 Pro 목록과 어긋나면 잠금이 빠진 것이다.
    func testLockedFeatureList() {
        XCTAssertEqual(
            Set(ProFeature.allCases.map(\.rawValue)),
            ["affinityDetail", "monthlyTrends", "weekOverWeek", "reductionGoal"]
        )
    }
}
