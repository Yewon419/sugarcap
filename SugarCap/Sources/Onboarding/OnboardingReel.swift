import SwiftUI

/// 온보딩 모션 릴(2026-09-26 대표님 확정: 15초 모션그래픽 v2를 온보딩으로, 이름 글꼴은 Pretendard).
/// 1080×1920 무대를 화면 높이에 맞춰 줄인다. 그림은 전부 시각 t의 순수 함수(`design/proto/screens-onboarding.js`와 같은 시각·곡선).
/// 장별 한 줄 설명 = 대표님 문구 7줄. 번호 라벨(01~07)은 전역 규칙(번호 섹션 라벨 기본 금지)에 따라 뺐다.
enum OnboardingReel {
    static let chapters = ReelChapters(starts: [0, 1.45, 2.8, 5.55, 7.5, 8.9, 11.4], end: 15)
    static let lines = [
        "단 걸 좋아하는 당신!",
        "하루에 당을 얼마나 먹고 계신지 아나요?",
        "카페인 없이 못 사는 당신!",
        "우리 함께 줄여나가요",
        "매일매일 음료를 기록하고",
        "목표한 만큼 덜 마셔 봅시다",
        "오늘의 분량을 남기면 어디로 가냐고요...?",
    ]
}

/// 릴 무대(1080×1920 좌표).
struct OnboardingReelStage: View {
    let t: Double

    private func seg(_ a: Double, _ b: Double, _ ease: (Double) -> Double = Ease.linear) -> Double {
        Motion.seg(t, a, b, ease)
    }

    private static let pinkTop = Color(red: 0xF6 / 255, green: 0xC1 / 255, blue: 0xCC / 255)
    private static let pinkBottom = Color(red: 0xDF / 255, green: 0x76 / 255, blue: 0x90 / 255)
    private static let sparkDeep = Color(red: 0xC9 / 255, green: 0x54 / 255, blue: 0x6E / 255)

    var body: some View {
        let zoom: Double = Motion.lerp(1, 1.04, seg(12.4, 15, Ease.sineInOut))
        ZStack(alignment: .topLeading) {
            Color.wall
            grid
            liquidA
            spark(top: 1100, color: Self.sparkDeep, rise: 620, scaleTo: 1, start: 1.52, end: 2.3)
            pinkWipe
            amberWipe
            ring
            dots
            cup
            spark(top: 1000, color: .sugarPink, rise: 560, scaleTo: 0.8, start: 10.57, end: 11.1)
            spark(top: 1300, color: .sugarPink, rise: 700, scaleTo: 0.6, start: 11.07, end: 11.55)
            numerals
            ripples
            orbitDrops
            word
        }
        .frame(width: 1080, height: 1920)
        .scaleEffect(zoom, anchor: UnitPoint(x: 0.5, y: 0.45))
    }

    // MARK: 바탕

    private var grid: some View {
        ForEach([180.0, 360, 540, 720, 900], id: \.self) { x in
            Rectangle()
                .fill(Color.ink.opacity(0.1))
                .frame(width: x == 540 ? 2 : 1.2, height: 1920)
                .offset(x: x)
        }
        .opacity(seg(0, 0.8, Ease.power2Out))
    }

    // MARK: 1~2장 · 화면 가득 차오르는 딸기 라떼

    private static func slosh(_ t: Double, beats: [Double], peak: Double) -> Double {
        beats.reduce(0) { $0 + Motion.decay(t, at: $1, rate: 4.2) * peak }
    }

    @ViewBuilder
    private var liquidA: some View {
        if t < 3.7 {
            let rise: Double = Motion.lerp(-0.04, 1.02, seg(0.15, 1.0, Ease.power3Out))
            let drop1: Double = Motion.lerp(rise, 0.4, seg(1.5, 1.85, Ease.power4Out))
            let level: Double = Motion.lerp(drop1, 0.08, seg(2.2, 2.55, Ease.power4Out))
            let amp: Double = 16 + Self.slosh(t, beats: [1.0, 1.5, 2.2], peak: 62)
            WaveShape(baseY: 1920 * (1 - level), amplitude: amp, phase: t * 4.2, minX: -20, maxX: 1100, bottom: 1960)
                .fill(LinearGradient(colors: [Self.pinkTop, Self.pinkBottom], startPoint: .top, endPoint: .bottom))
        }
    }

