import SwiftData
import SwiftUI

/// 영향 미리보기 패널(2026-09-26 HTML 프로토타입 확정, SPEC §4.2). 브랜드 메뉴와 기록 시트 검색에서 메뉴를 누르면 뜬다.
/// 사이즈·원두 → "마시면 남는 당"(지금 → 마신 뒤, 컵 전후 사진) → 수량 + 추가.
/// 사이즈는 사이즈 선택 브랜드만, 원두는 더벤티만 나온다.
struct ServingPanel: View {
    let brand: Brand
    let todayTotals: DayTotals
    let limits: DailyLimits
    let onAdd: (ServingSelection) -> Void

    @State private var selection: ServingSelection
    @Query private var favorites: [FavoriteDrink]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var failureMessage: String?

    init(drink: Drink, brand: Brand, todayTotals: DayTotals, limits: DailyLimits, onAdd: @escaping (ServingSelection) -> Void) {
        self.brand = brand
        self.todayTotals = todayTotals
        self.limits = limits
        self.onAdd = onAdd
        _selection = State(initialValue: ServingSelection(drink: drink))
    }

    private var isFavorite: Bool { favorites.contains { $0.key == selection.drinkKey } }

    private var kicker: String {
        let size = selection.serving.sizeLabel == "기본" ? nil : selection.serving.sizeLabel
        let parts = [selection.drink.temperatureLabel, size].compactMap { $0 }
        return parts.isEmpty ? "메뉴" : parts.joined(separator: " · ")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(kicker).kicker()
                        Text(selection.drink.name)
                            .font(AppFont.pretendard(24, .bold, relativeTo: .title2))
                            .tracking(-0.5)
                    }
                    Spacer(minLength: 8)
                    StarButton(isOn: isFavorite) { toggleFavorite() }
                    Button("닫기") { dismiss() }
                        .font(AppFont.pretendard(15, .regular, relativeTo: .subheadline))
                        .tapTarget()
                        .accessibilityIdentifier("panel-close")
                }

                if selection.drink.servings.count > 1 {
                    Picker("사이즈", selection: $selection.servingIndex) {
                        ForEach(Array(selection.drink.servings.enumerated()), id: \.offset) { index, serving in
                            Text(serving.sizeLabel).tag(index)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.top, 12)
                }

                if !selection.serving.caffeineVariants.isEmpty {
                    Picker("원두", selection: $selection.variantIndex) {
                        ForEach(Array(selection.serving.caffeineVariants.enumerated()), id: \.offset) { index, variant in
                            Text(variant.label).tag(index)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.top, 12)
                }

                impact
                    .padding(.vertical, 20)

                HStack(spacing: 16) {
                    QuantityStepper(quantity: $selection.quantity)
                    Button {
                        onAdd(selection)
                    } label: {
                        Text("추가")
                            .ctaLabel()
                            .foregroundStyle(.white)
                            .background(Color.accentColor, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("add-entry")
                }

                Text(brand.servingNote)
                    .font(AppFont.pretendard(12, .regular, relativeTo: .caption))
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(.regularMaterial)
        .alert(failureMessage ?? "", isPresented: Binding(get: { failureMessage != nil }, set: { if !$0 { failureMessage = nil } })) {
            Button("확인", role: .cancel) {}
        }
    }

    // MARK: - 마시면 남는 당

    private var impact: some View {
        let limit = limits.sugarG
        let sugar = selection.sugarG
        let beforeLeft = todayTotals.leftSugarG
        let afterUsed = todayTotals.sugarG + (sugar ?? 0)
        let afterLeft = max(0, limit - afterUsed)
        let afterOver = max(0, afterUsed - limit)
        let caffeineAfter = max(0, limits.caffeineMg - todayTotals.caffeineMg - (selection.caffeineMg ?? 0))
        let note: String = {
            guard let sugar else { return "당 미공개 메뉴라 컵은 그대로예요" }
            return afterOver > 0 ? "하루 기준을 \(Amount.number(afterOver)) g 넘겨요" : "이 잔은 당 \(Amount.number(sugar)) g"
        }()

        return HStack(spacing: 12) {
            ImpactCup(step: CupLevel.step(remaining: beforeLeft, limit: limit))
            VStack(spacing: 4) {
                Text("마시면 남는 당").kicker()
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(Amount.number(beforeLeft))
                    Text("→")
                        .font(AppFont.pretendard(22, .medium, relativeTo: .title2))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                    Text(Amount.number(afterLeft))
                    Text("g")
                        .font(AppFont.pretendard(15, .medium, relativeTo: .subheadline))
                        .padding(.leading, 2)
                }
                .font(AppFont.pretendard(36, .bold, relativeTo: .largeTitle))
                .tracking(-1.2)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
                .animation(.snappy, value: afterLeft)
                Text(note)
                Text("카페인은 \(Amount.number(caffeineAfter)) mg 남아요")
            }
            .font(AppFont.pretendard(12, .regular, relativeTo: .caption))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            ImpactCup(step: CupLevel.step(remaining: afterLeft, limit: limit))
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("serving-impact")
    }

    private func toggleFavorite() {
        do {
            try Favorites.toggle(selection, favorites: favorites, in: context)
        } catch {
            failureMessage = "즐겨찾기를 저장하지 못했어요. 다시 시도해 주세요."
        }
    }
}

/// 당 컵 한 장(패널 좌우). 오늘 화면과 같은 사진을 작게, 바닥 기준으로 자른다.
private struct ImpactCup: View {
    let step: Int

    var body: some View {
        Color.clear
            .frame(width: 74, height: 110)
            .overlay(alignment: .bottom) {
                Image(CupLevel.assetName(setID: CupSide.sugar.cupSetID, step: step))
                    .resizable()
                    .scaledToFill()
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.black.opacity(0.05)))
            .accessibilityHidden(true)
    }
}

/// − 수량 + . 1잔 아래로는 내려가지 않는다.
struct QuantityStepper: View {
    @Binding var quantity: Int

    var body: some View {
        HStack(spacing: 14) {
            stepButton("minus", label: "한 잔 빼기", enabled: quantity > 1) { quantity -= 1 }
            Text("\(quantity)")
                .font(AppFont.pretendard(17, .bold, relativeTo: .headline))
                .monospacedDigit()
                .frame(minWidth: 18)
                .accessibilityLabel("\(quantity)잔")
            stepButton("plus", label: "한 잔 더", enabled: quantity < 99) { quantity += 1 }
        }
        .sensoryFeedback(.selection, trigger: quantity)
    }

    private func stepButton(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 34, height: 34)
                .background(Color(.tertiarySystemFill), in: Circle())
                .tapTarget()
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}
