import SwiftData
import SwiftUI

/// 온보딩(SPEC §4.5, 2026-09-26 HTML 프로토타입 확정). 모션 릴(15초, 7장) → 하루 기준 두 단계(당 → 카페인).
/// 로슈·카인 소개는 여기가 아니라 첫 마감 때 한다(대표님 결정). 계정·페이월 없음.
/// 완료 여부는 기기 단위 플래그라 SwiftData가 아니라 UserDefaults에 둔다.
struct OnboardingView: View {
    static let completedKey = "onboardingCompleted"
    /// Debug 전용 실행 인자. CI가 화면을 찍을 때 `-onboardingPage 2`(당 기준)·`3`(카페인 기준)처럼 넘긴다.
    static let pageArgumentKey = "onboardingPage"
    /// Debug 전용. 릴을 이 시각에 멈춰 찍는다(`-onboardingReelAt 8.8`).
    static let reelAtArgumentKey = "onboardingReelAt"

    let brands: [Brand]
    let onStart: () -> Void
    /// 설정에서 다시 볼 때만 준다. 있으면 "건너뛰기" 자리가 "닫기"가 되고 마지막 버튼은 "완료"다.
    var onClose: (() -> Void)?

    enum Stage: Equatable { case reel, sugar, caffeine }

    @Query private var settingsRows: [AppSettings]
    @Query private var goals: [ReductionGoal]
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scene: Stage = OnboardingView.initialScene
    @State private var clock = ReelClock(end: OnboardingReel.chapters.end)
    @State private var sugar: Double?
    @State private var caffeine: Double?

    private static var initialScene: Stage {
        #if DEBUG
        switch UserDefaults.standard.integer(forKey: pageArgumentKey) {
        case 2: return .sugar
        case 3: return .caffeine
        default: return .reel
        }
        #else
        return .reel
        #endif
    }

    private var frozenReelAt: Double? {
        #if DEBUG
        UserDefaults.standard.object(forKey: Self.reelAtArgumentKey) == nil ? nil : UserDefaults.standard.double(forKey: Self.reelAtArgumentKey)
        #else
        nil
        #endif
    }