    private func spark(top: Double, color: Color, rise: Double, scaleTo: Double, start: Double, end: Double) -> some View {
        let up: Double = seg(start, start + 0.5, Ease.power3Out)
        let out: Double = seg(end, end + 0.25, Ease.power2In)
        let scale: Double = t < start ? 0 : scaleTo * up * (1 - out)
        return Circle()
            .fill(color)
            .frame(width: 90, height: 90)
            .scaleEffect(scale)
            .position(x: 540, y: top + 45 - rise * up)
    }

    private var pinkWipe: some View {
        let enter: Double = seg(2.22, 2.72, Ease.power3Out)
        let fill: Double = seg(2.78, 3.33, Ease.power3In)
        let scale: Double = t < 2.22 ? 0 : Motion.lerp(0, 0.55, enter) + 12.45 * fill
        let y: Double = 960 + Motion.lerp(760, 0, enter)
        return Circle()
            .fill(Color.sugarPink)
            .frame(width: 200, height: 200)
            .scaleEffect(scale)
            .position(x: 540, y: y)
            .opacity(t >= 3.9 ? 0 : 1)
    }

    private var amberWipe: some View {
        let grow: Double = seg(3.12, 3.67, Ease.expoInOut)
        let shrink: Double = seg(5.12, 5.54, Ease.power3In)
        return Circle()
            .fill(Color.caffeineAmber)
            .frame(width: 200, height: 200)
            .scaleEffect(13 * grow * (1 - shrink))
            .position(x: 540, y: 960)
    }

    // MARK: 3장 · 카페인 시계

    @ViewBuilder
    private var ring: some View {
        if t > 3.4, t < 5.6 {
            let draw: Double = Motion.lerp(seg(3.55, 4.1, Ease.power3Out), 0.5, seg(4.55, 4.9, Ease.power4Out))
            let turn: Double = -90 + 50 * seg(3.5, 5.5, Ease.power3InOut)
            let spin: Double = -(t - 3.4) * 22
            let alpha: Double = seg(3.4, 3.7) * (1 - seg(5.2, 5.45))
            ZStack {
                Circle()
                    .trim(from: 0, to: draw)
                    .stroke(Color.kainRing, style: StrokeStyle(lineWidth: 56, lineCap: .round))
                    .frame(width: 760, height: 760)
                    .rotationEffect(.degrees(turn))
                ForEach(0..<60, id: \.self) { index in
                    let long = index % 5 == 0
                    Capsule()
                        .fill(Color.wall)
                        .frame(width: long ? 6 : 3, height: long ? 48 : 26)
                        .offset(y: -(452 + (long ? 24 : 13)))
                        .rotationEffect(.degrees(Double(index) * 6))
                }
                .rotationEffect(.degrees(spin))
            }
            .opacity(alpha)
            .position(x: 540, y: 960)
        }
    }

    // MARK: 4~5장 · 점 행렬(기록이 쌓이고, 한 줄만 남는다)

    private static let dotColumns = 7
    private static let dotRows = 11
    private static let keepRow = 5
    private static let palette: [Color] = [.sugarPink, .caffeineAmber, Color(red: 0x5B / 255, green: 0x84 / 255, blue: 0xAA / 255)]

    @ViewBuilder
    private var dots: some View {
        if t > 5.5, t < 10.1 {
            let envelope: Double = seg(6.2, 6.6, Ease.power3InOut) * (1 - seg(7.25, 7.6, Ease.power3InOut))
            ZStack(alignment: .topLeading) {
                ForEach(0..<(Self.dotColumns * Self.dotRows), id: \.self) { index in
                    dot(index: index, envelope: envelope)
                }
            }
        }
    }

    private func dot(index: Int, envelope: Double) -> some View {
        let c = index % Self.dotColumns
        let r = index / Self.dotColumns
        let baseX: Double = 186 + Double(c) * 118
        let baseY: Double = 260 + Double(r) * 140
        let distance: Double = hypot(baseX - 540, baseY - 960) / hypot(354, 700)
        let appear: Double = seg(5.55 + distance * 0.45, 6.0 + distance * 0.45, Ease.power3Out)
        let wave: Double = 1 + 0.55 * envelope * sin(2 * Double.pi * (t - 6.2) * 1.15 - Double(c + r) * 0.6)
        var x = baseX
        var y = baseY
        var radius: Double = 34 * appear * wave
        var alpha: Double = 1
        var color = Self.palette[(c + r) % 3]
        if r != Self.keepRow {
            let lag: Double = 7.55 + Double(c) * 0.03 + Double(abs(r - Self.keepRow)) * 0.018
            y = Motion.lerp(baseY, 2050 + Double(r) * 20, seg(lag, lag + 0.6, Ease.power2In))
        } else {
            let gather: Double = seg(8.55 + Double(c) * 0.02, 8.95 + Double(c) * 0.02, Ease.power3InOut)
            let fall: Double = seg(9.05 + Double(c) * 0.05, 9.5 + Double(c) * 0.05, Ease.power2In)
            x = Motion.lerp(baseX, 395 + Double(c) * 48.3, gather)
            y = Motion.lerp(Motion.lerp(baseY, 520, gather), 1452, fall)
            radius = Motion.lerp(radius, 22, gather)
            alpha = 1 - seg(9.55, 9.95)
            if seg(7.85, 8.2) > 0.5 { color = .sugarPink }
        }
        return Circle()
            .fill(color)
            .frame(width: max(0, radius) * 2, height: max(0, radius) * 2)
            .opacity(alpha)
            .position(x: x, y: y)
    }

