import SwiftUI

/// 로슈·카인 소개(2026-09-26 HTML 프로토타입 `screens-intro.js` 확정, SPEC §4.5). 첫 마감(먹이기) 직전에 한 번만 나온다.
/// 온보딩 마지막 질문 "오늘의 분량을 남기면 어디로 가냐고요...?"의 답이다.
/// 4장(문구 = 대표님): 오늘 남긴 만큼은/이 친구들에게 가요 → 달달한 걸 좋아하는 로슈! → 카페인을 좋아하는 카인!
/// → 많이많이 남겨서 두 친구와 더 가까워져요 → 밤 → "먹이러 가기".
/// v2(2026-10-01 `design/proto/intro-v2.html` 확정): 캐릭터는 대기 자세 리그(`RigPainter`)로 그린다. 걸어 들어오고 숨 쉬고 깜빡이며,
/// 크기는 오늘 화면 배율 비(카인 = 로슈 × 0.891), 카인은 회전 대신 갸웃 → 콩콩, 마지막 장에서 점프하며 정면으로 돈다.
/// 무대는 1080×1920 픽셀 좌표로 짜고 화면 높이에 맞춰 줄인다(온보딩 릴과 같은 방식). 그림은 전부 시각 t의 순수 함수다.
/// 화면을 누르면 다음 장, 건너뛰기는 끝(버튼 화면)으로.
struct CompanionIntroView: View {
    let onFinish: () -> Void
    /// 스크린샷용(Debug 인자). 이 시각에 멈춰 그린다.
    var frozenAt: Double?

    static let open = 2.6
    static let chapters = ReelChapters(starts: [0, open, open + 3.7, open + 7.3], end: open + 11)
    /// 밤으로 넘어가는 시각(소개 뒤 세 장 기준).
    private static let nightAt = 10.2

