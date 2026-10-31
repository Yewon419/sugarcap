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

final class ProTrialTests: XCTestCase {
    func testOneWeekFreeTrialIsSevenDays() {
        XCTAssertEqual(ProTrial.days(isFreeTrial: true, isEligible: true, unitDays: 7, value: 1), 7)
        XCTAssertEqual(ProTrial.days(isFreeTrial: true, isEligible: true, unitDays: 1, value: 7), 7)
    }

    /// 이미 체험한 Apple ID에게 "무료"를 보여 주면 결제 안내와 실제 청구가 어긋난다.
    func testNoTrialWhenNotEligibleOrNotFree() {
        XCTAssertNil(ProTrial.days(isFreeTrial: true, isEligible: false, unitDays: 7, value: 1))
        XCTAssertNil(ProTrial.days(isFreeTrial: false, isEligible: true, unitDays: 7, value: 1))
        XCTAssertNil(ProTrial.days(isFreeTrial: true, isEligible: true, unitDays: nil, value: 1))
    }

    @MainActor
    func testMockPlansOfferTrialOnYearlyOnly() {
        let plans = ProStore.mockPlans
        XCTAssertEqual(plans.first { $0.id == ProProduct.yearly }?.trialDays, 7)
        XCTAssertNil(plans.first { $0.id == ProProduct.lifetime }?.trialDays)
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
            ["monthlyTrends", "reductionGoal", "gifts"]
        )
    }
}
