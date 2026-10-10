import SwiftUI

/// 선물 상자를 들고 오늘 화면으로 들어오는 캐릭터(SPEC §4.9). `CupView` 사진 칸 안에 그려 컵을 넘길 때 한 몸으로 민다.
/// 로슈는 화면 오른쪽 밖에서 걸어 들어와 잔 앞 바닥 가운데에 서고, 앉은 카인은 위에서 톡 떨어져 앉는다(2026-10-10 대표님).
/// 캐릭터를 누르면 뚜껑이 열리고 조각이 터지며 `onOpen`(상자 입구, 이 레이어 좌표)을 부른다. 그 밖을 누르면 `onMiss`.
///
/// 당 면은 로슈, 카페인 면은 카인 `gift-carry` 그림(둘 다 2026-10-09 원화).
struct GiftCarrierLayer: View {
    let side: CupSide
    let step: Int
    /// 움직여도 되는지. 옆 면이거나 컵을 넘기는 중이면 멈춘다(`IdleCharacterLayer`와 같은 이유).
    let isActive: Bool
    var onOpen: (CGPoint) -> Void = { _ in }
    var onMiss: (CGPoint) -> Void = { _ in }
    /// 이 레이어의 화면 자리. 열쇠 오버레이가 입구를 화면 좌표로 옮길 때 쓴다.
    var onFrame: (CGRect) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var pausedAt: Date?
    @State private var seed = UInt64.random(in: 0 ... UInt64.max)
    /// 누른 시각(이 레이어 시계). 한 번 열면 다시 누르지 않는다.
    @State private var openedAt: Double?

