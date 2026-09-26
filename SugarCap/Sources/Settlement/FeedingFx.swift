import SwiftUI

/// 먹이기 전환 모션그래픽(2026-09-26 HTML 프로토타입 `FEED_FX` 확정). 좌표는 프로토타입 폰(402×874) 비율로 잡아
/// 실제 화면 크기에 맞춘다. 단색 면·또렷한 선만 쓴다(에어브러시 금지, 대표님 교정).
enum FeedFx: Equatable {
    /// 마감 진입: 밤하늘이 지평선처럼 차오르고 달·별이 뜬 뒤 걷히며 밤 장면이 드러난다.
    case dusk(title: String)
    /// 로슈 → 카인: 버튼 자리에서 호박색이 번지고 카인이 튀어나온 뒤 카인 자리로 오므라든다.
    case turn
    /// 마무리: 밤하늘이 내려오고 두 방울이 합쳐져 흰 링과 별로 흩어진다.
    case night

    var duration: Double {
        switch self {
        case .dusk: return 1.8
        case .turn: return 1.85
        case .night: return 2.2
        }
    }

    /// 화면이 다 덮여 밑 화면을 바꿔도 되는 시각.
    var swapAt: Double {
        switch self {
        case .dusk: return 1.1
        case .turn: return 0.95
        case .night: return 1.35
        }
    }
}

struct FeedFxOverlay: View {
    let fx: FeedFx
    let t: Double
    let date: String

    private static let stars: [CGPoint] = [
        CGPoint(x: 46, y: 150), CGPoint(x: 330, y: 118), CGPoint(x: 262, y: 226), CGPoint(x: 104, y: 292),
        CGPoint(x: 356, y: 318), CGPoint(x: 30, y: 404), CGPoint(x: 190, y: 96), CGPoint(x: 300, y: 430),
    ]

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            // 프로토타입 폰 좌표 → 이 화면 좌표.
            let sx = size.width / 402
            let sy = size.height / 874
            switch fx {
            case .dusk(let title): dusk(title: title, size: size, sx: sx, sy: sy)
            case .turn: turn(size: size, sx: sx, sy: sy)
            case .night: night(size: size, sx: sx, sy: sy)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(true)
        .accessibilityHidden(true)
    }

    // MARK: - 마감 진입