    @State private var clock = ReelClock(end: CompanionIntroView.chapters.end)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: frozenAt != nil)) { context in
            let t = frozenAt ?? clock.time(at: context.date)
            GeometryReader { proxy in
                let scale = proxy.size.height / 1920
                ZStack(alignment: .topLeading) {
                    IntroStage(t: t, scale: scale, blinks: frozenAt == nil)
                        .frame(width: 1080, height: 1920)
                        .scaleEffect(scale, anchor: .topLeading)
                        .offset(x: (proxy.size.width - 1080 * scale) / 2)
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                .clipped()
                .contentShape(Rectangle())
                .onTapGesture { clock.seek(to: Self.chapters.next(after: clock.time(at: Date()))) }
            }
            .ignoresSafeArea()
            // 무대만 화면 끝까지 깔고, 막대·버튼은 상태 바·홈 표시줄 안쪽에 둔다.
            .overlay(alignment: .top) { chrome(t: t) }
            .overlay(alignment: .bottom) { cta(t: t) }
        }
        .background(Color.wall)
        .onAppear {
            if reduceMotion { clock.seek(to: Self.chapters.end) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("로슈와 카인 소개. 남긴 당은 로슈가, 남긴 카페인은 카인이 먹어요. 많이 남길수록 더 가까워져요.")
    }

    /// 진행 막대 + 건너뛰기. 밤이 되면 흰색으로.
    private func chrome(t: Double) -> some View {
        let isNight = t >= Self.open + Self.nightAt + 0.3
        return VStack(alignment: .trailing, spacing: 0) {
            HStack(spacing: 5) {
                ForEach(0..<Self.chapters.starts.count, id: \.self) { index in
                    GeometryReader { bar in
                        Capsule().fill(isNight ? Color.white.opacity(0.22) : Color.ink.opacity(0.16))
                            .overlay(alignment: .leading) {
                                Capsule().fill(isNight ? Color.white : Color.ink)
                                    .frame(width: bar.size.width * Self.chapters.progress(of: index, at: t))
                            }
                    }
                    .frame(height: 3)
                }
            }
            Button("건너뛰기") { clock.seek(to: Self.chapters.end) }
                .font(AppFont.pretendard(14, .medium, relativeTo: .footnote))
                .foregroundStyle(isNight ? Color.white.opacity(0.8) : Color.ink.opacity(0.72))
                .tapTarget()
                .accessibilityIdentifier("intro-skip")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    /// 밤에 뜨는 버튼이라 흰 바탕에 진한 글자(남색 위 진한 버튼은 안 보인다, 대표님 2026-10-01). 마무리 요약 버튼과 같다.
    private func cta(t: Double) -> some View {
        let k = Motion.seg(t, Self.open + 10.45, Self.open + 10.9, Ease.power3Out)
        return Button(action: onFinish) {
            Text("먹이러 가기")
                .ctaLabel()
                .foregroundStyle(Color.ink)
                .background(Color.wall, in: Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
        .opacity(k)
        .offset(y: 20 * (1 - k))
        .allowsHitTesting(k > 0.5)
        .accessibilityIdentifier("intro-done")
    }
}

/// 1080×1920 무대. 좌표·시각은 프로토타입과 같다. 가로 위치는 무대 가운데(540) 기준, 세로는 윗변 기준.
private struct IntroStage: View {
    let t: Double
    /// 무대 → 화면 배율. 캐릭터 캔버스를 화면 해상도로 그리는 데 쓴다.
    let scale: Double
    /// 멈춘 스크린샷에선 깜빡이지 않는다.
    let blinks: Bool

    private static let open = CompanionIntroView.open
    private static let rain: [(x: Double, side: CupSide)] = [
        (-260, .sugar), (220, .caffeine), (-60, .sugar), (380, .caffeine), (-400, .sugar), (80, .caffeine), (-180, .sugar),
        (300, .caffeine), (-330, .sugar), (140, .caffeine), (-20, .sugar), (420, .caffeine), (-120, .sugar), (260, .caffeine),
    ]

    private func seg(_ a: Double, _ b: Double, _ ease: (Double) -> Double = Ease.linear) -> Double {
        Motion.seg(t, a, b, ease)
    }

    /// 뒤 세 장(소개 본편)의 시각. 첫 장 뒤에 이어 붙였다.
    private var u: Double { t - Self.open }

    private func useg(_ a: Double, _ b: Double, _ ease: (Double) -> Double = Ease.linear) -> Double {
        Motion.seg(u, a, b, ease)
    }

    private func blink(at time: Double, seed: UInt64) -> Double {
        blinks ? IdleMotion.blink(t: time, seed: seed) : 0
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.wall
            grid
            opener
            ripples
            chapterRoshu
                .offset(y: -700 * useg(3.65, 4.3, Ease.power4InOut))
            dropImage(.sugar, size: 220)
                .scaleEffect(x: sugarSquash.x, y: sugarSquash.y, anchor: .bottom)
                .scaleEffect(1 - useg(0.95, 1.25, Ease.power2In))
                .stagePosition(x: 0, top: Motion.lerp(-320, 1080, useg(0.1, 0.6, Ease.power2In)), height: 220)
            chapterKain
            chapterTogether
        }
        .frame(width: 1080, height: 1920)
    }

    // MARK: 공통

    private var grid: some View {
        ForEach([180.0, 360, 540, 720, 900], id: \.self) { x in
            Rectangle()
                .fill(Color.ink.opacity(0.1))
                .frame(width: x == 540 ? 2 : 1.2, height: 1920)
                .offset(x: x)
        }
    }

    private func dropImage(_ side: CupSide, size: CGFloat) -> some View {
        Image(side.dropAsset)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }

    private func maskedText(_ lines: [String], size: CGFloat, name: String?, revealAt: Double, hideAt: Double?, clock: Double,
                            accentLast: Bool, color: Color, nameColor: Color = .white, accent: Color = .accentColor) -> some View {
        let lineHeight = size * (name == nil && accentLast ? 1.2 : 1.14)
        let all = lines + (name.map { [$0] } ?? [])
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(all.enumerated()), id: \.offset) { index, line in
                let isName = name != nil && index == all.count - 1
                let reveal = Motion.seg(clock, revealAt + Double(index) * 0.09, revealAt + Double(index) * 0.09 + 0.6, Ease.power4Out)
                let exit = hideAt.map { Motion.seg(clock, $0 + Double(index) * 0.04, $0 + Double(index) * 0.04 + 0.3, Ease.power3In) } ?? 0
                let isAccent = accentLast && index == all.count - 1
                MaskLine(
                    text: line,
                    font: AppFont.pretendardFixed(isName ? 240 : size, isName ? .black : .extraBold),
                    lineHeight: isName ? 240 * 1.1 : lineHeight,
                    color: isName ? nameColor : (isAccent ? accent : color),
                    tracking: isName ? 0 : AppFont.displayTracking(for: size),
                    reveal: reveal, exit: exit
                )
                .padding(.top, isName ? 6 : 0)
            }
        }
        .offset(x: 150, y: 250)
    }

    // MARK: 첫 장 · 오늘 남긴 만큼은 이 친구들에게 가요

    private var opener: some View {
        let lines = [String(localized: "오늘 남긴 만큼은"), String(localized: "이 친구들에게 가요")]
        let reveal0 = seg(0.35, 0.95, Ease.power4Out)
        let reveal1 = seg(1.15, 1.75, Ease.power4Out)
        let exit0 = seg(2.05, 2.35, Ease.power3In)
        let exit1 = seg(2.09, 2.39, Ease.power3In)
        return ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                MaskLine(text: lines[0], font: AppFont.pretendardFixed(96, .extraBold), lineHeight: 96 * 1.2, color: .ink,
                         tracking: AppFont.displayTracking(for: 96), reveal: reveal0, exit: exit0)
                MaskLine(text: lines[1], font: AppFont.pretendardFixed(96, .extraBold), lineHeight: 96 * 1.2, color: .accentColor,
                         tracking: AppFont.displayTracking(for: 96), reveal: reveal1, exit: exit1)
            }
            .offset(x: 150, y: 250)

            ForEach(CupSide.allCases) { side in
                let isSugar = side == .sugar
                let popStart = isSugar ? 0.15 : 0.27
                let pop = seg(popStart, popStart + 0.5) { Ease.backOut($0, overshoot: 1.8) }
                let bobStart = isSugar ? 0.75 : 0.87
                let bob: Double = seg(bobStart, bobStart + 0.42, Ease.sineInOut) - seg(bobStart + 0.42, bobStart + 0.84, Ease.sineInOut)
                let leaveUp: Double = isSugar ? seg(2.1, 2.55, Ease.power3In) : 0
                let leaveRight: Double = isSugar ? 0 : seg(2.18, 2.63, Ease.power3In)
                let home: Double = isSugar ? -120 : 120
                let x: Double = home + 780 * leaveRight
                let top: Double = 1000 - 50 * bob - 1400 * leaveUp
                dropImage(side, size: 170)
                    .scaleEffect(max(0, pop))
                    .stagePosition(x: x, top: top, height: 170)
            }
        }
    }

    // MARK: 로슈

    private var sugarSquash: (x: Double, y: Double) {
        let squash = useg(0.6, 0.69, Ease.power2Out) - useg(0.69, 0.78, Ease.power2Out)
        return (1 + 0.3 * squash, 1 - 0.34 * squash)
    }

    private var ripples: some View {
        ForEach(0..<2, id: \.self) { index in
            let start = 0.6 + Double(index) * 0.1
            let k = useg(start, start + 0.9, Ease.power2Out)
            Circle()
                .strokeBorder(Color.sugarPink, lineWidth: 6)
                .frame(width: 400, height: 400)
                .scaleEffect(Motion.lerp(0.2, 2.6 + Double(index), k))
                .opacity(u < start ? 0 : 0.9 * (1 - k))
                .position(x: 540, y: 1190)
        }
    }

    /// 분홍 면이 번진 뒤 오른쪽에서 걸어 들어와 가운데 선다 → 멈추며 한 번 눌림 → 옆 지느러미 흔들어 인사.
    private var roshuFigures: [IntroRig.Figure] {
        guard u > 1.0, u < 4.5, let painter = IntroRig.roshuWalkArt else { return [] }
        let walk = IntroRig.entrance(u, 1.2, 2.25, from: 760, to: 0)
        var m = IdleFrame()
        IntroRig.roshuWalk(&m, travelled: walk.travelled, moving: walk.moving)
        let wave: Double = useg(2.4, 2.55) * (1 - useg(3.25, 3.45))
        let flap: Double = wave * 26 * sin(2 * Double.pi * (u - 2.4) / 0.32)
        m.limbs["flipper_side", default: 0] += flap
        if u > 2.3 { RigMotion.breathe(&m, t: u - 2.3, period: 1.6, amount: 0.018) }
        return [IntroRig.Figure(
            painter: painter, base: CGPoint(x: 540 + walk.x, y: 1540), frame: m,
            squash: IntroRig.roshuSquash * RigMotion.bump(u, 2.2, 0.28), blink: blink(at: u - 2.4, seed: 1)
        )]
    }

    private var chapterRoshu: some View {
        let radius = 2300 * useg(0.7, 1.45, Ease.expoInOut)
        let orbitOn = useg(2.35, 2.7, Ease.power3Out)

        return ZStack(alignment: .topLeading) {
            Circle()
                .fill(Color.sugarPink)
                .frame(width: radius * 2, height: radius * 2)
                .position(x: 540, y: 1190)

            // 뒤쪽 궤도 방울 → 로슈 → 앞쪽 궤도 방울
            orbit(front: false, on: orbitOn)
            IntroRigLayer(scale: scale, figures: roshuFigures)
            orbit(front: true, on: orbitOn)

            maskedText([String(localized: "달달한 걸"), String(localized: "좋아하는")], size: 150, name: String(localized: "로슈!"), revealAt: 1.05, hideAt: 3.45, clock: u,
                       accentLast: false, color: .ink)
        }
    }

    private func orbit(front: Bool, on: Double) -> some View {
        // 식을 쪼개 둔다. 한 줄에 몰면 컴파일러가 타입을 제때 못 푼다(CI 오류).
        ForEach(0..<3, id: \.self) { index in
            let angle: Double = (u - 2.35) * 3.1 + Double(index) * Double.pi * 2 / 3
            let depth: Double = sin(angle)
            let size: Double = max(0, on * (0.8 + 0.25 * depth))
            let x: Double = 360 * cos(angle)
            let top: Double = 1360 + 110 * depth - 55
            if (depth > 0) == front {
                dropImage(.sugar, size: 110)
                    .scaleEffect(size)
                    .stagePosition(x: x, top: top, height: 110)
            }
        }
    }

    // MARK: 카인

    /// 왼쪽에서 뒤뚱 걸어 들어와 오른쪽(방울 오는 쪽)을 본다 → 방울 꿀꺽(눌림) → 고개 갸웃 → 제자리 콩콩 두 번.
    private var kainFigures: [IntroRig.Figure] {
        guard u > 4.0, u < 7.4, let painter = IntroRig.kainWalkArt else { return [] }
        let walk = IntroRig.entrance(u, 4.15, 4.95, from: -780, to: 0)
        var m = IdleFrame()
        m.flip = -1
        IntroRig.kainWalk(&m, travelled: walk.travelled, moving: walk.moving)
        // 갸웃: 발밑 축으로 뒤로 젖힌다(5.5~5.78 기울고, 6.08까지 멈춤, 6.32에 돌아오며 살짝 넘침).
        let tiltIn: Double = useg(5.5, 5.78, Ease.power3Out)
        let tiltOut: Double = useg(6.08, 6.32) { Ease.backOut($0, overshoot: 2.2) }
        m.rot += 13 * tiltIn * (1 - tiltOut)
        var squash: Double = RigMotion.bump(u, 5.25, 0.22)
        var hopY = 0.0
        for start in [6.4, 6.74] {
            let k: Double = RigMotion.bump(u, start, 0.3)
            hopY += 95 * k
            m.limbs["leg_near", default: 0] += 20 * k
            m.limbs["leg_far", default: 0] -= 14 * k
            squash += RigMotion.bump(u, start - 0.06, 0.08) + RigMotion.bump(u, start + 0.3, 0.1)
        }
        m.dy = -hopY
        if u > 4.95 { RigMotion.breathe(&m, t: u - 4.95, period: 1.9, amount: 0.012) }
        return [IntroRig.Figure(
            painter: painter, base: CGPoint(x: 540 + walk.x, y: 1495), frame: m, squash: squash, blink: blink(at: u - 5.0, seed: 2)
        )]
    }

    private var chapterKain: some View {
        let cover = useg(3.65, 4.3, Ease.power4InOut)
        let bounce = useg(4.55, 5.25)
        let ring = useg(5.25, 5.8, Ease.power3Out)
        let caffeineScale: Double = u < 4.55 ? 0 : 1 - useg(5.15, 5.3)
        let caffeineX: Double = Motion.lerp(760, 0, bounce)
        let bounceHeight: Double = 520 * abs(sin(Double.pi * bounce * 2.5)) * (1 - bounce)
        let caffeineTop: Double = 1180 - bounceHeight

        return ZStack(alignment: .topLeading) {
            Color.caffeineAmber
                .frame(width: 1080, height: 1920)
                .offset(y: 1920 * (1 - cover))

            ZStack {
                Circle()
                    .trim(from: 0, to: ring)
                    .stroke(Color.kainRing, style: StrokeStyle(lineWidth: 40, lineCap: .round))
                    .frame(width: 640, height: 640)
                    .rotationEffect(.degrees(-90 + 140 * useg(5.25, 7.3, Ease.power3InOut)))
                    .opacity(ring > 0 ? 1 : 0)
                ForEach(0..<60, id: \.self) { index in
                    let long = index % 5 == 0
                    Capsule()
                        .fill(Color.kainRing)
                        .frame(width: long ? 6 : 3, height: long ? 40 : 22)
                        .offset(y: -(366 + (long ? 20 : 11)))
                        .rotationEffect(.degrees(Double(index) * 6))
                }
                .rotationEffect(.degrees(-(u - 5.25) * 30))
                .opacity(useg(5.3, 5.7))
            }
            .position(x: 540, y: 1290)

            IntroRigLayer(scale: scale, figures: kainFigures)

            dropImage(.caffeine, size: 170)
                .scaleEffect(caffeineScale)
                .stagePosition(x: caffeineX, top: caffeineTop, height: 170)

            // 라떼 무대라 흰 이름은 안 읽힌다(대비 약 1.7:1). 카인 링과 같은 진한 갈색으로.
            maskedText([String(localized: "카페인을"), String(localized: "좋아하는")], size: 150, name: String(localized: "카인!"), revealAt: 4.1, hideAt: 7.05, clock: u,
                       accentLast: false, color: .ink, nameColor: .kainRing)
        }
    }

    // MARK: 함께

    private static let hitDelay = 0.5

    /// 방울 비 받은 양(0~7)과 받을 때 튀는 정도(0~1).
    private var rainState: (gotSugar: Double, gotCaffeine: Double, hopSugar: Double, hopCaffeine: Double) {
        var gotSugar = 0.0, gotCaffeine = 0.0, hopSugar = 0.0, hopCaffeine = 0.0
        for (index, drop) in Self.rain.enumerated() {
            let at = 8.2 + Double(index) * 0.1
            let got = useg(at + Self.hitDelay, at + Self.hitDelay + 0.3, Ease.power3Out)
            let hop = Motion.decay(u, at: at + Self.hitDelay, rate: 9)
            if drop.side == .sugar { gotSugar += got; hopSugar += hop } else { gotCaffeine += got; hopCaffeine += hop }
        }
        return (gotSugar, gotCaffeine, min(1, hopSugar), min(1, hopCaffeine))
    }

    /// 마지막 장 두 캐릭터의 가로 자리(무대 가운데 기준). 방울 비가 이 자리로 날아간다.
    private var togetherX: (roshu: Double, kain: Double) {
        let rain = rainState
        let roshu = IntroRig.entrance(u, 7.45, 8.3, from: -1000, to: -225).x + 80 * rain.gotSugar / 7
        let kain = IntroRig.entrance(u, 7.5, 8.35, from: 1000, to: 245).x - 80 * rain.gotCaffeine / 7
        return (roshu, kain)
    }

    /// 둘이 양쪽에서 걸어 들어와 마주 본다 → 방울 받을 때마다 통 튀며 다가온다 →
    /// "처음 만난 사이"가 뜰 때 콩 뛰어 공중에서 정면으로 돈다(그림 교체를 점프 꼭대기에 숨긴다).
    private var togetherFigures: [IntroRig.Figure] {
        guard u > 7.3 else { return [] }
        let rain = rainState
        let x = togetherX
        let turnLength = 0.3
        func turnHop(_ at: Double) -> Double { RigMotion.bump(u, at, turnLength) }
        func landSquash(_ at: Double) -> Double { IntroRig.roshuSquash * RigMotion.bump(u, at + turnLength, 0.12) }
        var figures: [IntroRig.Figure] = []

        let roshuTurn = 9.66
        let roshuWalk = IntroRig.entrance(u, 7.45, 8.3, from: -1000, to: -225)
        var roshu = IdleFrame()
        let roshuFront = u >= roshuTurn + turnLength / 2
        if roshuFront {
            roshu.limbs["arm_left"] = 16 * rain.hopSugar
            roshu.limbs["arm_right"] = -16 * rain.hopSugar
        } else {
            roshu.flip = -1
            IntroRig.roshuWalk(&roshu, travelled: roshuWalk.travelled, moving: roshuWalk.moving)
            roshu.limbs["foot_back", default: 0] += 14 * rain.hopSugar
            roshu.limbs["foot_front", default: 0] += 14 * rain.hopSugar
            roshu.limbs["flipper_front", default: 0] += 6 * rain.hopSugar
        }
        roshu.dy = -(46 * rain.hopSugar + 70 * turnHop(roshuTurn))
        if u > 8.3 { RigMotion.breathe(&roshu, t: u - 8.3, period: 1.6, amount: 0.018) }
        if let painter = roshuFront ? IntroRig.roshuStandArt : IntroRig.roshuWalkArt {
            figures.append(IntroRig.Figure(
                painter: painter, base: CGPoint(x: 540 + x.roshu, y: 1530), frame: roshu,
                squash: landSquash(roshuTurn), blink: blink(at: u - 8.0, seed: 3)
            ))
        }

        let kainTurn = 9.72
        let kainWalk = IntroRig.entrance(u, 7.5, 8.35, from: 1000, to: 245)
        var kain = IdleFrame()
        let kainFront = u >= kainTurn + turnLength / 2
        if kainFront {
            kain.limbs["leg_left"] = 10 * rain.hopCaffeine
            kain.limbs["leg_right"] = -10 * rain.hopCaffeine
        } else {
            IntroRig.kainWalk(&kain, travelled: kainWalk.travelled, moving: kainWalk.moving)
            kain.limbs["leg_near", default: 0] += 16 * rain.hopCaffeine
            kain.limbs["leg_far", default: 0] -= 12 * rain.hopCaffeine
        }
        kain.dy = -(46 * rain.hopCaffeine + 70 * turnHop(kainTurn))
        if u > 8.35 { RigMotion.breathe(&kain, t: u - 8.35, period: 1.9, amount: 0.012) }
        if let painter = kainFront ? IntroRig.kainStandArt : IntroRig.kainWalkArt {
            figures.append(IntroRig.Figure(
                painter: painter, base: CGPoint(x: 540 + x.kain, y: 1530), frame: kain,
                squash: landSquash(kainTurn), blink: blink(at: u - 8.2, seed: 4)
            ))
        }
        return figures
    }

    private var chapterTogether: some View {
        let radius = 2300 * useg(7.25, 7.95, Ease.expoInOut)
        let hitDelay = Self.hitDelay
        let x = togetherX
        let roshuX = x.roshu
        let kainX = x.kain
        let night = useg(10.2, 11.0, Ease.power2InOut)
        let bondIn = useg(9.75, 10.25, Ease.power3Out)
        let textColor = Color.ink(towardWhite: night)

        return ZStack(alignment: .topLeading) {
            Circle()
                .fill(Color.wall)
                .frame(width: radius * 2, height: radius * 2)
                .position(x: 540, y: 1250)
            Color.nightSky
                .frame(width: 1080, height: 1920)
                .opacity(night)

            ForEach(Array(Self.rain.enumerated()), id: \.offset) { index, drop in
                let at: Double = 8.2 + Double(index) * 0.1
                let k: Double = useg(at, at + hitDelay, Ease.power2In)
                let target: Double = drop.side == .sugar ? roshuX : kainX
                let grow: Double = useg(at, at + 0.12, Ease.power3Out)
                let fade: Double = 1 - useg(at + hitDelay - 0.06, at + hitDelay + 0.04)
                let scale: Double = u < at ? 0 : grow * fade
                let landing: Double = drop.side == .sugar ? 1200 : 1240
                let arc: Double = 260 * sin(Double.pi * k)
                let x: Double = Motion.lerp(drop.x * 0.8, target, k)
                let top: Double = Motion.lerp(780, landing, k) - arc
                dropImage(drop.side, size: 96)
                    .scaleEffect(scale)
                    .stagePosition(x: x, top: top, height: 96)
            }

            IntroRigLayer(scale: scale, figures: togetherFigures)

            maskedText([String(localized: "많이많이 남겨서"), String(localized: "두 친구와"), String(localized: "더 가까워져요")], size: 96, name: nil, revealAt: 7.85, hideAt: nil, clock: u,
                       accentLast: true, color: textColor, accent: textColor)

            VStack(spacing: 26) {
                Text("처음 만난 사이")
                    .font(AppFont.pretendardFixed(54, .extraBold))
                    .tracking(AppFont.displayTracking(for: 54))
                    .foregroundStyle(textColor)
                GeometryReader { bar in
                    Capsule().fill(Color(white: 0.5, opacity: 0.3))
                        .overlay(alignment: .leading) {
                            // 강조색(진한 잉크)은 밤 남색에 묻힌다. 글자와 같이 흰색으로 넘어간다.
                            Capsule().fill(textColor)
                                .frame(width: bar.size.width * 0.1 * useg(9.95, 10.75, Ease.power3Out))
                        }
                }
                .frame(height: 14)
            }
            .frame(width: 600)
            .opacity(bondIn)
            .stagePosition(x: 0, top: 1590 + 30 * (1 - bondIn), height: 120)
        }
    }
}

