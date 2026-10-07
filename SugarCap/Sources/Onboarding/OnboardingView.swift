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
                    finishLabel: onClose == nil ? String(localized: "시작") : String(localized: "완료"),
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
            // 당 기준 단계의 "다음"(onboarding-next)과 식별자를 나눈다. 같으면 건너뛰기 직후 사라지는 중인
            // 릴 버튼을 UI 테스트가 눌러 카페인 단계가 안 열렸다(2026-09-27 CI).
            .accessibilityIdentifier("onboarding-reel-next")
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

    private var title: String {
        side == .sugar
            ? String(localized: "하루에 당은\n얼마까지 마실래요?")
            : String(localized: "카페인은\n얼마까지 마실래요?")
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

            LimitCupPicker(side: side, value: $value, isLocked: isManaged, identifierPrefix: "onboarding")
                .padding(.top, 24)

            if isManaged {
                Label("줄이기 목표가 \(side.label) 기준을 맡고 있어요", systemImage: "lock.fill")
                    .font(AppFont.pretendard(13, .regular, relativeTo: .footnote))
                    .foregroundStyle(.secondary)
                    .padding(.top, 24)
            }

            Spacer(minLength: 16)

            VStack(spacing: 10) {
                Button(action: onNext) {
                    Text(side == .sugar ? String(localized: "다음") : finishLabel)
                        .ctaLabel()
                        .foregroundStyle(.white)
                        .background(Color.accentColor, in: Capsule())
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityIdentifier(side == .sugar ? "onboarding-next" : "onboarding-start")
                Text("나중에 추이 화면에서 언제든 바꿀 수 있어요.")
                    .font(AppFont.pretendard(12, .regular, relativeTo: .caption))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
    }
}

#Preview {
    OnboardingView(brands: [], onStart: {})
        .modelContainer(for: [AppSettings.self, ReductionGoal.self], inMemory: true)
}
