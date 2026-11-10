import SwiftData
import SwiftUI

/// 기록 시트(2026-09-26 HTML 프로토타입 확정). `+` 버튼이 연다.
/// 검색 먼저 → 즐겨찾기(별표한 음료 → 최근 마신 음료, `+` 한 번에 1잔 기록) → 브랜드 격자(+ 직접 입력).
/// 오늘 기록 목록은 뺐다. 보기·지우기는 오늘 화면 큰 숫자를 누르면 뜨는 하루 기록 시트에서 한다.
struct RecordSheet: View {
    let catalog: CatalogIndex
    let todayTotals: DayTotals
    let limits: DailyLimits
    let onBrand: (BrandRoute) -> Void
    let onManualEntry: () -> Void
    /// 검색 → 패널에서 추가.
    let onAdd: (ServingSelection, Brand) -> Void
    /// 즐겨찾기·최근 줄의 `+`. 오늘 화면에 되돌리기 안내가 뜬다. 어느 줄이었는지 같이 넘긴다(이용 기록 §9.10).
    let onQuickAdd: (QuickDrink, EntryPath) -> Void
    /// 오늘 기록 잔 수. 0보다 크면 제목이 하루 기록 시트로 가는 버튼이 된다.
    let todayCount: Int
    /// 잘못 넣은 음료를 바로 고치러 간다(빌드 272 대표님 "수정할 경로가 가까워야지").
    let onTodayLog: () -> Void

