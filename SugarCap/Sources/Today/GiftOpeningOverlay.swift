import SwiftUI

/// 첫 선물 열림 연출의 시간표(SPEC §4.9, 시안 `design/proto/gift-open.html`). `o` = 상자를 누른 뒤 초.
/// 뚜껑이 기울며 열리고 → 조각이 터지고 → 열쇠가 떠올라 추이 버튼으로 날아가 돌고 → 버튼만 남기고 어두워진다.
/// 전부 `o`의 순수 함수다. 조각·뚜껑은 운반 레이어(사진 칸 안), 열쇠·어둠은 이 오버레이(화면 전체)가 그린다.
enum GiftOpeningTimeline {
    static let lidStart = 0.05
    static let lidLength = 0.42
    static let lidOpen = -38.0
    static let burstStart = 0.22
    static let burstLength = 1.1
    static let keyStart = 0.3
    static let keyRiseEnd = 0.8
    static let flightStart = 1.3
    static let flightLength = 0.75
    /// 열쇠가 버튼에 닿아 도는 때. 이때 연 것으로 저장한다.
    static let unlock = flightStart + flightLength
    static let ringPeriod = 1.1
    /// 어둠의 구멍 반지름(pt). 버튼 원(36)보다 조금 크다.
    static let holeRadius = 26.0
    static let dim = 0.58

    /// 뚜껑 각도(도, 음수 = 반시계). 동작 줄이기면 바로 열린 채.
    static func lidAngle(_ o: Double, instant: Bool) -> Double {
        if instant { return lidOpen }
        let k: Double = Motion.seg(o, lidStart, lidStart + lidLength) { Ease.backOut($0, overshoot: 2.2) }
        return lidOpen * k
    }

    /// 상자 입구에서 위로 튀어 중력으로 떨어지는 단색 조각 22개. 위치·회전은 번호로 정해진다(매 프레임 같음).
    static func drawBits(in context: GraphicsContext, at mouth: CGPoint, o: Double, colors: [Color]) {
        let t: Double = o - burstStart
        guard t > 0, t < burstLength, !colors.isEmpty else { return }
        let fade: Double = t < 0.8 ? 1 : max(0, 1 - (t - 0.8) / 0.3)
        for i in 0 ..< 22 {
            let bit = Bit(index: i)
            let x: Double = Double(mouth.x) + bit.vx * t
            let y: Double = Double(mouth.y) + bit.vy * t + 0.5 * 520 * t * t
            var piece = context
            piece.opacity = fade
            piece.translateBy(x: x, y: y)
            piece.rotate(by: .degrees(bit.spin * t))
            let rect = CGRect(x: -bit.width / 2, y: -bit.height / 2, width: bit.width, height: bit.height)
            let shape = bit.isRound ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 1)
            piece.fill(shape, with: .color(colors[i % colors.count]))
        }
    }

    private struct Bit {
        let vx: Double
        let vy: Double
        let spin: Double
        let width: Double
        let height: Double
        let isRound: Bool

        init(index i: Int) {
            let angle: Double = -Double.pi / 2 + (Self.noise(i, 1) - 0.5) * 1.9
            let speed: Double = 150 + Self.noise(i, 2) * 190
            vx = cos(angle) * speed
            vy = sin(angle) * speed
            spin = (Self.noise(i, 3) - 0.5) * 900
            isRound = i % 3 == 0
            width = isRound ? 6 : Double(5 + i % 4)
            height = isRound ? 6 : 8
        }

        /// 0..<1 고정 난수(번호·채널마다 같은 값).
        private static func noise(_ i: Int, _ channel: Int) -> Double {
            var x = UInt64(i * 7919 + channel * 104_729) &+ 0x9E37_79B9_7F4A_7C15
            x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
            x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
            x ^= x >> 31
            return Double(x % 10000) / 10000
        }
    }

    /// 열쇠의 자리·회전·크기·불투명도. 상자 입구에서 떠올라 한 번 흔들리고, 버튼까지 날아가 돌며 사라진다.
    static func key(_ o: Double, from: CGPoint, to: CGPoint) -> (point: CGPoint, angle: Double, scale: Double, opacity: Double) {
        guard o >= keyStart else { return (from, 0, 0, 0) }
        let fx = Double(from.x), fy = Double(from.y)
        let top: Double = fy - 48
        if o < flightStart {
            let rise: Double = Motion.seg(o, keyStart, keyRiseEnd) { Ease.backOut($0, overshoot: 1.6) }
            let y: Double = Motion.lerp(fy + 6, top, rise)
            let wiggle: Double = 14 * sin(Double.pi * Motion.seg(o, keyRiseEnd, flightStart, Ease.sineInOut))
            let angle: Double = Motion.lerp(-20, 8, rise) - wiggle
            return (CGPoint(x: fx, y: y), angle, Motion.lerp(0.4, 1, rise), 1)
        }
        let k: Double = Motion.seg(o, flightStart, unlock)
        let x: Double = Motion.lerp(fx, Double(to.x), Ease.power2InOut(k))
        let up: Double = top - 102
        let y: Double =
            k < 0.45
            ? Motion.lerp(top, up, Ease.power2Out(k / 0.45))
            : Motion.lerp(up, Double(to.y), Ease.power2In((k - 0.45) / 0.55))
        let turn: Double = Motion.seg(o, unlock, unlock + 0.22, Ease.power2InOut)
        let angle: Double = Motion.lerp(8, -30, k) + 90 * turn
        let gone: Double = Motion.seg(o, unlock + 0.3, unlock + 0.55)
        let scale: Double = Motion.lerp(1, 0.8, k) * (1 - 0.5 * gone)
        return (CGPoint(x: x, y: y), angle, scale, 1 - gone)
    }

    /// 어둠의 진하기(0~1). 열쇠가 닿으면 0.35초에 걸쳐 깔린다.
    static func spot(_ o: Double) -> Double { Motion.seg(o, unlock, unlock + 0.35) }

    /// 밝아진 버튼: 불투명도, 크기(한 번 톡).
    static func lit(_ o: Double) -> (opacity: Double, scale: Double) {
        (Motion.seg(o, unlock + 0.1, unlock + 0.3), 1 + 0.12 * RigMotion.bump(o, unlock + 0.25, 0.28))
    }

    /// 누르기를 부르는 링 맥박(1.1초마다, 1초 동안 퍼지며 사라짐). 반환: 배율(1 → 2.1), 불투명도.
    static func ring(_ o: Double) -> (scale: Double, opacity: Double)? {
        let since: Double = o - unlock - 0.4
        guard since >= 0 else { return nil }
        let phase: Double = RigMotion.remainder(since, ringPeriod)
        guard phase < 1 else { return nil }
        let k: Double = 1 - (1 - phase) * (1 - phase)
        return (1 + 1.1 * k, 0.9 * (1 - k))
    }
}

