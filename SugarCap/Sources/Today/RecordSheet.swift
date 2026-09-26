import SwiftData
import SwiftUI

/// 기록 시트(2026-09-26 HTML 프로토타입 확정). `+` 버튼이 연다.
/// 검색 먼저 → 즐겨찾기(별표한 음료 → 최근 마신 음료, `+` 한 번에 1잔 기록) → 브랜드 격자(+ 직접 입력).
/// 오늘 기록 목록은 뺐다. 보기·지우기는 오늘 화면 큰 숫자를 누르면 뜨는 하루 기록 시트에서 한다.
struct RecordSheet: View {
    let catalog: CatalogIndex
    let todayTotals: DayTotals
    let limits: DailyLimits
    let onBrand: (String) -> Void
    let onManualEntry: () -> Void
    /// 검색 → 패널에서 추가.
    let onAdd: (ServingSelection, Brand) -> Void
    /// 즐겨찾기·최근 줄의 `+`. 오늘 화면에 되돌리기 안내가 뜬다.
    let onQuickAdd: (QuickDrink) -> Void

    @Query(sort: \FavoriteDrink.addedAt) private var favorites: [FavoriteDrink]
    @Query(sort: \Entry.loggedAt, order: .reverse) private var entries: [Entry]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var query = ""
    @State private var panelDrink: Drink?
    @State private var failureMessage: String?

    private var favoriteRows: [QuickDrink] {
        favorites.compactMap { QuickDrink(key: $0.key, catalog: catalog) }
    }

    private var recentRows: [QuickDrink] {
        let keys = RecentDrinks.pick(keysNewestFirst: entries.compactMap(\.drinkKey), favorites: Set(favorites.map(\.key)))
        return keys.compactMap { QuickDrink(key: $0, catalog: catalog) }
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "기록") {
                Button("닫기") { dismiss() }
                    .tapTarget()
                    .accessibilityIdentifier("record-close")
            }

            SearchField(prompt: "메뉴 이름으로 찾기", text: $query, height: 52, isProminent: true)
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 6)
                .accessibilityIdentifier("record-search")

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if query.trimmingCharacters(in: .whitespaces).isEmpty {
                        favoriteSection
                        brandGrid
                    } else {
                        searchResults
                    }
                    Color.clear.frame(height: 40)
                }
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(38)
        // 컵 장면이 비치는 유리 바탕(메인 화면 문법).
        .presentationBackground(.regularMaterial)
        .sheet(item: $panelDrink) { drink in
            if let brand = catalog.brand(id: drink.brandId) {
                ServingPanel(drink: drink, brand: brand, todayTotals: todayTotals, limits: limits) { selection in
                    panelDrink = nil
                    onAdd(selection, brand)
                }
            }
        }
        .alert(failureMessage ?? "", isPresented: Binding(get: { failureMessage != nil }, set: { if !$0 { failureMessage = nil } })) {
            Button("확인", role: .cancel) {}
        }
    }

    // MARK: - 즐겨찾기

    @ViewBuilder
    private var favoriteSection: some View {
        let starred = favoriteRows
        let recents = recentRows
        SectionKicker(title: "즐겨찾기", topPadding: 6)
        if starred.isEmpty, recents.isEmpty {
            CaptionNote(text: "자주 마시는 음료는 별을 눌러 두세요. 최근 마신 음료도 여기 모여요. 한 번 눌러 바로 기록해요.")
        } else {
            ForEach(starred) { quickRow($0, isStarred: true) }
            if !recents.isEmpty {
                if !starred.isEmpty {
                    Text("최근 마신 음료")
                        .font(AppFont.pretendard(11, .medium, relativeTo: .caption2))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        .padding(.bottom, 4)
                }
                ForEach(recents) { quickRow($0, isStarred: false) }
            }
        }
    }

    private func quickRow(_ drink: QuickDrink, isStarred: Bool) -> some View {
        DrinkLine(
            title: drink.name,
            meta: "\(drink.meta) · 당 \(Amount.text(drink.selection.sugarG, unit: CupSide.sugar.unit))",
            figure: nil
        ) {
            StarButton(isOn: isStarred) { toggleFavorite(drink.selection) }
                .padding(.leading, -6)
        } trailing: {
            Button {
                onQuickAdd(drink)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.7), in: Circle())
                    .overlay(Circle().strokeBorder(Color.accentColor.opacity(0.35)))
                    .tapTarget()
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel("\(drink.name) 기록")
            .accessibilityIdentifier("quick-add")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("quick-row")
    }

    // MARK: - 브랜드

    @ViewBuilder
    private var brandGrid: some View {
        SectionKicker(title: "브랜드")
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: typeSize.isAccessibilitySize ? 1 : 2)
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(catalog.catalog.brands) { brand in
                Button {
                    onBrand(brand.id)
                } label: {
                    brandCard(name: brand.name, detail: "메뉴 \(catalog.drinks(brandID: brand.id).count)", dashed: false)
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityIdentifier("brand-\(brand.id)")
            }
            Button(action: onManualEntry) {
                brandCard(name: "＋ 직접 입력", detail: "목록에 없을 때", dashed: true)
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityIdentifier("manual-entry")
        }
        .padding(.horizontal, 20)
    }

    private func brandCard(name: String, detail: String, dashed: Bool) -> some View {
        VStack(alignment: .leading) {
            Text(name)
                .font(AppFont.pretendard(17, .semibold, relativeTo: .headline))
                .tracking(-0.3)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 6)
            Text(detail)
                .font(AppFont.pretendard(11, .regular, relativeTo: .caption2))
                .tracking(0.5)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
        .background {
            let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
            if dashed {
                shape.strokeBorder(Color(.separator), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
            } else {
                shape.fill(.white.opacity(0.72)).overlay(shape.strokeBorder(.white.opacity(0.95)))
            }
        }
    }

    // MARK: - 검색

    @ViewBuilder
    private var searchResults: some View {
        let hits = catalog.search(query)
        if hits.isEmpty {
            CaptionNote(text: "\"\(query)\" 메뉴가 없어요. 직접 입력으로 남길 수 있어요.")
                .padding(.top, 10)
            Button(action: onManualEntry) {
                Label("직접 입력", systemImage: "plus").glassPill()
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .accessibilityIdentifier("search-manual-entry")
        } else {
            SectionKicker(title: "\(catalog.catalog.brands.count)개 브랜드에서 찾은 메뉴", topPadding: 6)
            ForEach(hits) { drink in
                Button {
                    panelDrink = drink
                } label: {
                    let first = drink.servings.first
                    DrinkLine(
                        title: drink.name,
                        meta: [catalog.brand(id: drink.brandId)?.name, drink.temperatureLabel, first?.sizeLabel]
                            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "),
                        figure: DrinkFigure(
                            sugarG: first?.sugarG,
                            caffeineMg: first.flatMap { $0.caffeineVariants.first?.caffeineMg ?? $0.caffeineMg }
                        )
                    )
                }
                .buttonStyle(RowPressStyle())
                .accessibilityIdentifier("drink-\(drink.id)")
            }
        }
    }

    private func toggleFavorite(_ selection: ServingSelection) {
        do {
            try Favorites.toggle(selection, favorites: favorites, in: context)
        } catch {
            failureMessage = "즐겨찾기를 저장하지 못했어요. 다시 시도해 주세요."
        }
    }
}

/// 버튼·카드 누름: 누르는 순간 0.97로(앱 전체 한 가지 누름 어휘).
struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
