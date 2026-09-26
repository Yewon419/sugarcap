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

        // 새 시뮬레이터라 온보딩이 떠야 한다(§4.5). 4페이지라 건너뛰기로 마지막 장까지 간 뒤 시작한다.
        let skip = app.buttons["onboarding-skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 15), "첫 실행에 온보딩이 없음")
        skip.tap()
        let start = app.buttons["onboarding-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5), "온보딩 마지막 장(하루 기준)이 안 열림")
        start.tap()

        let summary = ui.element("cup-summary")
        XCTAssertTrue(summary.waitForExistence(timeout: 15))
        XCTAssertTrue(
            summary.label.contains("50 g / 50 g"),
            "기록 0건에서 컵이 가득 차 있지 않음: \(summary.label)"
        )

        // 브랜드 선택은 기록 시트 안에 있다(2026-09-24 디자인).
        app.buttons["record-add"].tap()
        let starbucks = app.buttons["brand-starbucks"]
        XCTAssertTrue(starbucks.waitForExistence(timeout: 5), "기록 시트에 브랜드가 없음")
        starbucks.tap()

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

        // 직접 입력: 당 30 g, 카페인 200 mg
        app.buttons["record-add"].tap()
        let manual = app.buttons["manual-entry"]
        XCTAssertTrue(manual.waitForExistence(timeout: 5))
        manual.tap()
        ui.type("Test drink", into: app.textFields["manual-name"])
        ui.type("30", into: app.textFields["manual-sugar"])
        ui.type("200", into: app.textFields["manual-caffeine"])
        app.buttons["manual-save"].tap()

        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertFalse(
            summary.label.contains("50 g / 50 g"),
            "당 30 g 이상을 기록했는데 컵이 그대로임: \(summary.label)"
        )

        // 기록 2건은 큰 숫자를 누르면 뜨는 하루 기록 시트에 있다(2026-09-26, 기록 시트에서 뺐다).
        summary.tap()
        let rows = app.descendants(matching: .any).matching(identifier: "entry-row")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5), "하루 기록 시트에 기록 줄이 안 보임")
        XCTAssertEqual(rows.count, 2)

        // 편집 → 지우기 하면 한 줄이 빠지고 컵이 그만큼 다시 찬다.
        app.buttons["daylog-edit"].tap()
        let delete = app.buttons.matching(identifier: "delete-entry").firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "편집에 지우기 버튼이 없음")
        delete.tap()
        let oneLeft = NSPredicate(format: "count == 1")
        expectation(for: oneLeft, evaluatedWith: rows)
        waitForExpectations(timeout: 5)
        app.buttons["daylog-close"].tap()
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
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
        completeOnboardingIfPresented(app)

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
    /// 감소 목표는 Pro라 목 구매 상태(Debug 전용 인자)로 띄운다.
    @MainActor
    func testStartAndStopSugarReductionGoal() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-mockProOwned", "YES"]
        app.launch()

        completeOnboardingIfPresented(app)
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
        // 되돌릴 수 없는 동작이라 확인을 한 번 거친다.
        // iOS 26 confirmationDialog는 같은 식별자를 두 요소로 노출한다. 누를 수 있는 쪽을 고른다.
        let confirmStops = app.buttons.matching(identifier: "confirm-stop-goal")
        XCTAssertTrue(confirmStops.firstMatch.waitForExistence(timeout: 5), "그만두기 확인 창이 안 뜸")
        let confirmStop = try XCTUnwrap(
            confirmStops.allElementsBoundByIndex.first { $0.isHittable },
            "그만두기 확인 버튼을 누를 수 없음:\n\(app.debugDescription)"
        )
        confirmStop.tap()
        XCTAssertTrue(startGoal.waitForExistence(timeout: 5), "그만두면 다시 만들 수 있어야 한다")
        XCTAssertTrue(app.buttons["25 g"].waitForExistence(timeout: 5), "프리셋이 돌아와야 한다")
    }
}

extension RecordFlowUITests {
    /// 무료 사용자가 Pro 기능을 누르면 페이월이 열린다(§6).
    @MainActor
    func testTappingProFeatureOpensPaywall() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-mockPro", "YES"]
        app.launch()

        completeOnboardingIfPresented(app)

        let affinity = app.buttons["affinity"]
        XCTAssertTrue(affinity.waitForExistence(timeout: 15))
        affinity.tap()

        XCTAssertTrue(
            app.buttons["plan-\(ProductIDs.yearly)"].waitForExistence(timeout: 5),
            "페이월에 상품이 안 보임"
        )
        app.buttons["paywall-close"].tap()
        XCTAssertTrue(affinity.waitForExistence(timeout: 5), "닫으면 원래 화면으로 돌아와야 한다")
    }
}

extension RecordFlowUITests {
    /// 설정에서 앱 소개를 다시 열고, "닫기"와 마지막 장 "완료" 두 길로 모두 설정에 돌아온다(§4.4).
    @MainActor
    func testReplayOnboardingFromSettings() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        completeOnboardingIfPresented(app)
        app.tabBars.buttons["설정"].tap()

        let replay = app.buttons["replay-onboarding"]
        Driver(app: app).tap(replay)

        let close = app.buttons["onboarding-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5), "앱 소개가 안 열림")
        XCTAssertFalse(app.buttons["onboarding-skip"].exists, "다시 보기에는 건너뛰기 대신 닫기만 있어야 한다")
        close.tap()
        XCTAssertTrue(replay.waitForExistence(timeout: 5), "닫기 후 설정으로 돌아와야 한다")

        Driver(app: app).tap(replay)
        let next = app.buttons["onboarding-next"]
        for _ in 0..<3 {
            XCTAssertTrue(next.waitForExistence(timeout: 5))
            next.tap()
        }
        let finish = app.buttons["onboarding-start"]
        XCTAssertTrue(finish.waitForExistence(timeout: 5), "마지막 장이 안 열림")
        XCTAssertEqual(finish.label, "완료")
        finish.tap()
        XCTAssertTrue(replay.waitForExistence(timeout: 5), "완료 후 설정으로 돌아와야 한다")
        XCTAssertTrue(app.tabBars.buttons["설정"].isSelected, "다시 보기는 온보딩 완료 상태를 건드리지 않는다")
    }
}

/// UI 테스트 번들은 앱 코드를 불러오지 않는다. 상품 id는 여기에 따로 적는다.
private enum ProductIDs {
    static let yearly = "com.sugarcap.app.pro.yearly"
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

}

extension RecordFlowUITests {
    /// 단독 실행이면 온보딩부터 뜬다. 건너뛰기 → 마지막 장 "시작". 이미 지났으면 아무것도 안 한다.
    @MainActor
    func completeOnboardingIfPresented(_ app: XCUIApplication) {
        let skip = app.buttons["onboarding-skip"]
        guard skip.waitForExistence(timeout: 5) else { return }
        skip.tap()
        let start = app.buttons["onboarding-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5), "온보딩 마지막 장이 안 열림")
        start.tap()
    }
}
