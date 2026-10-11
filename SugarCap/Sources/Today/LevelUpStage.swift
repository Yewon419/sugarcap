import SwiftUI

/// 단계 상승 무대 연출의 시간표(SPEC §4.9 결정 4, 시안 `design/proto/levelup-stage.html`). `t` = 시작 뒤 초.
/// 화면이 어두워지고 → 위에서 연극 조명이 "딱" 떨어지고(깜빡 한 번) → 캐릭터가 폴짝 뛰며 팡파레 조각 두 발 →
/// 왼쪽에 세 줄 → 조명이 꺼지고 어둠이 걷힌다. 전부 `t`의 순수 함수다.
/// 에어브러시 없음(CLAUDE.md 모션 규칙): 조명은 가장자리가 또렷한 단색 반투명 원뿔 + 바닥 타원, 조각은 단색 면.
enum LevelUpTimeline {
    static let dimStart = 0.4
    static let dimLength = 0.3
    static let lightOn = dimStart + 0.45
    static let jump = lightOn + 0.35
    static let burst = jump + 0.3
    /// 오른쪽 발 쪽 두 번째 발.
    static let secondBurst = 0.12
    static let textIn = burst + 0.15
    static let lightOff = textIn + 2.0
    static let end = lightOff + 0.35
    static let dim = 0.66
    /// 점프 높이(캐릭터 키 대비, 시안 34pt / 로슈 92pt).
    static let jumpRatio = 0.37

    /// 동작 줄이기: 움직임 없이 어둠·조명·글자만 0.3초에 켜졌다가 꺼진다.
    static let calmHold = 2.6
    static let calmEnd = calmHold + 0.3

    static func duration(calm: Bool) -> Double { calm ? calmEnd : end }

    /// 어둠의 진하기(0~1).
    static func darkness(_ t: Double, calm: Bool) -> Double {
        if calm { return Motion.seg(t, 0, 0.3) * (1 - Motion.seg(t, calmHold, calmEnd)) }
        let fadeIn: Double = Motion.seg(t, dimStart, dimStart + dimLength, Ease.power2Out)
        let fadeOut: Double = Motion.seg(t, lightOff + 0.05, end)
        return fadeIn * (1 - fadeOut)
    }

    /// 조명 불투명도. 켜질 때 한 번 깜빡이고, 끝에 "딱" 꺼진다(서서히 밝아지지 않는다).
    static func light(_ t: Double, calm: Bool) -> Double {
        if calm { return darkness(t, calm: true) }
        if t < lightOn || t >= lightOff { return 0 }
        if t >= lightOn + 0.07, t < lightOn + 0.13 { return 0.25 }
        return 1
    }

    /// 글자: 불투명도, 위에서 내려오는 거리(pt).
    static func text(_ t: Double, calm: Bool) -> (opacity: Double, dy: Double) {
        if calm { return (darkness(t, calm: true), 0) }
        let k: Double = Motion.seg(t, textIn, textIn + 0.35, Ease.power3Out)
        let gone: Double = Motion.seg(t, lightOff - 0.1, lightOff + 0.1)
        return (k * (1 - gone), -16 * (1 - k))
    }

    /// 폴짝: 눌림 → 점프 → 착지 눌림 → 제자리. 반환: 뜬 정도(0~1, 키 × `jumpRatio`), RigPainter 눌림(1 = 세로 8% 줄음).
    /// 회전 없음(카인 360도 금지 규칙).
    static func hop(_ t: Double) -> (lift: Double, squash: Double) {
        let u: Double = t - jump
        if u < 0 { return (0, 0) }
        if u < 0.1 { return (0, 1.25 * Motion.seg(u, 0, 0.1)) }
        if u < 0.36 {
            let k: Double = Motion.seg(u, 0.1, 0.36, Ease.power2Out)
            return (k, Motion.lerp(1.25, -0.75, k))
        }
        if u < 0.58 {
            let k: Double = Motion.seg(u, 0.36, 0.58, Ease.power2In)
            return (1 - k, Motion.lerp(-0.75, 0, k))
        }
        if u < 0.66 { return (0, 1.5 * Motion.seg(u, 0.58, 0.66)) }
        let k: Double = Motion.seg(u, 0.66, 0.84) { Ease.backOut($0, overshoot: 2) }
        return (0, 1.5 * (1 - k))
    }