/// 소개 무대의 리그 캐릭터(시안 `intro-v2.html`과 같은 조각·축·방향). 단위는 무대 픽셀.
enum IntroRig {
    struct Figure {
        let painter: RigPainter
        let base: CGPoint
        let frame: IdleFrame
        let squash: Double
        let blink: Double
    }

    /// 로슈 걷기 그림 높이(무대 px). 정면 그림도 같은 높이로 맞춘다(캔버스 크기가 달라서).
    private static let roshuHeight = 400.0
    private static let roshuPx = CupSide.sugar.idleCast.scalePerPhotoHeight
    private static let kainPx = CupSide.caffeine.idleCast.scalePerPhotoHeight

    /// 무대 배율 = 로슈 높이 400 기준. 카인은 오늘 화면 배율 비(× 0.891)를 따른다.
    private static let roshuScale: Double = scale(fitting: "walk", of: "roshu")
    private static let kainScale: Double = roshuScale * kainPx / roshuPx
    /// 오늘 화면 대비 무대 배율(걷기 발 들기·내딛기 pt를 키울 때 쓴다).
    private static let stageK: Double = roshuScale / (IdlePhoto.referenceHeight * roshuPx)
    /// RigPainter의 눌림(세로 8%)을 로슈 시안 값(세로 7%)으로 맞춘다.
    static let roshuSquash = 0.875

