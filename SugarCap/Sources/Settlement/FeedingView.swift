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

    /// 그날 합계. 정산 화면에서 연 기록 시트의 서빙 패널이 "마시면 남는 양"을 계산할 때 쓴다.
    var totals: DayTotals {
        DayTotals(
            sugarG: limits.sugarG - sugarLeftG + sugarOverG,
            caffeineMg: limits.caffeineMg - caffeineLeftMg + caffeineOverMg,
            leftSugarG: sugarLeftG,
            leftCaffeineMg: caffeineLeftMg,
            overSugarG: sugarOverG,
            overCaffeineMg: caffeineOverMg
        )
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
    /// 설정 테스트 카드에서 연 먹이기. 마감·적립·음료 추가를 저장하지 않는다.
    var isRehearsal = false

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
    enum Stage: String { case ask, patting, dropped, eaten, caffeine, summary }
    var stage: Stage = .ask
    var fx: FeedFx?
    var fxAt: Double = 0
    var introAt: Double?
}

/// 먹이기(2026-09-26 HTML 프로토타입 확정). 밤 장면, 당(로슈)·카페인(카인) 화면을 나눠 차례로 먹인다.
///  1) 캐릭터가 컵에 붙어 조른다(로슈 = 컵 옆에 매달려 까치발, 카인 = 가장자리에서 발 동동, `FeedingCharacter`). 컵에 "눌러요" 신호
///  2) 컵을 누르면 흔들리며 빈 컵이 되고 남은 양 방울이 나온다
///  3) 방울을 캐릭터에게 끌어다 놓으면(또는 방울을 누르면) 먹는다
///  4) 카페인도 같은 과정 → 마무리 요약으로 넘어가는 순간에만 저장한다. 중간에 닫으면 남기지 않는다.
/// 하루 한 번 보는 장면이라 연출을 허용한다. 모션 줄이기면 흔들기·전환·튀기를 빼고 결과만 바꾼다.
struct FeedingView: View {
    let opening: FeedingOpening
    let catalog: CatalogIndex
    let onFeed: () throws -> [FeedResult]
    /// 정산 화면에서 음료를 더 기록한다. 그날 남은 양을 다시 계산한 요청을 돌려준다.
    let onAddDrink: (Entry) throws -> FeedingRequest
    var snapshot: FeedingSnapshot?

    /// 음료를 더 기록하면 바뀐다.
    @State private var request: FeedingRequest
    @State private var isRecordPresented = false

    enum Step { case sugar, caffeine, done }
    /// searching = 먹일 게 없는 날(남은 0) 컵을 누른 뒤 방울이 나올 때까지(빈 컵 털기, 2026-10-02 시안 `feeding-empty.html`).
    enum Stage { case ask, searching, dropped, eaten }
    /// 빈 컵 털기 박자: 눌러도 안 나옴 → 갸웃 → 컵을 톡톡 세 번(세 번째에 작은 방울).
    enum SearchBeat { case emptied, puzzled, patting }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var step: Step = .sugar
    @State private var stage: Stage = .ask
    @State private var searchBeat: SearchBeat = .emptied
    @State private var patTrigger = 0
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
    /// 요약 바닥 면 윗선(캐릭터 발밑, 좌표 공간 "summary").
    @State private var summaryFloorY: CGFloat = 0

    private static let logger = Logger(subsystem: "com.sugarcap.app", category: "feeding")

