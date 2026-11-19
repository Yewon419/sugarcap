import XCTest

@testable import SugarCap

final class ReviewPromptTests: XCTestCase {
    func testAsksOnceFromTheEarlyBirdCell() {
        XCTAssertFalse(ReviewPrompt.isDue(stampedCells: StampMath.earlyBirdCell - 1, asked: false))
        XCTAssertTrue(ReviewPrompt.isDue(stampedCells: StampMath.earlyBirdCell, asked: false))
        XCTAssertTrue(ReviewPrompt.isDue(stampedCells: StampMath.cells, asked: false), "7칸을 지나 처음 닫아도 묻는다")
        XCTAssertFalse(ReviewPrompt.isDue(stampedCells: StampMath.cells, asked: true))
    }
}
