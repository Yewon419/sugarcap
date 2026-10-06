import SwiftUI

/// 추이 화면에 가끔 나오는 등장(2026-10-06 대표님): 로슈는 늦게 걸어 들어오고, 카인은 지면 끝줄 선에 거꾸로 매달린다.
/// 앱을 열 때처럼 추이를 열 때마다 하나씩 따로 뽑는다(각각 4번에 1번꼴). 동작 줄이기면 로슈는 처음부터 서 있다.
enum TrendEntrance {
    static let chance = 0.25
}

/// 로슈가 늦게 온다. 빈 벽 → 화면 옆에서 걸어 들어와 제자리에 서고 → 콩 뛰며 정면으로 돌아선다.
/// 걷기는 로슈카인 소개와 같은 리그·걸음(`IntroRig`, 무대 px)을 이 높이로 줄여 그린다.
/// 끝 그림이 서 있는 그림(`CastMember`)과 같은 자리·크기라 끝나고 바꿔 끼워도 티가 안 난다.
struct TrendWalkIn: View {
    let asset: String
    let height: CGFloat
    /// 화면 옆 밖에서 제자리까지(pt). 양수면 오른쪽에서 들어온다.
    let distance: CGFloat
    let start: Date
    /// Debug 스크린샷용으로 멈춘 시각(초).
    let frozenAt: Double?

    static let delay = 0.9
    static let walkEnd = delay + 1.5
    static let turnAt = walkEnd + 0.25
    static let turnLength = 0.3
    static let duration = turnAt + turnLength + 0.2

    /// 정면 그림(`character-roshu`) 안에서 몸이 차지하는 높이·발끝 자리(그림 높이 비율). 걷기 그림을 여기에 맞춘다.
    private static let figureHeight = 0.92
    private static let footY = 0.957
    /// 소개 무대에서 로슈 걷기 그림 높이(px).
    private static let stageHeight = 400.0
    private static let margin: CGFloat = 80

    var body: some View {
        Image(asset)
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .opacity(0)
            .overlay {
                TimelineView(.animation(minimumInterval: nil, paused: frozenAt != nil)) { timeline in
                    let u: Double = frozenAt ?? timeline.date.timeIntervalSince(start)
                    figure(u: u)
                }
            }
    }

    @ViewBuilder
    private func figure(u: Double) -> some View {
        let turn = Motion.seg(u, Self.turnAt, Self.turnAt + Self.turnLength)
        let lift: Double = 26 * sin(Double.pi * turn)
        if turn >= 0.5 {
            let land: Double = RigMotion.bump(u, Self.turnAt + Self.turnLength, 0.16)
            Image(asset)
                .resizable()
                .scaledToFit()
                .frame(height: height)
                .scaleEffect(x: 1 + 0.06 * land, y: 1 - 0.08 * land, anchor: .bottom)
                .offset(y: -lift)
        } else if u >= Self.delay {
            let side: CGFloat = abs(distance) + Self.margin
            Canvas { context, size in
                drawWalk(in: context, size: size, u: u, lift: lift)
            }
            .padding(.horizontal, -side)
            .padding(.vertical, -Self.margin)
        }
    }

    private func drawWalk(in context: GraphicsContext, size: CGSize, u: Double, lift: Double) {
        guard let painter = IntroRig.roshuWalkArt else { return }
        // pt / 무대 px
        let r: Double = Double(height) * Self.figureHeight / Self.stageHeight
        let walk = IntroRig.entrance(u, Self.delay, Self.walkEnd, from: Double(distance), to: 0)
        var m = IdleFrame()
        IntroRig.roshuWalk(&m, travelled: walk.travelled / r, moving: walk.moving)
        // 걷기 그림은 왼쪽을 본다. 왼쪽에서 들어오면 뒤집는다.
        m.flip = distance > 0 ? 1 : -1
        m.dy = -lift / r
        let footY: Double = Double(Self.margin) + Double(height) * Self.footY
        let squash: Double = IntroRig.roshuSquash * RigMotion.bump(u, Self.walkEnd - 0.05, 0.28)
        var stage = context
        let centerX: Double = Double(size.width) / 2 + walk.x
        stage.translateBy(x: centerX, y: footY)
        stage.scaleBy(x: r, y: r)
        painter.draw(in: stage, base: .zero, m: m, squash: squash, blink: 0)
    }
}

