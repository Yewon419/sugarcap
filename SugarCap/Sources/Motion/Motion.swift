import Foundation
import Observation

/// 모션그래픽(온보딩 릴·로슈카인 소개·먹이기 전환) 공용 곡선. HTML 프로토타입(GSAP 3)과 같은 식이라
/// 프로토타입에서 맞춘 시각·곡선 이름을 그대로 옮겨 적으면 같은 움직임이 나온다.
/// GSAP 이름 대응: power1 = 2차, power2 = 3차, power3 = 4차, power4 = 5차.
enum Ease {
    static func linear(_ x: Double) -> Double { x }

    static func power2In(_ x: Double) -> Double { x * x * x }
    static func power2Out(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
    static func power3In(_ x: Double) -> Double { pow(x, 4) }
    static func power3Out(_ x: Double) -> Double { 1 - pow(1 - x, 4) }
    static func power4Out(_ x: Double) -> Double { 1 - pow(1 - x, 5) }

    static func power2InOut(_ x: Double) -> Double {
        x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
    }

    static func power3InOut(_ x: Double) -> Double {
        x < 0.5 ? 8 * pow(x, 4) : 1 - pow(-2 * x + 2, 4) / 2
    }

    static func power4InOut(_ x: Double) -> Double {
        x < 0.5 ? 16 * pow(x, 5) : 1 - pow(-2 * x + 2, 5) / 2
    }

    static func sineInOut(_ x: Double) -> Double { -(cos(Double.pi * x) - 1) / 2 }

    static func expoInOut(_ x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        return x < 0.5 ? pow(2, 20 * x - 10) / 2 : (2 - pow(2, -20 * x + 10)) / 2
    }

    /// GSAP `back.out(s)`. 기본 1.7.
    static func backOut(_ x: Double, overshoot s: Double = 1.70158) -> Double {
        let p = x - 1
        return 1 + (s + 1) * p * p * p + s * p * p
    }
}

enum Motion {
    static func clamp01(_ v: Double) -> Double { min(1, max(0, v)) }

    static func lerp(_ a: Double, _ b: Double, _ k: Double) -> Double { a + (b - a) * k }

    /// 시각 t가 [a, b] 구간에서 얼마나 왔는지 0~1, 곡선을 입혀서. 구간 전이면 0, 뒤면 1.
    static func seg(_ t: Double, _ a: Double, _ b: Double, _ ease: (Double) -> Double = Ease.linear) -> Double {
        guard b > a else { return t >= b ? 1 : 0 }
        return ease(clamp01((t - a) / (b - a)))
    }

    /// 튀어 올랐다 가라앉는 한 번의 흔들림. `at` 이후 지수로 줄어든다(물결·착지 반동).
    static func decay(_ t: Double, at: Double, rate: Double) -> Double {
        t < at ? 0 : exp(-(t - at) * rate)
    }
}

/// 장(chapter)으로 나뉜 릴. 화면을 누르면 다음 장 시작으로, 건너뛰기는 끝으로 간다.
struct ReelChapters: Equatable, Sendable {
    let starts: [Double]
    let end: Double

    init(starts: [Double], end: Double) {
        precondition(!starts.isEmpty && starts == starts.sorted() && (starts.last ?? 0) < end, "장 시작은 오름차순, 끝보다 앞")
        self.starts = starts
        self.end = end
    }

    func index(at t: Double) -> Int {
        starts.lastIndex(where: { t >= $0 }) ?? 0
    }

    /// 다음 장 시작. 마지막 장이면 끝.
    func next(after t: Double) -> Double {
        let i = index(at: t)
        return i + 1 < starts.count ? starts[i + 1] : end
    }

    /// 장 i의 진행 0~1(진행 막대).
    func progress(of i: Int, at t: Double) -> Double {
        let start = starts[i]
        let stop = i + 1 < starts.count ? starts[i + 1] : end
        return Motion.clamp01((t - start) / (stop - start))
    }
}

/// 릴의 시계. `TimelineView`가 주는 날짜를 릴 시각 t로 바꾼다. 끝에 닿으면 멈춘다.
/// 그림은 전부 t의 순수 함수로 그리므로, 되감기·건너뛰기가 시계 하나만 옮기면 끝난다.
@MainActor
@Observable
final class ReelClock {
    private var origin: Date
    private var pausedAt: Double?
    let end: Double

    init(end: Double, start: Date = .now) {
        self.end = end
        self.origin = start
    }

    func time(at date: Date) -> Double {
        min(end, pausedAt ?? date.timeIntervalSince(origin))
    }

    func isFinished(at date: Date) -> Bool {
        time(at: date) >= end
    }

    func seek(to t: Double, now: Date = .now) {
        let clamped = min(end, max(0, t))
        origin = now.addingTimeInterval(-clamped)
        if pausedAt != nil { pausedAt = clamped }
    }

    func pause(now: Date = .now) {
        pausedAt = time(at: now)
    }

    func resume(now: Date = .now) {
        guard let t = pausedAt else { return }
        pausedAt = nil
        origin = now.addingTimeInterval(-t)
    }
}
