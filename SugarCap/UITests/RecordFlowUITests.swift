import XCTest

/// 기록 루프 end-to-end(SPEC §8 Phase 1 게이트). 실제 앱을 띄워 탭으로만 진행한다.
/// 브랜드 메뉴 경로와 직접 입력 경로를 둘 다 지나고, 컵 수치가 줄었는지 본다.
///
/// CI의 시뮬레이터는 매번 새것이라 기록 0건에서 시작한다고 가정한다.
final class RecordFlowUITests: XCTestCase {
    @MainActor
    func testRecordingFromBrandMenuAndManualEntryShrinksTheCup() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let ui = Driver(app: app)

        let summary = ui.element("cup-summary")
        XCTAssertTrue(summary.waitForExistence(timeout: 15))
        XCTAssertTrue(
            summary.label.contains("50 g / 50 g"),
            "기록 0건에서 컵이 가득 차 있지 않음: \(summary.label)"
        )

        // 브랜드 메뉴 → 첫 음료 → 추가
        ui.tap(app.buttons["brand-starbucks"])
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
        XCTAssertEqual(ui.entryRowCount(), 1)

        // 직접 입력: 당 30 g, 카페인 200 mg
        ui.scrollToTop()
        ui.tap(app.buttons["manual-entry"])
        ui.type("Test drink", into: app.textFields["manual-name"])
        ui.type("30", into: app.textFields["manual-sugar"])
        ui.type("200", into: app.textFields["manual-caffeine"])
        app.buttons["manual-save"].tap()

        XCTAssertEqual(ui.entryRowCount(), 2)

        ui.scrollToTop()
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertFalse(
            summary.label.contains("50 g / 50 g"),
            "당 30 g 이상을 기록했는데 컵이 그대로임: \(summary.label)"
        )
    }
}

/// List는 화면에 보이는 셀만 접근성 트리에 올린다. 아래로 밀려난 요소는 스크롤해서 꺼낸다.
@MainActor
private struct Driver {
    let app: XCUIApplication

    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    /// `isHittable`은 요소가 일부만 보여도 참이다. 화면 아래 끝에 걸친 버튼은 탭 지점이
    /// 홈 인디케이터 제스처 영역에 떨어져 시스템이 먹는다(실측: 874pt 화면에서 y=851~892 칩).
    /// 그래서 내비게이션 바 아래 ~ 하단 여유 위, 온전히 안쪽에 들어올 때까지 움직인다.
    func reveal(_ target: XCUIElement, maxSwipes: Int = 6) {
        let window = app.windows.firstMatch.frame
        let safeTop = window.minY + 160
        let safeBottom = window.maxY - 120

        for _ in 0..<maxSwipes {
            guard target.exists else {
                app.swipeUp()
                continue
            }
            let frame = target.frame
            if frame.minY >= safeTop, frame.maxY <= safeBottom, target.isHittable {
                return
            }
            if frame.minY < safeTop {
                app.swipeDown()
            } else {
                app.swipeUp()
            }
        }
    }

    func scrollToTop() {
        for _ in 0..<4 {
            app.swipeDown()
        }
    }

    func tap(_ target: XCUIElement) {
        reveal(target)
        XCTAssertTrue(target.isHittable, "\(target) 를 누를 수 없음")
        target.tap()
    }

    func type(_ text: String, into field: XCUIElement) {
        XCTAssertTrue(
            field.waitForExistence(timeout: 5),
            "\(field) 없음. 현재 화면 계층:\n\(app.debugDescription)"
        )
        field.tap()
        field.typeText(text)
    }

    /// 기록은 리스트 맨 아래라 끝까지 내리면 전부 보인다.
    func entryRowCount() -> Int {
        for _ in 0..<3 {
            app.swipeUp()
        }
        let rows = app.descendants(matching: .any).matching(identifier: "entry-row")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5), "기록 행이 안 보임")
        return rows.count
    }
}
