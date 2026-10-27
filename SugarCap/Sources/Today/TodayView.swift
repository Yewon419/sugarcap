import OSLog
import SwiftData
import SwiftUI
import WidgetKit

/// 오늘 화면(SPEC §4.1). 컵은 가득 찬 채로 시작해 기록할 때마다 줄어든다.
struct TodayView: View {
    let catalog: CatalogIndex

    @Environment(\.modelContext) private var context
    @Query private var settingsRows: [AppSettings]
    @Query(sort: \Entry.loggedAt, order: .reverse) private var entries: [Entry]
    @Query private var settlements: [DaySettlement]
    @Query private var affinities: [Affinity]
    @Query(sort: \GiftEvent.createdAt) private var gifts: [GiftEvent]

    /// 마지막으로 보던 면으로 연다(2026-10-06 대표님). 손으로 넘길 때만 저장한다(스크린샷 인자는 저장하지 않는다).
    @State private var pickedSide: CupSide = UserDefaults.standard.string(forKey: TodayView.lastSideKey)
        .flatMap(CupSide.init(rawValue:)) ?? .sugar
    /// 한 면만 켰을 때 꺼진 쪽 캐릭터가 컵 옆에 앉아 구경하는지(2026-10-06 대표님 "구경만 하게 남김"). 앱을 열 때 한 번 뽑는다.
    @State private var hasOnlooker = TodayView.rollOnlooker()
    /// 넘기는 중 손가락이 끈 거리. 놓으면 0으로 돌아가며 가까운 컵에 붙는다.
    @State private var dragX: CGFloat = 0
    /// 컵을 넘기는 중(끄는 중 + 놓은 뒤 제자리로 붙는 중). 이 동안 캐릭터 움직임을 멈춰 컵과 한 몸으로 밀리게 한다.
    @State private var isSliding = false
    /// 오늘 화면이 보이는지. 다른 화면으로 가면 캐릭터를 멈춘다(뒤에서도 매 프레임 그리면 앱 전체가 무거워진다).
    @State private var isOnScreen = false
    /// 하단 탭 대신 모서리 버튼으로 연다(2026-10-05). 추이는 밀어 넣고, 설정은 시트.
    @State private var isTrendsPresented = AppTab.initial == .trends
    /// 첫 선물로 추이를 열 때 그 선물의 면. 추이가 첫 등장 연출을 한 번 보여 준다(§4.9). 돌아오면 지운다.
    @State private var trendsReveal: CupSide?
    @State private var isSettingsPresented = AppTab.initial == .settings
    @State private var path: [String] = []
    @State private var isManualEntryPresented = false
    /// 먹이기 요청 + 여는 방식을 한 덩어리로 둔다. 따로 두면 전체 화면이 뜨기 전 값을 붙잡아
    /// 첫 마감 소개가 안 나왔다(2026-09-27 CI 스크린샷에서 발견).
    @State private var feeding: FeedingPresentation?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var prompt: SettlementPlan.Prompt?
    /// 어젯밤 처리할 게 있으면 앱을 열자마자 전체 화면으로 띄운다(2026-09-27 대표님). 처리 전까지 계속 뜬다.
    @State private var gate: YesterdayGate?
    /// 지금 뜬 어젯밤 화면이 설정 테스트 카드에서 연 것인지. 그렇다면 아무것도 저장하지 않는다.
    @State private var isGateRehearsal = false
    /// 설정 테스트 카드에서 고른 일. 시트가 다 닫힌 뒤 실행한다.
    @State private var pendingTestAction: SettingsTestAction?
    /// 이번 실행에서 실제로 먹였는지. 먹이기 화면이 닫히면 첫 마감 뒤 알림을 한 번 묻는 데 쓴다.
    @State private var didFeed = false
    @State private var asksReminder = false
    /// "어젯밤 이후 마신 만큼 빠졌어요"를 보여 준 날. 그날엔 다시 띄우지 않는다.
    @AppStorage("dismissedShrankNoticeDay") private var dismissedShrankDay = ""
    /// 보관함에서 잔을 바꾸면 컵을 다시 그린다(§4.10). 값은 `CupSide.cupSetID`가 읽는다.
    @AppStorage("cupSet.sugar") private var sugarCupSet: String?
    @AppStorage("cupSet.caffeine") private var caffeineCupSet: String?
    /// 지난 마감분이 방금 확정됐을 때만 채운다. 이번 실행 동안만 보인다.
    @State private var creditNotice: [FeedResult]?
    @State private var paywall: ProFeature?
    /// 오른쪽 위 별 버튼으로 연 결제창(기능 없이 여는 것, 설정의 Pro 줄과 같다).
    @State private var isProPaywallPresented = false
    /// 면마다 큰 숫자(`CupHero`)의 화면 자리. 누르기·보이스오버 요소를 여기에 맞춘다.
    @State private var heroFrames: [CupSide: CGRect] = [:]
    @State private var isRecordSheetPresented = false
    /// 컵(숫자 포함)을 누른 횟수. 누를 때마다 진동(대표님 2026-10-23, 캐릭터보다 한 단계 큰 진동).
    @State private var cupTaps = 0
    @State private var isDayLogPresented = false
    /// 즐겨찾기 `+`로 방금 기록한 음료. 4초 동안 되돌리기 안내를 띄운다.
    @State private var undoToast: UndoToast?
    /// 저장·정산 실패를 사용자에게 알린다. 로그만 남기면 기록이 사라져도 모른다.
    @State private var failureMessage: String?
    /// 상자를 눌러 조명 무대가 떠 있는 선물(SPEC §4.9). 눌러 닫아야 연 것으로 저장한다.
    @State private var reveal: GiftReveal?
    /// 상자를 눌러 뚜껑이 열리는 동안(무대 뜨기 전) 기다리는 일. 그 사이 다시 열지 않는다.
    @State private var revealLead: Task<Void, Never>?
    /// 첫 보상 전에 추이 버튼을 누른 때. 2초 동안 "아직 잠긴 기능이에요".
    @State private var trendsLockToastAt: Date?
    /// 첫 선물(추이 열림) 연출 중이면 채운다(SPEC §4.9). 열린 추이 버튼을 누르면 비운다.
    @State private var opening: GiftOpening?
    /// 추이 버튼 자리(화면 좌표). 열쇠가 날아가 닿고 어둠의 구멍이 뚫리는 곳.
    @State private var trendsButtonFrame: CGRect = .zero
    @State private var giftCarrierFrames: [CupSide: CGRect] = [:]
    /// 단계 상승 무대 연출 중이면 채운다(SPEC §4.9 결정 4). 끝나거나 누르면 연 것으로 저장하고 비운다.
    @State private var levelUp: LevelUpStage?
    @State private var levelUpFrames: [CupSide: CGRect] = [:]
    /// 방금 먹이기로 기준 지킨 주 선물이 생겼으면 채운다. 먹이기 화면이 닫히면 축하 화면으로 넘긴다(§4.9 2026-10-12).
    @State private var pendingWeekKept: WeekKeptCelebration?
    @State private var weekKept: WeekKeptCelebration?
    /// 거래 제안(§4.10). 제안 순서대로.
    @Query(sort: \TradeOffer.offeredAt) private var trades: [TradeOffer]
    /// 열려 있는 거래 무대.
    @State private var trade: TradeStage?
    /// "다음에"로 상자를 들고 나가는 중인 제안. 다 나가면 지운다.
    @State private var leavingOffer: UUID?
    /// 바꾸기 성공 햅틱 신호.
    @State private var tradesAccepted = 0
    /// CI 스크린샷·UI 테스트 전용 제안(Debug `-screenshotTrade`). 저장소에 넣지 않는다.
    @State private var screenshotOffer: TradeOffer?

    @Environment(ProStore.self) private var pro

    private static let logger = Logger(subsystem: "com.sugarcap.app", category: "today")

    private static let lastSideKey = "lastCupSide"

    private var limits: DailyLimits { settingsRows.first?.limits ?? .default }
    /// 설정 "기록할 것"에서 켠 면. 한 면만 켜면 컵도 하나고 넘기지 않는다.
    private var trackedSides: [CupSide] { settingsRows.first?.trackedSides ?? CupSide.allCases }
    /// 보이는 면. 보던 면을 껐으면 켜진 면으로.
    private var side: CupSide { CupSide.visible(pickedSide, in: trackedSides) }

    /// 도달한 단계까지 풀린다. Pro를 끊어도 얻은 자세는 남고 점수만 멈춘다(2026-10-27 대표님, §9.8).
    private func unlockedLevel(_ side: CupSide) -> Int {
        affinityLevel(side)
    }
    /// 열어 받은 물건(물건 대기 자세 해금, §9.8).
    private var ownedItems: Set<String> { GiftContent.takenItems(in: gifts.filter(\.isOpened)) }
    private func affinityLevel(_ side: CupSide) -> Int {
        let points = affinities.first { $0.character == side.characterID }?.points ?? 0
        return AffinityMath.level(points: points)
    }
    private var boundaryHour: Int { settingsRows.first?.dayBoundaryHour ?? 4 }
    private var closeFromHour: Int { settingsRows.first?.closeFromHour ?? 20 }

