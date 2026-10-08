import SwiftUI

/// 브랜드 메뉴(2026-09-26 HTML 프로토타입 확정, SPEC §4.2). 오늘 스택에 푸시되고, "추가"하면 오늘 루트로 돌아간다.
/// 소제목(잔 기준 안내) → 큰 브랜드 이름 → 검색 → 분류 칩 → 메뉴 줄. 메뉴를 누르면 영향 미리보기 패널이 뜬다.
/// 편의점처럼 메뉴가 수천 개면 분류 칩·전체 목록 없이 검색부터 보여 준다(2026-10-01).
struct BrandMenuView: View {
    let brand: Brand
    let catalog: CatalogIndex
    let todayTotals: DayTotals
    let limits: DailyLimits
    let onAdd: (ServingSelection) -> Void
    let onManualEntry: () -> Void

    @State private var query = BrandMenuView.initialQuery
    @State private var category = BrandMenuView.allCategory
    @State private var panelDrink: Drink?

    private static let allCategory = String(localized: "전체")
    /// 이보다 메뉴가 많으면(편의점) 전체 목록·분류 칩 대신 검색부터 보여 준다. 카페 최대는 빽다방 296개.
    private static let searchFirstThreshold = 1000
    /// 검색 우선 브랜드에서 한 번에 그리는 결과 수. 넘치면 더 입력하라고 안내한다.
    private static let searchFirstLimit = 100

    /// CI 스크린샷이 검색 결과를 찍게 검색어를 미리 넣는다(`-screenshotBrandQuery 바나나`, Debug 빌드만).
    private static var initialQuery: String {
        #if DEBUG
        UserDefaults.standard.string(forKey: "screenshotBrandQuery") ?? ""
        #else
        ""
        #endif
    }

    private var drinks: [Drink] { catalog.drinks(brandID: brand.id) }

    private var isSearchFirst: Bool { drinks.count > Self.searchFirstThreshold }

    private func results() -> [Drink] {
        let found = catalog.drinks(brandID: brand.id, matching: DrinkQuery(query))
        guard category != Self.allCategory else { return found }
        return found.filter { $0.category == category }
    }

    /// 브랜드 잔 기준 안내가 짧으면 소제목으로, 길면 메뉴 수로(길면 줄이 넘친다).
    private var kicker: String {
        brand.servingNote.count <= 20 ? brand.servingNote : String(localized: "메뉴 \(drinks.count.formatted())")
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(kicker).kicker()
                    Text(brand.name)
                        .font(AppFont.pretendard(34, .bold, relativeTo: .largeTitle))
                        .tracking(-0.7)
                        .accessibilityAddTraits(.isHeader)
                }
                .padding(.horizontal, 24)
                .padding(.top, 2)
                .padding(.bottom, 12)

                SearchField(prompt: isSearchFirst ? String(localized: "제품 이름 검색") : String(localized: "메뉴 검색"), text: $query)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)

                if isSearchFirst {
                    searchFirstList
                } else {
                    chips
                    menuList(results())
                }
                Color.clear.frame(height: 40)
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: openPanelForScreenshot)
        .sheet(item: $panelDrink) { drink in
            ServingPanel(drink: drink, brand: brand, todayTotals: todayTotals, limits: limits) { selection in
                // 패널을 먼저 닫고 기록한다. 기록하면 오늘 루트로 돌아간다(§4.2).
                panelDrink = nil
                onAdd(selection)
            }
        }
    }

    /// 편의점처럼 메뉴가 수천 개인 브랜드: 검색어가 없으면 안내만, 결과는 앞 `searchFirstLimit`개만 그린다.
    @ViewBuilder
    private var searchFirstList: some View {
        if DrinkQuery(query).isEmpty {
            CaptionNote(text: String(localized: "제품 이름으로 찾아 주세요. 띄어쓰기는 상관없어요. 예: 바나나맛우유"))
        } else {
            let found = results()
            menuList(Array(found.prefix(Self.searchFirstLimit)))
            if found.count > Self.searchFirstLimit {
                CaptionNote(text: String(localized: "\(found.count.formatted())개 중 \(Self.searchFirstLimit)개만 보여요. 이름을 더 입력해 주세요."))
            }
        }
    }

    /// CI 스크린샷이 메뉴 패널(출렁이는 큰 원)을 찍게 첫 결과를 연다(`-screenshotBrandPanel YES`, Debug 빌드만).
    private func openPanelForScreenshot() {
        #if DEBUG
        guard UserDefaults.standard.bool(forKey: "screenshotBrandPanel"), panelDrink == nil else { return }
        panelDrink = results().first
        #endif
    }

    @ViewBuilder
    private func menuList(_ found: [Drink]) -> some View {
        if found.isEmpty {
            CaptionNote(text: String(localized: "맞는 메뉴가 없어요."))
            Button(action: onManualEntry) {
                Label("직접 입력", systemImage: "plus")
                    .glassPill()
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .accessibilityIdentifier("brand-manual-entry")
        } else {
            ForEach(found) { drink in
                Button {
                    panelDrink = drink
                } label: {
                    DrinkLine(
                        title: drink.name,
                        meta: meta(drink),
                        figure: DrinkFigure(
                            name: drink.name,
                            sugarG: drink.servings.first?.sugarG,
                            caffeineMg: drink.servings.first.flatMap { $0.caffeineVariants.first?.caffeineMg ?? $0.caffeineMg },
                            caffeineRange: drink.servings.first?.caffeineRange
                        ),
                        liquid: drink.liquid
                    )
                }
                .buttonStyle(RowPressStyle())
                .accessibilityIdentifier("drink-\(drink.id)")
            }
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach([Self.allCategory] + catalog.categories(brandID: brand.id), id: \.self) { name in
                    let isOn = name == category
                    Button {
                        category = name
                    } label: {
                        Text(name)
                            .font(AppFont.pretendard(14, .medium, relativeTo: .subheadline))
                            .foregroundStyle(isOn ? Color.white : Color.primary)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 32)
                            .background(isOn ? Color.accentColor : Color(.tertiarySystemFill), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 12)
        }
        .sensoryFeedback(.selection, trigger: category)
    }

    /// 온도 · 첫 사이즈. 목록 수치는 첫 serving 기준이다(§4.2).
    private func meta(_ drink: Drink) -> String {
        [drink.temperatureLabel, drink.servings.first?.sizeLabel]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

/// 검색 칸(브랜드 메뉴용 36pt). 자동 포커스 안 함(§4.2): 눌러야 키보드가 올라온다.
struct SearchField: View {
    let prompt: String
    @Binding var text: String
    var height: CGFloat = 36
    var isProminent = false

    var body: some View {
        HStack(spacing: isProminent ? 10 : 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .font(AppFont.pretendard(17, .regular, relativeTo: .body))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .tapTarget()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("검색어 지우기")
            }
        }
        .padding(.horizontal, isProminent ? 16 : 10)
        .frame(minHeight: height)
        .background {
            if isProminent {
                Capsule().fill(.white.opacity(0.8))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.95)))
                    .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(.tertiarySystemFill))
            }
        }
    }
}

/// 목록 줄 누름: 크기 변화 없이 바탕만 옅게(목록은 scale하지 않는다).
struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.black.opacity(0.04) : Color.clear)
    }
}
