import OSLog
import SwiftUI

/// 무엇을 먹이는지. 오늘 화면이 정산 상태를 보고 고른다(SPEC §4.7).
struct FeedingRequest: Identifiable, Equatable {
    enum Kind: Equatable {
        /// 오늘 마감. 적립은 하루가 바뀐 뒤 최종 값으로 한다.
        case closeToday
        /// 어제 미마감분 또는 "안 마셨어요". 하루가 끝났으니 바로 적립한다.
        case pastDay(DayKey)
    }

    let kind: Kind
    let sugarLeftG: Double
    let caffeineLeftMg: Double
    /// 컵 장면 단계를 고르는 데만 쓴다(남은 비율). 적립 계산은 저장소가 따로 한다.
    var limits: DailyLimits = .default
    /// 하루 기준을 넘긴 양. 넘긴 날은 캐릭터가 살짝 아쉬워할 뿐 죄책감 문구·감점은 없다(§4.7).
    var sugarOverG: Double = 0
    var caffeineOverMg: Double = 0

    var id: String {
        switch kind {
        case .closeToday: return "close-today"
        case .pastDay(let day): return "past-\(day.rawValue)"
        }
    }

    func left(_ side: CupSide) -> Double {
        switch side {
        case .sugar: return sugarLeftG
        case .caffeine: return caffeineLeftMg
        }
    }

    func over(_ side: CupSide) -> Double {
        switch side {
        case .sugar: return sugarOverG
        case .caffeine: return caffeineOverMg
        }
    }
}

/// 전체 화면으로 띄울 한 덩어리(요청 + 여는 방식). `fullScreenCover(item:)`에 넘긴다.
struct FeedingPresentation: Identifiable, Equatable {
    let request: FeedingRequest
    let opening: FeedingOpening
    let snapshot: FeedingSnapshot?

    var id: String { request.id }
}

/// 먹이기 화면이 어떻게 열리는지. 첫 마감이면 로슈·카인 소개, 그 뒤로는 마감 진입 모션.
enum FeedingOpening: Equatable {
    case companionIntro
    case dusk
    /// 모션 없이 바로(모션 줄이기, 스크린샷).
    case immediate
}

/// CI 스크린샷 전용(Debug 인자). 특정 단계·전환 시각에 멈춘 화면을 찍는다.
struct FeedingSnapshot: Equatable {
    enum Stage: String { case ask, dropped, eaten, caffeine, summary }
    var stage: Stage = .ask
    var fx: FeedFx?
    var fxAt: Double = 0
    var introAt: Double?
}

/// 먹이기(2026-09-26 HTML 프로토타입 확정). 밤 장면, 당(로슈)·카페인(카인) 화면을 나눠 차례로 먹인다.
///  1) 컵 아래에서 캐릭터가 달라는 몸짓, 컵에 "눌러요" 신호
///  2) 컵을 누르면 흔들리며 빈 컵이 되고 남은 양 방울이 나온다
///  3) 방울을 캐릭터에게 끌어다 놓으면(또는 방울을 누르면) 먹는다
///  4) 카페인도 같은 과정 → 마무리 요약으로 넘어가는 순간에만 저장한다. 중간에 닫으면 남기지 않는다.
/// 하루 한 번 보는 장면이라 연출을 허용한다. 모션 줄이기면 흔들기·전환·튀기를 빼고 결과만 바꾼다.
struct FeedingView: View {
    let request: FeedingRequest
    let opening: FeedingOpening
    let onFeed: () throws -> [FeedResult]
    var snapshot: FeedingSnapshot?

    enum Step { case sugar, caffeine, done }
    enum Stage { case ask, dropped, eaten }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var step: Step = .sugar
    @State private var stage: Stage = .ask
    @State private var results: [FeedResult]?
    @State private var errorText: String?
    /// 소개 릴을 보는 중.
    @State private var isIntroPlaying: Bool
    /// 밤 장면을 그릴지. 마감 진입 모션은 처음에 비워 두고(밑의 오늘 화면이 보인다) 하늘이 덮은 순간 켠다.
    @State private var isSceneVisible: Bool
    @State private var fx: FeedFx?
    @State private var fxRun = 0
    @State private var shakeTrigger = 0
    @State private var bounceTrigger = 0
    @State private var dragOffset: CGSize = .zero
    @State private var isOverCharacter = false
    @State private var isDropEaten = false
    @State private var characterFrame: CGRect = .zero
    @State private var summaryIn = false