/// 첫 선물 연출 진행 상태(오늘 화면이 들고 있는다).
struct GiftOpening: Identifiable {
    let id = UUID()
    let gift: GiftEvent
    /// 상자 입구(화면 좌표). 보이스오버 "선물 열기"로 열면 없다(열쇠 없이 바로 어둠).
    let from: CGPoint?
    let startedAt: Date
    /// 열쇠가 닿아 연 것으로 저장됐는지. 그 뒤에만 버튼 구멍을 누를 수 있다.
    var isUnlocked = false
}

/// 열쇠 비행 + 추이 버튼만 남긴 어둠(SPEC §4.9). 화면 전체를 덮어 다른 누르기를 막고, 구멍(버튼)만 받는다.
/// 어둠은 또렷한 원 구멍 하나(그라데이션 없음, CLAUDE.md 모션 규칙).
struct GiftOpeningOverlay: View {
    let opening: GiftOpening
    /// 추이 버튼 자리(화면 좌표).
    let target: CGRect
    let onOpenTrends: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isInstant: Bool { reduceMotion || opening.from == nil }

    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            let center = CGPoint(x: target.midX - origin.x, y: target.midY - origin.y)
            let from = opening.from.map { CGPoint(x: $0.x - origin.x, y: $0.y - origin.y) } ?? center
            let frozen = Self.frozenTime
            ZStack {
                // 구멍 밖 누르기는 막기만 한다.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {}
                    .accessibilityHidden(true)
                TimelineView(.animation(minimumInterval: nil, paused: frozen != nil)) { timeline in
                    let o: Double = isInstant
                        ? GiftOpeningTimeline.unlock + 0.6
                        : (frozen ?? timeline.date.timeIntervalSince(opening.startedAt))
                    ZStack {
                        Canvas { context, size in
                            draw(in: context, size: size, o: o, from: from, center: center)
                        }
                        let lit = GiftOpeningTimeline.lit(o)
                        NavGlyphView(glyph: .trends)
                            .foregroundStyle(.primary)
                            .frame(width: 36, height: 36)
                            .background(.white, in: Circle())
                            .scaleEffect(lit.scale)
                            .opacity(lit.opacity)
                            .position(center)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                if opening.isUnlocked {
                    Button(action: onOpenTrends) {
                        Color.clear
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .position(center)
                    .accessibilityLabel("추이")
                    .accessibilityHint("추이가 열렸어요")
                    .accessibilityIdentifier("gift-open-trends")
                }
            }
        }
        .ignoresSafeArea()
    }

    private func draw(in context: GraphicsContext, size: CGSize, o: Double, from: CGPoint, center: CGPoint) {
        let spot = GiftOpeningTimeline.spot(o)
        if spot > 0 {
            var shade = Path(CGRect(origin: .zero, size: size))
            let r = GiftOpeningTimeline.holeRadius
            shade.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
            context.fill(shade, with: .color(.black.opacity(GiftOpeningTimeline.dim * spot)), style: FillStyle(eoFill: true))
        }
        if !isInstant, let ring = GiftOpeningTimeline.ring(o) {
            let r: Double = 18 * ring.scale
            let circle = Path(ellipseIn: CGRect(x: Double(center.x) - r, y: Double(center.y) - r, width: r * 2, height: r * 2))
            context.stroke(circle, with: .color(.white.opacity(ring.opacity)), lineWidth: 2)
        }
        guard !isInstant else { return }
        let key = GiftOpeningTimeline.key(o, from: from, to: center)
        guard key.opacity > 0, key.scale > 0 else { return }
        var image = context.resolve(Image(systemName: "key.fill"))
        image.shading = .color(Color.accentColor)
        // 긴 변 30pt(시안 열쇠 크기).
        let longest: Double = max(1, Double(max(image.size.width, image.size.height)))
        let fit: Double = 30 / longest * key.scale
        var symbol = context
        symbol.opacity = key.opacity
        symbol.translateBy(x: key.point.x, y: key.point.y)
        symbol.rotate(by: .degrees(key.angle))
        symbol.scaleBy(x: fit, y: fit)
        symbol.draw(image, at: .zero, anchor: .center)
    }

    /// CI 스크린샷(Debug `-giftOpenAt <누른 뒤 초>`)이면 그 시각에 멈춘다.
    static var frozenTime: Double? {
        #if DEBUG
        if UserDefaults.standard.object(forKey: "giftOpenAt") != nil {
            return UserDefaults.standard.double(forKey: "giftOpenAt")
        }
        #endif
        return nil
    }
}