    init(
        request: FeedingRequest,
        opening: FeedingOpening,
        catalog: CatalogIndex,
        snapshot: FeedingSnapshot? = nil,
        onFeed: @escaping () throws -> [FeedResult],
        onAddDrink: @escaping (Entry) throws -> FeedingRequest
    ) {
        _request = State(initialValue: request)
        self.opening = opening
        self.catalog = catalog
        self.snapshot = snapshot
        self.onFeed = onFeed
        self.onAddDrink = onAddDrink
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
        .sheet(isPresented: $isRecordPresented) {
            FeedingRecordSheet(catalog: catalog, request: request, onRecord: addDrink)
                // 앱은 라이트 전용(§5)이다. 밤 장면의 다크가 시트로 번지지 않게 한다.
                .preferredColorScheme(.light)
        }
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
                // 흔들 때 컵 장면이 돌아도 모서리에 검은 바탕이 비치지 않게 벽은 따로 고정해 깐다.
                CupView.wallColor.ignoresSafeArea()
                CupView(step: stage == .ask ? cupStart : 0, setID: side.cupSetID)
                    .modifier(CupShake(trigger: shakeTrigger))
                    .modifier(CupTap(trigger: patTrigger))
                    .ignoresSafeArea()

                NightScrim()

                // 캐릭터는 덮개 위(덮개 밑이면 칙칙해진다). 컵과 같이 흔들린다.
                FeedingCharacter(
                    side: side, step: stage == .ask ? cupStart : 0,
                    mood: mood(left: left, over: over), bubble: bubble(left: left),
                    targetFrame: $characterFrame
                )
                .id(side)
                .modifier(CupShake(trigger: shakeTrigger))
                .modifier(CupTap(trigger: patTrigger))
                .ignoresSafeArea()
                .allowsHitTesting(false)

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

                if stage == .dropped || stage == .eaten {
                    // 먹일 게 없는 날의 작은 방울은 컵 입구 바로 아래에 뜬다(이름표 없음).
                    let dropY: CGFloat = left <= 0 ? 372 * sy : 400 * sy + 60
                    drop(left: left, limit: limit, rise: 76 * sy)
                        .position(x: proxy.size.width / 2, y: dropY - proxy.safeAreaInsets.top)
                        .offset(dragOffset)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .overlay(alignment: .bottom) { foot }
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 0) {
                    skipButton
                    closeButton
                }
            }
        }
        .coordinateSpace(.named("feed"))
        .sensoryFeedback(.impact(weight: .light), trigger: shakeTrigger)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: patTrigger)
        .sensoryFeedback(.success, trigger: bounceTrigger)
    }

    private func headline(left: Double, over: Double) -> some View {
        let caption: String = {
            // 줄을 짧게 끊는다. 길면 가장자리 오른쪽에 선 카인 몸 밑으로 글이 들어간다.
            switch stage {
            case .ask:
                return over > 0
                    ? "\(Amount.number(over)) \(side.unit) 넘겼어요.\n그래도 \(side.characterNameWithIga) 기다려요.\n컵을 눌러 주세요."
                    : "\(side.characterNameWithIga) 기다려요.\n컵을 눌러 주세요."
            case .searching:
                return searchBeat == .patting ? "컵이 비었어요.\n\(side.characterNameWithIga) 털어 보는 중이에요." : "컵이 비었어요."
            case .dropped:
                return left <= 0
                    ? "마지막 한 방울이 나왔어요.\n\(side.characterName)에게 끌어다 주세요."
                    : "방울을 \(side.characterName)에게 끌어다 주세요."
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
                Text(AttributedString.heroDigits(Amount.number(stage == .eaten ? 0 : left)))
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
    /// 먹일 게 없는 날은 이름표 없는 아주 작은 방울(22pt)이 컵 입구에서 톡 튀어나온다. 잡기 쉽게 누르는 영역은 44pt.
    /// `rise` = 컵 입구에서 방울 자리까지 내려오는 거리.
    private func drop(left: Double, limit: Double, rise: CGFloat) -> some View {
        let isCrumb = left <= 0
        let ratio = limit > 0 ? min(1, left / limit) : 0
        let size: CGFloat = isCrumb ? 22 : 58 + 30 * ratio
        let isMoving = !reduceMotion && stage == .dropped
        return VStack(spacing: 8) {
            Image(side.dropAsset)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
            if !isCrumb {
                Text("\(Amount.number(left)) \(side.unit)")
                    .font(AppFont.pretendard(13, .bold, relativeTo: .footnote))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.26), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.28)))
            }
        }
        .padding(isCrumb ? 11 : 0)
        .contentShape(Rectangle())
        .modifier(DropEmerge(isActive: isMoving && !isCrumb))
        .modifier(DropPop(isActive: isMoving && isCrumb, rise: rise))
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
        .accessibilityLabel(
            isCrumb
                ? "마지막 한 방울을 \(side.characterName)에게 주기"
                : "\(side.label) \(Amount.number(left)) \(side.unit)를 \(side.characterName)에게 주기"
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { feedDrop() }
        .accessibilityIdentifier("feeding-drop")
    }

    private func bubble(left: Double) -> String {
        switch stage {
        case .ask: return "주세요!"
        case .searching:
            switch searchBeat {
            case .emptied: return "주세요!"
            case .puzzled: return "어라?"
            case .patting: return "톡, 톡"
            }
        case .dropped: return "여기요!"
        case .eaten: return left <= 0 ? "냠, 고마워요" : "냠, \(Amount.number(left)) \(side.unit)"
        }
    }

    private func mood(left: Double, over: Double) -> FeedingCharacter.Mood {
        switch stage {
        case .ask: return over > 0 ? .sulking : .asking
        case .searching:
            switch searchBeat {
            case .emptied: return .emptied
            case .puzzled: return .puzzled
            case .patting: return .patting
            }
        case .dropped: return isOverCharacter ? .ready : .waiting
        case .eaten: return left <= 0 ? .savoring : .eaten
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
                } else if step == .sugar && stage == .ask {
                    // 깜빡한 음료를 먹이기 전에 넣는다(2026-10-02 대표님). 먹이기를 시작하면 숨긴다.
                    // 유리 알약이 "구리다"(2026-10-05 대표님) → 밤 장면 위 흰 단색 칸. 그림자·유리 없음.
                    Button { isRecordPresented = true } label: {
                        Label("음료 추가", systemImage: "plus")
                            .font(AppFont.pretendard(15, .bold, relativeTo: .subheadline))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 20)
                            .frame(minHeight: 48)
                            .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityIdentifier("feeding-add-drink")
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

    /// 컵 누르기·방울 끌기를 건너뛰고 바로 먹인다(2026-10-02 대표님). 적립은 끝까지 먹였을 때와 같다.
    private var skipButton: some View {
        Button(action: skip) {
            Text("건너뛰기")
                .font(AppFont.pretendard(15, .regular, relativeTo: .subheadline))
                .foregroundStyle(.white)
                .tapTarget()
        }
        .accessibilityIdentifier("feeding-skip")
    }

    // MARK: - 마무리 요약

    /// 밤 전환(남색)에서 이어지는 남색 밤(2026-10-01 HTML 시안 확정). 둘이 정면으로 나란히 서고 아래에 먹은 양.
    /// 캐릭터가 허공에 뜨지 않게 발밑부터 한 톤 밝은 남색 바닥 면을 깐다. 완료 버튼은 남색 위에서 보이게 흰 바탕.
    private var summary: some View {
        ZStack(alignment: .topLeading) {
            Color.nightSky.ignoresSafeArea()
            NightSkyDecor(isIn: summaryIn).ignoresSafeArea()
            Color(red: 0x1F / 255, green: 0x2C / 255, blue: 0x47 / 255)
                .padding(.top, summaryFloorY)
                .ignoresSafeArea(edges: .bottom)
                .opacity(summaryFloorY > 0 ? 1 : 0)

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
                    summaryColumn(.sugar, delay: 0.2)
                    summaryColumn(.caffeine, delay: 0.32)
                }
                Button { dismiss() } label: {
                    Text("완료")
                        .ctaLabel()
                        .foregroundStyle(Color.ink)
                        .background(Color.wall, in: Capsule())
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityIdentifier("feeding-done")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
        .overlay(alignment: .topTrailing) { closeButton }
        .coordinateSpace(.named("summary"))
        // 하루 한 번 보는 한 장짜리 요약이라 제목·캐릭터·숫자가 한 화면에 들어가야 한다. 글자 상한을 둔다.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .onAppear {
            if reduceMotion { summaryIn = true } else { withAnimation { summaryIn = true } }
        }
    }

    /// 말풍선·숫자는 아래에서 올라오고, 캐릭터는 따로 위에서 떨어져 들어온다(`SummaryCharacter`).
    private func summaryColumn(_ side: CupSide, delay: Double) -> some View {
        let result = results?.first { $0.side == side }
        let note: String = {
            if let result, result.leveledUp { return "\(AffinityMath.stageName(level: result.levelAfter))가 됐어요" }
            return request.over(side) > 0 ? "조금 아쉬워요" : "\(side.characterNameWithIga) 먹었어요"
        }()
        return VStack(spacing: 10) {
            NightBubble(text: note)
                .summaryEntrance(summaryIn, delay: delay + 0.4)
            SummaryCharacter(side: side, isIn: summaryIn, delay: delay)
                // 틀 위 여유(떨어져 들어오는 자리)는 말풍선과 겹쳐 둔다.
                .padding(.top, -SummaryCharacter.headroom)
                .background {
                    if side == .sugar {
                        GeometryReader { geo in
                            Color.clear
                                .onAppear { summaryFloorY = geo.frame(in: .named("summary")).maxY - 4 }
                                .onChange(of: geo.frame(in: .named("summary")).maxY) { _, y in summaryFloorY = y - 4 }
                        }
                    }
                }
                .accessibilityLabel(side.characterName)
            summaryAmount(side)
                .summaryEntrance(summaryIn, delay: delay, distance: 60)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func summaryAmount(_ side: CupSide) -> some View {
        VStack(spacing: 10) {
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
    }

    // MARK: - 동작

    private func tapCup() {
        guard stage == .ask else { return }
        if !reduceMotion { shakeTrigger += 1 }
        if request.left(side) <= 0, !reduceMotion {
            searchBeat = .emptied
            stage = .searching
            searchEmptyCup()
        } else {
            withAnimation(.easeInOut(duration: 0.6)) { stage = .dropped }
        }
    }

    /// 빈 컵 털기: 0.65초 뒤 갸웃, 0.4초 뒤 톡톡(`FeedingCharacter.patTimes`), 세 번째 톡에 작은 방울.
    private func searchEmptyCup() {
        let current = side
        Task {
            func wait(_ seconds: Double) async -> Bool {
                try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
                return stage == .searching && side == current
            }
            guard await wait(0.65) else { return }
            searchBeat = .puzzled
            guard await wait(0.4) else { return }
            searchBeat = .patting
            var last = 0.0
            for at in FeedingCharacter.patTimes {
                guard await wait(at - last) else { return }
                last = at
                patTrigger += 1
            }
            stage = .dropped
        }
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
            searchBeat = .emptied
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

    private func addDrink(_ entry: Entry) {
        do {
            request = try onAddDrink(entry)
            errorText = nil
        } catch {
            Self.logger.error("정산 중 음료 추가 실패(\(request.id, privacy: .public)): \(String(describing: error), privacy: .public)")
            errorText = "음료를 저장하지 못했어요. 다시 시도해 주세요."
        }
    }

    /// 도는 중인 전환은 끊고, 빈 컵 털기 태스크는 stage가 바뀌면 스스로 멈춘다.
    private func skip() {
        guard step != .done else { return }
        fx = nil
        stage = .ask
        resetDrop()
        do {
            results = try onFeed()
            step = .done
        } catch {
            Self.logger.error("건너뛰기 저장 실패(\(request.id, privacy: .public)): \(String(describing: error), privacy: .public)")
            errorText = "저장하지 못했어요. 다시 시도해 주세요."
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
        case .patting:
            stage = .searching
            searchBeat = .patting
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

struct NightBubble: View {
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

/// 먹일 게 없는 날의 작은 방울: 컵 입구(`rise`만큼 위)에서 톡 튀어 올랐다가 제자리로 떨어지고, 그 뒤 살짝 둥실거린다.
private struct DropPop: ViewModifier {
    let isActive: Bool
    let rise: CGFloat
    @State private var fired = false

    func body(content: Content) -> some View {
        content
            // 끝 값(1)을 처음 값으로 둬서 재생이 끝나도 제자리에 남는다.
            .keyframeAnimator(initialValue: 1.0, trigger: fired) { view, k in
                let arc: Double = Double(rise) * 1.6 * sin(Double.pi * k)
                let fall: Double = Double(rise) * (1 - k)
                view
                    .scaleEffect(min(1, 0.3 + k * 3))
                    .offset(y: -fall - arc)
            } keyframes: { _ in
                KeyframeTrack {
                    MoveKeyframe(0.0)
                    CubicKeyframe(1.0, duration: 0.6, startVelocity: 3, endVelocity: 0)
                }
            }
            .phaseAnimator([0.0, -3.0]) { view, lift in
                view.offset(y: isActive ? lift : 0)
            } animation: { _ in .easeInOut(duration: 1.6) }
            .opacity(fired || !isActive ? 1 : 0)
            .onAppear {
                if isActive { fired = true }
            }
    }
}

/// 캐릭터가 빈 컵을 톡톡 칠 때마다 컵이 작게 떨린다(누를 때 흔들림 `CupShake`의 축소판). 컵 장면과 캐릭터 층에 같이 건다.
private struct CupTap: ViewModifier {
    let trigger: Int

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, x in
                view.offset(x: x)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(1.2, duration: 0.05)
                    CubicKeyframe(-0.6, duration: 0.08)
                    CubicKeyframe(0.0, duration: 0.1)
                }
            }
    }
}

/// 컵을 누르면 짧게 떨린다. 컵 장면과 캐릭터 층에 같이 건다(같은 박자로 흔들리게).
/// 장면이 식탁까지 든 사진 한 장이라 돌리면 식탁째 기울어 부자연스러웠다(대표님 2026-10-05: ±4° 회전 → 너무 크다).
/// 돌리지 않고 옆으로만 몇 pt 떨고 빠르게 잦아든다.
private struct CupShake: ViewModifier {
    let trigger: Int

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, x in
                view.offset(x: x)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(-3.0, duration: 0.05)
                    CubicKeyframe(2.4, duration: 0.07)
                    CubicKeyframe(-1.4, duration: 0.07)
                    CubicKeyframe(0.6, duration: 0.07)
                    CubicKeyframe(0.0, duration: 0.08)
                }
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
