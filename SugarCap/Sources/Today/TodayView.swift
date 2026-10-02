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

    @State private var side: CupSide = .sugar
    /// 넘기는 중 손가락이 끈 거리. 놓으면 0으로 돌아가며 가까운 컵에 붙는다.
    @State private var dragX: CGFloat = 0
    /// 컵을 넘기는 중(끄는 중 + 놓은 뒤 제자리로 붙는 중). 이 동안 캐릭터 움직임을 멈춰 컵과 한 몸으로 밀리게 한다.
    @State private var isSliding = false
    /// 오늘 화면이 보이는지. 다른 탭·다른 화면으로 가면 캐릭터를 멈춘다(탭 뒤에서도 매 프레임 그리면 앱 전체가 무거워진다).
    @State private var isOnScreen = false
    @State private var path: [String] = []
    @State private var isManualEntryPresented = false
    /// 먹이기 요청 + 여는 방식을 한 덩어리로 둔다. 따로 두면 전체 화면이 뜨기 전 값을 붙잡아
    /// 첫 마감 소개가 안 나왔다(2026-09-27 CI 스크린샷에서 발견).
    @State private var feeding: FeedingPresentation?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var prompt: SettlementPlan.Prompt?
    /// 어젯밤 처리할 게 있으면 앱을 열자마자 전체 화면으로 띄운다(2026-09-27 대표님). 처리 전까지 계속 뜬다.
    @State private var gate: YesterdayGate?
    /// "어젯밤 이후 마신 만큼 빠졌어요"를 X로 닫은 날. 그날엔 다시 띄우지 않는다.
    @AppStorage("dismissedShrankNoticeDay") private var dismissedShrankDay = ""
    /// 지난 마감분이 방금 확정됐을 때만 채운다. 이번 실행 동안만 보인다.
    @State private var creditNotice: [FeedResult]?
    @State private var paywall: ProFeature?
    @State private var isAffinityPresented = false
    @State private var isRecordSheetPresented = false
    @State private var isDayLogPresented = false
    /// 즐겨찾기 `+`로 방금 기록한 음료. 4초 동안 되돌리기 안내를 띄운다.
    @State private var undoToast: UndoToast?
    /// 호감도를 누르다 페이월로 간 경우. 구매하고 닫히면 호감도 화면을 이어서 연다.
    @State private var pendingAffinity = false
    /// 저장·정산 실패를 사용자에게 알린다. 로그만 남기면 기록이 사라져도 모른다.
    @State private var failureMessage: String?

    @Environment(ProStore.self) private var pro

    private static let logger = Logger(subsystem: "com.sugarcap.app", category: "today")

    private var limits: DailyLimits { settingsRows.first?.limits ?? .default }
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
                }
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
                    undoToast = UndoToast(entryID: entry.id, text: "\(drink.name) 기록했어요")
                }
            )
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
        .fullScreenCover(item: $feeding) { presentation in
            let request = presentation.request
            FeedingView(request: request, opening: presentation.opening, snapshot: presentation.snapshot, onFeed: { try feed(request) })
        }
        .sheet(item: $paywall, onDismiss: {
            if pro.isPro, pendingAffinity { isAffinityPresented = true }
            pendingAffinity = false
        }) { feature in
            PaywallView(feature: feature)
        }
        .sheet(isPresented: $isAffinityPresented) {
            AffinityView()
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
        // 기록할 때만 햅틱 1회(§4.1). 삭제로 줄어들 때는 울리지 않는다.
        .sensoryFeedback(.success, trigger: entries.count) { old, new in new > old }
    }

    /// 당 · 카페인 컵 장면 두 장을 옆으로 붙여 두고 손가락을 따라 통째로 민다(2026-09-27 대표님:
    /// "이미지 두 개 붙여 놓고 미는 식으로"). 놓으면 끈 거리·속도로 가까운 쪽에 붙는다. 끝에서는 고무줄처럼 덜 끌린다.
    private func cupStrip(totals: DayTotals) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let index = CGFloat(CupSide.allCases.firstIndex(of: side) ?? 0)
            HStack(spacing: 0) {
                ForEach(CupSide.allCases) { cupSide in
                    let step = cupStep(cupSide, totals: totals)
                    CupView(
                        step: step, setID: cupSide.cupSetID,
                        idle: IdleCharacterLayer(side: cupSide, step: step, isActive: cupSide == side && !isSliding && isOnScreen)
                    )
                    .frame(width: width)
                }
            }
            .offset(x: -index * width + dragX)
            .frame(width: width, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        isSliding = true
                        let pullingPastEdge = (side == .sugar && value.translation.width > 0)
                            || (side == .caffeine && value.translation.width < 0)
                        dragX = pullingPastEdge ? value.translation.width * 0.25 : value.translation.width
                    }
                    .onEnded { value in
                        let travel = value.predictedEndTranslation.width
                        let next: CupSide = travel < -width / 3 ? .caffeine : (travel > width / 3 ? .sugar : side)
                        withAnimation(reduceMotion ? .easeInOut(duration: 0.25) : .spring(response: 0.45, dampingFraction: 0.86)) {
                            side = next
                            dragX = 0
                        } completion: {
                            isSliding = false
                        }
                    }
            )
        }
        .ignoresSafeArea()
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
        guard next != side else { return }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.25) : .spring(response: 0.45, dampingFraction: 0.86)) {
            side = next
        }
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
            cupStrip(totals: totals)

            // 상태 바 글자가 밝은 사진 위에서 묻히지 않게 아주 옅게만 깐다.
            LinearGradient(
                colors: [Color.black.opacity(0.09), .clear],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 160)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)

            headline(remaining: remaining, limit: limit, overflow: side.overflow(totals))

            banners(today: today)
                .padding(.horizontal, 20)
                .padding(.top, 191)
        }
        .fullScreenCover(item: $gate, onDismiss: presentGateIfPending) { gate in
            YesterdayGateView(
                gate: gate,
                opening: feedingOpening(),
                onFeed: { request in try feed(request) },
                onDrank: { dismissPastDay(gate.day) }
            )
        }
        .overlay(alignment: .bottom) { bottomControls(now: now, today: today, totals: totals) }
        .overlay(alignment: .topTrailing) { affinityButton }
        .onAppear { isOnScreen = true }
        .onDisappear { isOnScreen = false }
        // 하루가 바뀔 때마다(앱을 켠 날마다) 정산을 한 번 돈다(§4.7).
        .task(id: today) {
            refreshSettlement(today: today)
            presentScreenshotFeedingIfRequested(totals: totals)
        }
    }

    /// 무엇의 수치인지 → 숫자 순으로 읽힌다. 자간과 크기 대비로 위계를 만든다.
    /// 날짜 줄은 대표님 지시로 뺐다(2026-09-29). 제목이 그 자리로 올라간다.
    private func headline(remaining: Double, limit: Double, overflow: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("오늘 남은 \(side.label)")
                .font(.system(.caption2, weight: .semibold))
                .tracking(1.3)
                .foregroundStyle(.tint)
                .padding(.top, 8)

            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(Amount.number(remaining))
                    .font(.system(size: 96, weight: .bold))
                    .tracking(-5.8)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(side.unit)
                    .font(.system(size: 30, weight: .medium))
                    .opacity(0.85)
                    .padding(.leading, 2)
                Text("/\(Amount.number(limit)) \(side.unit)")
                    .font(.footnote)
                    .tracking(0.3)
                    .foregroundStyle(.secondary)
                    .opacity(0.8)
                    .padding(.leading, 10)
            }
            .animation(.spring(response: 0.4), value: remaining)

            if overflow > 0 {
                Text("+\(Amount.number(overflow)) \(side.unit) 넘김")
                    .font(.system(.footnote, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            }
        }
        .padding(.leading, 24)
        // 큰 숫자를 누르면 하루 기록 시트(2026-09-26). 기록 보기·지우기는 여기서 한다.
        .contentShape(Rectangle())
        .onTapGesture { isDayLogPresented = true }
        .accessibilityElement(children: .combine)
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
        .accessibilityHint("눌러서 오늘 기록을 봐요. 위아래로 쓸어 당과 카페인 컵을 오가요")
    }

    private var affinityButton: some View {
        Button {
            // 무료는 페이월, Pro는 호감도 화면(§4.8).
            if pro.isPro {
                isAffinityPresented = true
            } else {
                pendingAffinity = true
                paywall = .affinityDetail
            }
        } label: {
            // 보이는 원은 36pt 그대로, 누르는 영역만 44pt.
            Image(systemName: "heart")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.7))
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.22), in: Circle())
                .tapTarget()
        }
        .padding(.trailing, 16)
        .padding(.top, 2)
        .accessibilityLabel("호감도")
        .accessibilityIdentifier("affinity")
    }

    /// 아래에서 위로: 마감 버튼(시간대에만) → 페이지 점 → 기록 버튼.
    @ViewBuilder
    private func bottomControls(now: Date, today: DayKey, totals: DayTotals) -> some View {
        // 액센트는 기록 버튼 하나만 쓴다. 마감은 조용한 유리 알약으로 왼쪽에 둔다.
        HStack(alignment: .center, spacing: 12) {
            closeControl(now: now, today: today, totals: totals)
            Spacer(minLength: 0)
            Button {
                isRecordSheetPresented = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(.white)
                    .frame(width: 59, height: 59)
                    .background(Color.accentColor, in: Circle())
                    .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
            }
            .accessibilityLabel("기록 추가")
            .accessibilityIdentifier("record-add")
        }
        .overlay { pageDots }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private var pageDots: some View {
        HStack(spacing: 7) {
            ForEach(CupSide.allCases) { cupSide in
                Circle()
                    .fill(Color.primary.opacity(cupSide == side ? 0.85 : 0.25))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - 정산(§4.7)

    /// 컵 위에 뜨는 안내. 음료를 가리므로 투명하게 두고 반드시 X로 닫을 수 있게 한다(2026-09-27 대표님 베타 피드백).
    /// 어제 먹이기·"안 마셨나요?"는 여기가 아니라 앱을 열면 먼저 뜨는 전체 화면(`YesterdayGateView`)이 맡는다.
    private func banners(today: DayKey) -> some View {
        let yesterday = today.shifted(by: -1)
        let yesterdayRow = settlements.first { $0.day == yesterday.rawValue }
        let showsShrank = yesterdayRow?.shrankAfterClose == true && dismissedShrankDay != yesterday.rawValue

        return VStack(spacing: 10) {
            if let creditNotice {
                notice(onClose: { self.creditNotice = nil }) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("지난밤 먹인 음료가 반영됐어요")
                        ForEach(creditNotice.filter(\.leveledUp), id: \.side) { result in
                            Text("\(result.side.characterNameWithGwa) \(AffinityMath.stageName(level: result.levelAfter))가 됐어요")
                                .font(AppFont.pretendard(15, .semibold, relativeTo: .subheadline))
                                .foregroundStyle(.tint)
                        }
                    }
                }
                .accessibilityIdentifier("notice-credit")
            }
            if showsShrank {
                notice(onClose: { dismissedShrankDay = yesterday.rawValue }) {
                    Text("어젯밤 이후 마신 만큼 빠졌어요")
                }
                .accessibilityIdentifier("notice-shrank")
            }
        }
        .animation(.easeOut(duration: 0.2), value: creditNotice == nil)
        .animation(.easeOut(duration: 0.2), value: showsShrank)
    }

    /// 투명한 안내 카드 + X. 컵 사진이 비쳐 보이게 옅은 흰 막만 깐다.
    private func notice(onClose: @escaping () -> Void, @ViewBuilder _ content: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 8) {
            content()
                .font(AppFont.pretendard(15, .regular, relativeTo: .subheadline))
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .background(.white.opacity(0.5), in: Circle())
                    .tapTarget()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("닫기")
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .frame(minHeight: 52)
        .background(.white.opacity(0.28), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.6)))
        .transition(.opacity.combined(with: .move(edge: .top)))
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

            let plan = SettlementPlanner.plan(
                today: today, records: try SettlementStore.records(in: context)
            )
            var credited: [FeedResult] = []
            for day in plan.finalize {
                let row = try SettlementStore.row(for: day, in: context)
                credited += try SettlementStore.finalize(
                    row, entries: entries, limits: limits, boundaryHour: boundaryHour,
                    now: Date(), in: context
                )
            }
            if let settings = settingsRows.first {
                for goal in try ReductionStore.goals(in: context) {
                    ReductionStore.advance(
                        goal, entries: entries, boundaryHour: boundaryHour, today: today,
                        settings: settings, in: context
                    )
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
            failureMessage = "지난 기록을 정리하지 못했어요. 앱을 다시 열어 주세요."
        }
    }

    private func feed(_ request: FeedingRequest) throws -> [FeedResult] {
        let now = Date()
        let results: [FeedResult]
        switch request.kind {
        case .closeToday:
            let today = DayKey(at: now, boundaryHour: boundaryHour)
            let row = try SettlementStore.row(for: today, in: context)
            SettlementStore.close(row, totals: totals(for: today), now: now)
            results = []
        case .pastDay(let day):
            results = try SettlementStore.feedPastDay(
                day, entries: entries, limits: limits, boundaryHour: boundaryHour,
                now: now, in: context
            )
            prompt = nil
        }
        try context.save()
        return results
    }

    private func dismissPastDay(_ day: DayKey) {
        do {
            try SettlementStore.dismissPastDay(day, now: Date(), in: context)
            try context.save()
            prompt = nil
            gate = nil
        } catch {
            Self.logger.error("어제 닫기 실패(\(day.rawValue, privacy: .public)): \(String(describing: error), privacy: .public)")
            failureMessage = "저장하지 못했어요. 다시 시도해 주세요."
        }
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
            case "dusk": snapshot.fx = .dusk(title: "오늘 마감")
            case "turn": snapshot.fx = .turn
            case "night": snapshot.fx = .night
            default: break
            }
            snapshot.fxAt = defaults.double(forKey: "screenshotFxAt")
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
        if defaults.bool(forKey: "screenshotPaywall") {
            paywall = .affinityDetail
        }
        if defaults.bool(forKey: "screenshotAffinity") {
            isAffinityPresented = true
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
            side = requested
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
        persist("기록 저장")
        path = []
    }

    private func delete(_ targets: [Entry]) {
        for entry in targets {
            context.delete(entry)
        }
        persist("기록 삭제")
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
            failureMessage = "\(action)에 실패했어요. 다시 시도해 주세요."
        }
    }
}

#Preview {
    if let catalog = try? CatalogStore.loadBundled() {
        TodayView(catalog: CatalogIndex(catalog: catalog))
            .environment(ProStore(previewPlans: ProStore.mockPlans, isPro: false))
            .modelContainer(for: [Entry.self, AppSettings.self, DaySettlement.self, Affinity.self, ReductionGoal.self, FavoriteDrink.self], inMemory: true)
    } else {
        Text("번들 카탈로그를 읽지 못함")
    }
}