    // MARK: 6~7장 · 컵 선이 그려지고 목표만큼 채웠다가 남긴다

    @ViewBuilder
    private var cup: some View {
        let shrink: Double = seg(11.38, 11.83, Ease.power3In)
        if t >= 8.45, shrink < 1 {
            let lineDraw: Double = seg(8.45, 9.2, Ease.power3InOut)
            ZStack(alignment: .topLeading) {
                if t > 9.3, t < 11.9 {
                    let fill1: Double = seg(9.45, 10.15, Ease.power3Out) * 0.86
                    let fill2: Double = Motion.lerp(fill1, 0.46, seg(10.55, 10.9, Ease.power4Out))
                    let level: Double = Motion.lerp(fill2, 0.12, seg(11.05, 11.4, Ease.power4Out))
                    let amp: Double = 8 + Self.slosh(t, beats: [10.15, 10.55, 11.05], peak: 40)
                    WaveShape(baseY: 1490 - 864 * level, amplitude: amp, phase: t * 4.6 + 1.3, minX: 260, maxX: 830, bottom: 1500)
                        .fill(LinearGradient(colors: [Self.pinkTop, Self.pinkBottom], startPoint: .top, endPoint: .bottom))
                        .clipShape(CupInnerShape())
                }
                CupOutlineShape()
                    .trim(from: 0, to: lineDraw)
                    .stroke(Color.ink, style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
            }
            .frame(width: 1080, height: 1920)
            .scaleEffect(Motion.lerp(1, 0.18, shrink), anchor: UnitPoint(x: 0.5, y: 1060.0 / 1920))
            .opacity(1 - shrink)
        }
    }

    // MARK: 큰 숫자(글자 속이 빈 외곽선)

    private var numerals: some View {
        ZStack(alignment: .topLeading) {
            slam("50", size: 540, color: .ink, at: 0.85, out: 1.48)
            slam("20", size: 540, color: .ink, at: 1.5, out: 2.18)
            slam("4", size: 540, color: .ink, at: 2.2, out: 2.62)
            slam("400", size: 380, color: .wall, at: 3.72, out: 4.52)
            slam("200", size: 380, color: .wall, at: 4.56, out: 5.2)
        }
    }

    @ViewBuilder
    private func slam(_ text: String, size: CGFloat, color: Color, at: Double, out: Double) -> some View {
        if t >= at, t < out + 0.12 {
            let enter: Double = seg(at, at + 0.34, Ease.power4Out)
            let exit: Double = seg(out, out + 0.12, Ease.power2In)
            let scale: Double = Motion.lerp(1.45, 1, enter) * Motion.lerp(1, 0.86, exit)
            OutlineText(text: text, font: AppFont.numeralFixed(size), color: color, lineWidth: 8)
                .scaleEffect(scale)
                .opacity(enter * (1 - exit))
                .position(x: 540, y: 840)
        }
    }

    // MARK: 끝 · 두 방울이 돌고 "슈가캡"

    private var ripples: some View {
        ZStack {
            ripple(start: 12.9, to: 1.9, alpha: 0.9)
            ripple(start: 13.04, to: 1.45, alpha: 0.7)
        }
    }

    @ViewBuilder
    private func ripple(start: Double, to: Double, alpha: Double) -> some View {
        if t >= start {
            let k: Double = seg(start, start + 0.95, Ease.power2Out)
            Circle()
                .strokeBorder(Color.accentColor, lineWidth: 5)
                .frame(width: 520, height: 520)
                .scaleEffect(Motion.lerp(0.35, to, k))
                .opacity(alpha * (1 - k))
                .position(x: 540, y: 820)
        }
    }

    @ViewBuilder
    private var orbitDrops: some View {
        if t >= 11.72 {
            let e: Double = seg(11.8, 12.9, Ease.power3InOut)
            let angle: Double = Double.pi * 0.5 + 2.5 * Double.pi * e
            let radius: Double = Motion.lerp(230, 118, e)
            let dx: Double = radius * cos(angle)
            let dy: Double = radius * sin(angle) * 0.55
            ForEach(CupSide.allCases) { side in
                let sign: Double = side == .sugar ? 1 : -1
                let start: Double = side == .sugar ? 11.72 : 11.78
                let pop: Double = seg(start, start + 0.5, Ease.power3Out)
                Image(side.dropAsset)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 210, height: 210)
                    .scaleEffect(pop)
                    .position(x: 540 + sign * dx, y: 820 + sign * dy)
            }
        }
    }

