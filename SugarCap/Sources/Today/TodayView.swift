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
    @State private var path: [String] = []
    @State private var isManualEntryPresented = false
    @State private var feeding: FeedingRequest?
    @State private var prompt: SettlementPlan.Prompt?
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
                onDelete: delete
            )
        }
        .fullScreenCover(item: $feeding) { request in
            FeedingView(request: request, onFeed: { try feed(request) })
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
            CupView(step: CupLevel.step(remaining: remaining, limit: limit), setID: side.cupSetID)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                // 좌우로 밀어 당 컵과 카페인 컵을 오간다(§4.1).
                .gesture(
                    DragGesture(minimumDistance: 24)
                        .onEnded { value in
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                                side = value.translation.width < 0 ? .caffeine : .sugar
                            }
                        }
                )

            // 상태 바 글자가 밝은 사진 위에서 묻히지 않게 아주 옅게만 깐다.
            LinearGradient(
                colors: [Color.black.opacity(0.09), .clear],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 160)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)

            headline(remaining: remaining, limit: limit, overflow: side.overflow(totals), now: now)

            banners(today: today)
                .padding(.horizontal, 20)
                .padding(.top, 232)
        }
        .overlay(alignment: .bottom) { bottomControls(now: now, today: today, totals: totals) }
        .overlay(alignment: .topTrailing) { affinityButton }
        // 하루가 바뀔 때마다(앱을 켠 날마다) 정산을 한 번 돈다(§4.7).
        .task(id: today) {
            refreshSettlement(today: today)
            presentScreenshotFeedingIfRequested(totals: totals)
        }
    }

    /// 날짜 → 무엇의 수치인지 → 숫자 순으로 읽힌다. 자간과 크기 대비로 위계를 만든다.
    private func headline(remaining: Double, limit: Double, overflow: Double, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(now.formatted(.dateTime.month().day().weekday(.wide)))
                .font(.system(.caption2, weight: .medium))
                .tracking(1.5)
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            Text("오늘 남은 \(side.label)")
                .font(.system(.caption2, weight: .semibold))
                .tracking(1.3)
                .foregroundStyle(.tint)
                .padding(.top, 28)

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
            case .increment: side = .caffeine
            case .decrement: side = .sugar
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

    @ViewBuilder
    private func banners(today: DayKey) -> some View {
        let yesterday = today.shifted(by: -1)
        let yesterdayRow = settlements.first { $0.day == yesterday.rawValue }

        switch prompt {
        case .feedYesterday(let day)?:
            banner {
                HStack {
                    Text("어제 남은 음료를 먹여 주세요")
                    Spacer(minLength: 8)
                    Button("먹이기") {
                        let dayTotals = totals(for: day)
                        feeding = FeedingRequest(
                            kind: .pastDay(day),
                            sugarLeftG: dayTotals.leftSugarG,
                            caffeineLeftMg: dayTotals.leftCaffeineMg,
                            limits: limits
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .accessibilityIdentifier("banner-feed-yesterday")
                }
            }
        case .askNoDrink(let day)?:
            banner {
                VStack(alignment: .leading, spacing: 12) {
                    Text("어제는 기록이 없어요. 음료를 안 마셨나요?")
                    HStack(spacing: 8) {
                        Button("안 마셨어요") {
                            feeding = FeedingRequest(
                                kind: .pastDay(day),
                                sugarLeftG: limits.sugarG,
                                caffeineLeftMg: limits.caffeineMg,
                                limits: limits
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        Button("마셨어요") { dismissPastDay(day) }
                            .buttonStyle(.bordered)
                    }
                    .buttonBorderShape(.capsule)
                }
            }
        case nil:
            EmptyView()
        }

        if let creditNotice {
            banner {
                VStack(alignment: .leading, spacing: 4) {
                    Text("지난밤 먹인 음료가 반영됐어요")
                    ForEach(creditNotice.filter(\.leveledUp), id: \.side) { result in
                        Text("\(result.side.characterNameWithGwa) \(AffinityMath.stageName(level: result.levelAfter))가 됐어요")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.tint)
                    }
                }
            }
        }

        if yesterdayRow?.shrankAfterClose == true {
            banner {
                Text("어젯밤 이후 마신 만큼 빠졌어요")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func banner(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(.secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
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
                feeding = FeedingRequest(
                    kind: .closeToday,
                    sugarLeftG: totals.leftSugarG,
                    caffeineLeftMg: totals.leftCaffeineMg,
                    limits: limits
                )
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
            feeding = FeedingRequest(
                kind: .closeToday, sugarLeftG: totals.leftSugarG, caffeineLeftMg: totals.leftCaffeineMg,
                limits: limits
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
            .modelContainer(for: [Entry.self, AppSettings.self, DaySettlement.self, Affinity.self, ReductionGoal.self, FavoriteDrink.self, TalkLog.self], inMemory: true)
    } else {
        Text("번들 카탈로그를 읽지 못함")
    }
}