    // 로슈 앞 지느러미는 몸 안쪽(-)으로만 돈다. 바깥으로 젖히면 자른 선이 드러난다(무대 400px에서 눈에 띔).
    static let roshuWalkArt = RigPainter(
        character: "roshu", art: "walk", scale: roshuScale, lidPad: 0.35,
        limbDirection: ["flipper_front": -1, "foot_back": -1, "foot_front": 1, "flipper_side": 0]
    )
    static let roshuStandArt = RigPainter(
        character: "roshu", art: "stand", scale: scale(fitting: "stand", of: "roshu"), lidPad: 0.35,
        limbDirection: ["arm_left": 0, "arm_right": 0, "foot_left": 0, "foot_right": 0]
    )
    /// 선물 상자를 들고 오는 로슈(SPEC §4.9). 정면 그림이라 팔은 상자를 받친 채 고정, 발만 걷는다.
    static let roshuGiftArt = RigPainter(
        character: "roshu", art: "gift-carry", scale: scale(fitting: "gift-carry", of: "roshu"), lidPad: 0.35,
        limbDirection: ["arm_left": 0, "arm_right": 0, "foot_left": 0, "foot_right": 0]
    )
    static let kainWalkArt = RigPainter(
        character: "kain", art: "walk", scale: kainScale, lidPad: 0.04, limbDirection: ["leg_far": 0, "leg_near": 0]
    )
    static let kainStandArt = RigPainter(
        character: "kain", art: "rim-stand", scale: kainScale, lidPad: 0.04, limbDirection: ["leg_left": 0, "leg_right": 0]
    )
    /// 선물 상자를 들고 오는 카인(SPEC §4.9). 상자는 몸 앞 별도 부위(고정), 발 둘이 걷는다. 그림은 왼쪽을 본다.
    static let kainGiftArt = RigPainter(
        character: "kain", art: "gift-carry", scale: kainScale, lidPad: 0.04,
        limbDirection: ["box": 0, "leg_near": 0, "leg_far": 0]
    )