    private static let logger = Logger(subsystem: "com.sugarcap.app", category: "feeding")

    init(request: FeedingRequest, opening: FeedingOpening, snapshot: FeedingSnapshot? = nil, onFeed: @escaping () throws -> [FeedResult]) {
        self.request = request
        self.opening = opening
        self.snapshot = snapshot
        self.onFeed = onFeed
        _isIntroPlaying = State(initialValue: opening == .companionIntro)
        _isSceneVisible = State(initialValue: opening == .immediate)
        _fx = State(initialValue: opening == .dusk ? .dusk(title: request.kind == .closeToday ? "오늘 마감" : "어제 마감") : nil)
    }

    private var side: CupSide { step == .caffeine ? .caffeine : .sugar }

    private var dateText: String {
        Date().formatted(.dateTime.month().day().weekday(.wide))
    }

    var body: some View {
        ZStack {
            if isSceneVisible {
                Group {
                    if step == .done { summary } else { scene }
                }
                .transition(.identity)
            }
            if isIntroPlaying {
                CompanionIntroView(onFinish: finishIntro, frozenAt: snapshot?.introAt)
            }
            if let fx {
                TimedPlayer(
                    duration: fx.duration,
                    cues: [(fx.swapAt, { swap(for: fx) }), (fx.duration, { self.fx = nil })],
                    frozenAt: snapshot?.fx == fx ? snapshot?.fxAt : nil
                ) { t in
                    FeedFxOverlay(fx: fx, t: t, date: dateText)
                }
                .id(fxRun)
            }
        }
        // 마감 진입 전에는 비워 둬 밑의 오늘 화면 위로 밤하늘이 차오르게 한다.
        .presentationBackground(isSceneVisible || isIntroPlaying ? Color.black : Color.clear)
        .preferredColorScheme(isIntroPlaying ? .light : .dark)
        .onAppear(perform: applySnapshot)
    }

    // MARK: - 밤 장면(당·카페인)

