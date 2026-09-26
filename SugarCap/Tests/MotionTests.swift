import XCTest

@testable import SugarCap

final class EaseTests: XCTestCase {
    private let curves: [(String, (Double) -> Double)] = [
        ("power2In", Ease.power2In), ("power2Out", Ease.power2Out), ("power3In", Ease.power3In),
        ("power3Out", Ease.power3Out), ("power4Out", Ease.power4Out), ("power2InOut", Ease.power2InOut),
        ("power3InOut", Ease.power3InOut), ("sineInOut", Ease.sineInOut), ("expoInOut", Ease.expoInOut),
        ("backOut", { Ease.backOut($0) }),
    ]

    func testEveryCurveStartsAtZeroAndEndsAtOne() {
        for (name, curve) in curves {
            XCTAssertEqual(curve(0), 0, accuracy: 1e-9, name)
            XCTAssertEqual(curve(1), 1, accuracy: 1e-9, name)
        }
    }

    func testInOutCurvesAreHalfwayAtMidpoint() {
        XCTAssertEqual(Ease.power3InOut(0.5), 0.5, accuracy: 1e-9)
        XCTAssertEqual(Ease.expoInOut(0.5), 0.5, accuracy: 1e-9)
        XCTAssertEqual(Ease.sineInOut(0.5), 0.5, accuracy: 1e-9)
    }

    func testOutCurvesLeadAndBackOutOvershoots() {
        XCTAssertGreaterThan(Ease.power3Out(0.3), 0.3)
        XCTAssertLessThan(Ease.power2In(0.3), 0.3)
        let peak = stride(from: 0.0, through: 1.0, by: 0.01).map { Ease.backOut($0) }.max() ?? 0
        XCTAssertGreaterThan(peak, 1, "back.out은 목표를 살짝 넘었다 돌아온다")
    }
}

final class MotionSegmentTests: XCTestCase {
    func testSegmentClampsOutsideItsWindow() {
        XCTAssertEqual(Motion.seg(0.5, 1, 2), 0)
        XCTAssertEqual(Motion.seg(1.5, 1, 2), 0.5, accuracy: 1e-9)
        XCTAssertEqual(Motion.seg(3, 1, 2), 1)
    }

    func testDecayIsZeroBeforeAndOneAtTheHit() {
        XCTAssertEqual(Motion.decay(0.9, at: 1, rate: 9), 0)
        XCTAssertEqual(Motion.decay(1, at: 1, rate: 9), 1, accuracy: 1e-9)
        XCTAssertLessThan(Motion.decay(1.5, at: 1, rate: 9), 0.02)
    }
}

final class ReelChaptersTests: XCTestCase {
    // 로슈·카인 소개와 같은 배치(프로토타입 INTRO_CHAPTERS).
    private let chapters = ReelChapters(starts: [0, 2.6, 6.3, 9.9], end: 13.6)

    func testTapJumpsToNextChapterStartAndLastGoesToEnd() {
        XCTAssertEqual(chapters.next(after: 0.4), 2.6)
        XCTAssertEqual(chapters.next(after: 2.6), 6.3)
        XCTAssertEqual(chapters.next(after: 12), 13.6)
    }

    func testProgressBarsFillPerChapter() {
        XCTAssertEqual(chapters.progress(of: 0, at: 1.3), 0.5, accuracy: 1e-9)
        XCTAssertEqual(chapters.progress(of: 1, at: 1.3), 0)
        XCTAssertEqual(chapters.progress(of: 3, at: 20), 1)
    }
}

@MainActor
final class ReelClockTests: XCTestCase {
    func testClockRunsSeeksPausesAndStopsAtEnd() {
        let start = Date(timeIntervalSince1970: 1_000)
        let clock = ReelClock(end: 10, start: start)
        XCTAssertEqual(clock.time(at: start.addingTimeInterval(2)), 2, accuracy: 1e-9)

        clock.seek(to: 6, now: start.addingTimeInterval(2))
        XCTAssertEqual(clock.time(at: start.addingTimeInterval(3)), 7, accuracy: 1e-9)

        clock.pause(now: start.addingTimeInterval(3))
        XCTAssertEqual(clock.time(at: start.addingTimeInterval(30)), 7, accuracy: 1e-9, "멈춘 동안은 흐르지 않는다")

        clock.resume(now: start.addingTimeInterval(30))
        XCTAssertEqual(clock.time(at: start.addingTimeInterval(31)), 8, accuracy: 1e-9)
        XCTAssertTrue(clock.isFinished(at: start.addingTimeInterval(60)))
        XCTAssertEqual(clock.time(at: start.addingTimeInterval(60)), 10, "끝에서 멈춘다")
    }
}
