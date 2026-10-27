import XCTest

@testable import SugarCap

final class IdleFussTests: XCTestCase {
    func testHeartChanceStartsAtFivePercentOnLevelThreeAndGrows() {
        XCTAssertEqual(IdleFussMath.heartChance(level: 2), 0)
        XCTAssertEqual(IdleFussMath.heartChance(level: 3), 0.05, accuracy: 1e-9)
        XCTAssertEqual(IdleFussMath.heartChance(level: 10), 0.4, accuracy: 1e-9)
        XCTAssertEqual(IdleFussMath.pick(canDodge: false, canStare: true, level: 3, heartRoll: 0.04, otherRoll: 0), .heart)
        XCTAssertEqual(IdleFussMath.pick(canDodge: false, canStare: true, level: 3, heartRoll: 0.06, otherRoll: 0), .shiver)
        XCTAssertEqual(IdleFussMath.pick(canDodge: false, canStare: true, level: 2, heartRoll: 0, otherRoll: 0.99), .stare)
    }

    func testDodgeOnlyWhenThereIsSomewhereToGo() {
        let picks = Set(stride(from: 0.0, to: 1.0, by: 0.1).map {
            IdleFussMath.pick(canDodge: false, canStare: true, level: 1, heartRoll: 1, otherRoll: $0)
        })
        XCTAssertEqual(picks, [.shiver, .stare])
        XCTAssertEqual(IdleFussMath.pick(canDodge: true, canStare: true, level: 1, heartRoll: 1, otherRoll: 0.5), .dodge)
    }

    func testKainSkipsStareWhereStandingFrontWouldLookWrong() {
        XCTAssertTrue(IdleFussMath.canStare(character: "kain", pose: "swim"))
        XCTAssertFalse(IdleFussMath.canStare(character: "kain", pose: "lie-left"))
        XCTAssertFalse(IdleFussMath.canStare(character: "kain", pose: "bean-balance-left"))
        XCTAssertFalse(IdleFussMath.canStare(character: "kain", pose: "bean-balance-right"))
        XCTAssertTrue(IdleFussMath.canStare(character: "kain", pose: "rim-sit"))
        XCTAssertFalse(IdleFussMath.canStare(character: "roshu", pose: "in-cup"))
        XCTAssertFalse(IdleFussMath.canStare(character: "roshu", pose: "hug-strawberry"))
        XCTAssertFalse(IdleFussMath.canStare(character: "roshu", pose: "hug-strawberry-left"))
        XCTAssertTrue(IdleFussMath.canStare(character: "roshu", pose: "watch"))
        XCTAssertEqual(IdleFussMath.frontArt(character: "roshu", art: "watch"), "stand")
        XCTAssertEqual(IdleFussMath.frontArt(character: "roshu", art: "walk"), "stand")
        XCTAssertNil(IdleFussMath.frontArt(character: "roshu", art: "wave"))
        XCTAssertEqual(IdleFussMath.frontArt(character: "kain", art: "sit"), "rim-stand")
        XCTAssertNil(IdleFussMath.frontArt(character: "kain", art: "rim-stand"))
        XCTAssertFalse(IdleFussMath.canPoke(character: "kain", pose: "swim"), "잔 속 헤엄은 안 눌린다")
        XCTAssertFalse(IdleFussMath.canPoke(character: "kain", pose: "swim-front"))
        XCTAssertTrue(IdleFussMath.canPoke(character: "kain", pose: "sit"))
        XCTAssertTrue(IdleFussMath.canPoke(character: "roshu", pose: "in-cup"))
        let picks = Set(stride(from: 0.0, to: 1.0, by: 0.1).map {
            IdleFussMath.pick(canDodge: false, canStare: false, level: 1, heartRoll: 1, otherRoll: $0)
        })
        XCTAssertEqual(picks, [.shiver])
    }

    func testFifthQuickTapStartsAFussAndSlowTapsDoNot() {
        let base = Date(timeIntervalSince1970: 0)
        var quick = IdleFussState()
        for i in 0 ..< PokeMath.comboCount {
            quick = quick.poked(now: base.addingTimeInterval(Double(i) * 0.3), t: Double(i) * 0.3, candidate: .shiver)
            XCTAssertEqual(quick.fuss, i == PokeMath.comboCount - 1 ? .shiver : nil)
        }
        var slow = IdleFussState()
        for i in 0 ..< 8 {
            slow = slow.poked(now: base.addingTimeInterval(Double(i) * 1.0), t: Double(i), candidate: .shiver)
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