    private static func scale(fitting art: String, of character: String) -> Double {
        guard let height = IdleRig.arts[character]?[art]?.bbox.height, height > 0 else { return 0 }
        return roshuHeight / Double(height)
    }

    /// 입장 걷기: a→b를 감속으로 가고, 걸음 위상은 지나온 거리로 잰다. 끝 0.14초 동안 다리를 모은다.
    static func entrance(_ t: Double, _ a: Double, _ b: Double, from x0: Double, to x1: Double)
        -> (x: Double, travelled: Double, moving: Double) {
        let x = Motion.lerp(x0, x1, Motion.seg(t, a, b, Ease.power2Out))
        let moving: Double = t > b ? 0 : (t < a ? 1 : 1 - Motion.seg(t, b - 0.14, b))
        return (x, abs(x - x0), moving)
    }

    /// 한 발의 한 주기. 옆으로 미는 폭은 오늘 화면 배율 그대로, 발 들기만 `liftBoost`배.
    private static func footStep(_ c: Double, liftBoost: Double) -> (x: Double, lift: Double, rot: Double) {
        let reach = 1.5, lift = 1.6, rot = 8.0
        if c < 0.5 {
            let v = c / 0.5
            let arc = sin(Double.pi * v)
            return ((reach - 2 * reach * RigMotion.smooth(v)) * stageK, lift * arc * stageK * liftBoost, rot * arc * 1.4)
        }
        return ((-reach + 2 * reach * (c - 0.5) / 0.5) * stageK, 0, 0)
    }

