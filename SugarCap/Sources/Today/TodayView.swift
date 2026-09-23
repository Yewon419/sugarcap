import OSLog
import SwiftData
import SwiftUI

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
            .navigationTitle("오늘")
            .navigationDestination(for: String.self) { brandID in
                if let brand = catalog.brand(id: brandID) {
                    BrandMenuView(
                        brand: brand,
                        drinks: catalog.drinks(brandID: brandID),
                        onAdd: { selection in
                            record(selection.makeEntry(brandName: brand.name, at: Date()))
                        },
                        onManualEntry: { isManualEntryPresented = true }
                    )
                }
            }
        }
        .sheet(isPresented: $isManualEntryPresented) {
            ManualEntrySheet(onSave: record)
        }
        .fullScreenCover(item: $feeding) { request in
            FeedingView(request: request, onFeed: { try feed(request) })
        }
        // 기록할 때만 햅틱 1회(§4.1). 삭제로 줄어들 때는 울리지 않는다.
        .sensoryFeedback(.success, trigger: entries.count) { old, new in new > old }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let today = DayKey(at: now, boundaryHour: boundaryHour)
        let todays = entries.filter { $0.dayKey(boundaryHour: boundaryHour) == today }
        let totals = DayMath.totals(todays.map(\.consumption), limits: limits)

        List {
            banners(today: today)
                .listRowSeparator(.hidden)

            cupPager(totals: totals)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)

            summary(totals: totals)
                .listRowSeparator(.hidden)

            closeControl(now: now, today: today, totals: totals)
                .listRowSeparator(.hidden)

            brandPicker
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 12, trailing: 0))
                .listRowSeparator(.hidden)

            Section {
                if todays.isEmpty {
                    Text("첫 잔을 기록해 보세요")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(todays) { entry in
                        EntryRow(entry: entry)
                            .accessibilityIdentifier("entry-row")
                    }
                    .onDelete { offsets in
                        delete(offsets.map { todays[$0] })
                    }
                }
            } header: {
                Text("오늘 기록")
            }
        }
        .listStyle(.plain)
        // 하루가 바뀔 때마다(앱을 켠 날마다) 정산을 한 번 돈다(§4.7).
        .task(id: today) {
            refreshSettlement(today: today)
            presentScreenshotFeedingIfRequested(totals: totals)
        }
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
                            caffeineLeftMg: dayTotals.leftCaffeineMg
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
                                caffeineLeftMg: limits.caffeineMg
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
                        Text("\(result.side.characterNameWithGwa) 한 단계 더 친해졌어요 · Lv \(result.levelAfter)")
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
            Text("오늘 마감했어요")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        } else if CloseWindow.isOpen(at: now, closeFromHour: closeFromHour, boundaryHour: boundaryHour) {
            Button {
                feeding = FeedingRequest(
                    kind: .closeToday,
                    sugarLeftG: totals.leftSugarG,
                    caffeineLeftMg: totals.leftCaffeineMg
                )
            } label: {
                Text("오늘 마감")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .padding(.horizontal)
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
        }
    }

    /// CI 스크린샷 전용(Debug 빌드만): `simctl launch … -screenshotFeeding YES`로 마감 화면을 띄운다.
    /// 마감 버튼은 저녁 이후에만 보여서 러너 시각에 따라 화면에 닿지 못한다.
    private func presentScreenshotFeedingIfRequested(totals: DayTotals) {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "screenshotFeeding") {
            feeding = FeedingRequest(
                kind: .closeToday, sugarLeftG: totals.leftSugarG, caffeineLeftMg: totals.leftCaffeineMg
            )
        }
        #endif
    }

    private func cupPager(totals: DayTotals) -> some View {
        TabView(selection: $side) {
            ForEach(CupSide.allCases) { cupSide in
                cupPage(cupSide, totals: totals)
                    .tag(cupSide)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        // 장면은 9:16이지만 아래에 수치·기록이 와야 하므로 3:4로 잘라 쓴다.
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
    }

    private func cupPage(_ cupSide: CupSide, totals: DayTotals) -> some View {
        let step = CupLevel.step(
            remaining: cupSide.remaining(totals), limit: cupSide.limit(limits)
        )
        return CupView(step: step)
            .overlay(alignment: .bottomTrailing) {
                // 캐릭터는 컵에 붙어 있다(§4.1). 잔 오른쪽 냅킨 위에 기대 세운다.
                CharacterView(side: cupSide, isOverLimit: cupSide.overflow(totals) > 0)
                    .frame(width: 112, height: 112)
                    .padding(.trailing, 20)
                    .padding(.bottom, 28)
            }
    }

    private func summary(totals: DayTotals) -> some View {
        let remaining = side.remaining(totals)
        let limit = side.limit(limits)
        let overflow = side.overflow(totals)

        return VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(CupSide.allCases) { cupSide in
                    Circle()
                        .fill(cupSide == side ? Color.primary : Color.secondary.opacity(0.35))
                        .frame(width: 6, height: 6)
                }
            }
            .accessibilityHidden(true)

            Text("\(side.label) 남은 \(Amount.number(remaining)) \(side.unit) / \(Amount.number(limit)) \(side.unit)")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.spring(response: 0.4), value: remaining)

            if overflow > 0 {
                Text("+\(Amount.number(overflow)) \(side.unit) 넘김")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("cup-summary")
    }

    /// 브랜드 8개 + 직접 입력(§4.1). 카탈로그 등록 순서 그대로, 전부 한눈에 보이게 줄바꿈한다.
    private var brandPicker: some View {
        FlowLayout {
            ForEach(catalog.catalog.brands) { brand in
                Button(brand.name) { path = [brand.id] }
                    .accessibilityIdentifier("brand-\(brand.id)")
            }
            Button {
                isManualEntryPresented = true
            } label: {
                Label("직접 입력", systemImage: "square.and.pencil")
            }
            .accessibilityIdentifier("manual-entry")
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
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
        } catch {
            Self.logger.error("\(action, privacy: .public) 실패: \(String(describing: error), privacy: .public)")
        }
    }
}

#Preview {
    if let catalog = try? CatalogStore.loadBundled() {
        TodayView(catalog: CatalogIndex(catalog: catalog))
            .modelContainer(for: [Entry.self, AppSettings.self, DaySettlement.self, Affinity.self, ReductionGoal.self], inMemory: true)
    } else {
        Text("번들 카탈로그를 읽지 못함")
    }
}
