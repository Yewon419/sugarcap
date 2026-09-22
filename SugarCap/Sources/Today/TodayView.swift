import OSLog
import SwiftData
import SwiftUI

/// 오늘 화면(SPEC §4.1). 컵은 가득 찬 채로 시작해 기록할 때마다 줄어든다.
struct TodayView: View {
    let catalog: CatalogIndex

    @Environment(\.modelContext) private var context
    @Query private var settingsRows: [AppSettings]
    @Query(sort: \Entry.loggedAt, order: .reverse) private var entries: [Entry]

    @State private var side: CupSide = .sugar
    @State private var path: [String] = []
    @State private var isManualEntryPresented = false

    private static let logger = Logger(subsystem: "com.sugarcap.app", category: "today")

    private var limits: DailyLimits { settingsRows.first?.limits ?? .default }
    private var boundaryHour: Int { settingsRows.first?.dayBoundaryHour ?? 4 }

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
        // 기록할 때만 햅틱 1회(§4.1). 삭제로 줄어들 때는 울리지 않는다.
        .sensoryFeedback(.success, trigger: entries.count) { old, new in new > old }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let today = DayKey(at: now, boundaryHour: boundaryHour)
        let todays = entries.filter { $0.dayKey(boundaryHour: boundaryHour) == today }
        let totals = DayMath.totals(todays.map(\.consumption), limits: limits)

        List {
            cupPager(totals: totals)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)

            summary(totals: totals)
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
            .modelContainer(for: [Entry.self, AppSettings.self], inMemory: true)
    } else {
        Text("번들 카탈로그를 읽지 못함")
    }
}