    /// 캐릭터 양옆 바닥에서 두 번 터지는 단색 조각 40개(폭죽 두 발). 위치·회전은 번호로 정해진다(매 프레임 같음).
    static func drawFanfare(in context: GraphicsContext, foot: CGPoint, height: Double, t: Double, colors: [Color]) {
        guard !colors.isEmpty else { return }
        for i in 0 ..< 40 {
            let bit = Bit(index: i)
            let delay: Double = bit.isLeft ? 0 : secondBurst
            let since: Double = t - burst - delay
            guard since > 0, since < 1.5 else { continue }
            let side: Double = bit.isLeft ? -1 : 1
            let ox: Double = Double(foot.x) + side * height * 0.75
            let oy: Double = Double(foot.y) - 6
            let drag: Double = 1 - 0.25 * since
            let x: Double = ox + bit.vx * since * drag
            let fall: Double = 0.5 * 560 * since * since
            let y: Double = oy + bit.vy * since + fall
            var piece = context
            piece.opacity = since < 1.15 ? 1 : max(0, 1 - (since - 1.15) / 0.35)
            piece.translateBy(x: x, y: y)
            piece.rotate(by: .degrees(bit.spin * since))
            let rect = CGRect(x: -bit.width / 2, y: -bit.height / 2, width: bit.width, height: bit.height)
            let shape = bit.kind == 0 ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 1)
            piece.fill(shape, with: .color(colors[i % colors.count]))
        }
    }

    /// 조각 색: 그 면 상자 색 + 흰색(시안 값).
    static func fanfareColors(_ side: CupSide) -> [Color] {
        let hex: [String] =
            switch side {
            case .sugar: ["#F6E56A", "#5DA9F0", "#FFFFFF", "#F2A7B8", "#F2CF3F"]
            case .caffeine: ["#8FCB96", "#EDE8C9", "#FFFFFF", "#5FA868", "#F2CF3F"]
            }
        return hex.map(IdleSprite.color(hex:))
    }

    private struct Bit {
        let isLeft: Bool
        let kind: Int
        let vx: Double
        let vy: Double
        let spin: Double
        let width: Double
        let height: Double

        init(index i: Int) {
            isLeft = i % 2 == 0
            kind = i % 4
            let lean: Double = isLeft ? -0.35 : 0.35
            let angle: Double = -Double.pi / 2 + lean + (Self.noise(i, 1) - 0.5) * 0.9
            let speed: Double = 260 + Self.noise(i, 2) * 170
            vx = cos(angle) * speed
            vy = sin(angle) * speed
            spin = (Self.noise(i, 3) - 0.5) * 1100
            switch kind {
            case 0:
                width = 6
                height = 6
            case 1:
                width = 3
                height = 13
            default:
                width = Double(5 + i % 3)
                height = 8
            }
        }

        /// 0..<1 고정 난수(번호·채널마다 같은 값).
        private static func noise(_ i: Int, _ channel: Int) -> Double {
            var x = UInt64(i * 6271 + channel * 92_821) &+ 0x9E37_79B9_7F4A_7C15
            x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
            x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
            x ^= x >> 31
            return Double(x % 10000) / 10000
        }
    }

    /// CI 스크린샷(Debug `-levelUpAt <초>`)이면 그 시각에 멈춘다.
    static var frozenTime: Double? {
        #if DEBUG
        if UserDefaults.standard.object(forKey: "levelUpAt") != nil {
            return UserDefaults.standard.double(forKey: "levelUpAt")
        }
        #endif
        return nil
    }
}

/// 진행 중인 단계 상승 연출(오늘 화면이 들고 있는다).
struct LevelUpStage: Identifiable {
    let id = UUID()
    let gift: GiftEvent
    let side: CupSide
    let level: Int
    let startedAt: Date
}