    var body: some View {
        GeometryReader { proxy in
            if let figure = GiftCarrierFigure(side: side, size: proxy.size) {
                let frozen = frozenTime
                let opened = Self.screenshotOpenTime(figure) ?? openedAt
                TimelineView(.animation(minimumInterval: nil, paused: frozen != nil || pausedAt != nil)) { timeline in
                    let t = frozen ?? (pausedAt ?? timeline.date).timeIntervalSince(start)
                    let blink = frozen == nil ? IdleMotion.blink(t: t, seed: seed) : 0
                    Canvas { context, _ in
                        figure.draw(in: context, t: t, blink: blink, openedAt: opened, instant: reduceMotion)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .global) { location in
                    let origin = proxy.frame(in: .global).origin
                    let local = CGPoint(x: location.x - origin.x, y: location.y - origin.y)
                    let t = frozenTime ?? (pausedAt ?? Date()).timeIntervalSince(start)
                    if openedAt == nil, figure.contains(local, t: t) {
                        openedAt = t
                        onOpen(figure.mouth(t: t))
                    } else if openedAt == nil {
                        onMiss(location)
                    }
                }
                .onAppear {
                    // CI 스크린샷(Debug `-giftOpenAt`): 누른 것처럼 연출을 시작시킨다.
                    if let at = Self.screenshotOpenTime(figure) {
                        onOpen(figure.mouth(t: at))
                    }
                }
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { onFrame($0) }
        .allowsHitTesting(isActive)
        // 컵 장면이 접근성 요소 하나라 여기는 숨긴다. 보이스오버는 컵 장면의 "선물 열기" 동작으로 연다(`TodayView`).
        .accessibilityHidden(true)
        .onChange(of: isActive, initial: true) { _, active in
            if active {
                if let pausedAt { start = start.addingTimeInterval(Date().timeIntervalSince(pausedAt)) }
                pausedAt = nil
            } else if pausedAt == nil {
                pausedAt = Date()
            }
        }
    }

    /// 멈춘 시각. 동작 줄이기면 들어온 뒤 선 모습, CI 스크린샷(Debug `-giftAt`·`-giftOpenAt`)이면 그 시각.
    private var frozenTime: Double? {
        #if DEBUG
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "giftOpenAt") != nil {
            return GiftCarrierFigure.screenshotOpenAt(side) + defaults.double(forKey: "giftOpenAt")
        }
        if defaults.object(forKey: "giftAt") != nil {
            return defaults.double(forKey: "giftAt")
        }
        #endif
        return reduceMotion ? GiftCarrierFigure.arriveEnd(side) + 0.5 : nil
    }

    /// CI 스크린샷(Debug `-giftOpenAt <누른 뒤 초>`)에서 누른 시각. 들어오고 1초 뒤에 누른 것으로 친다.
    private static func screenshotOpenTime(_ figure: GiftCarrierFigure) -> Double? {
        #if DEBUG
        if UserDefaults.standard.object(forKey: "giftOpenAt") != nil {
            return GiftCarrierFigure.screenshotOpenAt(figure.side)
        }
        #endif
        return nil
    }
}

/// 운반 캐릭터의 자리·배율(틀 크기가 같으면 매 프레임 같다). 그림은 소개·추이 걷기와 같은 무대 리그(`IntroRig`)를
/// 그 면 캐릭터의 오늘 화면 배율로 줄여 그린다. 잔 바닥 선은 그 면의 컵 것.
struct GiftCarrierFigure {
    let side: CupSide
    let painter: RigPainter
    let photo: IdlePhoto
    /// 기다리는 자리(발끝, pt).
    let base: CGPoint
    /// pt / 무대 px.
    let r: Double
    /// 화면 오른쪽 밖 출발점까지의 거리(pt). 로슈만 쓴다.
    let distance: Double

    static let delay = 0.6
    static let walkEnd = delay + 1.6
    /// 카인이 떨어지는 시간(가속, 시안 `design/proto/gift-open.html`).
    static let fallEnd = delay + 0.55

    /// 들어와 자리를 잡은 시각(착지 눌림까지).
    static func arriveEnd(_ side: CupSide) -> Double {
        side == .sugar ? walkEnd : fallEnd + 0.4
    }

    static func screenshotOpenAt(_ side: CupSide) -> Double {
        arriveEnd(side) + 1
    }

    init?(side: CupSide, size: CGSize) {
        let art = side == .sugar ? IntroRig.roshuGiftArt : IntroRig.kainGiftArt
        guard size.width > 0, size.height > 0, let painter = art else { return nil }
        let photo = IdlePhoto(slot: size)
        let scale: Double = photo.height * side.idleCast.scalePerPhotoHeight
        self.side = side
        self.painter = painter
        self.photo = photo
        r = scale / painter.scale
        // 카인은 발이 잔 앞 바닥선보다 9px(3x) 떠 보여 조금 더 내린다(대표님 2026-10-10).
        let dy: Double = side == .sugar ? 0.012 : 0.016
        base = photo.point(0.5, side.idleCast.bottom + dy)
        distance = Double(size.width) - Double(base.x) + painter.width * r
    }

    /// 자리에서 벗어난 거리(pt): 로슈는 오른쪽으로(걷기), 카인은 위로(떨어지기).
    private func offset(_ t: Double) -> (x: Double, y: Double) {
        switch side {
        case .sugar:
            return (IntroRig.entrance(t, Self.delay, Self.walkEnd, from: distance, to: 0).x, 0)
        case .caffeine:
            let height: Double = Double(base.y) + 20
            let fall: Double = Motion.seg(t, Self.delay, Self.fallEnd, Ease.power2In)
            return (0, -height * (1 - fall))
        }
    }

    private func frame(_ t: Double, openedAt: Double?, instant: Bool) -> IdleFrame {
        var m = IdleFrame()
        if side == .sugar {
            let walk = IntroRig.entrance(t, Self.delay, Self.walkEnd, from: distance, to: 0)
            IntroRig.roshuGiftWalk(&m, travelled: walk.travelled / r, moving: walk.moving)
        }
        let arrived = Self.arriveEnd(side)
        if t > arrived {
            RigMotion.breathe(&m, t: t - arrived, period: 3.4, amount: 0.012)
        }
        if let openedAt {
            m.limbs["lid"] = GiftOpeningTimeline.lidAngle(t - openedAt, instant: instant)
        }
        return m
    }

    /// 착지 눌림(로슈 걸음 끝, 카인 착지) + 누를 때 한 번 눌림. RigPainter 눌림 1 = 세로 8% 줄음.
    private func squash(_ t: Double, openedAt: Double?) -> Double {
        let land: Double =
            switch side {
            case .sugar: IntroRig.roshuSquash * RigMotion.bump(t, Self.walkEnd - 0.05, 0.28)
            case .caffeine: 1.75 * RigMotion.bump(t, Self.fallEnd, 0.18) - 0.5 * RigMotion.bump(t, Self.fallEnd + 0.15, 0.24)
            }
        let press: Double = openedAt.map { 0.6 * RigMotion.bump(t, $0, 0.2) } ?? 0
        return land + press
    }

    func draw(in context: GraphicsContext, t: Double, blink: Double, openedAt: Double?, instant: Bool) {
        let shift = offset(t)
        let m = frame(t, openedAt: openedAt, instant: instant)
        let x: Double = Double(base.x) + shift.x
        drawShadow(in: context, x: x, lift: -m.bodyDy * r - shift.y)
        var stage = context
        stage.translateBy(x: x, y: Double(base.y) + shift.y)
        stage.scaleBy(x: r, y: r)
        painter.draw(in: stage, base: .zero, m: m, squash: squash(t, openedAt: openedAt), blink: blink)
        if let openedAt, !instant {
            GiftOpeningTimeline.drawBits(in: context, at: mouth(t: t), o: t - openedAt, colors: Self.bitColors(side))
        }
    }

    /// 상자 입구 가운데(뚜껑 자른 선, pt). 조각과 열쇠가 여기서 나온다.
    func mouth(t: Double) -> CGPoint {
        guard let lid = painter.art.parts.first(where: { $0.name == "lid" }) else {
            return CGPoint(x: Double(base.x), y: Double(base.y) - painter.height * r * 0.6)
        }
        let shift = offset(t)
        let k: Double = painter.scale * r
        let x: Double = Double(base.x) + shift.x + (Double(lid.frame.midX) - Double(painter.art.bbox.midX)) * k
        let y: Double = Double(base.y) + shift.y + (Double(lid.pivot.y) - Double(painter.art.bbox.maxY)) * k
        return CGPoint(x: x, y: y)
    }

    /// 조각 색: 그 면 상자의 색 + 흰색(시안 값).
    private static func bitColors(_ side: CupSide) -> [Color] {
        let hex: [String] =
            switch side {
            case .sugar: ["#F6E56A", "#5DA9F0", "#FFFFFF", "#F2CF3F"]
            case .caffeine: ["#8FCB96", "#EDE8C9", "#FFFFFF", "#5FA868"]
            }
        return hex.map(IdleSprite.color(hex:))
    }

    /// 접지 그늘 하나. 몸이 들썩이거나 떨어지는 중이면 작고 옅어진다. 대기 자세 그림자(`IdleSprite`)와 같은 색.
    private func drawShadow(in context: GraphicsContext, x: Double, lift: Double) {
        let width: Double = painter.width * r * 0.7
        let height: Double = painter.width * r * 0.09
        let strength: Double = 1 - min(0.45, max(0, lift) / (6 * r))
        var shade = context
        shade.opacity = strength
        shade.translateBy(x: x, y: Double(base.y))
        shade.scaleBy(x: width * strength / 2, y: height * strength / 2)
        shade.fill(
            Path(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2)),
            with: .radialGradient(Self.contact, center: .zero, startRadius: 0, endRadius: 1)
        )
    }

    private static let contact = Gradient(stops: [
        .init(color: Color(red: 70 / 255, green: 56 / 255, blue: 60 / 255).opacity(0.8), location: 0),
        .init(color: Color(red: 70 / 255, green: 56 / 255, blue: 60 / 255).opacity(0.45), location: 0.4),
        .init(color: Color(red: 70 / 255, green: 56 / 255, blue: 60 / 255).opacity(0), location: 1),
    ])

    /// 화면 위 점이 시각 t의 캐릭터(상자 포함) 위인지. 손가락 여유 8pt.
    func contains(_ point: CGPoint, t: Double) -> Bool {
        let shift = offset(t)
        let w: Double = painter.width * r
        let h: Double = painter.height * r
        let box = CGRect(x: Double(base.x) + shift.x - w / 2, y: Double(base.y) + shift.y - h, width: w, height: h)
        return box.insetBy(dx: -8, dy: -8).contains(point)
    }
}