    @Query(sort: \FavoriteDrink.addedAt) private var favorites: [FavoriteDrink]
    @Query(sort: \FavoriteBrand.addedAt) private var favoriteBrands: [FavoriteBrand]
    @Query(sort: \Entry.loggedAt, order: .reverse) private var entries: [Entry]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.recordCup) private var recordCup
    @Environment(\.trackedSides) private var trackedSides
    @Environment(\.drinkTutorial) private var tutorial

    @State private var query = RecordSheet.initialQuery
    /// 첫 기록 안내에서 밝힐 첫 브랜드 칸(화면 좌표).
    @State private var firstBrandFrame: CGRect = .zero
    @State private var panelDrink: Drink?
    @State private var failureMessage: String?

    /// CI 스크린샷이 검색 결과를 찍게 검색어를 미리 넣는다(`-screenshotRecordQuery 스타벅스`, Debug 빌드만).
    private static var initialQuery: String {
        #if DEBUG
        UserDefaults.standard.string(forKey: "screenshotRecordQuery") ?? ""
        #else
        ""
        #endif
    }

    private var favoriteRows: [QuickDrink] {
        favorites.compactMap { QuickDrink(key: $0.key, catalog: catalog) }
    }

    private var recentRows: [QuickDrink] {
        let keys = RecentDrinks.pick(keysNewestFirst: entries.compactMap(\.drinkKey), favorites: Set(favorites.map(\.key)))
        return keys.compactMap { QuickDrink(key: $0, catalog: catalog) }
    }

    private var closeButton: some View {
        Button("닫기") { dismiss() }
            .tapTarget()
            .accessibilityIdentifier("record-close")
    }

    var body: some View {
        VStack(spacing: 0) {
            if todayCount > 0 {
                let base = String(localized: "오늘 기록")
                SheetHeader(title: String(localized: "\(base) · \(todayCount)잔"), actions: { closeButton }, onTitle: onTodayLog)
            } else {
                SheetHeader(title: String(localized: "기록")) { closeButton }
            }

            SearchField(prompt: String(localized: "메뉴 이름으로 찾기"), text: $query, height: 52, isProminent: true)
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
        // 첫 기록 안내: 연습용 브랜드 칸만 밝힌다.
        .overlay {
            if tutorial == .record, let first = catalog.catalog.brands.first {
                CoachMark(hole: firstBrandFrame, text: String(localized: "마신 음료의 브랜드를 탭하세요")) { onBrand(BrandRoute(brandID: first.id)) }
            }
        }
        .interactiveDismissDisabled(tutorial != nil)
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
        SectionKicker(title: String(localized: "즐겨찾기"), topPadding: 6)
        if starred.isEmpty, recents.isEmpty {
            CaptionNote(text: String(localized: "자주 마시는 음료는 별을 눌러 두세요. 최근 마신 음료도 여기 모여요. 한 번 눌러 바로 기록해요."))
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
        let side = CupSide.shown(in: recordCup, primary: drink.selection.primarySide, tracked: trackedSides)
        return DrinkLine(
            title: drink.name,
            meta: "\(drink.meta) · \(side.label) \(Amount.text(drink.selection.amount(side), unit: side.unit))",
            figure: nil,
            liquid: drink.selection.drink.liquid
        ) {
            StarButton(isOn: isStarred) { toggleFavorite(drink.selection) }
                .padding(.leading, -6)
        } trailing: {
            Button {
                onQuickAdd(drink, isStarred ? .favorite : .recent)
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
        SectionKicker(title: String(localized: "브랜드"))
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: typeSize.isAccessibilitySize ? 1 : 2)
        let starred = Set(favoriteBrands.map(\.brandID))
        LazyVGrid(columns: columns, spacing: 10) {
            // 별표한 브랜드가 맨 앞(2026-11-10 대표님). 별표는 브랜드 메뉴 제목 옆 별이나 카드를 길게 눌러서.
            ForEach(Favorites.starredFirst(catalog.catalog.brands, brandID: \.id, favorites: favoriteBrands)) { brand in
                let isStarred = starred.contains(brand.id)
                Button {
                    onBrand(BrandRoute(brandID: brand.id))
                } label: {
                    brandCard(name: brand.name, detail: Brand.menuCount(catalog.drinks(brandID: brand.id).count), dashed: false, isStarred: isStarred)
                }
                .buttonStyle(PressScaleStyle())
                .contextMenu {
                    if tutorial == nil {
                        Button {
                            toggleFavoriteBrand(brand.id)
                        } label: {
                            Label(
                                isStarred ? String(localized: "즐겨찾기 해제") : String(localized: "즐겨찾기"),
                                systemImage: isStarred ? "star.slash" : "star"
                            )
                        }
                        .accessibilityIdentifier("brand-favorite-menu")
                    }
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                    if brand.id == catalog.catalog.brands.first?.id { firstBrandFrame = frame }
                }
                .accessibilityIdentifier("brand-\(brand.id)")
            }
            Button(action: onManualEntry) {
                brandCard(name: String(localized: "＋ 직접 입력"), detail: String(localized: "목록에 없을 때"), dashed: true)
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityIdentifier("manual-entry")
        }
        .padding(.horizontal, 20)
    }

    private func brandCard(name: String, detail: String, dashed: Bool, isStarred: Bool = false) -> some View {
        VStack(alignment: .leading) {
            HStack(alignment: .top, spacing: 6) {
                Text(name)
                    .font(AppFont.pretendard(17, .semibold, relativeTo: .headline))
                    .tracking(-0.3)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if isStarred {
                    Spacer(minLength: 0)
                    Image(systemName: "star.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tint)
                        .padding(.top, 3)
                        .accessibilityLabel(String(localized: "즐겨찾기"))
                }
            }
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

    /// 검색어가 브랜드 이름에 걸리면 브랜드 줄을 먼저 띄운다(2026-11-10 대표님). 누르면 그 브랜드 메뉴로 가서 이어 찾는다.
    /// "브랜드 + 메뉴"로 치면 아래 결과도 그 브랜드 메뉴에서 찾는다(이름에 브랜드가 든 메뉴는 거의 없어 전체 검색은 비게 된다).
    @ViewBuilder
    private var searchResults: some View {
        let brands = Favorites.starredFirst(catalog.brandMatches(query), brandID: \.brand.id, favorites: favoriteBrands)
        let scoped = brands.filter { !$0.menuQuery.isEmpty }
        if !brands.isEmpty {
            SectionKicker(title: String(localized: "브랜드"), topPadding: 6)
            ForEach(brands) { brandRow($0) }
        }
        if scoped.isEmpty {
            let hits = catalog.search(query)
            if !hits.isEmpty {
                SectionKicker(title: String(localized: "\(catalog.catalog.brands.count)개 브랜드에서 찾은 메뉴"), topPadding: brands.isEmpty ? 6 : 30)
                ForEach(hits) { drinkRow($0) }
            } else if brands.isEmpty {
                CaptionNote(text: String(localized: "\"\(query)\" 메뉴가 없어요. 직접 입력으로 남길 수 있어요."))
                    .padding(.top, 10)
                Button(action: onManualEntry) {
                    Label("직접 입력", systemImage: "plus").glassPill()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .accessibilityIdentifier("search-manual-entry")
            }
        } else {
            ForEach(scoped) { match in
                let hits = catalog.drinks(brandID: match.brand.id, matching: DrinkQuery(match.menuQuery)).prefix(60)
                if !hits.isEmpty {
                    SectionKicker(title: String(localized: "\(match.brand.name)에서 찾은 메뉴"))
                    ForEach(Array(hits)) { drinkRow($0) }
                }
            }
        }
    }

    private func brandRow(_ match: BrandMatch) -> some View {
        Button {
            onBrand(BrandRoute(brandID: match.brand.id, menuQuery: match.menuQuery))
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(match.brand.name)
                        .font(AppFont.pretendard(17, .semibold, relativeTo: .headline))
                        .tracking(-0.3)
                    Text(Brand.menuCount(catalog.drinks(brandID: match.brand.id).count))
                        .font(AppFont.pretendard(11, .regular, relativeTo: .caption2))
                        .tracking(0.5)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if favoriteBrands.contains(where: { $0.brandID == match.brand.id }) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tint)
                        .accessibilityLabel(String(localized: "즐겨찾기"))
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
                shape.fill(.white.opacity(0.72)).overlay(shape.strokeBorder(.white.opacity(0.95)))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .accessibilityIdentifier("search-brand-\(match.brand.id)")
    }

    private func drinkRow(_ drink: Drink) -> some View {
        Button {
            panelDrink = drink
        } label: {
            let first = drink.servings.first
            DrinkLine(
                title: drink.name,
                meta: [catalog.brand(id: drink.brandId)?.name, drink.temperatureLabel, first.map { Serving.displaySize($0.sizeLabel) }]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "),
                figure: DrinkFigure(
                    name: drink.name,
                    sugarG: first?.sugarG,
                    caffeineMg: first.flatMap { $0.caffeineVariants.first?.caffeineMg ?? $0.caffeineMg },
                    caffeineRange: first?.caffeineRange,
                    estimated: first?.isEstimated ?? false
                ),
                liquid: drink.liquid
            )
        }
        .buttonStyle(RowPressStyle())
        .accessibilityIdentifier("drink-\(drink.id)")
    }

    private func toggleFavoriteBrand(_ brandID: String) {
        do {
            try Favorites.toggleBrand(brandID, favorites: favoriteBrands, in: context)
        } catch {
            failureMessage = String(localized: "즐겨찾기를 저장하지 못했어요. 다시 시도해 주세요.")
        }
    }

    private func toggleFavorite(_ selection: ServingSelection) {
        do {
            try Favorites.toggle(selection, favorites: favorites, in: context)
        } catch {
            failureMessage = String(localized: "즐겨찾기를 저장하지 못했어요. 다시 시도해 주세요.")
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