    private var scene: some View {
        let left = request.left(side)
        let over = request.over(side)
        let limit = side.limit(request.limits)
        let cupStart = CupLevel.step(remaining: left, limit: limit)

        return GeometryReader { proxy in
            let sx = proxy.size.width / 402
            let sy = proxy.size.height / 874
            ZStack(alignment: .topLeading) {
                CupView(step: stage == .ask ? cupStart : 0, setID: side.cupSetID)
                    .keyframeAnimator(initialValue: 0.0, trigger: shakeTrigger) { content, angle in
                        content.rotationEffect(.degrees(angle), anchor: UnitPoint(x: 0.5, y: 0.9))
                    } keyframes: { _ in
                        KeyframeTrack {
                            CubicKeyframe(-4.0, duration: 0.09)
                            CubicKeyframe(3.5, duration: 0.09)
                            CubicKeyframe(-3.0, duration: 0.09)
                            CubicKeyframe(2.0, duration: 0.09)
                            CubicKeyframe(-1.0, duration: 0.09)
                            CubicKeyframe(0.0, duration: 0.1)
                        }
                    }
                    .ignoresSafeArea()

                NightScrim()

                if stage == .ask {
                    Button(action: tapCup) {
                        // 투명한 바탕은 누르는 판정이 없다. 영역 전체를 누를 수 있게 모양을 준다.
                        Color.clear
                            .contentShape(Rectangle())
                            .overlay(alignment: .center) { CupPulse().offset(y: 440 * sy * 0.08) }
                    }
                    .buttonStyle(.plain)
                    .frame(width: proxy.size.width - 140 * sx, height: 440 * sy)
                    .offset(x: 70 * sx, y: 250 * sy - proxy.safeAreaInsets.top)
                    .accessibilityLabel("\(side.label) 컵 누르기")
                    .accessibilityIdentifier("feeding-cup")
                }

                headline(left: left, over: over)

                if stage != .ask {
                    drop(left: left, limit: limit)
                        .position(x: proxy.size.width / 2, y: 400 * sy - proxy.safeAreaInsets.top + 60)
                        .offset(dragOffset)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .overlay(alignment: .bottom) {
                asker(left: left, over: over)
                    .padding(.bottom, 150 * sy - 34)
            }
            .overlay(alignment: .bottom) { foot }
            .overlay(alignment: .topTrailing) { closeButton }
        }
        .coordinateSpace(.named("feed"))
        .sensoryFeedback(.impact(weight: .light), trigger: shakeTrigger)
        .sensoryFeedback(.success, trigger: bounceTrigger)
    }

    private func headline(left: Double, over: Double) -> some View {
        let caption: String = {
            switch stage {
            case .ask:
                return over > 0
                    ? "오늘은 \(side.label)을 \(Amount.number(over)) \(side.unit) 넘겼어요.\n그래도 \(side.characterNameWithIga) 기다려요. 컵을 눌러 주세요."
                    : "\(side.characterNameWithIga) 기다려요.\n컵을 눌러 주세요."
            case .dropped: return "방울을 \(side.characterName)에게 끌어다 주세요."
            case .eaten: return side == .sugar ? "다음은 카인 차례예요." : "둘 다 먹었어요."
            }
        }()
        let kind = request.kind == .closeToday ? "오늘 마감" : "어제 남은 음료"

        return VStack(alignment: .leading, spacing: 0) {
            NightDateLabel(text: dateText)
                .padding(.top, 8)
            Text("\(kind) · \(side == .sugar ? 1 : 2)/2")
                .font(AppFont.pretendard(11, .semibold, relativeTo: .caption2))
                .tracking(1.3)
                .foregroundStyle(Color.nightKicker)
                .padding(.top, 28)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(Amount.number(stage == .eaten ? 0 : left))
                    .heroNumber()
                    .contentTransition(.numericText(countsDown: true))
                Text(side.unit)
                    .heroUnit()
                    .padding(.leading, 2)
            }
            .foregroundStyle(.white)
            .animation(.easeOut(duration: 0.5), value: stage)
            Text("남은 \(side.label) · \(caption)")
                .font(AppFont.pretendard(13, .regular, relativeTo: .footnote))
                .tracking(0.3)
                .lineSpacing(4)
                .foregroundStyle(.white.opacity(0.78))
                .padding(.top, 8)
                .fixedSize(horizontal: false, vertical: true)
            if let errorText {
                Text(errorText)
                    .font(AppFont.pretendard(13, .semibold, relativeTo: .footnote))
                    .foregroundStyle(Color(red: 1, green: 0.62, blue: 0.62))
                    .padding(.top, 10)
            }
        }
        .shadow(color: .black.opacity(0.28), radius: 10, y: 1)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("feeding-headline")
    }

    /// 방울. 남은 비율만큼 크되 너무 작아지지 않게. 기준을 넘긴 날(0)도 먹이면 1점이니 방울은 준다.
    private func drop(left: Double, limit: Double) -> some View {
        let ratio = limit > 0 ? min(1, left / limit) : 0
        let size = 58 + 30 * ratio
        return VStack(spacing: 8) {
            Image(side.dropAsset)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
            Text("\(Amount.number(left)) \(side.unit)")
                .font(AppFont.pretendard(13, .bold, relativeTo: .footnote))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.black.opacity(0.26), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.28)))
        }
        .modifier(DropEmerge(isActive: !reduceMotion && stage == .dropped))
        .scaleEffect(isDropEaten ? 0.3 : 1)
        .opacity(isDropEaten || stage == .eaten ? 0 : 1)
        .animation(.easeIn(duration: 0.18), value: isDropEaten)
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("feed"))
                .onChanged { value in
                    guard stage == .dropped else { return }
                    dragOffset = value.translation
                    isOverCharacter = characterFrame.insetBy(dx: -36, dy: -36).contains(value.location)
                }
                .onEnded { value in
                    guard stage == .dropped else { return }
                    let moved = hypot(value.translation.width, value.translation.height)
                    if moved < 8 || characterFrame.insetBy(dx: -36, dy: -36).contains(value.location) {
                        feedDrop()
                    } else {
                        isOverCharacter = false
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.62)) { dragOffset = .zero }
                    }
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(side.label) \(Amount.number(left)) \(side.unit)를 \(side.characterName)에게 주기")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { feedDrop() }
        .accessibilityIdentifier("feeding-drop")
    }

    private func asker(left: Double, over: Double) -> some View {
        let bubble: String = {
            switch stage {
            case .ask: return "주세요!"
            case .dropped: return "여기요!"
            case .eaten: return over > 0 ? "조금 아쉬워요" : "냠, \(Amount.number(left)) \(side.unit)"
            }
        }()
        return VStack(spacing: 8) {
            NightBubble(text: bubble)
                .id("\(side)-\(stage)")
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            Image(side.characterAsset)
                .resizable()
                .scaledToFit()
                .frame(height: side == .sugar ? 150 : 128)
                .modifier(CharacterPose(
                    pose: pose(over: over),
                    bounceTrigger: bounceTrigger,
                    reduceMotion: reduceMotion
                ))
                .background {
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { characterFrame = geo.frame(in: .named("feed")) }
                            .onChange(of: geo.frame(in: .named("feed"))) { _, frame in characterFrame = frame }
                    }
                }
                .accessibilityLabel(side.characterName)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: stage)
        .allowsHitTesting(false)
    }

    private func pose(over: Double) -> CharacterPose.Pose {
        switch stage {
        case .ask: return over > 0 ? .sulk : .asking
        case .dropped: return isOverCharacter ? .ready : (over > 0 ? .sulk : .waiting)
        case .eaten: return .rest
        }
    }

    private var foot: some View {
        VStack(spacing: 12) {
            ZStack {
                if stage == .eaten {
                    Button(action: nextStep) {
                        Text(side == .sugar ? "다음 · 카인" : "마무리")
                            .ctaLabel()
                            .foregroundStyle(.white)
                            .background(Color.accentColor, in: Capsule())
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityIdentifier("feeding-next")
                    .transition(.opacity)
                }
            }
            .frame(minHeight: 56)
            // 안내 자리는 늘 잡아 둔다. 문구가 빠져도 버튼이 내려앉지 않게.
            Text("마감 뒤에 마신 음료도 오늘 몫으로 빠져요")
                .font(AppFont.pretendard(12, .regular, relativeTo: .caption))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .opacity(request.kind == .closeToday && stage != .eaten ? 1 : 0)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
        .animation(.easeOut(duration: 0.25), value: stage)
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Text("닫기")
                .font(AppFont.pretendard(15, .regular, relativeTo: .subheadline))
                .foregroundStyle(.white)
                .tapTarget()
        }
        .padding(.trailing, 16)
        .accessibilityIdentifier("feeding-close")
    }

    // MARK: - 마무리 요약

    private var summary: some View {
        ZStack(alignment: .topLeading) {
            CupView(step: 0, setID: CupSide.sugar.cupSetID)
                .ignoresSafeArea()
            NightScrim()

            VStack(alignment: .leading, spacing: 0) {
                NightDateLabel(text: dateText)
                    .padding(.top, 8)
                    .summaryEntrance(summaryIn, delay: 0)
                Text("잘 먹었어요")
                    .font(AppFont.pretendard(11, .semibold, relativeTo: .caption2))
                    .tracking(1.3)
                    .foregroundStyle(Color.nightKicker)
                    .padding(.top, 28)
                    .summaryEntrance(summaryIn, delay: 0.07)
                Text("오늘도\n잘 마무리했어요")
                    .font(AppFont.pretendard(40, .bold, relativeTo: .largeTitle))
                    .tracking(-0.8)
                    .lineSpacing(2)
                    .foregroundStyle(.white)
                    .padding(.top, 14)
                    .summaryEntrance(summaryIn, delay: 0.14)
                Text(request.kind == .closeToday ? "호감도는 내일 아침에 반영돼요." : "호감도에 바로 반영했어요.")
                    .font(AppFont.pretendard(13, .regular, relativeTo: .footnote))
                    .foregroundStyle(.white.opacity(0.78))
                    .padding(.top, 8)
                    .summaryEntrance(summaryIn, delay: 0.21)
            }
            .shadow(color: .black.opacity(0.28), radius: 10, y: 1)
            .padding(.horizontal, 24)
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 28) {
                HStack(alignment: .bottom, spacing: 0) {
                    summaryColumn(.sugar).summaryEntrance(summaryIn, delay: 0.2, distance: 60)
                    summaryColumn(.caffeine).summaryEntrance(summaryIn, delay: 0.32, distance: 60)
                }
                Button { dismiss() } label: {
                    Text("완료")
                        .ctaLabel()
                        .foregroundStyle(.white)
                        .background(Color.accentColor, in: Capsule())
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityIdentifier("feeding-done")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
        .overlay(alignment: .topTrailing) { closeButton }
        // 하루 한 번 보는 한 장짜리 요약이라 제목·캐릭터·숫자가 한 화면에 들어가야 한다. 글자 상한을 둔다.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .onAppear {
            if reduceMotion { summaryIn = true } else { withAnimation { summaryIn = true } }
        }
    }

    private func summaryColumn(_ side: CupSide) -> some View {
        let result = results?.first { $0.side == side }
        let note: String = {
            if let result, result.leveledUp { return "\(AffinityMath.stageName(level: result.levelAfter))가 됐어요" }
            return request.over(side) > 0 ? "조금 아쉬워요" : "\(side.characterNameWithIga) 먹었어요"
        }()
        return VStack(spacing: 10) {
            NightBubble(text: note)
            Image(side.characterAsset)
                .resizable()
                .scaledToFit()
                .frame(height: side == .sugar ? 150 : 104)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(Amount.number(summaryIn ? request.left(side) : 0))
                    .font(AppFont.pretendard(44, .bold, relativeTo: .largeTitle))
                    .tracking(-1.8)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.9).delay(0.3), value: summaryIn)
                Text(side.unit)
                    .font(AppFont.pretendard(17, .medium, relativeTo: .body))
                    .opacity(0.85)
            }
            .foregroundStyle(.white)
            .padding(.top, 6)
            Text(side.label)
                .font(AppFont.pretendard(11, .semibold, relativeTo: .caption2))
                .tracking(1.3)
                .foregroundStyle(Color.nightKicker)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: - 동작

    private func tapCup() {
        guard stage == .ask else { return }
        if !reduceMotion { shakeTrigger += 1 }
        withAnimation(.easeInOut(duration: 0.6)) { stage = .dropped }
    }

    private func feedDrop() {
        guard stage == .dropped else { return }
        isDropEaten = true
        isOverCharacter = false
        Task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 180))
            stage = .eaten
            bounceTrigger += 1
        }
    }

    private func nextStep() {
        guard stage == .eaten else { return }
        let next: FeedFx = side == .sugar ? .turn : .night
        if reduceMotion {
            swap(for: next)
        } else {
            fxRun += 1
            fx = next
        }
    }

    /// 전환이 화면을 다 덮은 순간 밑 화면을 바꾼다.
    private func swap(for fx: FeedFx) {
        switch fx {
        case .dusk:
            isSceneVisible = true
        case .turn:
            step = .caffeine
            stage = .ask
            resetDrop()
        case .night:
            do {
                results = try onFeed()
                step = .done
            } catch {
                Self.logger.error("먹이기 저장 실패(\(request.id, privacy: .public)): \(String(describing: error), privacy: .public)")
                errorText = "저장하지 못했어요. 다시 시도해 주세요."
            }
        }
    }

    private func resetDrop() {
        isDropEaten = false
        isOverCharacter = false
        dragOffset = .zero
    }

    private func finishIntro() {
        UserDefaults.standard.set(true, forKey: CompanionIntro.seenKey)
        isIntroPlaying = false
        isSceneVisible = true
    }

    private func applySnapshot() {
        #if DEBUG
        guard let snapshot else { return }
        switch snapshot.stage {
        case .ask: break
        case .dropped: stage = .dropped
        case .eaten: stage = .eaten
        case .caffeine: step = .caffeine
        case .summary:
            results = []
            step = .done
            summaryIn = true
        }
        // 멈춘 전환은 그 시각까지의 신호(밑 화면 바꾸기)를 재생기가 한꺼번에 부른다.
        if let frozen = snapshot.fx {
            fx = frozen
        }
        #endif
    }
}

