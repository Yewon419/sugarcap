import SwiftUI

/// 브랜드 메뉴(SPEC §4.2). 오늘 스택에 푸시되고, "추가"하면 오늘 루트로 돌아간다.
struct BrandMenuView: View {
    let brand: Brand
    let drinks: [Drink]
    let onAdd: (ServingSelection) -> Void
    let onManualEntry: () -> Void

    @State private var query = ""
    @State private var selection: ServingSelection?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var results: [Drink] {
        drinks.filter { $0.matches(query) }
    }

    var body: some View {
        List {
            if results.isEmpty {
                Button(action: onManualEntry) {
                    Label("검색 결과 없음 · 직접 입력", systemImage: "square.and.pencil")
                }
            } else {
                ForEach(results) { drink in
                    Button {
                        selection = ServingSelection(drink: drink)
                    } label: {
                        DrinkRow(drink: drink)
                    }
                    .tint(.primary)
                    .accessibilityIdentifier("drink-\(drink.id)")
                }
            }
        }
        .listStyle(.plain)
        // 자동 포커스 안 함(§4.2). 탭해야 키보드가 올라온다.
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "메뉴 검색"
        )
        .navigationTitle(brand.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if let binding = Binding($selection) {
                ServingPanel(
                    selection: binding,
                    brand: brand,
                    onAdd: { onAdd(binding.wrappedValue) },
                    onClose: { selection = nil }
                )
                // 모션 줄이기를 켜면 아래에서 올라오지 않고 그 자리에서 나타난다.
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: selection?.drink.id)
    }
}

/// 행 = 이름 / 당 g · 카페인 mg / 사이즈 라벨(§4.2). 수치는 첫 serving 기준이다.
private struct DrinkRow: View {
    let drink: Drink

    private var first: Serving? { drink.servings.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(drink.name)
                if let temperature = drink.temperatureLabel {
                    Text(temperature)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            if let first {
                Text(
                    [
                        Amount.text(first.sugarG, unit: CupSide.sugar.unit),
                        Amount.text(first.caffeineMg, unit: CupSide.caffeine.unit),
                        first.sizeLabel,
                    ].joined(separator: " · ")
                )
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}
