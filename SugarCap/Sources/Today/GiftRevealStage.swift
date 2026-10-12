import SwiftUI

/// 상자에서 나온 것을 보여 주는 조명 무대(SPEC §4.9, 대표님 레퍼런스 2026-10-11 "팝업 대신 이런 연출").
/// 화면이 어두워지고 → 조명 두 개와 비스듬한 빛줄기가 화면을 훑고 → 가운데로 모여 "딱" 켜지며 물건이 드러나고
/// → 손그림 반짝이와 “ 이름 ” 캡션이 붙는다. 아무 데나 누르면 닫힌다(드러나기 전에 누르면 드러난 장면으로 건너뛴다).
/// 전부 `t`(시작 뒤 초)의 순수 함수다. 에어브러시 없음(CLAUDE.md 모션 규칙): 조명은 가장자리가 또렷한 단색 면.
enum GiftRevealTimeline {
    static let dimLength = 0.3
    static let searchStart = 0.45
    static let landStart = 1.6
    /// 조명이 물건에 모여 켜지는 때.
    static let land = 2.0
    static let captionIn = land + 0.3
    static let dim = 0.62
    /// 최종 조명 반지름(화면 폭 대비, 레퍼런스 300/923).
    static let spotRatio = 0.33
    /// 물건 자리(화면 비율, 레퍼런스 컵 가운데).
    static let centerY = 0.595

    /// 어둠의 진하기(0~1).
    static func darkness(_ t: Double, calm: Bool) -> Double {
        calm ? Motion.seg(t, 0, 0.3) : Motion.seg(t, 0, dimLength, Ease.power2Out)
    }

    /// 드러난 정도. 켜질 때 한 번 깜빡인다(서서히 밝아지지 않는다).
    static func lit(_ t: Double, calm: Bool) -> Double {
        if calm { return Motion.seg(t, 0, 0.3) }
        if t < land { return 0 }
        if t >= land + 0.06, t < land + 0.12 { return 0.25 }
        return 1
    }

    /// 훑는 조명 두 개(중심, 반지름). 착지 동안 가운데로 모이며 최종 크기가 된다.
    static func spots(_ t: Double, size: CGSize) -> [(center: CGPoint, radius: Double)] {
        guard t >= searchStart else { return [] }
        let w = Double(size.width)
        let h = Double(size.height)
        let u: Double = t - searchStart
        let gather: Double = Motion.seg(t, landStart, land, Ease.power3InOut)
        let target = CGPoint(x: w / 2, y: h * centerY)
        let finalRadius: Double = w * spotRatio
        let ax: Double = w * (0.5 + 0.36 * sin(2 * Double.pi * 0.62 * u + 0.6))
        let ay: Double = h * (0.42 + 0.24 * sin(2 * Double.pi * 0.41 * u + 2.2))
        let bx: Double = w * (0.5 + 0.34 * sin(2 * Double.pi * 0.52 * u + 3.6))
        let by: Double = h * (0.66 + 0.18 * sin(2 * Double.pi * 0.55 * u + 0.3))
        let a = CGPoint(x: Motion.lerp(ax, Double(target.x), gather), y: Motion.lerp(ay, Double(target.y), gather))
        let b = CGPoint(x: Motion.lerp(bx, Double(target.x), gather), y: Motion.lerp(by, Double(target.y), gather))
        return [
            (center: a, radius: Motion.lerp(w * 0.30, finalRadius, gather)),
            (center: b, radius: Motion.lerp(w * 0.25, finalRadius, gather)),
        ]
    }

