import SwiftUI

/// 선물 상자를 들고 오늘 화면으로 들어오는 캐릭터(SPEC §4.9). `CupView` 사진 칸 안에 그려 컵을 넘길 때 한 몸으로 민다.
/// 로슈는 화면 오른쪽 밖에서 걸어 들어와 잔 앞 바닥 가운데에 서고, 앉은 카인은 위에서 톡 떨어져 앉는다(2026-10-10 대표님).
/// 캐릭터를 누르면 뚜껑이 열리고 조각이 터지며 `onOpen`(누른 시각, 이 레이어 시계)을 부른다. 그 밖을 누르면 `onMiss`.
///
/// 당 면은 로슈, 카페인 면은 카인 `gift-carry` 그림(둘 다 2026-10-09 원화).
struct GiftCarrierLayer: View {
    let side: CupSide
    let step: Int
    /// 움직여도 되는지. 옆 면이거나 컵을 넘기는 중이면 멈춘다(`IdleCharacterLayer`와 같은 이유).
    let isActive: Bool
    var onOpen: (Double) -> Void = { _ in }
    var onMiss: (CGPoint) -> Void = { _ in }
    /// 이 레이어의 화면 자리. 열쇠 오버레이가 이 크기로 입구를 다시 계산해 화면 좌표로 옮긴다.
    var onFrame: (CGRect) -> Void = { _ in }
    /// 거래 상자(SPEC §4.10)면 상자 위 병뚜껑 꼬리표에 쓸 가격. 거래 상자는 눌러도 뚜껑이 열리지 않는다.
    var tag: Int? = nil
    /// 거절해서 들어온 쪽으로 나가는 중(로슈는 걸어서, 카인은 위로 튀어 올라).
    var isLeaving = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var pausedAt: Date?
    @State private var seed = UInt64.random(in: 0 ... UInt64.max)
    /// 누른 시각(이 레이어 시계). 한 번 열면 다시 누르지 않는다.
    @State private var openedAt: Double?
    /// 나가기 시작한 시각(이 레이어 시계).
    @State private var leftAt: Double?

