import Foundation

/// 14칸 룰렛 시간표(대표님 2026-11-21 확정 시안 `design/proto/stamp-flow.html`). "돌리기"를 누른 때부터 잰다.
/// 릴 위치는 칸 단위(0 = 첫 방울, `stop` = 당첨 방울). 아슬아슬하게 멈춘다: ① 당첨 앞 방울에서 멈출 듯 느려지고
/// ② 당첨 방울로 기어 넘어간 뒤 ③ 다음 방울이 반쯤 올라와 흔들리며 버티다 ④ 못 넘고 당첨 칸으로 튕겨 돌아온다.
/// 당첨 뒤에는 방울이 창 밖으로 튀어나왔다 들어가고(팡), 흰 띠가 한 번 지나간 뒤 이름과 받기가 뜬다.
enum RouletteMotion {
    static let delay = 0.35
    static let fast = 3.4
    static let hold = 0.06
    static let crawl = 0.7
    static let wobble = 0.09
    static let settle = 0.4

    /// 멘트가 "뭐가 나올까"에서 "과연?"으로 바뀌는 시각.
    static let doubtAt = delay + fast + hold
    /// 릴이 당첨 칸에 앉는 시각.
    static let landAt = doubtAt + crawl + wobble * 2 + settle

    /// 앉은 뒤 팡: 0.34초에 1.6배로 커지며 10pt 떠오르고, 0.45초 머문 뒤 0.32초에 제자리로.
    static let popGrow = 0.34
    static let popHold = 0.45
    static let popBack = 0.32
    static let popEnd = popGrow + popHold + popBack
    /// 앉은 뒤 흰 띠가 지나가는 구간.
    static let shineStart = 1.4
    static let shineLength = 0.5
    /// 앉은 뒤 이름과 받기가 뜨는 시각.
    static let revealAt = 1.96

    static func reel(at t: Double, stop: Int) -> Double {
        let s = Double(stop)
        let t0 = delay
        let t1 = t0 + fast
        let t2 = t1 + hold
        let t3 = t2 + crawl
        let t4 = t3 + wobble
        let t5 = t4 + wobble
        if t < t1 { return Motion.lerp(0, s - 0.56, Motion.seg(t, t0, t1, Ease.power4Out)) }
        if t < t2 { return s - 0.56 }
        if t < t3 { return Motion.lerp(s - 0.56, s + 0.46, Motion.seg(t, t2, t3, Ease.power2InOut)) }
        if t < t4 { return Motion.lerp(s + 0.46, s + 0.41, Motion.seg(t, t3, t4, Ease.sineInOut)) }
        if t < t5 { return Motion.lerp(s + 0.41, s + 0.46, Motion.seg(t, t4, t5, Ease.sineInOut)) }
        return Motion.lerp(s + 0.46, s, Motion.seg(t, t5, landAt) { Ease.backOut($0, overshoot: 2.8) })
    }

    /// 창 가운데에 걸린 칸. 바뀔 때마다 걸쇠가 튕기고 틱 햅틱.
    static func cell(at position: Double) -> Int {
        Int((position + 0.5).rounded(.down))
    }

    /// 팡의 크기와 위로 뜬 거리(pt). `t`는 앉은 뒤 시각.
    static func pop(at t: Double) -> (scale: Double, rise: Double) {
        let grow = Motion.seg(t, 0, popGrow) { Ease.backOut($0, overshoot: 2.6) }
        let back = Motion.seg(t, popGrow + popHold, popEnd, Ease.power2InOut)
        let k = grow * (1 - back)
        return (1 + 0.6 * k, 10 * k)
    }

    /// 흰 띠 위치(0 = 방울 왼쪽 밖, 1 = 오른쪽 밖). 구간 밖이면 nil.
    static func shine(at t: Double) -> Double? {
        guard t >= shineStart, t <= shineStart + shineLength else { return nil }
        return Motion.seg(t, shineStart, shineStart + shineLength, Ease.power2InOut)
    }

    /// 걸쇠 기울기(도). 칸이 넘어간 순간 32도로 젖혔다가 0.2초에 돌아온다.
    static func flap(sinceTick age: Double) -> Double {
        32 * (1 - Motion.seg(age, 0, 0.2, Ease.power2Out))
    }

    /// 누르기 전 "돌리기" 두근거림. 0.45초에 1.06배까지 커졌다 돌아온다.
    static func pulse(at t: Double) -> Double {
        let phase = t.truncatingRemainder(dividingBy: 0.9) / 0.45
        let k = phase <= 1 ? Ease.sineInOut(phase) : Ease.sineInOut(2 - phase)
        return 1 + 0.06 * k
    }

    /// 이름·받기가 뜰 때 0.9배에서 튀어 오르는 크기. `t`는 뜬 뒤 시각.
    static func reveal(at t: Double) -> Double {
        0.9 + 0.1 * Motion.seg(t, 0, 0.3) { Ease.backOut($0, overshoot: 3) }
    }
}