    /// 훑는 동안 화면을 비스듬히 지나가는 빛줄기(레퍼런스 2번째 장). 모이기 시작하면 꺼진다.
    static func sweep(_ t: Double, size: CGSize) -> Path? {
        guard t >= searchStart, t < landStart else { return nil }
        let w = Double(size.width)
        let h = Double(size.height)
        let u: Double = Motion.seg(t, searchStart, landStart, Ease.sineInOut)
        let px: Double = Motion.lerp(w * 0.95, w * 0.25, u)
        let py: Double = Motion.lerp(h * 0.25, h * 0.7, u)
        let angle: Double = Motion.lerp(-36, -50, u) * Double.pi / 180
        let half: Double = w * 0.24
        let length: Double = h * 1.6
        let dx: Double = cos(angle)
        let dy: Double = sin(angle)
        let nx: Double = -dy * half
        let ny: Double = dx * half
        var band = Path()
        band.move(to: CGPoint(x: px - dx * length + nx, y: py - dy * length + ny))
        band.addLine(to: CGPoint(x: px + dx * length + nx, y: py + dy * length + ny))
        band.addLine(to: CGPoint(x: px + dx * length - nx, y: py + dy * length - ny))
        band.addLine(to: CGPoint(x: px - dx * length - nx, y: py - dy * length - ny))
        band.closeSubpath()
        return band
    }

    /// 드러난 뒤 화면 가장자리에서 조명으로 모이는 빛줄기 네 개(레퍼런스 1번째 장). 밑변 두 점(화면 비율).
    private static let beamBases: [(CGPoint, CGPoint)] = [
        (CGPoint(x: 0, y: 0.15), CGPoint(x: 0, y: 0.45)),
        (CGPoint(x: 1, y: 0.10), CGPoint(x: 1, y: 0.42)),
        (CGPoint(x: 0, y: 0.72), CGPoint(x: 0.25, y: 1)),
        (CGPoint(x: 1, y: 0.75), CGPoint(x: 0.8, y: 1)),
    ]

    static func beams(size: CGSize) -> [Path] {
        let w = Double(size.width)
        let h = Double(size.height)
        let cx: Double = w / 2
        let cy: Double = h * centerY
        let radius: Double = w * spotRatio * 0.92
        return beamBases.map { first, second in
            let ax: Double = Double(first.x) * w
            let ay: Double = Double(first.y) * h
            let bx: Double = Double(second.x) * w
            let by: Double = Double(second.y) * h
            let mx: Double = (ax + bx) / 2 - cx
            let my: Double = (ay + by) / 2 - cy
            let length: Double = max(1, (mx * mx + my * my).squareRoot())
            let px: Double = -my / length * radius
            let py: Double = mx / length * radius
            var beam = Path()
            beam.move(to: CGPoint(x: ax, y: ay))
            beam.addLine(to: CGPoint(x: bx, y: by))
            beam.addLine(to: CGPoint(x: cx - px, y: cy - py))
            beam.addLine(to: CGPoint(x: cx + px, y: cy + py))
            beam.closeSubpath()
            return beam
        }
    }

    /// 물건 밝기(0 = 어둠과 같은 진하기, 1 = 제 색). 훑는 조명이 지나가면 그만큼 밝아진다.
    static func itemLight(_ t: Double, size: CGSize, calm: Bool) -> Double {
        let shown: Double = lit(t, calm: calm)
        if calm || t >= land { return shown }
        let center = CGPoint(x: Double(size.width) / 2, y: Double(size.height) * centerY)
        var cover = 0.0
        for spot in spots(t, size: size) {
            let dx: Double = Double(spot.center.x - center.x)
            let dy: Double = Double(spot.center.y - center.y)
            let inside: Double = (spot.radius - (dx * dx + dy * dy).squareRoot()) / 24
            cover = max(cover, Motion.clamp01(inside))
        }
        return cover
    }

    /// 물건이 켜질 때 한 번 톡.
    static func itemScale(_ t: Double, calm: Bool) -> Double {
        calm ? 1 : 1 + 0.1 * RigMotion.bump(t, land + 0.02, 0.32)
    }

    /// 캡션: 불투명도, 아래에서 올라오는 거리(pt).
    static func caption(_ t: Double, calm: Bool) -> (opacity: Double, dy: Double) {
        if calm { return (Motion.seg(t, 0, 0.3), 0) }
        let k: Double = Motion.seg(t, captionIn, captionIn + 0.35, Ease.power3Out)
        return (k, 10 * (1 - k))
    }

