import SwiftUI

/// 줄 단위로 가려졌다 올라오는 글자(프로토타입 `.it-mask`). `reveal` 0→1이면 아래에서 올라오고,
/// `exit` 0→1이면 위로 빠진다. 줄 높이만큼만 보이게 자른다.
struct MaskLine: View {
    let text: String
    let font: Font
    /// 한 줄 높이(pt). 글자 크기 × 줄 간격.
    let lineHeight: CGFloat
    var color: Color = .primary
    var tracking: CGFloat = 0
    let reveal: Double
    var exit: Double = 0

    var body: some View {
        Text(text)
            .font(font)
            .tracking(tracking)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
            .frame(height: lineHeight, alignment: .bottomLeading)
            .offset(y: lineHeight * 1.08 * (1 - reveal) - lineHeight * 1.08 * exit)
            .frame(height: lineHeight, alignment: .topLeading)
            .clipped()
    }
}

/// 시각 표에 맞춰 할 일을 부르는 재생기. 그림은 `content(t)`가 그리고, `cues`는 [시각: 할 일]이다.
/// 화면을 다 덮은 순간 밑 화면을 바꾸는 것(`swap`)처럼 한 번만 해야 하는 일을 여기에 건다.
struct TimedPlayer<Content: View>: View {
    let duration: Double
    let cues: [(at: Double, action: @MainActor () -> Void)]
    /// 스크린샷용으로 한 시각에 멈춰 그린다(Debug 인자). 멈추면 신호는 그 시각까지 한꺼번에 부른다.
    var frozenAt: Double?
    @ViewBuilder let content: (Double) -> Content

    @State private var clock: ReelClock?

    var body: some View {
        TimelineView(.animation(paused: frozenAt != nil)) { context in
            content(frozenAt ?? clock?.time(at: context.date) ?? 0)
        }
        .task {
            let started = ReelClock(end: duration)
            clock = started
            if let frozenAt {
                for cue in cues where cue.at <= frozenAt { cue.action() }
                return
            }
            var elapsed = 0.0
            for cue in cues.sorted(by: { $0.at < $1.at }) {
                let wait = cue.at - elapsed
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                if Task.isCancelled { return }
                elapsed = cue.at
                cue.action()
            }
        }
    }
}

extension Color {
    /// 밤 장면 단색(에어브러시 없이, 대표님 교정 2026-09-26).
    static let nightSky = Color(red: 0x17 / 255, green: 0x22 / 255, blue: 0x39 / 255)
    static let wall = Color(red: 0xF3 / 255, green: 0xF5 / 255, blue: 0xF8 / 255)
    static let ink = Color(red: 0x14 / 255, green: 0x1A / 255, blue: 0x24 / 255)
    static let sugarPink = Color(red: 0xE0 / 255, green: 0x7A / 255, blue: 0x91 / 255)
    static let caffeineAmber = Color(red: 0xB8 / 255, green: 0x73 / 255, blue: 0x2F / 255)
    static let kainRing = Color(red: 0x3B / 255, green: 0x1D / 255, blue: 0x0E / 255)
    /// 먹색에서 흰색으로(밤이 되며 글자가 바뀔 때). `Color.mix`는 iOS 18부터라 직접 섞는다.
    static func ink(towardWhite k: Double) -> Color {
        Color(
            red: Motion.lerp(0x14 / 255, 1, k),
            green: Motion.lerp(0x1A / 255, 1, k),
            blue: Motion.lerp(0x24 / 255, 1, k)
        )
    }

    /// 밤 장면 소제목(프로토타입 `.kicker.light`).
    static let nightKicker = Color(red: 0xB9 / 255, green: 0xCF / 255, blue: 0xE4 / 255)
}