    var body: some View {
        ZStack {
            switch scene {
            case .reel:
                reel
                    .transition(.opacity)
            case .sugar, .caffeine:
                LimitSetup(
                    side: scene == .sugar ? .sugar : .caffeine,
                    value: binding(scene == .sugar ? .sugar : .caffeine),
                    isManaged: isManaged(scene == .sugar ? .sugar : .caffeine),
                    finishLabel: onClose == nil ? "시작" : "완료",
                    onNext: next,
                    onBack: { withAnimation(.easeOut(duration: 0.25)) { scene = .sugar } }
                )
                .id(scene)
                .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)).combined(with: .opacity))
            }
        }
        .background(Color.wall.ignoresSafeArea())
        .overlay(alignment: .topTrailing) { topButton }
        .onAppear {
            if reduceMotion, scene == .reel { scene = .sugar }
        }
    }

    // MARK: 릴

    private var reel: some View {
        TimelineView(.animation(paused: frozenReelAt != nil)) { timeline in
            let t = frozenReelAt ?? clock.time(at: timeline.date)
            GeometryReader { proxy in
                let scale = proxy.size.height / 1920
                OnboardingReelStage(t: t)
                    .scaleEffect(scale, anchor: .topLeading)
                    .offset(x: (proxy.size.width - 1080 * scale) / 2)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                    .clipped()
            }
            .ignoresSafeArea()
            .overlay(alignment: .top) { progress(t: t) }
            .overlay(alignment: .bottom) { caption(t: t) }
            .onChange(of: t >= OnboardingReel.chapters.end) { _, ended in
                if ended { finishReel(after: 0.7) }
            }
        }
        // 화면 전체가 "다음 장" 버튼이다. 마지막 장에서 누르면 하루 기준으로.
        .overlay {
            Button(action: nextChapter) {
                Color.clear.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("다음 장")
            .accessibilityIdentifier("onboarding-next")
            .padding(.top, 70)
        }
    }

    private func progress(t: Double) -> some View {
        HStack(spacing: 5) {
            ForEach(0..<OnboardingReel.chapters.starts.count, id: \.self) { index in
                GeometryReader { bar in
                    Capsule().fill(Color.ink.opacity(0.16))
                        .overlay(alignment: .leading) {
                            Capsule().fill(Color.ink)
                                .frame(width: bar.size.width * OnboardingReel.chapters.progress(of: index, at: t))
                        }
                }
                .frame(height: 3)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .accessibilityHidden(true)
    }

    /// 장별 한 줄 설명. 장이 바뀔 때 한 번 떠오른다.
    private func caption(t: Double) -> some View {
        let index = OnboardingReel.chapters.index(at: t)
        return Text(OnboardingReel.lines[index])
            .font(AppFont.pretendard(19, .bold, relativeTo: .title3))
            .tracking(-0.3)
            .foregroundStyle(Color.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.9)))
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .id(index)
            .transition(.opacity.combined(with: .offset(y: 10)))
            .animation(.spring(response: 0.45, dampingFraction: 0.9), value: index)
            .allowsHitTesting(false)
    }

    private func nextChapter() {
        let now = Date()
        let t = clock.time(at: now)
        let next = OnboardingReel.chapters.next(after: t)
        if next >= OnboardingReel.chapters.end {
            finishReel(after: 0)
        } else {
            clock.seek(to: next, now: now)
        }
    }

    private func finishReel(after delay: Double) {
        Task {
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard scene == .reel else { return }
            withAnimation(.easeOut(duration: 0.3)) { scene = .sugar }
        }
    }

    // MARK: 위 버튼(건너뛰기·닫기)

    @ViewBuilder
    private var topButton: some View {
        if let onClose {
            Button(action: onClose) {
                Text("닫기")
                    .font(AppFont.pretendard(14, .medium, relativeTo: .footnote))
                    .tapTarget()
            }
            .foregroundStyle(Color.ink.opacity(0.72))
            .padding(.top, 12)
            .padding(.trailing, 12)
            .accessibilityIdentifier("onboarding-close")
        } else if scene == .reel {
            Button {
                withAnimation(.easeOut(duration: 0.3)) { scene = .sugar }
            } label: {
                Text("건너뛰기")
                    .font(AppFont.pretendard(14, .medium, relativeTo: .footnote))
                    .tapTarget()
            }
            .foregroundStyle(Color.ink.opacity(0.72))
            .padding(.top, 12)
            .padding(.trailing, 12)
            .accessibilityIdentifier("onboarding-skip")
        }
    }

    // MARK: 하루 기준

    private func isManaged(_ side: CupSide) -> Bool {
        goals.contains { $0.side == side.rawValue }
    }

    private func binding(_ side: CupSide) -> Binding<Double> {
        Binding(
            get: {
                switch side {
                case .sugar: return sugar ?? settingsRows.first?.sugarLimitG ?? DailyLimits.default.sugarG
                case .caffeine: return caffeine ?? settingsRows.first?.caffeineLimitMg ?? DailyLimits.default.caffeineMg
                }
            },
            set: { value in
                switch side {
                case .sugar: sugar = value
                case .caffeine: caffeine = value
                }
            }
        )
    }

    private func next() {
        if scene == .sugar {
            withAnimation(.easeOut(duration: 0.3)) { scene = .caffeine }
            return
        }
        // 고른 값을 저장하고 시작. 줄이기 목표가 맡은 쪽은 건드리지 않는다.
        if let settings = settingsRows.first {
            if let sugar, !isManaged(.sugar) { settings.sugarLimitG = sugar }
            if let caffeine, !isManaged(.caffeine) { settings.caffeineLimitMg = caffeine }
            try? context.save()
        }
        onStart()
    }
}

/// 하루 기준 한 단계(당 또는 카페인). 컵 선 안의 액체가 고른 양만큼 차고, 위아래로 끌거나 칩을 눌러 정한다.
private struct LimitSetup: View {
    let side: CupSide
    @Binding var value: Double
    let isManaged: Bool
    let finishLabel: String
    let onNext: () -> Void
    let onBack: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shownLevel: Double = 0
    @State private var isDragging = false

