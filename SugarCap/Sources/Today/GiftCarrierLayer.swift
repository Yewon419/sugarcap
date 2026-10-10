import SwiftUI

/// 선물 상자를 들고 오늘 화면으로 들어오는 캐릭터(SPEC §4.9). `CupView` 사진 칸 안에 그려 컵을 넘길 때 한 몸으로 민다.
/// 화면 오른쪽 밖에서 걸어 들어와 잔 앞 바닥 가운데에 서서 기다린다(들고 선 채, 내려놓기는 그림이 오면).
/// 캐릭터를 누르면 `onOpen`, 그 밖을 누르면 `onMiss`(오늘 화면은 컵 누르기로 받는다).
///
/// 당 면은 로슈, 카페인 면은 카인 `gift-carry` 그림(둘 다 2026-10-09 원화).
struct GiftCarrierLayer: View {
    let side: CupSide
    let step: Int
    /// 움직여도 되는지. 옆 면이거나 컵을 넘기는 중이면 멈춘다(`IdleCharacterLayer`와 같은 이유).
    let isActive: Bool
    var onOpen: () -> Void = {}
    var onMiss: (CGPoint) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var pausedAt: Date?
    @State private var seed = UInt64.random(in: 0 ... UInt64.max)

    var body: some View {
        GeometryReader { proxy in
            if let figure = GiftCarrierFigure(side: side, size: proxy.size) {
                let frozen = frozenTime
                TimelineView(.animation(minimumInterval: nil, paused: frozen != nil || pausedAt != nil)) { timeline in
                    let t = frozen ?? (pausedAt ?? timeline.date).timeIntervalSince(start)
                    let blink = frozen == nil ? IdleMotion.blink(t: t, seed: seed) : 0
                    Canvas { context, _ in
                        figure.draw(in: context, t: t, blink: blink)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .global) { location in
                    let origin = proxy.frame(in: .global).origin
                    let local = CGPoint(x: location.x - origin.x, y: location.y - origin.y)
                    let t = frozenTime ?? (pausedAt ?? Date()).timeIntervalSince(start)
                    if figure.contains(local, t: t) {
                        onOpen()
                    } else {
                        onMiss(location)
                    }
                }
            }
        }
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

    /// 멈춘 시각. 동작 줄이기면 걸어온 뒤 선 모습, CI 스크린샷(Debug `-giftAt`)이면 그 시각.
    private var frozenTime: Double? {
        #if DEBUG
        if UserDefaults.standard.object(forKey: "giftAt") != nil {
            return UserDefaults.standard.double(forKey: "giftAt")
        }
        #endif
        return reduceMotion ? GiftCarrierFigure.walkEnd + 0.5 : nil
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
    /// 화면 오른쪽 밖 출발점까지의 거리(pt).
    let distance: Double

    static let delay = 0.6
    static let walkEnd = delay + 1.6

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

    private func walk(_ t: Double) -> (x: Double, travelled: Double, moving: Double) {
        IntroRig.entrance(t, Self.delay, Self.walkEnd, from: distance, to: 0)
    }

    private func frame(_ t: Double) -> IdleFrame {
        let walk = walk(t)
        var m = IdleFrame()
        switch side {
        case .sugar: IntroRig.roshuGiftWalk(&m, travelled: walk.travelled / r, moving: walk.moving)
        case .caffeine: IntroRig.kainGiftWalk(&m, travelled: walk.travelled / r, moving: walk.moving)
        }
        if t > Self.walkEnd {
            RigMotion.breathe(&m, t: t - Self.walkEnd, period: 3.4, amount: 0.012)
        }
        return m
    }

    func draw(in context: GraphicsContext, t: Double, blink: Double) {
        let walk = walk(t)
        let m = frame(t)
        let x: Double = Double(base.x) + walk.x
        drawShadow(in: context, x: x, lift: -m.bodyDy * r)
        let squash: Double = IntroRig.roshuSquash * RigMotion.bump(t, Self.walkEnd - 0.05, 0.28)
        var stage = context
        stage.translateBy(x: x, y: Double(base.y))
        stage.scaleBy(x: r, y: r)
        painter.draw(in: stage, base: .zero, m: m, squash: squash, blink: blink)
    }

    /// 접지 그늘 하나. 몸이 들썩이면 작고 옅어진다. 대기 자세 그림자(`IdleSprite`)와 같은 색.
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
        let walk = walk(t)
        let w: Double = painter.width * r
        let h: Double = painter.height * r
        let box = CGRect(x: Double(base.x) + walk.x - w / 2, y: Double(base.y) - h, width: w, height: h)
        return box.insetBy(dx: -8, dy: -8).contains(point)
    }
}