// MARK: - 조각

/// 밤 장면 덮개. 어둡게 칠하지 않고 옅은 검정 그라데이션만 깐다(대표님: "검정 그라데이션만 살짝").
private struct NightScrim: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.55), location: 0),
                .init(color: .black.opacity(0.18), location: 0.34),
                .init(color: .black.opacity(0.08), location: 0.58),
                .init(color: .black.opacity(0.5), location: 1),
            ],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private struct NightDateLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(AppFont.pretendard(11, .medium, relativeTo: .caption2))
            .tracking(1.5)
            .foregroundStyle(.white.opacity(0.7))
    }
}

private struct NightBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(AppFont.pretendard(12, .semibold, relativeTo: .caption))
            .tracking(0.3)
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(minHeight: 28)
            .background(.white.opacity(0.14), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.22)))
    }
}

/// 컵 누르기 신호: 흰 링이 퍼지며 사라지기를 되풀이한다(또렷한 선, 번짐 없음).
private struct CupPulse: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            Circle().strokeBorder(.white.opacity(0.85), lineWidth: 2).frame(width: 92, height: 92)
        } else {
            PhaseAnimator([false, true]) { expanded in
                Circle()
                    .strokeBorder(.white.opacity(0.85), lineWidth: 2)
                    .frame(width: 92, height: 92)
                    .scaleEffect(expanded ? 1.5 : 0.6)
                    .opacity(expanded ? 0 : 0.9)
            } animation: { expanded in
                expanded ? .easeOut(duration: 1.6) : .linear(duration: 0.01)
            }
        }
    }
}