    /// 로슈 걷기: 다리로 걷고 지느러미는 반대 박자, 몸이 발 박자에 맞춰 살짝 들썩인다. `moving`으로 멈출 때 다리를 모은다.
    static func roshuWalk(_ m: inout IdleFrame, travelled: Double, moving: Double) {
        let c = RigMotion.remainder(travelled / 125 / 2, 1)
        for (foot, phase) in [("foot_back", c), ("foot_front", RigMotion.remainder(c + 0.5, 1))] {
            let g = footStep(phase, liftBoost: 2.2)
            m.limbs[foot] = g.rot * moving
            m.shift[foot] = CGVector(dx: g.x * moving, dy: -g.lift * moving)
        }
        let swing = cos(2 * Double.pi * c) * moving
        m.limbs["flipper_front"] = 6 * swing
        m.limbs["flipper_side"] = -12 * swing
        m.bodyDy = -6 * abs(sin(2 * Double.pi * c)) * moving
    }

    /// 선물 들고 걷기: 걷기와 같은 발 박자(그림만 정면 `gift-carry`). 팔은 상자를 받친 채 두고 몸이 발 박자에 들썩인다.
    static func roshuGiftWalk(_ m: inout IdleFrame, travelled: Double, moving: Double) {
        let c = RigMotion.remainder(travelled / 125 / 2, 1)
        for (foot, phase) in [("foot_left", c), ("foot_right", RigMotion.remainder(c + 0.5, 1))] {
            let g = footStep(phase, liftBoost: 2.2)
            m.limbs[foot] = g.rot * moving
            m.shift[foot] = CGVector(dx: g.x * moving, dy: -g.lift * moving)
        }
        m.bodyDy = -6 * abs(sin(2 * Double.pi * c)) * moving
    }