    /// 손그림 반짝이(조명 반지름 단위 자리, 크기 pt, 동그라미 여부). 레퍼런스처럼 안팎에 흩어 둔다.
    private static let sparkles: [(x: Double, y: Double, size: Double, ring: Bool)] = [
        (0.62, -0.88, 26, true), (-0.82, -0.62, 15, false), (1.02, -0.35, 13, false),
        (-1.05, 0.22, 22, false), (0.98, 0.42, 18, false), (-0.2, -0.42, 22, true),
        (0.62, 0.86, 14, false), (-0.72, 0.9, 12, false), (1.18, 0.62, 16, false),
    ]

    /// 켜진 뒤 하나씩 톡 붙고, 천천히 반짝인다. 선은 또렷한 흰 선(번짐 없음).
    static func drawSparkles(in context: GraphicsContext, size: CGSize, t: Double, calm: Bool) {
        let cx: Double = Double(size.width) / 2
        let cy: Double = Double(size.height) * centerY
        let radius: Double = Double(size.width) * spotRatio
        for (index, sparkle) in sparkles.enumerated() {
            let start: Double = land + 0.05 + Double(index) * 0.05
            let pop: Double = calm ? Motion.seg(t, 0, 0.3) : Motion.seg(t, start, start + 0.3) { Ease.backOut($0, overshoot: 2.4) }
            guard pop > 0 else { continue }
            let twinkle: Double = calm ? 1 : 0.82 + 0.18 * sin(2 * Double.pi * (t / 1.6 + Double(index) * 0.37))
            let scale: Double = pop * twinkle
            let tilt: Double = (Double(index % 3) - 1) * 9
            var mark = context
            mark.translateBy(x: cx + sparkle.x * radius, y: cy + sparkle.y * radius)
            mark.rotate(by: .degrees(tilt))
            mark.scaleBy(x: scale, y: scale)
            let s: Double = sparkle.size
            var cross = Path()
            // 손으로 그은 것처럼 세로가 길고 가로는 한쪽으로 치우친다.
            cross.move(to: CGPoint(x: 0.04 * s, y: -0.62 * s))
            cross.addLine(to: CGPoint(x: -0.03 * s, y: 0.58 * s))
            cross.move(to: CGPoint(x: -0.42 * s, y: 0.02 * s))
            cross.addLine(to: CGPoint(x: 0.36 * s, y: -0.04 * s))
            if sparkle.ring {
                cross.addEllipse(in: CGRect(x: -0.24 * s, y: -0.26 * s, width: 0.48 * s, height: 0.52 * s))
            }
            mark.stroke(cross, with: .color(.white), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        }
    }

    /// CI 스크린샷(Debug `-giftRevealAt <초>`)이면 그 시각에 멈춘다.
    static var frozenTime: Double? {
        #if DEBUG
        if UserDefaults.standard.object(forKey: "giftRevealAt") != nil {
            return UserDefaults.standard.double(forKey: "giftRevealAt")
        }
        #endif
        return nil
    }
}

/// 무대에 올리는 물건 그림과 이름. 마음·병뚜껑은 기호 + 하얀 윤곽으로 확정(대표님 2026-10-12, 따로 그리지 않는다).
struct GiftRevealItem {
    let name: String
    let asset: String?
    let symbol: String
    let tint: Color

    init?(gift: GiftEvent) {
        guard let side = gift.cupSide, let payload = gift.payload else { return nil }
        let tint: Color = side == .sugar ? .sugarPink : .caffeineAmber
        if gift.isHeart {
            self.init(name: String(localized: "\(side.characterName)의 마음"), asset: nil, symbol: "heart.fill", tint: tint)
        } else if gift.isCap {
            self.init(name: String(localized: "병뚜껑"), asset: nil, symbol: "seal.fill", tint: tint)
        } else if payload == GiftContent.item("strawberry") {
            self.init(name: String(localized: "딸기"), asset: "gift-item-strawberry", symbol: "", tint: tint)
        } else {
            return nil
        }
    }

