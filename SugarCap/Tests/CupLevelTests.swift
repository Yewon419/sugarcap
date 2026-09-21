import UIKit
import XCTest

@testable import SugarCap

final class CupLevelTests: XCTestCase {
    func testSpecExamplesRoundDownToTheNearestAvailableStep() {
        // SPEC §9-10에 박힌 예시 그대로.
        XCTAssertEqual(CupLevel.step(remainingRatio: 0.95), 80)
        XCTAssertEqual(CupLevel.step(remainingRatio: 0.65), 50)
    }

    func testSkippedStepsFallToTheNextLowerOne() {
        // 60·90은 이미지가 없다.
        XCTAssertEqual(CupLevel.step(remainingRatio: 0.69), 50)
        XCTAssertEqual(CupLevel.step(remainingRatio: 0.99), 80)
    }

    func testExactStepValuesMapToThemselves() {
        for step in CupLevel.steps where step > 0 && step < 100 {
            XCTAssertEqual(
                CupLevel.step(remainingRatio: Double(step) / 100), step,
                "\(step)% 가 자기 단계로 가지 않음"
            )
        }
    }

    func testFullSceneOnlyWhenNothingWasConsumed() {
        XCTAssertEqual(CupLevel.step(remainingRatio: 1), 100)
        XCTAssertEqual(CupLevel.step(remainingRatio: 0.999), 80)
    }

    func testEmptySceneOnlyAtExactlyZero() {
        XCTAssertEqual(CupLevel.step(remainingRatio: 0), 0)
        // 남은 양이 조금이라도 있으면 첫 단계까지는 보인다.
        XCTAssertEqual(CupLevel.step(remainingRatio: 0.001), 10)
        XCTAssertEqual(CupLevel.step(remainingRatio: 0.09), 10)
    }

    func testRemainingAndLimitAreConvertedToARatio() {
        XCTAssertEqual(CupLevel.step(remaining: 32.5, limit: 50), 50)
        XCTAssertEqual(CupLevel.step(remaining: 0, limit: 400), 0)
        XCTAssertEqual(CupLevel.step(remaining: 400, limit: 400), 100)
    }

    func testNonPositiveLimitDoesNotDivideByZero() {
        XCTAssertEqual(CupLevel.step(remaining: 10, limit: 0), 0)
    }

    func testEveryStepHasAnImageInTheAppBundle() {
        // 호스트 앱에 붙어 도는 테스트라 Bundle.main이 앱이다.
        // 에셋 이름이 어긋나면 화면엔 빈 칸만 뜨고 에러는 안 나므로 여기서 잡는다.
        for step in CupLevel.steps {
            let name = CupLevel.assetName(step: step)
            XCTAssertNotNil(
                UIImage(named: name, in: .main, with: nil),
                "\(name) 이미지가 앱 번들에 없음"
            )
        }
    }

    func testBothCharacterSpritesExistInTheAppBundle() {
        for side in CupSide.allCases {
            XCTAssertNotNil(
                UIImage(named: side.characterAsset, in: .main, with: nil),
                "\(side.characterAsset) 스프라이트가 앱 번들에 없음"
            )
        }
    }
}

final class AmountTests: XCTestCase {
    func testMissingValueReadsAsUndisclosedNotZero() {
        XCTAssertEqual(Amount.text(nil, unit: "g"), "미공개")
    }

    func testWholeNumbersDropTheDecimal() {
        XCTAssertEqual(Amount.number(18), "18")
    }

    func testFractionsKeepOneDecimal() {
        XCTAssertEqual(Amount.number(12.34), "12.3")
    }
}