    /// 카인 뒤뚱 걷기: 다리가 엉덩이를 축으로 엇갈리고 몸이 딛는 쪽으로 기운다.
    static func kainWalk(_ m: inout IdleFrame, travelled: Double, moving: Double) {
        let c = RigMotion.remainder(travelled / 95 / 2, 1)
        let k = sin(2 * Double.pi * c)
        let lift = cos(2 * Double.pi * c)
        let raise: Double = 2.1 * stageK * moving
        m.limbs["leg_near"] = 16 * k * moving
        m.limbs["leg_far"] = -16 * k * moving
        m.shift["leg_near"] = CGVector(dx: 0, dy: -raise * max(0, lift))
        m.shift["leg_far"] = CGVector(dx: 0, dy: -raise * max(0, -lift))
        m.rot += 4 * k * moving
    }

    /// 카인 선물 들고 걷기: 발 둘이 로슈 선물 걷기처럼 내딛고(발 기준점이 위라 돌면 발끝이 든다), 상자는 가만히,
    /// 몸은 뒤뚱 걷기와 같이 딛는 쪽으로 ±4° 기운다. 보폭은 뒤뚱 걷기(95)와 같다.
    static func kainGiftWalk(_ m: inout IdleFrame, travelled: Double, moving: Double) {
        let c = RigMotion.remainder(travelled / 95 / 2, 1)
        for (foot, phase) in [("leg_near", c), ("leg_far", RigMotion.remainder(c + 0.5, 1))] {
            let g = footStep(phase, liftBoost: 1.6)
            m.limbs[foot] = g.rot * moving
            m.shift[foot] = CGVector(dx: g.x * moving, dy: -g.lift * moving)
        }
        m.bodyDy = -4 * abs(sin(2 * Double.pi * c)) * moving
        m.rot += 4 * sin(2 * Double.pi * c) * moving
    }
}

/// 리그 캐릭터 캔버스. 무대(1080×1920) 크기로 그리면 줄이기 전 해상도로 래스터화돼 메모리가 크다.
/// 화면 크기로 그리고 무대 좌표로 되돌려 키운다(무대 전체 배율과 상쇄돼 화면 해상도 그대로 보인다).
private struct IntroRigLayer: View {
    let scale: Double
    let figures: [IntroRig.Figure]

    var body: some View {
        let s = max(scale, 0.01)
        Canvas { context, _ in
            var stage = context
            stage.scaleBy(x: s, y: s)
            for figure in figures {
                figure.painter.draw(in: stage, base: figure.base, m: figure.frame, squash: figure.squash, blink: figure.blink)
            }
        }
        .frame(width: 1080 * s, height: 1920 * s)
        .scaleEffect(1 / s, anchor: .topLeading)
        .frame(width: 1080, height: 1920, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private extension View {
    /// 무대 좌표로 놓기: 가로는 가운데(540)에서 떨어진 거리, 세로는 윗변.
    func stagePosition(x: Double, top: Double, height: Double) -> some View {
        position(x: 540 + x, y: top + height / 2)
    }
}