/// 무대에 선 캐릭터의 자리·배율. 잔 앞 바닥 가운데에 정면 그림(`IntroRig` stand)으로 선다. 운반 캐릭터와 같은 자리.
struct LevelUpFigure {
    let painter: RigPainter
    /// 발끝(pt, 사진 칸 좌표).
    let base: CGPoint
    /// pt / 무대 px.
    let r: Double

    init?(side: CupSide, size: CGSize) {
        let art = side == .sugar ? IntroRig.roshuStandArt : IntroRig.kainStandArt
        guard size.width > 0, size.height > 0, let painter = art else { return nil }
        let photo = IdlePhoto(slot: size)
        let scale: Double = photo.height * side.idleCast.scalePerPhotoHeight
        self.painter = painter
        r = scale / painter.scale
        let dy: Double = side == .sugar ? 0.012 : 0.016
        base = photo.point(0.5, side.idleCast.bottom + dy)
    }

    /// 캐릭터 키(pt).
    var height: Double { painter.height * r }

    func draw(in context: GraphicsContext, t: Double, blink: Double, calm: Bool) {
        let hop: (lift: Double, squash: Double) = calm ? (0, 0) : LevelUpTimeline.hop(t)
        let lift: Double = hop.lift * height * LevelUpTimeline.jumpRatio
        var m = IdleFrame()
        RigMotion.breathe(&m, t: t, period: 3.4, amount: 0.012)
        drawShadow(in: context, rise: hop.lift)
        var stage = context
        stage.translateBy(x: Double(base.x), y: Double(base.y) - lift)
        stage.scaleBy(x: r, y: r)
        painter.draw(in: stage, base: .zero, m: m, squash: hop.squash, blink: blink)
    }

    /// 접지 그늘. 뛰면 작고 옅어진다(운반 캐릭터와 같은 색·모양). `rise` = 뜬 정도 0~1.
    private func drawShadow(in context: GraphicsContext, rise: Double) {
        let width: Double = painter.width * r * 0.7
        let shadowHeight: Double = painter.width * r * 0.09
        let strength: Double = 1 - 0.45 * min(1, max(0, rise))
        var shade = context
        shade.opacity = strength
        shade.translateBy(x: Double(base.x), y: Double(base.y))
        shade.scaleBy(x: width * strength / 2, y: shadowHeight * strength / 2)
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
}

/// 무대에 선 캐릭터(`CupView` 사진 칸 안). 연출 동안 대기 자세 대신 이게 캐릭터다. 어둠·조명·글자는 `LevelUpStageOverlay`.
struct LevelUpStageLayer: View {
    let stage: LevelUpStage
    /// 이 레이어의 화면 자리. 오버레이가 이 크기로 발끝을 다시 계산해 조명을 맞춘다.
    var onFrame: (CGRect) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var seed = UInt64.random(in: 0 ... UInt64.max)