/// 방울이 컵에서 솟아 나오고(한 번) 그 뒤 둥실거린다.
private struct DropEmerge: ViewModifier {
    let isActive: Bool
    @State private var emerged = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(x: emerged ? 1 : 0.2, y: emerged ? 1 : 0.1)
            .offset(y: emerged ? 0 : 60)
            .opacity(emerged ? 1 : 0)
            .phaseAnimator([0.0, -8.0]) { view, lift in
                view.offset(y: isActive ? lift : 0)
            } animation: { _ in .easeInOut(duration: 1.3) }
            .onAppear {
                if isActive {
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.6).delay(0.2)) { emerged = true }
                } else {
                    emerged = true
                }
            }
    }
}

/// 캐릭터 몸짓. 원화는 정지 그림 1장이라 transform으로 흉내 낸다(§5, 애니메이션 원화가 오면 교체).
private struct CharacterPose: ViewModifier {
    enum Pose { case asking, waiting, sulk, ready, rest }
    let pose: Pose
    let bounceTrigger: Int
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .phaseAnimator([false, true]) { view, up in
                view
                    .rotationEffect(.degrees(pose == .asking && !reduceMotion ? (up ? 3 : -4) : 0), anchor: .bottom)
                    .offset(y: pose == .asking && !reduceMotion ? (up ? -6 : 0) : 0)
            } animation: { _ in .easeInOut(duration: 0.55) }
            .rotationEffect(.degrees(pose == .sulk ? -8 : 0), anchor: .bottom)
            .scaleEffect(scale, anchor: .bottom)
            .offset(y: pose == .waiting ? -4 : 0)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: pose)
            .keyframeAnimator(initialValue: 1.0, trigger: bounceTrigger) { view, bounce in
                view.scaleEffect(reduceMotion ? 1 : bounce, anchor: .bottom)
            } keyframes: { _ in
                KeyframeTrack {
                    SpringKeyframe(1.12, duration: 0.2)
                    SpringKeyframe(1.0, duration: 0.3)
                }
            }
    }

    private var scale: CGFloat {
        switch pose {
        case .sulk: return 0.94
        case .waiting: return 1.03
        case .ready: return 1.12
        case .asking, .rest: return 1
        }
    }
}

private extension View {
    /// 요약 화면 등장: 아래에서 올라오며 나타난다. 줄마다 조금씩 늦게.
    func summaryEntrance(_ isIn: Bool, delay: Double, distance: CGFloat = 24) -> some View {
        opacity(isIn ? 1 : 0)
            .offset(y: isIn ? 0 : distance)
            .animation(.spring(response: 0.55, dampingFraction: 0.82).delay(delay), value: isIn)
    }
}