    private var maxValue: Double { side == .sugar ? 100 : 600 }
    private var minValue: Double { side == .sugar ? 25 : 100 }

    private var chips: [(value: Double, note: String?)] {
        side == .sugar
            ? [(25, "더 줄이기"), (50, "WHO 권고"), (100, "넉넉하게")]
            : [(200, "가볍게"), (300, nil), (400, "식약처 권고"), (600, "최대")]
    }

    /// 끌어서 정한 값. 당은 프리셋 셋 중 가까운 것에 붙고(§4.4), 카페인은 25 단위.
    private func snap(_ raw: Double) -> Double {
        switch side {
        case .sugar: return SugarPreset.values.min { abs($0 - raw) < abs($1 - raw) } ?? 50
        case .caffeine: return min(600, max(100, (raw / 25).rounded() * 25))
        }
    }

    private var title: String {
        side == .sugar ? "하루에 당은\n얼마까지 마실래요?" : "카페인은\n얼마까지 마실래요?"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                Capsule().fill(Color.ink).frame(height: 3)
                Capsule().fill(side == .caffeine ? Color.ink : Color.ink.opacity(0.16)).frame(height: 3)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            HStack {
                if side == .caffeine {
                    Button("이전", action: onBack)
                        .font(AppFont.pretendard(14, .medium, relativeTo: .footnote))
                        .foregroundStyle(Color.ink.opacity(0.72))
                        .tapTarget()
                        .accessibilityIdentifier("onboarding-back")
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)

            VStack(alignment: .leading, spacing: 10) {
                Text("하루 기준 \(side == .sugar ? 1 : 2)/2").kicker()
                Text(title)
                    .font(AppFont.pretendard(30, .extraBold, relativeTo: .largeTitle))
                    .tracking(AppFont.displayTracking(for: 30))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)

            cup
                .padding(.top, 24)

            if isManaged {
                Label("줄이기 목표가 \(side.label) 기준을 맡고 있어요", systemImage: "lock.fill")
                    .font(AppFont.pretendard(13, .regular, relativeTo: .footnote))
                    .foregroundStyle(.secondary)
                    .padding(.top, 24)
            } else {
                chipRow
                    // 칩 네 칸이 한 줄이라 큰 글자에서 숫자가 "……"로 깨졌다. 이 줄만 글자 상한을 둔다.
                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                    .padding(.horizontal, 20)
                    .padding(.top, 36)
            }

            Spacer(minLength: 16)

            VStack(spacing: 10) {
                Button(action: onNext) {
                    Text(side == .sugar ? "다음" : finishLabel)
                        .ctaLabel()
                        .foregroundStyle(.white)
                        .background(Color.accentColor, in: Capsule())
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityIdentifier(side == .sugar ? "onboarding-next" : "onboarding-start")
                Text("나중에 설정에서 언제든 바꿀 수 있어요.")
                    .font(AppFont.pretendard(12, .regular, relativeTo: .caption))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
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
            if !isManaged {
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
                    guard !isManaged else { return }
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
            guard !isManaged else { return }
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
                                .font(AppFont.numeral(20, relativeTo: .title3))
                                .tracking(-0.5)
                            Text(side.unit)
                                .font(AppFont.numeral(11, relativeTo: .caption2))
                        }
                        if let note = chip.note {
                            Text(note)
                                .font(AppFont.pretendard(11, .regular, relativeTo: .caption2))
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
                .accessibilityIdentifier("onboarding-\(side.rawValue)-\(Amount.number(chip.value))")
            }
        }
    }
}

/// 설정 컵의 액체(300×400 좌표를 230×307에 맞춘다). 값이 바뀌면 수위가 스프링으로 따라가고 표면은 늘 조금 출렁인다.
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

#Preview {
    OnboardingView(brands: [], onStart: {})
        .modelContainer(for: [AppSettings.self, ReductionGoal.self], inMemory: true)
}
