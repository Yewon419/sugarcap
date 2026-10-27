import UIKit
import XCTest

@testable import SugarCap

final class CupLevelTests: XCTestCase {
    func testFiveStepBands() {
        // 2026-10-27 대표님: 더 적은 쪽 사진. 0 초과~50% 미만 → 30, 50~80% 미만 → 50, 80~100% 미만 → 80.
        XCTAssertEqual(CupLevel.steps, [0, 30, 50, 80, 100])
        XCTAssertEqual(CupLevel.step(remaining: 23, limit: 50), 30, "50 중 23 남으면 46%라 50이 아니라 30")
        XCTAssertEqual(CupLevel.step(remainingRatio: 0.499), 30)
        XCTAssertEqual(CupLevel.step(remainingRatio: 0.50), 50)
        XCTAssertEqual(CupLevel.step(remainingRatio: 0.799), 50)
        XCTAssertEqual(CupLevel.step(remainingRatio: 0.80), 80)
        XCTAssertEqual(CupLevel.step(remainingRatio: 0.95), 80)
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
        XCTAssertEqual(CupLevel.step(remainingRatio: 0.001), 30)
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
        for setID in ["iced-americano", "strawberry-latte"] + TradeCatalog.items.map(\.id) {
            for step in CupLevel.steps {
                for name in [
                    CupLevel.assetName(setID: setID, step: step), CupLevel.cutoutName(setID: setID, step: step),
                    CupLevel.wideName(setID: setID, step: step), CupLevel.rimLineName(setID: setID, step: step),
                ] {
                    XCTAssertNotNil(UIImage(named: name, in: .main, with: nil), "\(name) 이미지가 앱 번들에 없음")
                }
            }
        }
    }

    /// 거래 상품마다 방울 그림과 대기 자세용 잔 치수가 있어야 한다(§4.10). 없으면 캐릭터가 기본 잔 치수에 서서 공중에 뜬다.
    func testEveryTradeItemHasDropAndGeometry() {
        for item in TradeCatalog.items {
            XCTAssertNotNil(UIImage(named: item.dropAsset, in: .main, with: nil), "\(item.dropAsset) 없음")
            let geometry = CupSetGeometry.of(item.id)
            XCTAssertNotNil(geometry, "\(item.id) 치수 없음")
            for step in CupLevel.steps {
                XCTAssertNotNil(geometry?.rim[step], "\(item.id) \(step) 가장자리")
                XCTAssertNotNil(geometry?.liquid[step], "\(item.id) \(step) 음료 윗면")
                XCTAssertNotNil(geometry?.axis[step], "\(item.id) \(step) 잔 가운데")
            }
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
