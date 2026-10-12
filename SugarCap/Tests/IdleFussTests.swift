import XCTest

@testable import SugarCap

final class IdleFussTests: XCTestCase {
    func testHeartOnlyWhenFondAndDodgeOnlyWhenThereIsSomewhereToGo() {
        XCTAssertEqual(IdleFussMath.options(canDodge: false, level: 1), [.shiver, .stare])
        XCTAssertEqual(
            IdleFussMath.options(canDodge: true, level: IdleFussMath.fondLevel), [.shiver, .dodge, .stare, .heart]
        )
    }

    func testFifthQuickTapStartsAFussAndSlowTapsDoNot() {
        let base = Date(timeIntervalSince1970: 0)
        var quick = IdleFussState()
        for i in 0 ..< PokeMath.comboCount {
            quick = quick.poked(now: base.addingTimeInterval(Double(i) * 0.3), t: Double(i) * 0.3, options: [.shiver])
            XCTAssertEqual(quick.fuss, i == PokeMath.comboCount - 1 ? .shiver : nil)
        }
        var slow = IdleFussState()
        for i in 0 ..< 8 {
            slow = slow.poked(now: base.addingTimeInterval(Double(i) * 1.0), t: Double(i), options: [.shiver])
        }
        XCTAssertNil(slow.fuss)
    }

    func testStareHoldsTheClockThenResumesWithoutJumping() {
        var stare = IdleStare()
        stare.begin(at: 2)
        XCTAssertEqual(stare.time(2.5), 2, accuracy: 1e-9)
        XCTAssertTrue(stare.isStaring(at: 3))
        let end = 2 + IdleFussMath.stareLength
        XCTAssertEqual(stare.time(end), 2, accuracy: 1e-9)
        XCTAssertEqual(stare.time(end + 1), 3, accuracy: 1e-9)
        stare.begin(at: 10)
        XCTAssertEqual(stare.time(10.5), 10 - IdleFussMath.stareLength, accuracy: 1e-9)
    }

    func testShiverAndHeartSettle() {
        XCTAssertEqual(IdleFussMath.shiver(age: IdleFussMath.shiverLength), 0)
        XCTAssertNil(IdleFussMath.heart(age: IdleFussMath.heartLength))
        XCTAssertEqual(IdleFussMath.heart(age: 0.3)?.alpha ?? 0, 1, accuracy: 1e-9)
    }
}
