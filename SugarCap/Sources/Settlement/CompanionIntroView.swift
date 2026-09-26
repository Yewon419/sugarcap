import SwiftUI

/// 로슈·카인 소개(2026-09-26 HTML 프로토타입 `screens-intro.js` 확정, SPEC §4.5). 첫 마감(먹이기) 직전에 한 번만 나온다.
/// 온보딩 마지막 질문 "오늘의 분량을 남기면 어디로 가냐고요...?"의 답이다.
/// 4장(문구 = 대표님): 오늘 남긴 만큼은/이 친구들에게 가요 → 달달한 걸 좋아하는 로슈! → 카페인을 좋아하는 카인!
/// → 많이많이 남겨서 두 친구와 더 가까워져요 → 밤 → "먹이러 가기".
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
                    IntroStage(t: t)
                        .frame(width: 1080, height: 1920)
                        .scaleEffect(scale, anchor: .topLeading)
                        .offset(x: (proxy.size.width - 1080 * scale) / 2)
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                .clipped()
                .contentShape(Rectangle())
                .onTapGesture { clock.seek(to: Self.chapters.next(after: clock.time(at: Date()))) }
                .overlay(alignment: .top) { chrome(t: t) }
                .overlay(alignment: .bottom) { cta(t: t) }
            }
            .ignoresSafeArea()
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

    private func cta(t: Double) -> some View {
        let k = Motion.seg(t, Self.open + 10.45, Self.open + 10.9, Ease.power3Out)
        return Button(action: onFinish) {
            Text("먹이러 가기")
                .ctaLabel()
                .foregroundStyle(.white)
                .background(Color.accentColor, in: Capsule())
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
                            accentLast: Bool, color: Color) -> some View {
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
                    color: isName ? .white : (isAccent ? Color.accentColor : color),
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
        let lines = ["오늘 남긴 만큼은", "이 친구들에게 가요"]
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

    private var chapterRoshu: some View {
        let radius = 2300 * useg(0.7, 1.45, Ease.expoInOut)
        let rise = useg(1.35, 1.95) { Ease.backOut($0, overshoot: 1.5) }
        let land = useg(1.9, 2.0, Ease.power2Out) - useg(2.0, 2.1, Ease.power2Out)
        let wobble = [2.4, 2.7, 3.0, 3.3].enumerated().reduce(0.0) { sum, item in
            let k = useg(item.element, item.element + 0.3, Ease.sineInOut)
            return sum + (item.offset % 2 == 0 ? k : -k)
        }
        let orbitOn = useg(2.05, 2.4, Ease.power3Out)
        let burst = useg(1.9, 2.5, Ease.power3Out)
        let burstRadius = u < 1.9 ? 0 : 20 * (1 - useg(2.1, 2.55))

        return ZStack(alignment: .topLeading) {
            Circle()
                .fill(Color.sugarPink)
                .frame(width: radius * 2, height: radius * 2)
                .position(x: 540, y: 1190)

            ForEach(0..<14, id: \.self) { index in
                let angle: Double = Double(index) / 14 * Double.pi * 2 + 0.2
                let distance: Double = 300 + Double(index % 3) * 70
                let x: Double = 540 + cos(angle) * distance * burst
                let y: Double = 1320 + sin(angle) * distance * burst * 0.8
                Circle()
                    .fill(index % 2 == 0 ? Color.ink : Color.white)
                    .frame(width: burstRadius * 2, height: burstRadius * 2)
                    .position(x: x, y: y)
            }

            // 뒤쪽 궤도 방울 → 로슈 → 앞쪽 궤도 방울
            orbit(front: false, on: orbitOn)
            Image(CupSide.sugar.characterAsset)
                .resizable()
                .scaledToFit()
                .frame(height: 480)
                .scaleEffect(x: 1 + 0.1 * land, y: 1 - 0.12 * land, anchor: .bottom)
                .rotationEffect(.degrees(-7 * wobble), anchor: .bottom)
                .stagePosition(x: 0, top: Motion.lerp(2000, 1060, rise), height: 480)
            orbit(front: true, on: orbitOn)

            maskedText(["달달한 걸", "좋아하는"], size: 150, name: "로슈!", revealAt: 1.05, hideAt: 3.45, clock: u,
                       accentLast: false, color: .ink)
        }
    }

    private func orbit(front: Bool, on: Double) -> some View {
        // 식을 쪼개 둔다. 한 줄에 몰면 컴파일러가 타입을 제때 못 푼다(CI 오류).
        ForEach(0..<3, id: \.self) { index in
            let angle: Double = (u - 2.05) * 3.1 + Double(index) * Double.pi * 2 / 3
            let depth: Double = sin(angle)
            let scale: Double = max(0, on * (0.8 + 0.25 * depth))
            let x: Double = 360 * cos(angle)
            let top: Double = 1300 + 120 * depth - 55
            if (depth > 0) == front {
                dropImage(.sugar, size: 110)
                    .scaleEffect(scale)
                    .stagePosition(x: x, top: top, height: 110)
            }
        }
    }

    // MARK: 카인

    private var chapterKain: some View {
        let cover = useg(3.65, 4.3, Ease.power4InOut)
        let enter = useg(4.15, 4.7, Ease.power3Out)
        let hop = useg(4.15, 4.42, Ease.power2Out) - useg(4.42, 4.69, Ease.power2In)
        let jitter: Double = {
            guard u >= 5.3, u <= 5.75 else { return 0 }
            let phase = (u - 5.3) / 0.045
            let within = phase.truncatingRemainder(dividingBy: 2)
            return 18 * (within < 1 ? within : 2 - within)
        }()
        let spin = useg(5.85, 6.65, Ease.power3InOut)
        let pulse = useg(6.65, 6.85, Ease.power2Out) - useg(6.85, 7.05, Ease.power2Out)
        let bounce = useg(4.55, 5.25)
        let ring = useg(5.25, 5.8, Ease.power3Out)
        let caffeineScale: Double = u < 4.55 ? 0 : 1 - useg(5.15, 5.3)
        let caffeineX: Double = Motion.lerp(760, 0, bounce)
        let bounceHeight: Double = 520 * abs(sin(Double.pi * bounce * 2.5)) * (1 - bounce)
        let caffeineTop: Double = 1080 - bounceHeight
        let kainX: Double = Motion.lerp(-900, 0, enter) + jitter
        let kainTop: Double = 1060 - 180 * hop

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
                        .fill(Color.wall)
                        .frame(width: long ? 6 : 3, height: long ? 40 : 22)
                        .offset(y: -(366 + (long ? 20 : 11)))
                        .rotationEffect(.degrees(Double(index) * 6))
                }
                .rotationEffect(.degrees(-(u - 5.25) * 30))
                .opacity(useg(5.3, 5.7))
            }
            .position(x: 540, y: 1290)

            Image(CupSide.caffeine.characterAsset)
                .resizable()
                .scaledToFit()
                .frame(height: 420)
                .rotationEffect(.degrees(360 * spin), anchor: UnitPoint(x: 0.5, y: 0.55))
                .scaleEffect(1 + 0.08 * pulse, anchor: UnitPoint(x: 0.5, y: 0.55))
                .stagePosition(x: kainX, top: kainTop, height: 420)

            dropImage(.caffeine, size: 170)
                .scaleEffect(caffeineScale)
                .stagePosition(x: caffeineX, top: caffeineTop, height: 170)

            maskedText(["카페인을", "좋아하는"], size: 150, name: "카인!", revealAt: 4.1, hideAt: 7.05, clock: u,
                       accentLast: false, color: .ink)
        }
    }

    // MARK: 함께

    private var chapterTogether: some View {
        let radius = 2300 * useg(7.25, 7.95, Ease.expoInOut)
        let enter = useg(7.65, 8.15, Ease.power3Out)
        let hitDelay = 0.5
        var gotSugar = 0.0, gotCaffeine = 0.0, hopSugar = 0.0, hopCaffeine = 0.0
        for (index, drop) in Self.rain.enumerated() {
            let at = 8.2 + Double(index) * 0.1
            let got = useg(at + hitDelay, at + hitDelay + 0.3, Ease.power3Out)
            let hop = Motion.decay(u, at: at + hitDelay, rate: 9)
            if drop.side == .sugar { gotSugar += got; hopSugar += hop } else { gotCaffeine += got; hopCaffeine += hop }
        }
        let roshuX = Motion.lerp(-1000, -225, enter) + 80 * gotSugar / 7
        let kainX = Motion.lerp(1000, 245, enter) - 80 * gotCaffeine / 7
        let night = useg(10.2, 11.0, Ease.power2InOut)
        let bondIn = useg(9.75, 10.25, Ease.power3Out)
        let textColor = Color.ink(towardWhite: night)
        let roshuTop: Double = 1040 - 46 * min(1, hopSugar)
        let kainTop: Double = 1110 - 46 * min(1, hopCaffeine)

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

            Image(CupSide.sugar.characterAsset)
                .resizable()
                .scaledToFit()
                .frame(height: 480)
                .stagePosition(x: roshuX, top: roshuTop, height: 480)
            Image(CupSide.caffeine.characterAsset)
                .resizable()
                .scaledToFit()
                .frame(height: 420)
                .stagePosition(x: kainX, top: kainTop, height: 420)

            maskedText(["많이많이 남겨서", "두 친구와", "더 가까워져요"], size: 96, name: nil, revealAt: 7.85, hideAt: nil, clock: u,
                       accentLast: true, color: textColor)

            VStack(spacing: 26) {
                Text("처음 만난 사이")
                    .font(AppFont.pretendardFixed(54, .extraBold))
                    .tracking(AppFont.displayTracking(for: 54))
                    .foregroundStyle(textColor)
                GeometryReader { bar in
                    Capsule().fill(Color(white: 0.5, opacity: 0.3))
                        .overlay(alignment: .leading) {
                            Capsule().fill(Color.accentColor)
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

private extension View {
    /// 무대 좌표로 놓기: 가로는 가운데(540)에서 떨어진 거리, 세로는 윗변.
    func stagePosition(x: Double, top: Double, height: Double) -> some View {
        position(x: 540 + x, y: top + height / 2)
    }
}