    var body: some View {
        // path는 브랜드 id 스택이다. 기록하면 비워서 오늘 루트로 돌아온다(§4.2).
        NavigationStack(path: $path) {
            // 경계 시각(기본 새벽 4시)을 넘기면 화면을 켜 둔 채로도 오늘이 바뀌어야 한다.
            TimelineView(.everyMinute) { timeline in
                content(now: timeline.date)
            }
            .toolbar(.hidden, for: .navigationBar)
            // 브랜드 메뉴의 뒤로 버튼 글자("‹ 오늘"). 막대는 숨겨 두므로 제목은 보이지 않는다.
            .navigationTitle("오늘")
            .navigationDestination(for: String.self) { brandID in
                if let brand = catalog.brand(id: brandID) {
                    BrandMenuView(
                        brand: brand,
                        catalog: catalog,
                        todayTotals: todayTotals(now: Date()),
                        limits: limits,
                        onAdd: { selection in
                            record(selection.makeEntry(brandName: brand.name, at: Date()))
                        },
                        onManualEntry: { isManualEntryPresented = true }
                    )
                    .environment(\.recordCup, side)
                }
            }
            .navigationDestination(isPresented: $isTrendsPresented) {
                TrendsView(catalog: catalog, reveal: trendsReveal)
                    .navigationTitle("")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .onChange(of: isTrendsPresented) { _, shown in
                if !shown { trendsReveal = nil }
            }
        }
        .sheet(isPresented: $isSettingsPresented, onDismiss: runPendingTestAction) {
            SettingsView(catalog: catalog.catalog) { action in
                pendingTestAction = action
                isSettingsPresented = false
            }
        }
        .overlay(alignment: .bottom) {
            if let undoToast {
                UndoToastView(toast: undoToast) { undo(undoToast) }
                    .padding(.bottom, 110)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: undoToast.id) {
                        try? await Task.sleep(for: .seconds(4))
                        if self.undoToast?.id == undoToast.id { self.undoToast = nil }
                    }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 1), value: undoToast?.id)
        .sheet(isPresented: $isManualEntryPresented) {
            ManualEntrySheet(onSave: record)
        }
        .sheet(isPresented: $isRecordSheetPresented) {
            RecordSheet(
                catalog: catalog,
                todayTotals: todayTotals(now: Date()),
                limits: limits,
                onBrand: { brandID in
                    isRecordSheetPresented = false
                    path = [brandID]
                },
                onManualEntry: {
                    isRecordSheetPresented = false
                    isManualEntryPresented = true
                },
                onAdd: { selection, brand in
                    isRecordSheetPresented = false
                    record(selection.makeEntry(brandName: brand.name, at: Date()))
                },
                onQuickAdd: { drink in
                    isRecordSheetPresented = false
                    let entry = drink.selection.makeEntry(brandName: drink.brand.name, at: Date())
                    record(entry)
                    undoToast = UndoToast(entryID: entry.id, text: String(localized: "\(drink.name) 기록했어요"))
                },
                todayCount: todaysEntries(now: Date()).count,
                onTodayLog: {
                    isRecordSheetPresented = false
                    isDayLogPresented = true
                }
            )
            .environment(\.recordCup, side)
        }
        .sheet(isPresented: $isDayLogPresented) {
            let now = Date()
            DayLogSheet(
                day: DayKey(at: now, boundaryHour: boundaryHour),
                isToday: true,
                entries: todaysEntries(now: now),
                limits: limits,
                catalog: catalog,
                onDelete: delete
            )
        }
        .fullScreenCover(item: $feeding, onDismiss: afterFeedingClosed) { presentation in
            let request = presentation.request
            FeedingView(
                request: request, opening: presentation.opening, catalog: catalog, snapshot: presentation.snapshot,
                onFeed: { try presentation.isRehearsal ? [] : feed(request) },
                onAddDrink: { entry in
                    try presentation.isRehearsal ? Self.rehearse(entry, on: request) : addDrink(entry, to: request)
                }
            )
        }
        .fullScreenCover(item: $weekKept, onDismiss: askReminderAfterFirstFeed) { celebration in
            WeekKeptCelebrationView(celebration: celebration) {
                // 끝나면 선물을 든 캐릭터 쪽 오늘 화면.
                pickedSide = celebration.carrier
                weekKept = nil
            }
        }
        .sheet(item: $paywall) { feature in
            PaywallView(feature: feature)
        }
        .sheet(isPresented: $isProPaywallPresented) {
            PaywallView(feature: nil)
        }
        .alert(
            failureMessage ?? "",
            isPresented: Binding(
                get: { failureMessage != nil },
                set: { if !$0 { failureMessage = nil } }
            )
        ) {
            Button("확인", role: .cancel) {}
        }
        .alert("내일도 이 시간에 알려 줄까요?", isPresented: $asksReminder) {
            Button("알려 줘요") {
                Task { _ = await CloseReminder.enable(closeFromHour: closeFromHour) }
            }
            .accessibilityIdentifier("reminder-yes")
            Button("괜찮아요", role: .cancel) {}
                .accessibilityIdentifier("reminder-no")
        } message: {
            Text("매일 \(HourChoices.label(closeFromHour))에 오늘 마감이 열리면 알려 줘요. 설정에서 언제든 끌 수 있어요.")
        }
        // 기록할 때만 햅틱 1회(§4.1). 삭제로 줄어들 때는 울리지 않는다.
        .sensoryFeedback(.success, trigger: entries.count) { old, new in new > old }
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.7), trigger: cupTaps)
    }

    /// 당 · 카페인 컵 장면 두 장을 옆으로 붙여 두고 손가락을 따라 통째로 민다(2026-09-27 대표님:
    /// "이미지 두 개 붙여 놓고 미는 식으로"). 놓으면 끈 거리·속도로 가까운 쪽에 붙는다. 끝에서는 고무줄처럼 덜 끌린다.
    private func cupStrip(totals: DayTotals, notice: String?, today: DayKey) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let index = CGFloat(trackedSides.firstIndex(of: side) ?? 0)
            HStack(spacing: 0) {
                ForEach(trackedSides) { cupSide in
                    let step = cupStep(cupSide, totals: totals)
                    let isActive = cupSide == side && !isSliding && isOnScreen && !isSettingsPresented
                    let staged = levelUp.flatMap { $0.side == cupSide ? $0 : nil }
                    let gift = staged == nil ? carriedGift(for: cupSide) : nil
                    let offer = staged == nil && gift == nil ? carriedOffer(for: cupSide) : nil
                    let carrier = carrierLayer(
                        gift: gift, offer: offer, side: cupSide, step: step, isActive: isActive, screen: proxy.frame(in: .global)
                    )
                    // 선물·거래 상자가 와 있으면 운반 캐릭터가 곧 그 캐릭터다. 열고 나면 대기 자세로 돌아온다(SPEC §4.9·4.10).
                    // 단계 상승 무대 중이면 무대에 선 캐릭터가 그 캐릭터다.
                    CupView(
                        step: step, setID: cupSide.cupSetID,
                        idle: carrier != nil || staged != nil ? nil : IdleCharacterLayer(
                            side: cupSide, step: step, isActive: isActive,
                            unlockedLevel: unlockedLevel(cupSide),
                            ownedItems: ownedItems,
                            onMiss: { tapCup(at: $0, screen: proxy.frame(in: .global)) },
                            guest: trackedSides.count == 1 && hasOnlooker ? cupSide.other : nil,
                            affinityLevel: affinityLevel,
                            halo: heroFrames[cupSide]
                        ),
                        gift: carrier,
                        stage: staged.map { stage in
                            LevelUpStageLayer(stage: stage, onFrame: { levelUpFrames[cupSide] = $0 })
                        },
                        hero: CupHero(
                            side: cupSide, remaining: cupSide.remaining(totals), limit: cupSide.limit(limits),
                            overflow: cupSide.overflow(totals), widest: widestNumber(totals),
                            rimLine: CupLevel.rimLineName(setID: cupSide.cupSetID, step: step),
                            notice: notice,
                            day: today,
                            topInset: Double(proxy.safeAreaInsets.top),
                            onFrame: { heroFrames[cupSide] = $0 }
                        ),
                        seam: seam(of: cupSide, index: index, width: width)
                    )
                    .frame(width: width)
                }
            }
            .offset(x: -index * width + dragX)
            // 첫 onAppear엔 폭이 0일 수 있어(CI slide-* 가 안 끌린 채 찍힘) 폭이 잡힐 때마다 다시 건다.
            .onChange(of: width, initial: true) {
                if slideForScreenshot > 0 { dragX = (index > 0 ? 1 : -1) * width * slideForScreenshot }
            }
            .frame(width: width, alignment: .leading)
            .contentShape(Rectangle())
            // 캐릭터가 누르기를 안 받을 때(동작 줄이기·넘기는 중) 여기로 온다. 받을 때는 캐릭터 밖 누르기가 `onMiss`로 온다.
            .onTapGesture(coordinateSpace: .global) { tapCup(at: $0, screen: proxy.frame(in: .global)) }
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        isSliding = true
                        let pullingPastEdge = (side == trackedSides.first && value.translation.width > 0)
                            || (side == trackedSides.last && value.translation.width < 0)
                        var follow = Transaction()
                        follow.disablesAnimations = true
                        withTransaction(follow) {
                            dragX = pullingPastEdge ? value.translation.width * 0.25 : value.translation.width
                        }
                    }
                    .onEnded { value in
                        let travel = value.predictedEndTranslation.width
                        let step = travel < -width / 3 ? 1 : (travel > width / 3 ? -1 : 0)
                        let next = Self.neighbor(of: side, step: step, in: trackedSides)
                        UserDefaults.standard.set(next.rawValue, forKey: Self.lastSideKey)
                        withAnimation(reduceMotion ? .easeInOut(duration: 0.25) : .spring(response: 0.45, dampingFraction: 0.86)) {
                            pickedSide = next
                            dragX = 0
                        } completion: {
                            isSliding = false
                        }
                    }
            )
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("음료 추가")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { isRecordSheetPresented = true }
        .accessibilityActions {
            if let gift = pendingGift(for: side) {
                Button("선물 열기") { beginOpening(gift, at: nil, on: side) }
            } else if let offer = carriedOffer(for: side), offer.accepted == nil {
                Button("거래 상자 열기") { beginTrade(offer, on: side) }
            }
        }
        .accessibilityIdentifier("record-add")
    }

    /// 이 장의 왼쪽 날개를 얼마나 드러낼지(`CupView.seam`). 첫 장은 옆 장이 없어 늘 다 드러낸다. 나머지는 왼쪽 장에서
    /// 이 장으로 넘어간 정도(0~1)라, 가만히 있을 때는 한 장 사진만 보이고 넘기는 동안 냅킨·벽이 겹쳐 녹는다.
    private func seam(of cupSide: CupSide, index: CGFloat, width: CGFloat) -> Double {
        let page = trackedSides.firstIndex(of: cupSide) ?? 0
        guard page > 0, width > 0 else { return 1 }
        let position = Double(index - dragX / width)
        return min(max(position - Double(page - 1), 0), 1)
    }

    // MARK: - 선물(§4.9)

    /// 이 면으로 온 선물 중 가장 오래된 것. 면마다 하나씩만 보이고, 열면 다음 것이 온다.
    /// 단계 상승은 상자로 오지 않는다(무대 연출, `nextLevelUp`).
    private func pendingGift(for cupSide: CupSide) -> GiftEvent? {
        gifts.first { !$0.isOpened && $0.cupSide == cupSide && $0.giftKind != .levelUp }
    }

    // MARK: - 단계 상승 무대(§4.9 결정 4)

    /// 보고 있는 면의 아직 안 본 단계 상승. 그 면에 상자가 와 있으면 상자부터 받는다("선물 다 받고 나서").
    private var nextLevelUp: GiftEvent? {
        guard pendingGift(for: side) == nil else { return nil }
        return gifts.first { !$0.isOpened && $0.giftKind == .levelUp && $0.cupSide == side }
    }

    /// 무대를 열어도 되는 때의 단계 상승 id. 다른 연출·시트·화면이 떠 있거나 넘기는 중이면 없다.
    private var levelUpCue: UUID? {
        guard levelUp == nil, opening == nil, reveal == nil, trade == nil, feeding == nil, gate == nil, paywall == nil,
              isOnScreen, !isSliding, !isSettingsPresented, !isTrendsPresented, !isRecordSheetPresented,
              !isDayLogPresented, !isManualEntryPresented, path.isEmpty
        else { return nil }
        return nextLevelUp?.id
    }

    /// 화면이 자리 잡고 잠깐 뒤에 연다(앱을 열자마자 어두워지지 않게).
    private func startLevelUp(after cue: UUID) async {
        try? await Task.sleep(for: .seconds(0.8))
        guard !Task.isCancelled, levelUp == nil, let gift = nextLevelUp, gift.id == cue, let cupSide = gift.cupSide else {
            return
        }
        levelUp = LevelUpStage(gift: gift, side: cupSide, level: gift.level ?? 1, startedAt: Date())
    }

    /// 끝까지 보거나 눌러서 건너뛰면 연 것으로 저장한다. 스크린샷용 무대(저장소 밖)는 저장하지 않는다.
    private func finishLevelUp(_ stage: LevelUpStage) {
        guard levelUp?.id == stage.id else { return }
        if stage.gift.modelContext != nil { saveOpened(stage.gift) }
        levelUp = nil
        // 첫 만남(Lv1)은 둘이 같이 받는 거라 다른 컵으로 저절로 넘겨 이어 보여 준다(2026-10-27 대표님).
        guard stage.level == 1 else { return }
        let partner: CupSide? = trackedSides.first { other in
            other != stage.side && gifts.contains { gift in
                !gift.isOpened && gift.giftKind == .levelUp && gift.level == 1 && gift.cupSide == other
            }
        }
        if let partner { switchSide(to: partner) }
    }

    /// 끝까지 기다렸다 닫는다. CI 스크린샷(`-levelUpAt`)은 한 장면에 멈춰 두므로 닫지 않는다.
    private func playLevelUp(_ stage: LevelUpStage) async {
        guard LevelUpTimeline.frozenTime == nil else { return }
        try? await Task.sleep(for: .seconds(LevelUpTimeline.duration(calm: reduceMotion)))
        guard !Task.isCancelled else { return }
        finishLevelUp(stage)
    }

    @ViewBuilder
    private func levelUpOverlay() -> some View {
        if let levelUp {
            LevelUpStageOverlay(
                stage: levelUp, source: levelUpFrames[levelUp.side] ?? .zero,
                onSkip: { finishLevelUp(levelUp) }
            )
            .transition(.opacity)
        }
    }

    /// CI 스크린샷·UI 테스트 전용(Debug `-screenshotLevelUp <단계>`): 보고 있는 면에서 무대를 바로 연다.
    /// 저장소에 넣지 않는다(스크린샷 단계는 저장소를 이어 쓰니 뒤 컷에 무대가 남지 않게).
    /// Debug `-screenshotWeekKept sugar|caffeine|both`(+ `-weekKeptAt <초>`). 오늘을 그 주 일요일로 본다.
    private func presentScreenshotWeekKeptIfRequested(today: DayKey) {
        #if DEBUG
        guard let raw = UserDefaults.standard.string(forKey: "screenshotWeekKept"), weekKept == nil else { return }
        let sides = raw == "both" ? CupSide.allCases.filter(trackedSides.contains) : [CupSide(rawValue: raw) ?? side]
        weekKept = WeekKeptCelebration(closed: today, sides: sides, carrier: sides.last ?? side)
        #endif
    }

    private func presentScreenshotLevelUpIfRequested() {
        #if DEBUG
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "screenshotLevelUp") != nil, levelUp == nil else { return }
        let level = min(max(defaults.integer(forKey: "screenshotLevelUp"), 2), AffinityMath.maxLevel)
        let gift = GiftEvent(kind: .levelUp, side: side, level: level, createdAt: Date())
        levelUp = LevelUpStage(gift: gift, side: side, level: level, startedAt: Date())
        #endif
    }

    /// 컵 앞에 보일 선물. 연출 중인 선물은 저장(열림) 뒤에도 추이로 갈 때까지 그대로 둔다(대기 자세로 툭 바뀌지 않게).
    private func carriedGift(for cupSide: CupSide) -> GiftEvent? {
        #if DEBUG
        // CI 대기 자세 컷(`-idlePose`)은 앞 단계(UI 테스트)가 남긴 안 연 상자에 가려 로슈 자세가 안 찍혔다(빌드 227 확인).
        if UserDefaults.standard.string(forKey: "idlePose") != nil { return nil }
        // 거래 컷(`-screenshotTrade`)도 같은 이유로 남은 상자를 치운다.
        if UserDefaults.standard.string(forKey: "screenshotTrade") != nil { return nil }
        #endif
        if let opening, opening.gift.cupSide == cupSide { return opening.gift }
        return pendingGift(for: cupSide)
    }

    /// 상자를 눌렀을 때. 추이 열림 선물은 열쇠 연출로, 나머지(Phase 2·3)는 조명 무대로 연다. 보고 있는 면만 받는다.
    private func beginOpening(_ gift: GiftEvent, at time: Double?, on cupSide: CupSide) {
        guard cupSide == side, opening == nil, reveal == nil, revealLead == nil else { return }
        if gift.giftKind == .trendsUnlock {
            opening = GiftOpening(gift: gift, side: cupSide, openedAt: time, startedAt: Date())
        } else {
            // 내용은 상자가 생길 때 정해져 있다. 그 전에 생긴 옛 상자만 여기서 뽑는다(§4.9 2026-10-11).
            GiftStore.reveal(gift, isPro: pro.isPro, takenItems: GiftContent.takenItems(in: gifts), roll: Double.random(in: 0 ..< 1))
            // 무대가 뜨면 운반 캐릭터가 멈춰서, 바로 띄우면 뚜껑 열림·조각이 한 프레임도 안 보였다(빌드 227 대표님
            // "상자 열리는 연출이 아예 없던데"). 뚜껑이 열리고 조각이 솟은 뒤에 띄운다. 동작 줄이기·보이스오버면 바로.
            guard time != nil, !reduceMotion else {
                reveal = GiftReveal(gift: gift, startedAt: Date())
                return
            }
            revealLead = Task { @MainActor in
                try? await Task.sleep(for: .seconds(GiftOpeningTimeline.revealAfter))
                revealLead = nil
                reveal = GiftReveal(gift: gift, startedAt: Date())
            }
        }
    }


    /// 열쇠가 추이 버튼에 닿는 때 연 것으로 저장한다. 동작 줄이기·보이스오버로 열면 바로.
    /// CI 스크린샷(`-giftOpenAt`)은 한 장면에 멈춰 두므로 저장하지 않는다.
    private func unlockAfterKeyFlight(_ current: GiftOpening) async {
        if GiftOpeningOverlay.frozenTime != nil { return }
        if !(reduceMotion || current.openedAt == nil) {
            try? await Task.sleep(for: .seconds(GiftOpeningTimeline.unlock))
        }
        guard !Task.isCancelled, opening?.id == current.id else { return }
        saveOpened(current.gift)
        opening?.isUnlocked = true
    }

    /// 밝아진 추이 버튼을 눌렀을 때. 연출을 걷고 추이를 연다.
    private func finishOpening() {
        guard let opening else { return }
        if !opening.gift.isOpened { saveOpened(opening.gift) }
        self.opening = nil
        trendsReveal = opening.side
        isTrendsPresented = true
    }

    @ViewBuilder
    private func giftOpeningOverlay() -> some View {
        if let opening {
            GiftOpeningOverlay(
                opening: opening, target: trendsButtonFrame, source: giftCarrierFrames[side] ?? .zero,
                onOpenTrends: finishOpening
            )
            .transition(.opacity)
        }
    }

    /// 첫 보상(추이 열림) 선물을 열었는지. Debug에서는 추이로 바로 여는 스크린샷·UI 테스트가 많아 인자로 푼다.
    private var isTrendsUnlocked: Bool {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "trendsUnlocked") || AppTab.initial == .trends { return true }
        #endif
        return GiftMath.isTrendsUnlocked(gifts: gifts.compactMap { gift in
            gift.giftKind.map { GiftMath.Record(kind: $0, isOpened: gift.isOpened) }
        })
    }

    private func openTrends() {
        if isTrendsUnlocked {
            isTrendsPresented = true
        } else {
            trendsLockToastAt = Date()
        }
    }

    private func grantProWelcomeIfOwned() {
        guard pro.ownsRealPro else { return }
        do {
            if try GiftStore.grantProWelcome(sides: trackedSides, now: Date(), in: context) { try context.save() }
        } catch {
            Self.logger.error("Pro 축하 선물 저장 실패: \(String(describing: error), privacy: .public)")
        }
    }

    /// 무대를 눌러 닫을 때. 이때 연 것으로 저장한다(상자만 누르고 앱을 끄면 다시 들고 서 있다).
    private func confirmGift(_ gift: GiftEvent) {
        saveOpened(gift)
        reveal = nil
    }

    private func saveOpened(_ gift: GiftEvent) {
        GiftStore.open(gift, now: Date())
        do {
            try context.save()
        } catch {
            Self.logger.error("선물 저장 실패: \(String(describing: error), privacy: .public)")
            failureMessage = String(localized: "선물을 저장하지 못했어요. 앱을 다시 열어 주세요.")
        }
    }

    /// CI 스크린샷·UI 테스트 전용(Debug `-screenshotGift trends|weekKept`): 선물이 와 있는 상태로 연다. 이미 안 연 선물이 있으면 그대로.
    /// `-screenshotGiftCard YES` = 조명 무대를 연 채로(장면 시각은 `-giftRevealAt`). 마음 횟수는 `heartsReceived`(`-screenshotHearts`).
    private func presentScreenshotGiftIfRequested() {
        #if DEBUG
        let defaults = UserDefaults.standard
        guard let raw = defaults.string(forKey: "screenshotGift") else { return }
        let kind: GiftKind = raw == "trends" ? .trendsUnlock : (GiftKind(rawValue: raw) ?? .trendsUnlock)
        // 무대 컷은 앞 컷이 남긴 안 연 선물과 상관없이 새로 넣어 연다(스크린샷 단계는 저장소를 이어 쓴다).
        if defaults.bool(forKey: "screenshotGiftCard"), kind != .trendsUnlock {
            // 내용은 `-screenshotGiftContent heart|cap|item:strawberry`(기본 마음).
            let gift = GiftEvent(
                kind: kind, side: side, payload: defaults.string(forKey: "screenshotGiftContent") ?? GiftContent.heart,
                createdAt: Date()
            )
            context.insert(gift)
            reveal = GiftReveal(gift: gift, startedAt: Date())
        } else if pendingGift(for: side) == nil {
            context.insert(GiftEvent(kind: kind, side: side, createdAt: Date()))
        }
        try? context.save()
        #endif
    }

    /// 지금까지 받은 마음(로슈·카인 합쳐). Debug `-screenshotHearts <n>`이면 그 값(UI 테스트가 남긴 기록과 상관없이 찍으려고).
    private var heartsReceived: Int {
        #if DEBUG
        if UserDefaults.standard.object(forKey: "screenshotHearts") != nil {
            return UserDefaults.standard.integer(forKey: "screenshotHearts")
        }
        #endif
        return gifts.filter { $0.isHeart && $0.isOpened }.count
    }

    @ViewBuilder
    private func giftRevealOverlay() -> some View {
        if let reveal {
            GiftRevealOverlay(
                reveal: reveal,
                offersPro: GiftMath.offersPro(heartsBefore: heartsReceived, isPro: pro.isPro),
                onClose: { confirmGift(reveal.gift) },
                onPro: {
                    confirmGift(reveal.gift)
                    paywall = .gifts
                }
            )
            .transition(.opacity)
        }
    }

    // MARK: - 거래(§4.10)

    /// 컵 앞 운반 캐릭터. 선물이 먼저고, 없으면 거래 상자(병뚜껑 꼬리표).
    private func carrierLayer(
        gift: GiftEvent?, offer: TradeOffer?, side cupSide: CupSide, step: Int, isActive: Bool, screen: CGRect
    ) -> GiftCarrierLayer? {
        if let gift {
            return GiftCarrierLayer(
                side: cupSide, step: step, isActive: isActive && reveal == nil,
                onOpen: { beginOpening(gift, at: $0, on: cupSide) },
                onMiss: { tapCup(at: $0, screen: screen) },
                onFrame: { giftCarrierFrames[cupSide] = $0 }
            )
        }
        guard let offer else { return nil }
        return GiftCarrierLayer(
            side: cupSide, step: step, isActive: isActive && trade == nil,
            onOpen: { _ in beginTrade(offer, on: cupSide) },
            onMiss: { tapCup(at: $0, screen: screen) },
            onFrame: { giftCarrierFrames[cupSide] = $0 },
            tag: offer.price,
            isLeaving: offer.id == leavingOffer
        )
    }

    /// 이 면에 와 있는 거래 제안. 아직 안 정한 것, 또는 "다음에"로 들고 나가는 중인 것.
    private func carriedOffer(for cupSide: CupSide) -> TradeOffer? {
        #if DEBUG
        if UserDefaults.standard.string(forKey: "idlePose") != nil { return nil }
        if let screenshotOffer, screenshotOffer.cupSide == cupSide,
           screenshotOffer.accepted == nil || screenshotOffer.id == leavingOffer {
            return screenshotOffer
        }
        #endif
        return trades.first { $0.cupSide == cupSide && ($0.accepted == nil || $0.id == leavingOffer) }
    }

    /// 제안을 낼지 볼 때. 다른 연출·시트·화면이 떠 있거나 넘기는 중이면 없다(§4.10 "자리 잡았다").
    /// 켜 둔 사이에 다음 제안 시각이 지날 수 있어 10분마다 값이 바뀐다.
    private func tradeCue(now: Date) -> String? {
        guard trade == nil, leavingOffer == nil, levelUp == nil, opening == nil, reveal == nil, feeding == nil,
              gate == nil, paywall == nil, weekKept == nil, isOnScreen, !isSliding, !isSettingsPresented,
              !isTrendsPresented, !isRecordSheetPresented, !isDayLogPresented, !isManualEntryPresented, path.isEmpty,
              !trades.contains(where: { $0.accepted == nil })
        else { return nil }
        let opened = gifts.filter(\.isOpened).count
        return "\(Int(now.timeIntervalSince1970 / 600))-\(gifts.count)-\(opened)-\(trades.count)"
    }

    /// 화면이 자리 잡고 잠깐 뒤에 본다. 제안이 오면 캐릭터가 상자를 들고 들어온다.
    private func offerTradeIfDue(today: DayKey) async {
        try? await Task.sleep(for: .seconds(0.8))
        guard !Task.isCancelled, trade == nil, leavingOffer == nil else { return }
        #if DEBUG
        // CI 스크린샷은 저장소를 이어 쓰니 앞 단계가 남긴 병뚜껑으로 제안이 끼어들지 않게 한다.
        let defaults = UserDefaults.standard
        if defaults.string(forKey: "screenshotTrade") != nil || defaults.string(forKey: "idlePose") != nil { return }
        #endif
        do {
            let offered = try TradeStore.offerIfDue(
                sides: trackedSides, today: today, boundaryHour: boundaryHour, now: Date(),
                roll: Double.random(in: 0 ..< 1), in: context
            )
            if offered != nil { try context.save() }
        } catch {
            Self.logger.error("거래 제안 저장 실패: \(String(describing: error), privacy: .public)")
            context.rollback()
        }
    }

    /// 거래 상자를 눌렀을 때. 보고 있는 면만 받는다.
    private func beginTrade(_ offer: TradeOffer, on cupSide: CupSide) {
        guard cupSide == side, trade == nil, offer.accepted == nil else { return }
        trade = TradeStage(offer: offer, startedAt: Date())
    }

    /// 바꾸기. 저장한 뒤 무대를 닫고 그 면의 잔을 새 잔으로 바꾼다(`CupView`가 크로스페이드). 캐릭터는 대기 자세로 돌아온다.
    /// 스크린샷용 제안(저장소 밖)은 저장하지 않는다.
    private func acceptTrade(_ stage: TradeStage) {
        guard trade?.id == stage.id else { return }
        let offer = stage.offer
        guard let item = TradeCatalog.item(offer.itemID) else {
            Self.logger.error("모르는 거래 상품: \(offer.itemID, privacy: .public)")
            trade = nil
            return
        }
        if offer.modelContext != nil {
            do {
                try TradeStore.accept(offer, now: Date(), roll: Double.random(in: 0 ..< 1), in: context)
                try context.save()
            } catch {
                Self.logger.error("거래 수락 실패: \(String(describing: error), privacy: .public)")
                context.rollback()
                trade = nil
                failureMessage = String(localized: "바꾸지 못했어요. 다시 시도해 주세요.")
                return
            }
        } else {
            offer.accepted = true
        }
        tradesAccepted += 1
        trade = nil
        switch item.side {
        case .sugar: sugarCupSet = item.id
        case .caffeine: caffeineCupSet = item.id
        }
    }

    /// 다음에. 무대가 닫히고 캐릭터가 상자를 들고 들어온 쪽으로 나간다(동작 줄이기면 바로 사라진다).
    private func refuseTrade(_ stage: TradeStage) {
        guard trade?.id == stage.id else { return }
        let offer = stage.offer
        if offer.modelContext != nil {
            TradeStore.refuse(offer, now: Date(), roll: Double.random(in: 0 ..< 1))
            do {
                try context.save()
            } catch {
                Self.logger.error("거래 거절 저장 실패: \(String(describing: error), privacy: .public)")
                context.rollback()
                trade = nil
                failureMessage = String(localized: "저장하지 못했어요. 다시 시도해 주세요.")
                return
            }
        } else {
            offer.accepted = false
        }
        if !reduceMotion { leavingOffer = offer.id }
        trade = nil
    }

    /// 나가는 캐릭터가 화면 밖으로 다 나가면 지운다.
    private func finishLeaving(_ id: UUID) async {
        let length: Double = CupSide.allCases.map(GiftCarrierFigure.leaveLength).max() ?? 1.4
        try? await Task.sleep(for: .seconds(length + 0.2))
        guard !Task.isCancelled, leavingOffer == id else { return }
        leavingOffer = nil
    }

    @ViewBuilder
    private func tradeOverlay() -> some View {
        if let trade {
            TradeOfferOverlay(
                stage: trade,
                onAccept: { acceptTrade(trade) },
                onRefuse: { refuseTrade(trade) }
            )
            .transition(.opacity)
        }
    }

    /// CI 스크린샷·UI 테스트 전용(Debug `-screenshotTrade offer|card`): 첫 상품 제안이 와 있는 상태(`offer`),
    /// 무대를 연 상태(`card`). 제안은 저장소에 넣지 않는다(뒤 컷에 상자가 남지 않게).
    /// 상품은 `-screenshotTradeItem <id>`, 없으면 튜토리얼 상품.
    private func presentScreenshotTradeIfRequested() {
        #if DEBUG
        guard let raw = UserDefaults.standard.string(forKey: "screenshotTrade"), screenshotOffer == nil,
              let item = UserDefaults.standard.string(forKey: "screenshotTradeItem").flatMap(TradeCatalog.item)
                ?? TradeCatalog.tutorialItem(tracked: trackedSides) ?? TradeCatalog.items.first
        else { return }
        let offer = TradeOffer(itemID: item.id, side: item.side, price: TradeMath.firstPrice, offeredAt: Date())
        screenshotOffer = offer
        pickedSide = item.side
        if raw == "card" { trade = TradeStage(offer: offer, startedAt: Date()) }
        #endif
    }

    @ViewBuilder
    private func trendsLockToast() -> some View {
        if let trendsLockToastAt {
            Text("아직 잠긴 기능이에요")
                .font(AppFont.pretendard(15, .semibold, relativeTo: .subheadline))
                .glassPill()
                .padding(.top, 56)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .accessibilityIdentifier("trends-locked")
                .task(id: trendsLockToastAt) {
                    try? await Task.sleep(for: .seconds(2))
                    if self.trendsLockToastAt == trendsLockToastAt { self.trendsLockToastAt = nil }
                }
        }
    }

    /// 4번에 1번꼴. Debug(UI 테스트·CI 스크린샷)에서는 `-screenshotOnlooker YES`일 때만 나와 컵 누르기를 가리지 않는다.
    private static func rollOnlooker() -> Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "screenshotOnlooker")
        #else
        return Double.random(in: 0 ..< 1) < TrendEntrance.chance
        #endif
    }

    /// CI 스크린샷 전용(Debug `-screenshotCupSlide 0.5`). 옆 장 쪽으로 화면 폭의 이만큼 끈 채 멈춰 이음매 녹임을 찍는다.
    private var slideForScreenshot: CGFloat {
        #if DEBUG
        return CGFloat(UserDefaults.standard.double(forKey: "screenshotCupSlide"))
        #else
        return 0
        #endif
    }

    /// CI 스크린샷 전용(Debug `-screenshotCreditNotice YES`). 반영 알림을 띄운 채 사라지지 않게 둔다.
    private var showsCreditNoticeForScreenshot: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "screenshotCreditNotice")
        #else
        return false
        #endif
    }

    /// CI 스크린샷 전용(Debug `-screenshotCupHint YES`). CI 시뮬레이터는 UI 테스트 기록이 남아 첫 안내가 안 찍힌다.
    private var showsCupHintForScreenshot: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "screenshotCupHint")
        #else
        return false
        #endif
    }

    /// 컵을 누르면 음료 추가(2026-10-05 대표님, 오른쪽 아래 + 버튼 대신). 위 수치·아래 조작부 자리는 빼고
    /// 잔이 있는 칸만 받는다(프로토 `.cup-tap`과 같은 칸: 양옆 32, 위 35%, 아래 170).
    private func tapCup(at point: CGPoint, screen: CGRect) {
        // 큰 숫자는 컵 장면 안에 그려져 캐릭터 아래에 있다. 캐릭터가 안 받은 누르기가 숫자 위면 하루 기록(2026-09-26).
        if heroFrames[side]?.contains(point) == true {
            cupTaps += 1
            isDayLogPresented = true
            return
        }
        let area = CGRect(
            x: screen.minX + 32, y: screen.minY + screen.height * 0.35,
            width: screen.width - 64, height: screen.height * 0.65 - 170
        )
        if area.contains(point) {
            cupTaps += 1
            isRecordSheetPresented = true
        }
    }

    /// 켜진 면 숫자 중 가장 넓은 것. 두 면 큰 숫자 크기를 맞춘다(2026-10-07 대표님 "양쪽 숫자 크기 맞춰줘").
    private func widestNumber(_ totals: DayTotals) -> String {
        let numbers = trackedSides.map { Amount.number($0.remaining(totals)) }
        return numbers.max { CupHero.size(width: 100, widest: $0) > CupHero.size(width: 100, widest: $1) } ?? ""
    }

    private func cupStep(_ cupSide: CupSide, totals: DayTotals) -> Int {
        #if DEBUG
        // CI 스크린샷 전용: `-idleStep 100`으로 컵 단계를 고정해 자세마다 찍는다.
        if UserDefaults.standard.object(forKey: "idleStep") != nil {
            return UserDefaults.standard.integer(forKey: "idleStep")
        }
        #endif
        return CupLevel.step(remaining: cupSide.remaining(totals), limit: cupSide.limit(limits))
    }

    /// 보이스오버의 위아래 쓸기로 컵을 오갈 때.
    private func switchSide(to next: CupSide) {
        guard next != side, trackedSides.contains(next) else { return }
        UserDefaults.standard.set(next.rawValue, forKey: Self.lastSideKey)
        withAnimation(reduceMotion ? .easeInOut(duration: 0.25) : .spring(response: 0.45, dampingFraction: 0.86)) {
            pickedSide = next
        }
    }

    /// 켜진 면 순서에서 step만큼 옆 면. 끝을 넘으면 끝 면.
    private static func neighbor(of side: CupSide, step: Int, in tracked: [CupSide]) -> CupSide {
        guard let index = tracked.firstIndex(of: side) else { return tracked.first ?? side }
        return tracked[min(max(index + step, 0), tracked.count - 1)]
    }

    private func todaysEntries(now: Date) -> [Entry] {
        let today = DayKey(at: now, boundaryHour: boundaryHour)
        return entries.filter { $0.dayKey(boundaryHour: boundaryHour) == today }
    }

    private func todayTotals(now: Date) -> DayTotals {
        DayMath.totals(todaysEntries(now: now).map(\.consumption), limits: limits)
    }

    /// 방금 기록한 한 잔을 지운다. 이미 지워졌으면 아무것도 하지 않는다.
    private func undo(_ toast: UndoToast) {
        undoToast = nil
        guard let entry = entries.first(where: { $0.id == toast.entryID }) else { return }
        delete([entry])
    }

    /// 오늘 화면(2026-09-24 디자인). 컵 장면이 화면을 꽉 채우고 수치·조작부가 그 위에 얹힌다.
    @ViewBuilder
    private func content(now: Date) -> some View {
        let today = DayKey(at: now, boundaryHour: boundaryHour)
        let todays = todaysEntries(now: now)
        let totals = DayMath.totals(todays.map(\.consumption), limits: limits)
        let remaining = side.remaining(totals)
        let limit = side.limit(limits)

        ZStack(alignment: .topLeading) {
            cupStrip(totals: totals, notice: shownNotice(today: today), today: today)

            // 상태 바 글자가 밝은 사진 위에서 묻히지 않게 아주 옅게만 깐다.
            LinearGradient(
                colors: [Color.black.opacity(0.09), .clear],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 160)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)

            summaryProxy(remaining: remaining, limit: limit)

            // 처음 한 번만: 기록 버튼이 따로 없으니 컵을 누르면 된다고 알려 준다. 첫 기록을 남기면 사라진다.
            // 큰 숫자가 잔 입구로 내려가(2026-10-13) 비게 된 왼쪽 위에 둔다.
            if entries.isEmpty || showsCupHintForScreenshot {
                Text("컵을 눌러 마신 음료 적기")
                    .font(AppFont.pretendard(15, .semibold, relativeTo: .subheadline))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 24)
                    // 오른쪽 위 버튼 3개(별·추이·설정) 자리를 비운다. 큰 글자에서 겹치지 않고 줄을 바꾼다.
                    .padding(.trailing, 160)
                    .padding(.top, 14)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            // 안내 한 줄(큰 숫자 라벨 위, `CupHero.notice`)을 3.5초 보여 준 뒤 지운다. 둘 다 있으면 차례로.
            Color.clear
                .frame(width: 0, height: 0)
                .task(id: shownNotice(today: today)) {
                    guard let line = shownNotice(today: today) else { return }
                    AccessibilityNotification.Announcement(line).post()
                    guard !showsCreditNoticeForScreenshot else { return }
                    try? await Task.sleep(for: .seconds(3.5))
                    guard !Task.isCancelled else { return }
                    dismissNotice(today: today)
                }

            trendsLockToast()
                .frame(maxWidth: .infinity)
        }
        .animation(.easeOut(duration: 0.2), value: trendsLockToastAt)
        .fullScreenCover(item: $gate, onDismiss: {
            isGateRehearsal = false
            presentGateIfPending()
            if gate == nil { afterFeedingClosed() }
        }) { gate in
            YesterdayGateView(
                gate: gate,
                opening: feedingOpening(),
                catalog: catalog,
                onFeed: { request in try isGateRehearsal ? [] : feed(request) },
                onAddDrink: { entry, request in
                    try isGateRehearsal ? Self.rehearse(entry, on: request) : addDrink(entry, to: request)
                },
                onDrank: {
                    if isGateRehearsal { self.gate = nil } else { dismissPastDay(gate.day) }
                }
            )
        }
        .overlay(alignment: .bottom) { bottomControls(now: now, today: today, totals: totals) }
        .overlay(alignment: .topTrailing) { cornerButtons }
        .overlay { giftOpeningOverlay() }
        .animation(.easeOut(duration: 0.25), value: opening?.id)
        .overlay { levelUpOverlay() }
        .animation(.easeOut(duration: 0.25), value: levelUp?.id)
        .overlay { giftRevealOverlay() }
        .animation(.easeOut(duration: 0.25), value: reveal?.id)
        .overlay { tradeOverlay() }
        .animation(.easeOut(duration: 0.25), value: trade?.id)
        .task(id: tradeCue(now: now)) {
            if tradeCue(now: Date()) != nil { await offerTradeIfDue(today: today) }
        }
        .task(id: leavingOffer) {
            if let leavingOffer { await finishLeaving(leavingOffer) }
        }
        .sensoryFeedback(.success, trigger: tradesAccepted)
        .task(id: levelUpCue) {
            if let levelUpCue { await startLevelUp(after: levelUpCue) }
        }
        .task(id: levelUp?.id) {
            if let levelUp { await playLevelUp(levelUp) }
        }
        .task(id: opening?.id) {
            if let opening { await unlockAfterKeyFlight(opening) }
        }
        // 상자가 열리는 순간 가볍게, 열쇠가 버튼을 열 때 성공 햅틱(SPEC §4.9).
        .sensoryFeedback(.impact(weight: .light), trigger: opening?.id) { _, new in new != nil }
        .sensoryFeedback(.success, trigger: opening?.isUnlocked == true) { _, new in new }
        .onAppear { isOnScreen = true }
        .onDisappear { isOnScreen = false }
        // 하루가 바뀔 때마다(앱을 켠 날마다) 정산을 한 번 돈다(§4.7).
        // Pro를 처음 사면 축하 선물(§4.9 2026-10-12). 기록하는 면이 바뀌면 다시 본다(고를 물건이 생길 수 있다).
        .task(id: pro.ownsRealPro ? trackedSides : []) { grantProWelcomeIfOwned() }
        .task(id: today) {
            refreshSettlement(today: today)
            presentScreenshotFeedingIfRequested(totals: totals)
            presentScreenshotGiftIfRequested()
            presentScreenshotLevelUpIfRequested()
            presentScreenshotWeekKeptIfRequested(today: today)
            presentScreenshotTradeIfRequested()
        }
    }

    /// 큰 숫자는 컵 장면 안(`CupHero`)에 그린다. 컵 장면은 접근성 요소 하나라, 보이스오버·UI 테스트용 숫자 요소를
    /// 보고 있는 면 숫자 자리에 투명하게 겹친다. 누르기는 받지 않는다(캐릭터가 먼저 받고, 나머지는 `tapCup`이 숫자로 보낸다).
    private func summaryProxy(remaining: Double, limit: Double) -> some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            let frame = heroFrames[side] ?? .zero
            Rectangle()
                .fill(Color.white.opacity(0.001))
                .frame(width: max(frame.width, 1), height: max(frame.height, 1))
                .position(x: frame.midX - origin.x, y: frame.midY - origin.y)
                .allowsHitTesting(false)
                // 큰 숫자를 누르면 하루 기록 시트(2026-09-26). 기록 보기·지우기는 여기서 한다.
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { isDayLogPresented = true }
                .accessibilityIdentifier("cup-summary")
                .accessibilityLabel(
                    "\(side.label) 남은 \(Amount.number(remaining)) \(side.unit) / \(Amount.number(limit)) \(side.unit)"
                )
                // 컵 전환은 화면에서는 좌우 스와이프다. VoiceOver에서는 위아래 쓸기로 같은 일을 한다.
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: switchSide(to: .caffeine)
                    case .decrement: switchSide(to: .sugar)
                    @unknown default: break
                    }
                }
                .accessibilityHint(
                    trackedSides.count > 1
                        ? String(localized: "눌러서 오늘 기록을 봐요. 위아래로 쓸어 당과 카페인 컵을 오가요")
                        : String(localized: "눌러서 오늘 기록을 봐요")
                )
        }
    }

    /// (Pro 별) · 추이 · 설정. 모두 같은 36pt 옅은 원이다. 호감도 버튼은 2026-10-06 대표님 지시로 뺐다.
    /// 별은 무료일 때만 추이 왼쪽에 둔다. 누르면 결제창(2026-10-13 대표님).
    private var cornerButtons: some View {
        HStack(spacing: 0) {
            if !pro.isPro {
                Button { isProPaywallPresented = true } label: { cornerCircle(NavGlyphView(glyph: .pro)) }
                    .accessibilityLabel("슈가캡 Pro")
                    .accessibilityIdentifier("open-pro")
            }
            // 첫 보상 전에는 잠겨 있다(SPEC §4.9). 버튼은 그대로 두고 누르면 한 줄만 띄운다(2026-10-09 대표님).
            Button { openTrends() } label: { cornerCircle(NavGlyphView(glyph: .trends)) }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { trendsButtonFrame = $0 }
                .accessibilityLabel("추이")
                .accessibilityIdentifier("open-trends")
            Button { isSettingsPresented = true } label: { cornerCircle(NavGlyphView(glyph: .settings)) }
                .accessibilityLabel("설정")
                .accessibilityIdentifier("open-settings")
        }
        .padding(.trailing, 16)
        .padding(.top, 2)
    }

    /// 보이는 원은 36pt 그대로, 누르는 영역만 44pt.
    private func cornerCircle(_ icon: some View) -> some View {
        icon
            .foregroundStyle(.primary.opacity(0.7))
            .frame(width: 36, height: 36)
            .background(.white.opacity(0.22), in: Circle())
            .tapTarget()
    }

    /// 왼쪽부터: 마감 버튼(시간대에만) → 페이지 점(가운데).
    @ViewBuilder
    private func bottomControls(now: Date, today: DayKey, totals: DayTotals) -> some View {
        // 기록은 컵을 눌러서 한다(2026-10-05, + 버튼 제거). 마감은 조용한 유리 알약으로 왼쪽에 둔다.
        // 높이는 예전 + 버튼(59) 그대로 잡아 페이지 점 자리가 안 움직이게 한다.
        HStack(alignment: .center, spacing: 12) {
            closeControl(now: now, today: today, totals: totals)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 59)
        // 점은 냅킨 아래 빈 바닥으로 내린다(빌드 272 대표님). 냅킨 아래 끝은 가운데에서 화면 높이 약 93%.
        .overlay { pageDots.offset(y: 30) }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    /// 컵이 하나면(한 면만 기록) 점도 없다.
    private var pageDots: some View {
        HStack(spacing: 7) {
            ForEach(trackedSides.count > 1 ? trackedSides : []) { cupSide in
                Circle()
                    .fill(Color.primary.opacity(cupSide == side ? 0.85 : 0.25))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - 정산(§4.7)

    /// 큰 숫자 라벨 위에 잠깐 뜨는 안내(2026-10-23 대표님: 카드·X 대신 한 줄, 몇 초 뒤 사라짐). 반영 알림이 먼저.
    /// 어제 먹이기·"안 마셨나요?"는 여기가 아니라 앱을 열면 먼저 뜨는 전체 화면(`YesterdayGateView`)이 맡는다.
    private func noticeLine(today: DayKey) -> String? {
        // 단계가 오른 건 여기 말고 무대 연출로 알린다(SPEC §4.9 결정 4).
        if creditNotice != nil || showsCreditNoticeForScreenshot { return String(localized: "지난밤 먹인 음료가 반영됐어요") }
        let yesterday = today.shifted(by: -1)
        let yesterdayRow = settlements.first { $0.day == yesterday.rawValue }
        if yesterdayRow?.shrankAfterClose(on: trackedSides) == true && dismissedShrankDay != yesterday.rawValue {
            return String(localized: "어젯밤 이후 마신 만큼 빠졌어요")
        }
        return nil
    }

    /// 전체 화면(어제 먹이기·먹이기·주간 축하)에 가려져 있으면 띄우지 않는다. 뒤에서 시간이 흘러 못 보고 지나가지 않게.
    private func shownNotice(today: DayKey) -> String? {
        guard gate == nil, feeding == nil, weekKept == nil else { return nil }
        return noticeLine(today: today)
    }

    private func dismissNotice(today: DayKey) {
        if creditNotice != nil {
            creditNotice = nil
        } else {
            dismissedShrankDay = today.shifted(by: -1).rawValue
        }
    }

    /// 마감 가능 시각 이후에만 연다(이른 마감 방지). 마감한 뒤에도 기록은 계속 된다.
    @ViewBuilder
    private func closeControl(now: Date, today: DayKey, totals: DayTotals) -> some View {
        let isClosed = settlements.first { $0.day == today.rawValue }?.isClosed == true
        if isClosed {
            Label("마감함", systemImage: "moon.stars")
                .font(.system(.footnote, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.ultraThinMaterial, in: Capsule())
        } else if CloseWindow.isOpen(at: now, closeFromHour: closeFromHour, boundaryHour: boundaryHour) {
            Button {
                openFeeding(FeedingRequest(
                    kind: .closeToday,
                    sugarLeftG: totals.leftSugarG,
                    caffeineLeftMg: totals.leftCaffeineMg,
                    limits: limits,
                    sugarOverG: totals.overSugarG,
                    caffeineOverMg: totals.overCaffeineMg
                ))
            } label: {
                Label("오늘 마감", systemImage: "moon.stars")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.45), lineWidth: 1))
                    .shadow(color: .black.opacity(0.10), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("close-today")
        }
    }

    /// 어제 처리할 게 남아 있으면 전체 화면을 (다시) 띄운다. 먹이기를 도중에 닫아도 여기로 돌아온다.
    private func presentGateIfPending() {
        guard let prompt, gate == nil else { return }
        switch prompt {
        case .feedYesterday(let day):
            let dayTotals = totals(for: day)
            gate = YesterdayGate(
                kind: .feed, day: day, sugarLeftG: dayTotals.leftSugarG, caffeineLeftMg: dayTotals.leftCaffeineMg,
                limits: limits, sugarOverG: dayTotals.overSugarG, caffeineOverMg: dayTotals.overCaffeineMg
            )
        case .askNoDrink(let day):
            gate = YesterdayGate(
                kind: .askNoDrink, day: day, sugarLeftG: limits.sugarG, caffeineLeftMg: limits.caffeineMg, limits: limits
            )
        }
    }

    /// 첫 먹이기면 로슈·카인 소개부터(§4.5), 그 뒤로는 마감 진입 모션.
    private func feedingOpening() -> FeedingOpening {
        let seen = UserDefaults.standard.bool(forKey: CompanionIntro.seenKey)
        return !seen ? .companionIntro : (reduceMotion ? .immediate : .dusk)
    }

    /// 먹이기를 연다. 첫 마감이면 로슈·카인 소개부터(§4.5), 그 뒤로는 마감 진입 모션.
    /// 화면이 아래에서 밀려 올라오는 기본 전환은 끈다. 모션이 대신 화면을 연다.
    private func openFeeding(_ request: FeedingRequest) {
        let opening = feedingOpening()
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { feeding = FeedingPresentation(request: request, opening: opening, snapshot: nil) }
    }

    private func totals(for day: DayKey) -> DayTotals {
        let consumptions = entries
            .filter { $0.dayKey(boundaryHour: boundaryHour) == day }
            .map(\.consumption)
        return DayMath.totals(consumptions, limits: limits)
    }

    /// 오늘 행을 만들고(앱을 연 날 표시), 마감한 지난 날을 확정·적립하고, 어제에 대해 물을 것을 고른다.
    private func refreshSettlement(today: DayKey) {
        do {
            _ = try SettlementStore.row(for: today, in: context)
            try context.save()

            let records = try SettlementStore.records(in: context)
            let plan = SettlementPlanner.plan(today: today, records: records)
            // 선물이 생기기 전부터 쓰던 기기는 추이가 잠기지 않게 먼저 소급한다(이번 적립 전 상태로 판정).
            _ = try GiftStore.adoptExistingProgress(records: records, now: Date(), in: context)
            var credited: [FeedResult] = []
            for day in plan.finalize {
                let row = try SettlementStore.row(for: day, in: context)
                credited += try SettlementStore.finalize(
                    row, entries: entries, limits: limits, boundaryHour: boundaryHour, sides: trackedSides,
                    isPro: pro.isPro, now: Date(), in: context
                )
            }
            // 첫 적립 뒤 첫 선물 = 추이 열림(SPEC §4.9).
            _ = try GiftStore.grantFirstReward(credited: credited, now: Date(), in: context)
            _ = GiftStore.queueLevelUps(credited: credited, now: Date(), in: context)
            if let settings = settingsRows.first {
                // 꺼진 면의 감소 목표는 멈춘다. 다시 켜면 그동안의 주도 저장된 기록으로 판정한다.
                let sides = trackedSides
                for goal in try ReductionStore.goals(in: context) {
                    guard let goalSide = goal.cupSide, sides.contains(goalSide) else { continue }
                    let reached = ReductionStore.advance(
                        goal, entries: entries, boundaryHour: boundaryHour, today: today,
                        settings: settings, in: context
                    )
                    // 목표를 끝까지 해내면 그 면 캐릭터가 선물을 가져온다(§4.9).
                    if reached { try GiftStore.grantGoalReached(side: goalSide, isPro: pro.isPro, now: Date(), in: context) }
                }
            }
            try context.save()

            prompt = plan.prompt
            presentGateIfPending()
            if !credited.isEmpty {
                creditNotice = credited
            }
        } catch {
            Self.logger.error("정산 실패(\(today.rawValue, privacy: .public)): \(String(describing: error), privacy: .public)")
            failureMessage = String(localized: "지난 기록을 정리하지 못했어요. 앱을 다시 열어 주세요.")
        }
    }

    private func feed(_ request: FeedingRequest) throws -> [FeedResult] {
        let now = Date()
        let results: [FeedResult]
        var keptWeek: DayKey?
        switch request.kind {
        case .closeToday:
            let today = DayKey(at: now, boundaryHour: boundaryHour)
            let row = try SettlementStore.row(for: today, in: context)
            SettlementStore.close(row, totals: try storedTotals(for: today), now: now)
            results = []
            if try GiftStore.grantWeekKept(closed: today, sides: trackedSides, isPro: pro.isPro, now: now, in: context) {
                keptWeek = today
            }
        case .pastDay(let day):
            results = try SettlementStore.feedPastDay(
                day, entries: try context.fetch(FetchDescriptor<Entry>()), limits: limits, boundaryHour: boundaryHour,
                sides: trackedSides, isPro: pro.isPro, now: now, in: context
            )
            prompt = nil
            // 첫 적립이 "어제 먹이기"로 나도 첫 선물은 온다(SPEC §4.9).
            _ = try GiftStore.grantFirstReward(credited: results, now: now, in: context)
            _ = GiftStore.queueLevelUps(credited: results, now: now, in: context)
            if try GiftStore.grantWeekKept(closed: day, sides: trackedSides, isPro: pro.isPro, now: now, in: context) {
                keptWeek = day
            }
        }
        _ = try GiftStore.queueFirstMeeting(sides: trackedSides, now: now, in: context)
        // `close`가 행에 마감 시각을 적은 뒤라 방금 마감한 날도 센다.
        _ = try GiftStore.grantStarterCap(sides: trackedSides, now: now, in: context)
        try context.save()
        didFeed = true
        if let keptWeek { pendingWeekKept = try weekKeptCelebration(closed: keptWeek) }
        return results
    }

    /// 그 주 선물을 든 캐릭터 쪽으로 끝나는 축하. 축하할 면은 기록하는 면 전부(전부 지켜야 선물이 온다).
    private func weekKeptCelebration(closed: DayKey) throws -> WeekKeptCelebration {
        let week = GiftMath.weekStart(of: closed).rawValue
        let carrier = try GiftStore.all(in: context)
            .first { $0.giftKind == .weekKept && $0.week == week }?.cupSide
        return WeekKeptCelebration(closed: closed, sides: trackedSides, carrier: carrier ?? side)
    }

    /// 먹이기(오늘·어젯밤) 화면이 닫힌 뒤. 기준 지킨 주를 방금 채웠으면 축하부터, 아니면 첫 마감 알림 질문.
    private func afterFeedingClosed() {
        if let pending = pendingWeekKept {
            pendingWeekKept = nil
            weekKept = pending
        } else {
            askReminderAfterFirstFeed()
        }
    }

    /// 첫 마감(먹이기)을 마친 뒤 한 번만 마감 알림을 묻는다(2026-10-05 대표님). 테스트 카드 먹이기는 세지 않는다.
    private func askReminderAfterFirstFeed() {
        guard didFeed else { return }
        didFeed = false
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: CloseReminder.askedKey), !defaults.bool(forKey: CloseReminder.enabledKey) else { return }
        defaults.set(true, forKey: CloseReminder.askedKey)
        asksReminder = true
    }

    /// 정산 화면에서 음료를 더 기록하고(§4.7), 그날 남은 양으로 요청을 다시 만든다.
    private func addDrink(_ entry: Entry, to request: FeedingRequest) throws -> FeedingRequest {
        context.insert(entry)
        try context.save()
        let day: DayKey
        switch request.kind {
        case .closeToday: day = DayKey(at: Date(), boundaryHour: boundaryHour)
        case .pastDay(let past): day = past
        }
        let dayTotals = try storedTotals(for: day)
        return FeedingRequest(
            kind: request.kind,
            sugarLeftG: dayTotals.leftSugarG,
            caffeineLeftMg: dayTotals.leftCaffeineMg,
            limits: limits,
            sugarOverG: dayTotals.overSugarG,
            caffeineOverMg: dayTotals.overCaffeineMg
        )
    }

    /// 정산 화면은 열 때의 뷰를 붙잡고 있어 `@Query` 값이 늦을 수 있다. 저장소에서 바로 읽는다.
    private func storedTotals(for day: DayKey) throws -> DayTotals {
        let consumptions = try context.fetch(FetchDescriptor<Entry>())
            .filter { $0.dayKey(boundaryHour: boundaryHour) == day }
            .map(\.consumption)
        return DayMath.totals(consumptions, limits: limits)
    }

    private func dismissPastDay(_ day: DayKey) {
        do {
            try SettlementStore.dismissPastDay(day, now: Date(), in: context)
            try context.save()
            prompt = nil
            gate = nil
        } catch {
            Self.logger.error("어제 닫기 실패(\(day.rawValue, privacy: .public)): \(String(describing: error), privacy: .public)")
            failureMessage = String(localized: "저장하지 못했어요. 다시 시도해 주세요.")
        }
    }

    /// 설정 테스트 카드(TestFlight·Debug)에서 고른 일. 설정 시트가 다 닫힌 뒤에 부른다.
    /// 먹이기·어젯밤 화면은 실제와 같은 값·같은 여는 방식으로 띄우되 아무것도 저장하지 않는다.
    private func runPendingTestAction() {
        guard let action = pendingTestAction else { return }
        pendingTestAction = nil
        let now = Date()
        switch action {
        case .feeding:
            let todayTotals = todayTotals(now: now)
            let request = FeedingRequest(
                kind: .closeToday, sugarLeftG: todayTotals.leftSugarG, caffeineLeftMg: todayTotals.leftCaffeineMg,
                limits: limits, sugarOverG: todayTotals.overSugarG, caffeineOverMg: todayTotals.overCaffeineMg
            )
            let opening = feedingOpening()
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                feeding = FeedingPresentation(request: request, opening: opening, snapshot: nil, isRehearsal: true)
            }
        case .yesterdayGate:
            let yesterday = DayKey(at: now, boundaryHour: boundaryHour).shifted(by: -1)
            let dayTotals = totals(for: yesterday)
            isGateRehearsal = true
            gate = YesterdayGate(
                kind: .feed, day: yesterday, sugarLeftG: dayTotals.leftSugarG, caffeineLeftMg: dayTotals.leftCaffeineMg,
                limits: limits, sugarOverG: dayTotals.overSugarG, caffeineOverMg: dayTotals.overCaffeineMg
            )
        case .weekKept:
            // 선물 받기까지 체험한다(대표님 2026-10-12). 실제 상자를 넣되 주(week)는 비워 진짜 이번 주 선물을 막지 않는다.
            let today = DayKey(at: now, boundaryHour: boundaryHour)
            do {
                let picked = GiftStore.content(
                    owners: trackedSides, isPro: pro.isPro, taken: try GiftStore.takenItems(in: context),
                    roll: Double.random(in: 0 ..< 1)
                )
                let carrier = picked.owner ?? trackedSides.randomElement() ?? side
                context.insert(GiftEvent(kind: .weekKept, side: carrier, payload: picked.payload, createdAt: now))
                try context.save()
                weekKept = WeekKeptCelebration(closed: today, sides: trackedSides, carrier: carrier)
            } catch {
                Self.logger.error("테스트 주 선물 저장 실패: \(String(describing: error), privacy: .public)")
                context.rollback()
                failureMessage = String(localized: "기록을 저장하지 못했어요. 다시 시도해 주세요.")
            }
        case .firstRun:
            // 루트가 완료 플래그를 지켜보다 온보딩으로 바꾼다. 기록·정산·호감도는 그대로다.
            UserDefaults.standard.removeObject(forKey: CompanionIntro.seenKey)
            UserDefaults.standard.removeObject(forKey: CloseReminder.askedKey)
            UserDefaults.standard.set(false, forKey: OnboardingView.completedKey)
        }
    }

    /// 테스트 카드 먹이기의 음료 추가. 저장하지 않고 요청의 남은 양만 그 음료만큼 줄인다.
    private static func rehearse(_ entry: Entry, on request: FeedingRequest) -> FeedingRequest {
        let limits = request.limits
        let drunk = Consumption(
            sugarG: limits.sugarG - request.sugarLeftG + request.sugarOverG,
            caffeineMg: limits.caffeineMg - request.caffeineLeftMg + request.caffeineOverMg
        )
        let totals = DayMath.totals([drunk, entry.consumption], limits: limits)
        return FeedingRequest(
            kind: request.kind, sugarLeftG: totals.leftSugarG, caffeineLeftMg: totals.leftCaffeineMg,
            limits: limits, sugarOverG: totals.overSugarG, caffeineOverMg: totals.overCaffeineMg
        )
    }

    /// CI 스크린샷 전용(Debug 빌드만). 실행 인자로 덮인 화면을 바로 띄운다.
    /// 마감 버튼은 저녁 이후에만 보여서 러너 시각에 따라 화면에 닿지 못하고,
    /// 페이월·호감도는 탭을 거쳐야 열려 `simctl`로는 닿지 못한다.
    private func presentScreenshotFeedingIfRequested(totals: DayTotals) {
        #if DEBUG
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "screenshotFeeding") {
            // 단계·전환·소개 시각을 인자로 골라 멈춘 화면을 찍는다(스크립트: .github/workflows/testflight.yml).
            var snapshot = FeedingSnapshot()
            snapshot.stage = defaults.string(forKey: "screenshotFeedingStage").flatMap(FeedingSnapshot.Stage.init(rawValue:)) ?? .ask
            switch defaults.string(forKey: "screenshotFx") {
            case "dusk": snapshot.fx = .dusk(title: String(localized: "오늘 마감"))
            case "turn": snapshot.fx = .turn
            case "night": snapshot.fx = .night
            default: break
            }
            snapshot.fxAt = defaults.double(forKey: "screenshotFxAt")
            // `-screenshotFeedingTutorial YES` = 소개 직후 첫 먹이기의 튜토리얼 덮개.
            snapshot.tutorial = defaults.bool(forKey: "screenshotFeedingTutorial")
            if defaults.object(forKey: "screenshotIntroAt") != nil {
                snapshot.introAt = defaults.double(forKey: "screenshotIntroAt")
            }
            // `-screenshotFeedingEmpty YES` = 기준을 넘겨 먹일 게 없는 날(빈 컵 털기).
            let isEmptyDay = defaults.bool(forKey: "screenshotFeedingEmpty")
            let request = isEmptyDay
                ? FeedingRequest(
                    kind: .closeToday, sugarLeftG: 0, caffeineLeftMg: 0, limits: limits, sugarOverG: 12, caffeineOverMg: 85
                )
                : FeedingRequest(
                    kind: .closeToday, sugarLeftG: totals.leftSugarG, caffeineLeftMg: totals.leftCaffeineMg,
                    limits: limits, sugarOverG: totals.overSugarG, caffeineOverMg: totals.overCaffeineMg
                )
            feeding = FeedingPresentation(
                request: request, opening: snapshot.introAt != nil ? .companionIntro : .immediate, snapshot: snapshot
            )
        }
        // `YES`면 월 추이, 기능 이름(`ProFeature.rawValue`)이면 그 기능에서 연 페이월.
        if let raw = defaults.string(forKey: "screenshotPaywall") {
            paywall = ProFeature(rawValue: raw) ?? .monthlyTrends
        }
        if defaults.bool(forKey: "screenshotRecord") {
            isRecordSheetPresented = true
        }
        // 어젯밤 처리 전체 화면(`-screenshotGate feed|ask`).
        if let kind = defaults.string(forKey: "screenshotGate") {
            let yesterday = DayKey(at: Date(), boundaryHour: boundaryHour).shifted(by: -1)
            gate = YesterdayGate(
                kind: kind == "ask" ? .askNoDrink : .feed, day: yesterday,
                sugarLeftG: kind == "ask" ? limits.sugarG : 18, caffeineLeftMg: kind == "ask" ? limits.caffeineMg : 150,
                limits: limits
            )
        }
        // 카페인 컵 면으로 시작(`-screenshotSide caffeine`).
        if let raw = defaults.string(forKey: "screenshotSide"), let requested = CupSide(rawValue: raw) {
            pickedSide = requested
        }
        if defaults.bool(forKey: "screenshotDayLog") {
            isDayLogPresented = true
        }
        if let brandID = defaults.string(forKey: "screenshotBrand") {
            path = [brandID]
        }
        #endif
    }

    private func record(_ entry: Entry) {
        context.insert(entry)
        persist(String(localized: "기록 저장"))
        path = []
    }

    private func delete(_ targets: [Entry]) {
        for entry in targets {
            context.delete(entry)
        }
        persist(String(localized: "기록 삭제"))
    }

    /// 자동 저장을 기다리지 않는다. 기록 직후 앱이 종료돼도 남아야 한다.
    private func persist(_ action: String) {
        do {
            try context.save()
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            Self.logger.error("\(action, privacy: .public) 실패: \(String(describing: error), privacy: .public)")
            // 저장 안 된 변경을 되돌려 화면(컵)이 실제 저장 상태와 어긋나지 않게 한다.
            context.rollback()
            failureMessage = String(localized: "\(action)에 실패했어요. 다시 시도해 주세요.")
        }
    }
}

#Preview {
    if let catalog = try? CatalogStore.loadBundled(.kr) {
        TodayView(catalog: CatalogIndex(catalog: catalog))
            .environment(ProStore(previewPlans: ProStore.mockPlans, isPro: false))
            .modelContainer(for: [Entry.self, AppSettings.self, DaySettlement.self, Affinity.self, ReductionGoal.self, FavoriteDrink.self], inMemory: true)
    } else {
        Text("번들 카탈로그를 읽지 못함")
    }
}