    @ViewBuilder
    private var word: some View {
        if t >= 12.9 {
            let letters = ["슈", "가", "캡"]
            VStack(spacing: 0) {
                HStack(spacing: 4) {
                    ForEach(Array(letters.enumerated()), id: \.offset) { index, letter in
                        let k: Double = seg(13.0 + Double(index) * 0.09, 13.7 + Double(index) * 0.09) { x in
                            x >= 1 ? 1 : 1 - pow(2, -10 * x)
                        }
                        MaskLine(
                            text: letter, font: AppFont.pretendardFixed(220, .extraBold), lineHeight: 253,
                            color: .ink, tracking: AppFont.displayTracking(for: 220), reveal: k
                        )
                    }
                }
                let en: Double = seg(13.5, 14.1) { x in x >= 1 ? 1 : 1 - pow(2, -10 * x) }
                Text("SUGARCAP")
                    .font(AppFont.numeralFixed(40))
                    .tracking(20)
                    .foregroundStyle(Color.accentColor)
                    .opacity(en)
                    .offset(y: 20 * (1 - en))
                    .padding(.top, 37)
            }
            .frame(width: 1080)
            .offset(y: 1000)
        }
    }
}

// MARK: - 도형

/// 출렁이는 액체 윗면. 두 사인파를 겹친다(프로토타입 `wavePath`).
struct WaveShape: Shape {
    let baseY: Double
    let amplitude: Double
    let phase: Double
    let minX: Double
    let maxX: Double
    let bottom: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: minX, y: bottom))
        path.addLine(to: CGPoint(x: minX, y: baseY))
        var x = minX
        while x <= maxX {
            let y = baseY + amplitude * sin(x * 0.011 + phase) + amplitude * 0.45 * sin(x * 0.029 - phase * 1.35)
            path.addLine(to: CGPoint(x: x, y: y))
            x += 18
        }
        path.addLine(to: CGPoint(x: maxX, y: bottom))
        path.closeSubpath()
        return path
    }
}

/// 릴 속 컵 선(1080×1920 좌표).
private struct CupOutlineShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 256, y: 614))
        path.addLine(to: CGPoint(x: 322, y: 1472))
        path.addQuadCurve(to: CGPoint(x: 362, y: 1504), control: CGPoint(x: 328, y: 1504))
        path.addLine(to: CGPoint(x: 718, y: 1504))
        path.addQuadCurve(to: CGPoint(x: 758, y: 1472), control: CGPoint(x: 752, y: 1504))
        path.addLine(to: CGPoint(x: 824, y: 614))
        return path
    }
}

private struct CupInnerShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 272, y: 626))
        path.addLine(to: CGPoint(x: 336, y: 1466))
        path.addQuadCurve(to: CGPoint(x: 364, y: 1490), control: CGPoint(x: 340, y: 1490))
        path.addLine(to: CGPoint(x: 716, y: 1490))
        path.addQuadCurve(to: CGPoint(x: 744, y: 1466), control: CGPoint(x: 740, y: 1490))
        path.addLine(to: CGPoint(x: 808, y: 626))
        path.closeSubpath()
        return path
    }
}

/// 속이 빈 외곽선 글자. 글자를 둘레로 여러 번 찍은 뒤 가운데를 글자 모양으로 파낸다.
struct OutlineText: View {
    let text: String
    let font: Font
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        let half = lineWidth / 2
        ZStack {
            ForEach(0..<16, id: \.self) { index in
                let angle = Double(index) / 16 * 2 * Double.pi
                Text(text)
                    .font(font)
                    .foregroundStyle(color)
                    .offset(x: half * cos(angle), y: half * sin(angle))
            }
            Text(text)
                .font(font)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
        .fixedSize()
    }
}