    private func dusk(title: String, size: CGSize, sx: CGFloat, sy: CGFloat) -> some View {
        let seg = Motion.seg
        let rise = seg(t, 0, 0.6, Ease.power3InOut)
        let leave = seg(t, 1.25, 1.8, Ease.power3In)
        let skyHeight = size.height + 140
        let skyY = (1 - rise) * skyHeight - leave * skyHeight
        let moonK = seg(t, 0.15, 1.0, Ease.power3Out)
        let typeOut = seg(t, 1.15, 1.45, Ease.power3In)
        let small = seg(t, 0.4, 0.75, Ease.power2Out)

        return ZStack(alignment: .topLeading) {
            // 위아래가 둥근 하늘 한 장(지평선처럼 차오르고 그대로 걷힌다).
            RoundedRectangle(cornerRadius: 70, style: .continuous)
                .fill(Color.nightSky)
                .frame(width: size.width + 120, height: skyHeight)
                .offset(x: -60, y: -70)

            Circle()
                .fill(Color.wall)
                .frame(width: 64 * sx, height: 64 * sx)
                .scaleEffect(Motion.lerp(0.6, 1, moonK))
                .offset(x: 290 * sx, y: 190 * sy + Motion.lerp(300, 0, moonK) * sy)

            ForEach(Array(Self.stars.enumerated()), id: \.offset) { index, point in
                let k = seg(t, 0.45 + Double(index) * 0.05, 0.75 + Double(index) * 0.05) { Ease.backOut($0, overshoot: 3) }
                Circle()
                    .fill(.white)
                    .frame(width: 6, height: 6)
                    .scaleEffect(max(0, k))
                    .offset(x: point.x * sx, y: point.y * sy)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(date)
                    .font(AppFont.pretendardFixed(15, .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .opacity(small)
                    .offset(y: 8 * (1 - small))
                MaskLine(
                    text: title, font: AppFont.pretendardFixed(56, .extraBold), lineHeight: 64,
                    color: .white, tracking: AppFont.displayTracking(for: 56),
                    reveal: seg(t, 0.45, 1.0, Ease.power4Out)
                )
            }
            .offset(x: 24, y: 480 * sy - 40 * typeOut)
            .opacity(1 - typeOut)
        }
        .offset(y: skyY)
    }

    // MARK: - 로슈 → 카인

    private func turn(size: CGSize, sx: CGFloat, sy: CGFloat) -> some View {
        let seg = Motion.seg
        let grow = seg(t, 0, 0.6, Ease.expoInOut)
        let shrink = seg(t, 1.3, 1.85, Ease.expoInOut)
        let radius = 1000 * sy * grow * (1 - shrink)
        let center = CGPoint(x: size.width / 2, y: Motion.lerp(802, 662, shrink) * sy)
        let pop = seg(t, 0.42, 0.92) { Ease.backOut($0, overshoot: 1.7) }
        let drop = seg(t, 1.25, 1.7, Ease.power3In)
        let typeOut = seg(t, 1.25, 1.5, Ease.power3In)
        let small = seg(t, 0.32, 0.62, Ease.power2Out)

        return ZStack(alignment: .top) {
            Circle()
                .fill(Color.caffeineAmber)
                .frame(width: radius * 2, height: radius * 2)
                .position(center)

            VStack(spacing: 6) {
                Text("다음은")
                    .font(AppFont.pretendardFixed(15, .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .opacity(small)
                    .offset(y: 8 * (1 - small))
                MaskLine(
                    text: "카인 차례!", font: AppFont.pretendardFixed(56, .extraBold), lineHeight: 64,
                    color: .white, tracking: AppFont.displayTracking(for: 56),
                    reveal: seg(t, 0.36, 0.86, Ease.power4Out)
                )
            }
            .frame(maxWidth: .infinity)
            .offset(y: 200 * sy - 30 * typeOut)
            .opacity(1 - typeOut)

            Image(CupSide.caffeine.characterAsset)
                .resizable()
                .scaledToFit()
                .frame(height: 150)
                .rotationEffect(
                    .degrees(Motion.lerp(-25, 0, pop) + 360 * seg(t, 0.8, 1.3, Ease.power3InOut)),
                    anchor: UnitPoint(x: 0.5, y: 0.55)
                )
                .scaleEffect(Motion.lerp(0.4, 1, pop) * Motion.lerp(1, 0.55, drop))
                .opacity(min(1, max(0, pop * 2)) * (1 - seg(t, 1.62, 1.74, Ease.linear)))
                .offset(y: 360 * sy + Motion.lerp(140, 0, pop) + 250 * drop)
        }
    }

    // MARK: - 마무리

    private func night(size: CGSize, sx: CGFloat, sy: CGFloat) -> some View {
        let seg = Motion.seg
        let skyHeight = size.height + 140
        let down = seg(t, 0, 0.6, Ease.power3InOut)
        let fade = seg(t, 1.45, 1.95, Ease.power2InOut)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let merge = seg(t, 0.98, 1.26, Ease.power3In)
        let vanish = seg(t, 1.22, 1.34, Ease.power2In)
        let ring = seg(t, 1.22, 1.92, Ease.power2Out)
        let burst = seg(t, 1.24, 1.94, Ease.power3Out)
        let starsOut = seg(t, 1.6, 2.2, Ease.power2In)

        return ZStack(alignment: .topLeading) {
            UnevenRoundedRectangle(bottomLeadingRadius: 70, bottomTrailingRadius: 70, style: .continuous)
                .fill(Color.nightSky)
                .frame(width: size.width + 120, height: skyHeight)
                .offset(x: -60, y: -skyHeight * (1 - down) - 70 * down + 0)
                .opacity(1 - fade)

            ForEach(CupSide.allCases) { side in
                let sign: CGFloat = side == .sugar ? -1 : 1
                let enter = seg(t, side == .sugar ? 0.35 : 0.42, side == .sugar ? 0.9 : 0.97, Ease.power3Out)
                Image(side.dropAsset)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 76, height: 76)
                    .scaleEffect(Motion.lerp(0.4, 1, enter) * (1 - vanish))
                    .opacity(enter)
                    .position(
                        x: center.x + sign * Motion.lerp(Motion.lerp(150, 46, enter), 0, merge),
                        y: center.y + Motion.lerp(300, 0, enter)
                    )
            }

            Circle()
                .strokeBorder(.white, lineWidth: 3 / max(0.3, 1 + 6 * ring))
                .frame(width: 60, height: 60)
                .scaleEffect(t < 1.22 ? 0 : 1 + 6 * ring)
                .opacity(t < 1.22 ? 0 : 1 - ring)
                .position(center)

            ForEach(0..<14, id: \.self) { index in
                let angle = Double(index) / 14 * .pi * 2 + 0.3
                let distance = 120 + Double(index % 4) * 45
                Circle()
                    .fill(.white)
                    .frame(width: 6, height: 6)
                    .scaleEffect(t < 1.24 ? 0 : burst)
                    .opacity(1 - starsOut)
                    .position(
                        x: center.x + cos(angle) * distance * burst,
                        y: center.y + sin(angle) * distance * 1.3 * burst
                    )
            }
        }
    }
}
