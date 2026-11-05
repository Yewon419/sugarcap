import SwiftUI

/// 폭죽 한 번(대표님 2026-11-06 "스탬프로 보상 받았을 때 폭죽 팡"). 단색 조각이 퍼졌다가 떨어지며 사라진다.
/// 에어브러시(글로우·흐림·그라데이션) 없이 또렷한 면만. 동작 줄이기면 그리지 않는다. 다시 터뜨리려면 `.id`를 바꾼다.
struct ConfettiBurst: View {
    enum Size {
        /// 스탬프 한 칸.
        case small
        /// 잔·병뚜껑·얼리버드를 받을 때.
        case big
    }

    let size: Size

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: Double = 0

    private static let colors: [Color] = [
        .caffeineAmber,
        Color(red: 0.96, green: 0.42, blue: 0.53),
        Color(red: 0.33, green: 0.68, blue: 0.95),
        Color(red: 0.40, green: 0.80, blue: 0.52),
        Color(red: 0.99, green: 0.79, blue: 0.22),
        .ink,
    ]

    private var count: Int { size == .big ? 44 : 12 }
    private var duration: Double { size == .big ? 1.5 : 0.75 }

    var body: some View {
        ZStack {
            if !reduceMotion {
                ForEach(0 ..< count, id: \.self) { index in
                    piece(index)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(.linear(duration: duration)) { progress = 1 }
        }
    }

    private func piece(_ index: Int) -> some View {
        let a = Self.unit(index, salt: 1)
        let b = Self.unit(index, salt: 2)
        let c = Self.unit(index, salt: 3)
        let isBig = size == .big
        let angle: Double = (Double(index) / Double(count) + a * 0.12) * 2 * Double.pi
        let speed: Double = isBig ? 110 + b * 120 : 20 + b * 22
        let gravity: Double = isBig ? 170 : 26
        let spin: Double = (c - 0.5) * (isBig ? 900 : 540)
        let width: CGFloat = isBig ? 6 : 4
        let height: CGFloat = isBig ? 11 : 6
        let color = Self.colors[index % Self.colors.count]
        return Group {
            if index.isMultiple(of: 3) {
                Circle().fill(color).frame(width: width, height: width)
            } else {
                Rectangle().fill(color).frame(width: width, height: height)
            }
        }
        .modifier(ConfettiFlight(progress: progress, angle: angle, speed: speed, gravity: gravity, spin: spin))
    }

    /// 조각마다 고정된 0~1 값(매번 같은 모양으로 터진다).
    private static func unit(_ index: Int, salt: Int) -> Double {
        let mixed = (index * 7919 + salt * 104_729 + 13) % 997
        return Double(mixed) / 997
    }
}

/// 조각 하나의 궤적. 처음엔 빠르게 퍼지다 느려지고, 중력만큼 아래로 떨어지며 끝 30%에서 사라진다.
private struct ConfettiFlight: ViewModifier, Animatable {
    var progress: Double
    let angle: Double
    let speed: Double
    let gravity: Double
    let spin: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let p: Double = progress
        let spread: Double = 1 - (1 - p) * (1 - p)
        let x: Double = cos(angle) * speed * spread
        let y: Double = sin(angle) * speed * spread + gravity * p * p
        let fade: Double = p < 0.7 ? 1 : max(0, (1 - p) / 0.3)
        return content
            .rotationEffect(.degrees(spin * p))
            .offset(x: x, y: y)
            .opacity(fade)
    }
}
