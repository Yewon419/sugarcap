import XCTest

/// 기록 루프 end-to-end(SPEC §8 Phase 1 게이트). 실제 앱을 띄워 탭으로만 진행한다.
/// 브랜드 메뉴 경로와 직접 입력 경로를 둘 다 지나고, 컵 수치가 줄었는지 본다.
///
/// CI의 시뮬레이터는 매번 새것이라 기록 0건에서 시작한다고 가정한다.
final class RecordFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testRecordingFromBrandMenuAndManualEntryShrinksTheCup() throws {
        let app = XCUIApplication()
        app.launch()

        let summary = app.descendants(matching: .any)["cup-summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 15))
        XCTAssertTrue(
            summary.label.contains("50 g / 50 g"),
            "기록 0건에서 컵이 가득 차 있지 않음: \(summary.label)"
        )

        // 브랜드 메뉴 → 첫 음료 → 추가
        app.buttons["brand-starbucks"].tap()
        let firstDrink = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "drink-"))
            .firstMatch
        XCTAssertTrue(firstDrink.waitForExistence(timeout: 10))
        firstDrink.tap()

        let add = app.buttons["add-entry"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()

        // 추가하면 오늘 루트로 돌아와야 한다(§4.2).
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        let rows = app.descendants(matching: .any).matching(identifier: "entry-row")
        XCTAssertEqual(rows.count, 1)

        // 직접 입력: 당 30 g, 카페인 200 mg
        app.buttons["manual-entry"].tap()
        let name = app.textFields["manual-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Test drink")
        let sugar = app.textFields["manual-sugar"]
        sugar.tap()
        sugar.typeText("30")
        let caffeine = app.textFields["manual-caffeine"]
        caffeine.tap()
        caffeine.typeText("200")
        app.buttons["manual-save"].tap()

        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        XCTAssertEqual(rows.count, 2)
        XCTAssertFalse(
            summary.label.contains("50 g / 50 g"),
            "당 30 g 이상을 기록했는데 컵이 그대로임: \(summary.label)"
        )
    }
}