    var body: some View {
        GeometryReader { proxy in
            if let figure = GiftCarrierFigure(side: side, size: proxy.size) {
                let frozen = frozenTime
                let opened = Self.screenshotOpenTime(figure) ?? openedAt
                TimelineView(.animation(minimumInterval: nil, paused: frozen != nil || pausedAt != nil)) { timeline in
                    let t = frozen ?? (pausedAt ?? timeline.date).timeIntervalSince(start)
                    let blink = frozen == nil ? IdleMotion.blink(t: t, seed: seed) : 0
                    Canvas { context, _ in
                        figure.draw(
                            in: context, t: t, blink: blink, openedAt: tag == nil ? opened : nil, instant: reduceMotion,
                            tag: tag, leftAt: leftAt
                        )
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .global) { location in
                    let origin = proxy.frame(in: .global).origin
                    let local = CGPoint(x: location.x - origin.x, y: location.y - origin.y)
                    let t = frozenTime ?? (pausedAt ?? Date()).timeIntervalSince(start)
                    if openedAt == nil, leftAt == nil, figure.contains(local, t: t) {
                        openedAt = t
                        onOpen(t)
                    } else if openedAt == nil {
                        onMiss(location)
                    }
                }
                .onAppear {
                    // CI 스크린샷(Debug `-giftOpenAt`): 누른 것처럼 연출을 시작시킨다.
                    if let at = Self.screenshotOpenTime(figure) {
                        onOpen(at)
                    }
                }
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { onFrame($0) }
        .allowsHitTesting(isActive)
        // 컵 장면이 접근성 요소 하나라 여기는 숨긴다. 보이스오버는 컵 장면의 "선물 열기" 동작으로 연다(`TodayView`).
        .accessibilityHidden(true)
        .onChange(of: isLeaving, initial: true) { _, leaving in
            guard leaving, leftAt == nil else { return }
            leftAt = frozenTime ?? (pausedAt ?? Date()).timeIntervalSince(start)
        }
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

    /// 나가기 시작해서 화면 밖으로 다 나갈 때까지(초).
    static func leaveLength(_ side: CupSide) -> Double {
        side == .sugar ? 1.4 : 0.7
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
        // 잔 앞에 선 게 확실히 보이게 둘 다 사진 높이 .012 더 내렸다(대표님 2026-10-27 "공간감").
        let dy: Double = side == .sugar ? 0.024 : 0.028
        base = photo.point(0.5, side.idleCast.bottom + dy)
        distance = Double(size.width) - Double(base.x) + painter.width * r
    }

    /// 자리에서 벗어난 거리(pt): 로슈는 오른쪽으로(걷기), 카인은 위로(떨어지기).
    private func offset(_ t: Double, leftAt: Double?) -> (x: Double, y: Double) {
        if let leftAt { return leave(t - leftAt) }
        switch side {
        case .sugar:
            return (IntroRig.entrance(t, Self.delay, Self.walkEnd, from: distance, to: 0).x, 0)
        case .caffeine:
            let height: Double = Double(base.y) + 20
            let fall: Double = Motion.seg(t, Self.delay, Self.fallEnd, Ease.power2In)
            return (0, -height * (1 - fall))
        }
    }

    /// 나가는 길(나가기 시작한 뒤 o초). 로슈는 오른쪽 밖으로 걷고, 카인은 살짝 웅크렸다 위로 튀어 오른다.
    private func leave(_ o: Double) -> (x: Double, y: Double) {
        switch side {
        case .sugar:
            return (distance * Motion.seg(o, 0, Self.leaveLength(side), Ease.power2In), 0)
        case .caffeine:
            let height: Double = Double(base.y) + painter.height * r + 20
            return (0, -height * Motion.seg(o, 0.15, Self.leaveLength(side), Ease.power2In))
        }
    }

    private func frame(_ t: Double, openedAt: Double?, instant: Bool, leftAt: Double?) -> IdleFrame {
        var m = IdleFrame()
        if side == .sugar, let leftAt {
            IntroRig.roshuGiftWalk(&m, travelled: leave(t - leftAt).x / r, moving: 1)
            return m
        }
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
    private func squash(_ t: Double, openedAt: Double?, leftAt: Double?) -> Double {
        if let leftAt {
            return side == .caffeine ? 1.2 * RigMotion.bump(t - leftAt, 0.05, 0.2) : 0
        }
        let land: Double =
            switch side {
            case .sugar: IntroRig.roshuSquash * RigMotion.bump(t, Self.walkEnd - 0.05, 0.28)
            case .caffeine: 1.75 * RigMotion.bump(t, Self.fallEnd, 0.18) - 0.5 * RigMotion.bump(t, Self.fallEnd + 0.15, 0.24)
            }
        let press: Double = openedAt.map { 0.6 * RigMotion.bump(t, $0, 0.2) } ?? 0
        return land + press
    }

    func draw(
        in context: GraphicsContext, t: Double, blink: Double, openedAt: Double?, instant: Bool, tag: Int? = nil,
        leftAt: Double? = nil
    ) {
        let shift = offset(t, leftAt: leftAt)
        let m = frame(t, openedAt: openedAt, instant: instant, leftAt: leftAt)
        let x: Double = Double(base.x) + shift.x
        drawShadow(in: context, x: x, lift: -m.bodyDy * r - shift.y)
        var stage = context
        stage.translateBy(x: x, y: Double(base.y) + shift.y)
        stage.scaleBy(x: r, y: r)
        painter.draw(in: stage, base: .zero, m: m, squash: squash(t, openedAt: openedAt, leftAt: leftAt), blink: blink)
        if let openedAt, !instant {
            GiftOpeningTimeline.drawBits(in: context, at: mouth(t: t), o: t - openedAt, colors: Self.bitColors(side))
        }
        if let tag {
            drawTag(in: context, price: tag, at: mouth(t: t, leftAt: leftAt))
        }
    }

    /// 거래 상자 꼬리표(대표님 2026-10-25 "돼지꼬리 달린 꼬리표"): 상자 리본에서 꼬불꼬불한 끈이 나와
    /// 비스듬히 매달린 행택 구멍에 이어진다. 행택은 흰 바탕, 끈 쪽 끝이 뾰족하고, 안에 병뚜껑 기호 + 가격.
    /// 로슈는 오른쪽 위, 카인은 상자를 몸 왼쪽에 들어 얼굴을 안 가리게 왼쪽 위로 단다.
    /// 끈은 흰 테두리를 둘러 진한 커피 앞에서도 보이게 한다.
    private func drawTag(in context: GraphicsContext, price: Int, at mouth: CGPoint) {
        let dir: Double = side == .sugar ? 1 : -1
        let knot = CGPoint(x: Double(mouth.x), y: Double(mouth.y) - 4)
        let hole = CGPoint(x: Double(knot.x) + 22 * dir, y: Double(knot.y) - 24)
        let cord = Self.pigtail(from: knot, to: hole, loops: 3, radius: 4.5)
        context.stroke(cord, with: .color(.white), style: StrokeStyle(lineWidth: 3.4, lineCap: .round, lineJoin: .round))
        context.stroke(
            cord, with: .color(Color.ink.opacity(0.85)),
            style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round)
        )

        var symbol = context.resolve(Image(systemName: "seal.fill"))
        symbol.shading = .color(side == .sugar ? .roshuWhite : .caffeineAmber)
        var symbolEdge = context.resolve(Image(systemName: "seal.fill"))
        symbolEdge.shading = .color(.ink)
        let label = context.resolve(
            Text(verbatim: String(price)).font(AppFont.pretendardFixed(15, .extraBold)).foregroundColor(Color.ink)
        )
        let icon: Double = 14
        let gap: Double = 3
        let text = label.measure(in: CGSize(width: 100, height: 100))
        // 행택 좌표: 구멍이 원점, 몸통은 dir 쪽으로. 뾰족한 끝(-7)부터 어깨(5)까지가 끈 쪽 머리.
        let start: Double = 10
        let width: Double = start + icon + gap + Double(text.width) + 8
        let half: Double = (max(icon, Double(text.height)) + 8) / 2
        var tag = context
        tag.translateBy(x: hole.x, y: hole.y)
        tag.rotate(by: .degrees(14 * dir))
        var outline = Path()
        outline.addLines([
            CGPoint(x: -7 * dir, y: 0), CGPoint(x: 5 * dir, y: -half), CGPoint(x: width * dir, y: -half),
            CGPoint(x: width * dir, y: half), CGPoint(x: 5 * dir, y: half),
        ])
        outline.closeSubpath()
        var body = outline
        body.addEllipse(in: CGRect(x: -2.2, y: -2.2, width: 4.4, height: 4.4))
        var shadowed = tag
        shadowed.addFilter(.shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1))
        shadowed.fill(body, with: .color(.white), style: FillStyle(eoFill: true))
        // 모서리를 둥글게: 같은 흰색으로 바깥선을 굵게 한 번 더(구멍은 건드리지 않는다).
        tag.stroke(outline, with: .color(.white), style: StrokeStyle(lineWidth: 3, lineJoin: .round))
        tag.fill(body, with: .color(.white), style: FillStyle(eoFill: true))
        tag.stroke(
            Path(ellipseIn: CGRect(x: -2.2, y: -2.2, width: 4.4, height: 4.4)),
            with: .color(Color.ink.opacity(0.35)), lineWidth: 0.8
        )
        // 글자는 뒤집지 않는다. 왼쪽으로 단 행택도 기호 → 숫자 순서로 읽힌다.
        let left: Double = dir > 0 ? start : -width + 8
        let iconX: Double = left + icon / 2
        let iconRect = CGRect(x: iconX - icon / 2, y: -icon / 2, width: icon, height: icon)
        if side == .sugar {
            // 로슈 흰 병뚜껑은 흰 행택 위라 옅은 먹색 외곽선으로 모양을 잡는다(겹친 조각이 진해지지 않게 한 층에).
            var edgeLayer = tag
            edgeLayer.opacity = 0.45
            edgeLayer.drawLayer { e in
                for step in 0 ..< 16 {
                    let angle: Double = Double(step) / 16 * 2 * Double.pi
                    e.draw(symbolEdge, in: iconRect.offsetBy(dx: 1.1 * cos(angle), dy: 1.1 * sin(angle)))
                }
            }
        }
        tag.draw(symbol, in: iconRect)
        tag.draw(label, at: CGPoint(x: iconX + icon / 2 + gap + Double(text.width) / 2, y: 0))
    }

    /// 돼지꼬리 끈: a에서 b로 가며 고리를 `loops`번 감는다. 양 끝은 고리 없이 a·b에 정확히 닿는다.
    static func pigtail(from a: CGPoint, to b: CGPoint, loops: Double, radius: Double) -> Path {
        var path = Path()
        let steps = 80
        for i in 0 ... steps {
            let s: Double = Double(i) / Double(steps)
            let envelope: Double = max(0, sin(Double.pi * s)).squareRoot()
            let angle: Double = 2 * Double.pi * loops * s
            let x: Double = Double(a.x) + (Double(b.x) - Double(a.x)) * s + radius * envelope * sin(angle)
            let y: Double = Double(a.y) + (Double(b.y) - Double(a.y)) * s - radius * envelope * (1 - cos(angle))
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        return path
    }

    /// 상자 입구 가운데(뚜껑 자른 선, pt). 조각과 열쇠가 여기서 나온다.
    func mouth(t: Double, leftAt: Double? = nil) -> CGPoint {
        guard let lid = painter.art.parts.first(where: { $0.name == "lid" }) else {
            return CGPoint(x: Double(base.x), y: Double(base.y) - painter.height * r * 0.6)
        }
        let shift = offset(t, leftAt: leftAt)
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
        let shift = offset(t, leftAt: nil)
        let w: Double = painter.width * r
        let h: Double = painter.height * r
        let box = CGRect(x: Double(base.x) + shift.x - w / 2, y: Double(base.y) + shift.y - h, width: w, height: h)
        return box.insetBy(dx: -8, dy: -8).contains(point)
    }
}
