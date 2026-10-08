import SwiftUI

/// 당 하루 기준 프리셋(§3·§9.1). 사용자가 고를 수 있는 값은 이 셋뿐이다.
enum SugarPreset {
    static let values: [Double] = [25, 50, 100]
}

/// 하루 기준 컵(2026-09-26 온보딩 확정 화면). 컵 선 안의 액체가 고른 양만큼 차고, 위아래로 끌거나 칩을 눌러 정한다.
/// 온보딩 하루 기준 단계와 추이의 하루 기준 화면(2026-10-05)이 같이 쓴다.
/// 잠기면(줄이기 목표가 기준을 맡는 중) 컵은 값만 보여 주고 끌기·칩이 사라진다.
struct LimitCupPicker: View {
    let side: CupSide
    @Binding var value: Double
    let isLocked: Bool
    /// UI 테스트 식별자 앞머리. 온보딩은 "onboarding", 추이 쪽은 "limit".
    let identifierPrefix: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.menuCountry) private var menuCountry
    @State private var shownLevel: Double = 0
    @State private var isDragging = false

    private var maxValue: Double { side == .sugar ? 100 : 600 }
    private var minValue: Double { side == .sugar ? 25 : 100 }

    private var chips: [(value: Double, note: String?)] {
        if side == .sugar {
            return [(25, String(localized: "더 줄이기")), (50, String(localized: "WHO 권고")), (100, String(localized: "넉넉하게"))]
        }
        // 권고 기관 칩은 나라마다 자리가 다르다(한국·미국 400, 대만 300).
        let advice = menuCountry.caffeineAdviceMg
        let note = menuCountry.caffeineAdviceNote
        return [
            (200, String(localized: "가볍게")), (300, advice == 300 ? note : nil),
            (400, advice == 400 ? note : nil), (600, String(localized: "최대")),
        ]
    }

    /// 끌어서 정한 값. 당은 프리셋 셋 중 가까운 것에 붙고(§4.4), 카페인은 25 단위.
    private func snap(_ raw: Double) -> Double {
        switch side {
        case .sugar: return SugarPreset.values.min { abs($0 - raw) < abs($1 - raw) } ?? 50
        case .caffeine: return min(600, max(100, (raw / 25).rounded() * 25))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            cup
            if !isLocked {
                chipRow
                    // 칩 네 칸이 한 줄이라 큰 글자에서 숫자가 "……"로 깨졌다. 이 줄만 글자 상한을 둔다.
                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                    .padding(.horizontal, 20)
                    .padding(.top, 36)
            }
        }
        .sensoryFeedback(.selection, trigger: value)
    }

    // MARK: 컵

    private var cup: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                SetupLiquid(level: shownLevel, time: reduceMotion ? 0 : t, isSugar: side == .sugar, agitation: isDragging ? 1 : 0)
                    .clipShape(SetupCupInner())
                SetupCupOutline()
                    .stroke(Color.ink, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                VStack(spacing: 8) {
                    OutlineText(text: Amount.number(value), font: AppFont.numeralFixed(70), color: .ink, lineWidth: 2.5)
                    Text(side.unit)
                        .font(AppFont.pretendardFixed(15, .semibold))
                        .tracking(5)
                        .foregroundStyle(Color.ink)
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 64)
                .contentTransition(.numericText())
            }
            .frame(width: 230, height: 307)
        }
        .scaleEffect(isDragging ? 1.02 : 1)
        .overlay(alignment: .bottom) {
            if !isLocked {
                Text("위아래로 끌어 봐요")
                    .font(AppFont.pretendard(12, .regular, relativeTo: .caption))
                    .foregroundStyle(.secondary)
                    .offset(y: 30)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    guard !isLocked else { return }
                    isDragging = true
                    // 컵 안쪽 높이(307pt 중 위 5%~아래 96.5%)에서 손가락 높이를 비율로.
                    let top = 307.0 * 20 / 400
                    let bottom = 307.0 * 386 / 400
                    let ratio = max(0, min(1, (bottom - drag.location.y) / (bottom - top)))
                    value = snap(max(minValue, ratio * maxValue))
                }
                .onEnded { _ in isDragging = false }
        )
        .onAppear { settle(animated: false) }
        .onChange(of: value) { _, _ in settle(animated: true) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(side.label) 하루 기준")
        .accessibilityValue("\(Amount.number(value)) \(side.unit)")
        .accessibilityAdjustableAction { direction in
            guard !isLocked else { return }
            // 칩 값 사이를 한 칸씩 오간다. 끌어서 칩 사이 값이면 가장 가까운 칩에서 출발한다.
            let values = chips.map(\.value)
            let nearest = values.indices.min { abs(values[$0] - value) < abs(values[$1] - value) } ?? 0
            switch direction {
            case .increment: value = values[min(values.count - 1, nearest + 1)]
            case .decrement: value = values[max(0, nearest - 1)]
            @unknown default: break
            }
        }
    }

    private func settle(animated: Bool) {
        let target = value / maxValue
        if animated, !reduceMotion {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.62)) { shownLevel = target }
        } else {
            shownLevel = target
        }
    }

    private var chipRow: some View {
        HStack(spacing: 8) {
            ForEach(chips, id: \.value) { chip in
                let isOn = chip.value == value
                Button {
                    value = chip.value
                } label: {
                    VStack(spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(Amount.number(chip.value))
                                .font(AppFont.numeralFixed(20))
                                .tracking(-0.5)
                            Text(side.unit)
                                .font(AppFont.numeralFixed(11))
                        }
                        if let note = chip.note {
                            Text(note)
                                .font(AppFont.pretendardFixed(11, .regular))
                                .foregroundStyle(isOn ? Color.white.opacity(0.72) : Color.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    .foregroundStyle(isOn ? Color.white : Color.ink)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .padding(.horizontal, 4)
                    .background {
                        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
                        if isOn {
                            shape.fill(Color.ink)
                        } else {
                            shape.fill(.white.opacity(0.72)).overlay(shape.strokeBorder(Color.ink.opacity(0.12), lineWidth: 1.5))
                        }
                    }
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityAddTraits(isOn ? .isSelected : [])
                .accessibilityIdentifier("\(identifierPrefix)-\(side.rawValue)-\(Amount.number(chip.value))")
            }
        }
    }
}

/// 컵의 액체(300×400 좌표를 230×307에 맞춘다). 값이 바뀌면 수위가 스프링으로 따라가고 표면은 늘 조금 출렁인다.
private struct SetupLiquid: View, Animatable {
    var level: Double
    let time: Double
    let isSugar: Bool
    let agitation: Double

    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    private static let sugarColors = [Color(red: 0xF6 / 255, green: 0xC1 / 255, blue: 0xCC / 255), Color(red: 0xDF / 255, green: 0x76 / 255, blue: 0x90 / 255)]
    private static let caffeineColors = [Color(red: 0xE2 / 255, green: 0xAE / 255, blue: 0x76 / 255), Color(red: 0x8A / 255, green: 0x4A / 255, blue: 0x1C / 255)]

    var body: some View {
        Canvas { context, size in
            let sx = size.width / 300
            let sy = size.height / 400
            let baseY = (386 - (386 - 20) * level) * sy
            let amp = (5 + 10 * agitation) * sy
            var path = Path()
            path.move(to: CGPoint(x: 0, y: size.height))
            path.addLine(to: CGPoint(x: 0, y: baseY))
            var x = 0.0
            while x <= 300 {
                let y = baseY + amp * sin(x * 0.035 + time * 3.2) + amp * 0.4 * sin(x * 0.08 - time * 4.1)
                path.addLine(to: CGPoint(x: x * sx, y: y))
                x += 10
            }
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.closeSubpath()
            let colors = isSugar ? Self.sugarColors : Self.caffeineColors
            context.fill(path, with: .linearGradient(Gradient(colors: colors), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        }
    }
}

private struct SetupCupInner: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 300
        let sy = rect.height / 400
        var path = Path()
        path.move(to: CGPoint(x: 30 * sx, y: 16 * sy))
        path.addLine(to: CGPoint(x: 66 * sx, y: 368 * sy))
        path.addQuadCurve(to: CGPoint(x: 86 * sx, y: 384 * sy), control: CGPoint(x: 69 * sx, y: 384 * sy))
        path.addLine(to: CGPoint(x: 214 * sx, y: 384 * sy))
        path.addQuadCurve(to: CGPoint(x: 234 * sx, y: 368 * sy), control: CGPoint(x: 231 * sx, y: 384 * sy))
        path.addLine(to: CGPoint(x: 270 * sx, y: 16 * sy))
        path.closeSubpath()
        return path
    }
}

private struct SetupCupOutline: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 300
        let sy = rect.height / 400
        var path = Path()
        path.move(to: CGPoint(x: 22 * sx, y: 10 * sy))
        path.addLine(to: CGPoint(x: 58 * sx, y: 372 * sy))
        path.addQuadCurve(to: CGPoint(x: 82 * sx, y: 392 * sy), control: CGPoint(x: 62 * sx, y: 392 * sy))
        path.addLine(to: CGPoint(x: 218 * sx, y: 392 * sy))
        path.addQuadCurve(to: CGPoint(x: 242 * sx, y: 372 * sy), control: CGPoint(x: 238 * sx, y: 392 * sy))
        path.addLine(to: CGPoint(x: 278 * sx, y: 10 * sy))
        return path
    }
}