    private init(name: String, asset: String?, symbol: String, tint: Color) {
        self.name = name
        self.asset = asset
        self.symbol = symbol
        self.tint = tint
    }
}

/// 진행 중인 선물 무대(오늘 화면이 들고 있는다).
struct GiftReveal: Identifiable {
    let id = UUID()
    let gift: GiftEvent
    let startedAt: Date
}

/// 어둠 + 조명 + 물건 + 반짝이 + 캡션. 화면 전체를 덮고, 아무 데나 누르면 닫힌다.
struct GiftRevealOverlay: View {
    let reveal: GiftReveal
    /// 두 번째 마음부터(무료) 결제 줄을 붙인다(`GiftMath.offersPro`).
    let offersPro: Bool
    let onClose: () -> Void
    let onPro: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 드러나기 전에 누르면 드러난 장면으로 건너뛴 만큼(초).
    @State private var skipped = 0.0
    @State private var didLand = false

    private var item: GiftRevealItem? { GiftRevealItem(gift: reveal.gift) }

    var body: some View {
        let frozen = GiftRevealTimeline.frozenTime
        TimelineView(.animation(minimumInterval: nil, paused: frozen != nil)) { timeline in
            let t: Double = frozen ?? timeline.date.timeIntervalSince(reveal.startedAt) + skipped
            GeometryReader { proxy in
                let size = proxy.size
                let itemY: CGFloat = size.height * CGFloat(GiftRevealTimeline.centerY)
                let captionY: CGFloat = itemY + size.width * CGFloat(GiftRevealTimeline.spotRatio) + 60
                ZStack {
                    Canvas { context, canvasSize in
                        drawLights(in: context, size: canvasSize, t: t)
                    }
                    itemView(width: Double(size.width) * 0.27, t: t, size: size)
                        .position(x: size.width / 2, y: itemY)
                    Canvas { context, canvasSize in
                        GiftRevealTimeline.drawSparkles(in: context, size: canvasSize, t: t, calm: reduceMotion)
                    }
                    captionView(t: t)
                        .frame(width: size.width - 48)
                        .position(x: size.width / 2, y: captionY)
                }
                .contentShape(Rectangle())
                .onTapGesture { tap(at: t) }
            }
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gift-card")
        .sensoryFeedback(.success, trigger: didLand) { _, new in new }
        .task {
            guard frozen == nil, !reduceMotion else { return }
            let wait: Double = GiftRevealTimeline.land - Date().timeIntervalSince(reveal.startedAt)
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            if !Task.isCancelled { didLand = true }
        }
    }

    private func tap(at t: Double) {
        if !reduceMotion, t < GiftRevealTimeline.land {
            skipped += GiftRevealTimeline.land - t
            didLand = true
        } else {
            onClose()
        }
    }

    @ViewBuilder
    private func itemView(width: Double, t: Double, size: CGSize) -> some View {
        let light: Double = GiftRevealTimeline.itemLight(t, size: size, calm: reduceMotion)
        let dark: Double = GiftRevealTimeline.dim * GiftRevealTimeline.darkness(t, calm: reduceMotion) * (1 - light)
        Group {
            if let item, let asset = item.asset {
                Image(asset)
                    .resizable()
                    .scaledToFit()
            } else if let item {
                symbolView(item, width: width)
            }
        }
        .frame(width: width, height: width)
        .colorMultiply(Color(white: 1 - dark))
        .scaleEffect(GiftRevealTimeline.itemScale(t, calm: reduceMotion))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 마음·병뚜껑: 기호 + 하얀 윤곽(대표님 2026-10-12 "하얀 윤곽 붙여서 그냥 쓰자").
    /// 윤곽은 흰 기호를 둘레 16방향으로 조금씩 밀어 겹친 것이다. 흐림 없이 가장자리가 또렷하다(에어브러시 금지 규칙).
    private func symbolView(_ item: GiftRevealItem, width: Double) -> some View {
        let outline: Double = width * 0.035
        let symbol = Image(systemName: item.symbol).resizable().scaledToFit()
        return ZStack {
            ForEach(0 ..< 16, id: \.self) { step in
                let angle: Double = Double(step) / 16 * 2 * Double.pi
                symbol
                    .foregroundStyle(.white)
                    .offset(x: outline * cos(angle), y: outline * sin(angle))
            }
            symbol.foregroundStyle(item.tint)
        }
        .padding(width * 0.1)
    }

    @ViewBuilder
    private func captionView(t: Double) -> some View {
        let caption = GiftRevealTimeline.caption(t, calm: reduceMotion)
        VStack(spacing: 14) {
            Button(action: onClose) {
                HStack(alignment: .top, spacing: 10) {
                    Text(verbatim: "\u{201C}")
                        .font(AppFont.pretendardFixed(30, .regular))
                    Text(item?.name ?? "")
                        .font(AppFont.pretendard(24, .medium, relativeTo: .title2))
                        .padding(.top, 8)
                    Text(verbatim: "\u{201D}")
                        .font(AppFont.pretendardFixed(30, .regular))
                }
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item?.name ?? "")
            .accessibilityHint("눌러서 닫기")
            .accessibilityIdentifier("gift-confirm")
            if offersPro, reveal.gift.isHeart {
                Button(action: onPro) {
                    Text("이제 마음 말고 슬슬 다른 것도 받고 싶으시다고요?")
                        .underline()
                        .font(AppFont.pretendard(14, .semibold, relativeTo: .subheadline))
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("gift-pro")
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .opacity(caption.opacity)
        .offset(y: caption.dy)
        .allowsHitTesting(caption.opacity > 0.5)
    }

    /// 어둠은 한 장을 깔고 조명 자리를 도려낸다. 조명 원은 흰빛을 얹어 레퍼런스처럼 하얗게 바랜다.
    private func drawLights(in context: GraphicsContext, size: CGSize, t: Double) {
        let calm = reduceMotion
        let dark: Double = GiftRevealTimeline.darkness(t, calm: calm)
        guard dark > 0 else { return }
        let lit: Double = GiftRevealTimeline.lit(t, calm: calm)
        let center = CGPoint(x: Double(size.width) / 2, y: Double(size.height) * GiftRevealTimeline.centerY)
        let finalRadius: Double = Double(size.width) * GiftRevealTimeline.spotRatio
        let finalSpot = Path(ellipseIn: CGRect(
            x: Double(center.x) - finalRadius, y: Double(center.y) - finalRadius,
            width: finalRadius * 2, height: finalRadius * 2
        ))
        var spots: [Path] = []
        if lit > 0 || calm {
            spots = [finalSpot]
        } else {
            spots = GiftRevealTimeline.spots(t, size: size).map { spot in
                Path(ellipseIn: CGRect(
                    x: Double(spot.center.x) - spot.radius, y: Double(spot.center.y) - spot.radius,
                    width: spot.radius * 2, height: spot.radius * 2
                ))
            }
        }
        let beams: [Path] = lit > 0 ? GiftRevealTimeline.beams(size: size) : []
        let sweep: Path? = calm ? nil : GiftRevealTimeline.sweep(t, size: size)
        let spotOn: Double = calm || lit > 0 ? lit : 1

        context.drawLayer { layer in
            layer.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(GiftRevealTimeline.dim * dark)))
            layer.blendMode = .destinationOut
            if let sweep { layer.fill(sweep, with: .color(.black.opacity(0.5))) }
            for beam in beams { layer.fill(beam, with: .color(.black.opacity(0.45 * lit))) }
            for spot in spots { layer.fill(spot, with: .color(.black.opacity(spotOn))) }
        }
        // 두 원이 겹친 곳이 더 밝아지지 않게 합쳐서 한 번만 칠한다.
        var union = Path()
        for spot in spots { union.addPath(spot) }
        let wash: Double = lit > 0 ? 0.62 * lit : 0.5
        context.fill(union, with: .color(.white.opacity(wash * (calm ? lit : 1))), style: FillStyle(eoFill: false))
    }
}