    var body: some View {
        GeometryReader { proxy in
            if let figure = LevelUpFigure(side: stage.side, size: proxy.size) {
                let frozen = LevelUpTimeline.frozenTime
                TimelineView(.animation(minimumInterval: nil, paused: frozen != nil)) { timeline in
                    let t = frozen ?? timeline.date.timeIntervalSince(stage.startedAt)
                    let blink = frozen == nil ? IdleMotion.blink(t: t, seed: seed) : 0
                    Canvas { context, _ in
                        figure.draw(in: context, t: t, blink: blink, calm: reduceMotion)
                    }
                }
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { onFrame($0) }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 어둠(조명 모양 구멍) + 조명 + 팡파레 + 세 줄(SPEC §4.9 결정 4). 화면 전체를 덮고, 아무 데나 누르면 건너뛴다.
/// 캐릭터는 어둠 아래 사진 칸에 있고 조명 구멍으로 보인다.
struct LevelUpStageOverlay: View {
    let stage: LevelUpStage
    /// 무대 캐릭터 레이어 자리(화면 좌표).
    let source: CGRect
    let onSkip: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 팡파레가 터질 때 성공 햅틱 한 번.
    @State private var didBurst = false

    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            let figure = LevelUpFigure(side: stage.side, size: source.size)
            let foot = figure.map {
                CGPoint(x: $0.base.x + source.minX - origin.x, y: $0.base.y + source.minY - origin.y)
            } ?? CGPoint(x: proxy.size.width / 2, y: proxy.size.height * 0.8)
            let height: Double = figure?.height ?? 90
            let frozen = LevelUpTimeline.frozenTime
            TimelineView(.animation(minimumInterval: nil, paused: frozen != nil)) { timeline in
                let t = frozen ?? timeline.date.timeIntervalSince(stage.startedAt)
                let text = LevelUpTimeline.text(t, calm: reduceMotion)
                ZStack(alignment: .topLeading) {
                    Canvas { context, size in
                        draw(in: context, size: size, t: t, foot: foot, height: height)
                    }
                    message
                        .opacity(text.opacity)
                        .offset(y: text.dy)
                        .padding(.leading, 24)
                        .padding(.top, 196)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onSkip)
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.line(stage).replacingOccurrences(of: "\n", with: " "))
        .accessibilityHint("눌러서 닫기")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onSkip() }
        .accessibilityIdentifier("levelup-stage")
        .sensoryFeedback(.success, trigger: didBurst) { _, new in new }
        .task {
            guard LevelUpTimeline.frozenTime == nil, !reduceMotion else { return }
            let wait: Double = LevelUpTimeline.burst - Date().timeIntervalSince(stage.startedAt)
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            if !Task.isCancelled { didBurst = true }
        }
    }

    /// 조명 밖(왼쪽)에 세 줄: 이름 / 사이 이름 / 됐어요.
    private var message: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("사이")
                .font(AppFont.pretendard(11, .semibold, relativeTo: .caption2))
                .tracking(1.3)
                .opacity(0.7)
            Text(Self.line(stage))
                .font(AppFont.pretendard(28, .bold, relativeTo: .title))
                .tracking(-0.5)
                .lineSpacing(7)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white)
        .frame(width: 250, alignment: .leading)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .allowsHitTesting(false)
    }

    static func line(_ stage: LevelUpStage) -> String {
        String(localized: "\(stage.side.characterNameWithGwa)\n\(AffinityMath.stageName(level: stage.level))가\n됐어요!")
    }

    private func draw(in context: GraphicsContext, size: CGSize, t: Double, foot: CGPoint, height: Double) {
        let calm = reduceMotion
        let footX = Double(foot.x)
        let footY = Double(foot.y)
        let poolRect = CGRect(x: footX - height * 0.95, y: footY - height * 0.2, width: height * 1.9, height: height * 0.4)
        let pool = Path(ellipseIn: poolRect)
        // 화면 오른쪽 위 밖(꼭짓점)에서 발밑 타원까지 비스듬히. 왼쪽 글자와 겹치지 않는다.
        let apexX: Double = Double(size.width) + 30
        let apexY: Double = -40
        var cone = Path()
        cone.move(to: CGPoint(x: apexX - 14, y: apexY))
        cone.addLine(to: CGPoint(x: apexX + 14, y: apexY))
        cone.addLine(to: CGPoint(x: Double(poolRect.maxX), y: footY))
        cone.addLine(to: CGPoint(x: Double(poolRect.minX), y: footY))
        cone.closeSubpath()

        let dark = LevelUpTimeline.darkness(t, calm: calm)
        if dark > 0 {
            var shade = context
            shade.clip(to: cone, options: .inverse)
            shade.clip(to: pool, options: .inverse)
            shade.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(LevelUpTimeline.dim * dark)))
        }
        let light = LevelUpTimeline.light(t, calm: calm)
        if light > 0 {
            let beam = Color(red: 1, green: 248 / 255, blue: 226 / 255)
            context.fill(cone, with: .color(beam.opacity(0.16 * light)))
            context.fill(pool, with: .color(beam.opacity(0.30 * light)))
        }
        if !calm {
            LevelUpTimeline.drawFanfare(
                in: context, foot: foot, height: height, t: t, colors: LevelUpTimeline.fanfareColors(stage.side)
            )
        }
    }
}
