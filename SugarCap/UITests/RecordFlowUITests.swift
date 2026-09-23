import XCTest

/// 기록 루프 end-to-end(SPEC §8 Phase 1 게이트). 실제 앱을 띄워 탭으로만 진행한다.
/// 브랜드 메뉴 경로와 직접 입력 경로를 둘 다 지나고, 컵 수치가 줄었는지 본다.
///
/// CI의 시뮬레이터는 매번 새것이라 기록 0건·온보딩 전 상태에서 시작한다고 가정한다.
/// 테스트는 이름순으로 돌아 이 테스트가 먼저다.
final class RecordFlowUITests: XCTestCase {
    @MainActor
    func testRecordingFromBrandMenuAndManualEntryShrinksTheCup() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let ui = Driver(app: app)

        // 새 시뮬레이터라 온보딩이 떠야 한다(§4.5).
        let start = app.buttons["onboarding-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 15), "첫 실행에 온보딩이 없음")
        start.tap()

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

extension RecordFlowUITests {
    /// 설정에서 당 하루 기준을 바꾸면 오늘 화면 수치의 분모가 바로 바뀐다(§4.4).
    /// 끝나면 기본값 50 g으로 되돌린다. 뒤이은 CI 스크린샷이 기본 상태를 찍어야 한다.
    @MainActor
    func testSugarPresetChangesTodayLimit() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        // 단독 실행이면 온보딩부터 뜬다.
        let start = app.buttons["onboarding-start"]
        if start.waitForExistence(timeout: 5) {
            start.tap()
        }

        let summary = app.descendants(matching: .any)["cup-summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 15))
        XCTAssertTrue(summary.label.contains("/ 50 g"), "기본 당 기준이 50 g이 아님: \(summary.label)")

        app.tabBars.buttons["설정"].tap()
        let preset100 = app.buttons["100 g"]
        XCTAssertTrue(preset100.waitForExistence(timeout: 5), "당 프리셋이 안 보임:\n\(app.debugDescription)")
        preset100.tap()

        app.tabBars.buttons["오늘"].tap()
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(summary.label.contains("/ 100 g"), "프리셋 변경이 오늘 화면에 안 반영됨: \(summary.label)")

        // 되돌리기도 확인한다. 확인 없이 탭만 하면 실패해도 통과하고, 스크린샷이 100 g 상태로 찍힌다.
        app.tabBars.buttons["설정"].tap()
        let preset50 = app.buttons["50 g"]
        XCTAssertTrue(preset50.waitForExistence(timeout: 5))
        preset50.tap()
        let restored = NSPredicate(format: "isSelected == true")
        expectation(for: restored, evaluatedWith: preset50)
        waitForExpectations(timeout: 5)

        app.tabBars.buttons["오늘"].tap()
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(summary.label.contains("/ 50 g"), "기본값으로 안 돌아옴: \(summary.label)")
    }
}

extension RecordFlowUITests {
    /// 감소 목표를 만들면 하루 기준이 목표 관리로 넘어가고, 그만두면 되돌아온다(§4.3·§9.5).
    @MainActor
    func testStartAndStopSugarReductionGoal() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        let start = app.buttons["onboarding-start"]
        if start.waitForExistence(timeout: 5) {
            start.tap()
        }
        app.tabBars.buttons["설정"].tap()

        let startGoal = app.buttons["start-goal-sugar"]
        XCTAssertTrue(startGoal.waitForExistence(timeout: 10))
        startGoal.tap()

        let confirm = app.buttons["goal-start"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "목표 시트가 안 열림")
        confirm.tap()

        // 목표가 도는 동안에는 당 프리셋 대신 목표 진행 행이 보인다.
        let stopGoal = app.buttons["그만두기"]
        XCTAssertTrue(stopGoal.waitForExistence(timeout: 5), "목표 진행 행이 안 보임")
        XCTAssertFalse(app.buttons["25 g"].exists, "목표 중에는 프리셋을 만지지 못한다")

        stopGoal.tap()
        XCTAssertTrue(startGoal.waitForExistence(timeout: 5), "그만두면 다시 만들 수 있어야 한다")
        XCTAssertTrue(app.buttons["25 g"].waitForExistence(timeout: 5), "프리셋이 돌아와야 한다")
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
