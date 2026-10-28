import AVFoundation
import Combine
import OSLog
import SwiftData
import SwiftUI

/// 온보딩(SPEC §4.5). 온보딩 영상(22초, 8장면, `OnboardingFilm`) → 하루 기준 두 단계(당 → 카페인).
/// 로슈·카인 소개는 여기가 아니라 첫 마감 때 한다(대표님 결정). 계정·페이월 없음.
/// 완료 여부는 기기 단위 플래그라 SwiftData가 아니라 UserDefaults에 둔다.
struct OnboardingView: View {
    static let completedKey = "onboardingCompleted"
    /// Debug 전용 실행 인자. CI가 화면을 찍을 때 `-onboardingPage 2`(당 기준)·`3`(카페인 기준)처럼 넘긴다.
    static let pageArgumentKey = "onboardingPage"
    /// Debug 전용. 영상을 이 시각에 멈춰 찍는다(`-onboardingReelAt 8.8`).
    static let reelAtArgumentKey = "onboardingReelAt"
    private static let logger = Logger(subsystem: "com.sugarcap.app", category: "onboarding")

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
    @State private var player: AVPlayer?
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
        .overlay(alignment: .topTrailing) {
            if scene != .reel { topButton(onDark: false) }
        }
        .onAppear {
            if reduceMotion, scene == .reel { scene = .sugar }
        }
    }

    // MARK: 영상

    private var reel: some View {
        TimelineView(.animation(paused: frozenReelAt != nil)) { _ in
            let t = filmTime
            let onDark = OnboardingFilm.isTopDark(at: t)
            ZStack {
                Color.black
                if let player {
                    IntroVideoLayer(player: player)
                }
                OnboardingPeekLayer(t: t)
            }
            .ignoresSafeArea()
            .overlay(alignment: .top) { progress(t: t, onDark: onDark) }
            .overlay(alignment: .topTrailing) { topButton(onDark: onDark) }
            .animation(.easeOut(duration: 0.25), value: onDark)
        }
        // 화면 전체가 "다음 장" 버튼이다(위 70pt는 건너뛰기 자리). 마지막 장에서 누르면 하루 기준으로.
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
        .onAppear(perform: startFilm)
        .onDisappear { player?.pause() }
        // 끝 알림은 재생 스레드에서 온다. 화면 상태를 바꾸니 메인에서 받는다.
        .onReceive(
            NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification).receive(on: DispatchQueue.main)
        ) { note in
            guard frozenReelAt == nil, let item = note.object as? AVPlayerItem, item === player?.currentItem else { return }
            finishReel()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("슈가캡 소개 영상. 하루 당과 카페인을 기록하고, 정한 만큼 덜 마셔 봐요.")
    }

    private var filmTime: Double {
        if let frozenReelAt { return frozenReelAt }
        guard let seconds = player?.currentTime().seconds, seconds.isFinite else { return 0 }
        return min(max(seconds, 0), OnboardingFilm.chapters.end)
    }

    private func progress(t: Double, onDark: Bool) -> some View {
        let tint: Color = onDark ? .white : .ink
        return HStack(spacing: 5) {
            ForEach(0..<OnboardingFilm.chapters.starts.count, id: \.self) { index in
                GeometryReader { bar in
                    Capsule().fill(tint.opacity(onDark ? 0.35 : 0.16))
                        .overlay(alignment: .leading) {
                            Capsule().fill(tint)
                                .frame(width: bar.size.width * OnboardingFilm.chapters.progress(of: index, at: t))
                        }
                }
                .frame(height: 3)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .accessibilityHidden(true)
    }

    private func startFilm() {
        guard player == nil, scene == .reel else { return }
        if reduceMotion && frozenReelAt == nil { return }
        guard let url = Bundle.main.url(forResource: OnboardingFilm.videoName, withExtension: "mp4") else {
            // 번들에 영상이 없으면 바로 하루 기준으로 간다. 빌드 설정 문제라 크게 남긴다.
            Self.logger.fault("온보딩 영상이 번들에 없음: \(OnboardingFilm.videoName, privacy: .public).mp4")
            finishReel()
            return
        }
        let player = AVPlayer(url: url)
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        self.player = player
        if let frozenReelAt {
            player.seek(to: CMTime(seconds: frozenReelAt, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        } else {
            player.play()
        }
    }

    private func nextChapter() {
        guard frozenReelAt == nil else { return }
        let next = OnboardingFilm.chapters.next(after: filmTime)
        if next >= OnboardingFilm.chapters.end {
            finishReel()
        } else {
            player?.seek(to: CMTime(seconds: next, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    private func finishReel() {
        guard scene == .reel else { return }
        player?.pause()
        withAnimation(.easeOut(duration: 0.3)) { scene = .sugar }
    }

    // MARK: 위 버튼(건너뛰기·닫기)

    /// 영상 위에서는 위쪽이 어두운 방일 때 흰 글자에 그림자를 깐다(첫 마감 소개 영상과 같은 처리).
    @ViewBuilder
    private func topButton(onDark: Bool) -> some View {
        let tint: Color = onDark ? .white : Color.ink.opacity(0.72)
        if let onClose {
            Button(action: onClose) {
                Text("닫기")
                    .font(AppFont.pretendard(14, .medium, relativeTo: .footnote))
                    .tapTarget()
            }
            .foregroundStyle(tint)
            .shadow(color: .black.opacity(onDark ? 0.45 : 0), radius: 4, y: 1)
            .padding(.top, 12)
            .padding(.trailing, 12)
            .accessibilityIdentifier("onboarding-close")
        } else if scene == .reel {
            Button(action: finishReel) {
                Text("건너뛰기")
                    .font(AppFont.pretendard(14, .medium, relativeTo: .footnote))
                    .tapTarget()
            }
            .foregroundStyle(tint)
            .shadow(color: .black.opacity(onDark ? 0.45 : 0), radius: 4, y: 1)
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