/// 카인이 지면 끝줄 선에 발을 걸고 거꾸로 매달려 정면을 본다. 정면 그림(rim-stand)을 발끝 기준으로 뒤집는다.
/// 천천히 흔들리며 숨 쉬고 깜빡인다. 누르면 크게 그네 타고, 이어서 다섯 번 누르면 더 세게 한 번 그네 탄다. 한 바퀴 회전은 넣지 않는다(대표님 2026-10-06).
/// 옆 면이거나 넘기는 중이면 멈춘다(CLAUDE.md: 매 프레임 그리는 뷰는 넘길 때 멈춘다). 멈춘 만큼 시계를 미뤄 이어서 흔들린다.
struct TrendHangingKain: View {
    let isActive: Bool
    /// 멈춘 시각(동작 줄이기 0, Debug 스크린샷). 있으면 흔들지 않고 누르기도 받지 않는다.
    let frozenAt: Double?

    /// 그림(다리 포함) 높이.
    static let height: CGFloat = 124
    /// 그림 틀 한 변. 발끝이 가운데이고 크게 그네 타도(±50도) 안 잘리게 높이의 두 배보다 크게 둔다.
    static let box: CGFloat = height * 2.3

    @State private var start = Date()
    @State private var pausedAt: Date? = Date()
    @State private var running = false
    @State private var tapAt: Date?
    @State private var lastTap: Date?
    @State private var combo = 0
    @State private var taps = 0
    /// 이번 그네 세기(도). 연타면 크다.
    @State private var kickStrength: Double = 26

    private static let painter: RigPainter? = {
        guard let bbox = IdleRig.arts["kain"]?["rim-stand"]?.bbox, bbox.height > 0 else { return nil }
        return RigPainter(
            character: "kain", art: "rim-stand", scale: Double(height) / Double(bbox.height),
            lidPad: CupSide.caffeine.idleCast.lidPad, limbDirection: ["leg_left": 0, "leg_right": 0]
        )
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: frozenAt != nil || !running)) { timeline in
            let now = timeline.date
            let t: Double = frozenAt ?? (pausedAt ?? now).timeIntervalSince(start)
            let sinceTap: Double? = frozenAt == nil ? tapAt.map { now.timeIntervalSince($0) } : nil
            Canvas { context, size in
                draw(in: context, size: size, t: t, sinceTap: sinceTap)
            }
        }
        .frame(width: Self.box, height: Self.box)
        .contentShape(Self.bodyShape)
        .onTapGesture(perform: poke)
        .allowsHitTesting(isActive && frozenAt == nil)
        .accessibilityHidden(true)
        .sensoryFeedback(trigger: taps) { _, _ in
            kickStrength > 26 ? .impact(weight: .heavy) : .impact(weight: .light)
        }
        // 넘긴 직후 스프링이 다 서기 전에 그리기 시작하면 따라오다 늦는다. 잠깐 기다렸다 움직인다.
        .task(id: isActive) {
            if isActive {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                if let pausedAt { start = start.addingTimeInterval(Date().timeIntervalSince(pausedAt)) }
                pausedAt = nil
                running = true
            } else {
                running = false
                if pausedAt == nil { pausedAt = Date() }
            }
        }
    }

    /// 누를 수 있는 곳: 발끝 아래로 매달린 몸.
    private static var bodyShape: Path {
        let width: CGFloat = height * 0.6
        return Path(CGRect(x: box / 2 - width / 2, y: box / 2 - 6, width: width, height: height + 12))
    }

    private func draw(in context: GraphicsContext, size: CGSize, t: Double, sinceTap: Double?) {
        guard let painter = Self.painter else { return }
        var m = IdleFrame()
        m.rot = 180 + Self.swing(t: t, sinceTap: sinceTap, strength: kickStrength)
        let blink: Double = frozenAt == nil ? IdleMotion.blink(t: t, seed: 14) : 0
        if frozenAt == nil { RigMotion.breathe(&m, t: t, period: 1.9, amount: 0.012) }
        let squash: Double = sinceTap.map { 0.8 * RigMotion.bump($0, 0, 0.18) } ?? 0
        // 발끝이 선을 조금 넘어 걸치게 2pt 올린다.
        let hook = CGPoint(x: size.width / 2, y: size.height / 2 - 2)
        painter.draw(in: context, base: hook, m: m, squash: squash, blink: blink)
    }

    /// 흔들림(도). 평소 ±4도로 느리게, 누르면 `strength`만큼 흔들렸다 잦아든다.
    static func swing(t: Double, sinceTap: Double?, strength: Double) -> Double {
        let idle: Double = 4 * sin(2 * Double.pi * t / 2.8)
        var kick: Double = 0
        if let a = sinceTap, a >= 0, a < 4 {
            kick = strength * exp(-1.4 * a) * sin(2 * Double.pi * a / 1.1)
        }
        return idle + kick
    }

    private func poke() {
        let now = Date()
        combo = PokeMath.combo(previous: combo, lastTap: lastTap, now: now)
        kickStrength = combo >= PokeMath.comboCount ? 44 : 26
        tapAt = now
        lastTap = now
        taps += 1
    }
}
