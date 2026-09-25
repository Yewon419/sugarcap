import SwiftUI

/// 브랜드 메뉴 하단 고정 패널(SPEC §4.2). 사이즈는 사이즈 선택 브랜드만, 원두는 더벤티만 나온다.
struct ServingPanel: View {
    @Binding var selection: ServingSelection
    let brand: Brand
    let onAdd: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(selection.drink.name)
                    .font(.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .tapTarget()
                }
                .accessibilityLabel("닫기")
            }
            Text(brand.servingNote)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if selection.drink.servings.count > 1 {
                Picker("사이즈", selection: $selection.servingIndex) {
                    ForEach(Array(selection.drink.servings.enumerated()), id: \.offset) { index, serving in
                        Text(serving.sizeLabel).tag(index)
                    }
                }
                .pickerStyle(.segmented)
            }

            if !selection.serving.caffeineVariants.isEmpty {
                Picker("원두", selection: $selection.variantIndex) {
                    ForEach(Array(selection.serving.caffeineVariants.enumerated()), id: \.offset) { index, variant in
                        Text(variant.label).tag(index)
                    }
                }
                .pickerStyle(.segmented)
            }

            HStack {
                Stepper("\(selection.quantity)잔", value: $selection.quantity, in: 1...99)
                    .fixedSize()
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(Amount.text(selection.sugarG, unit: CupSide.sugar.unit))
                    Text(Amount.text(selection.caffeineMg, unit: CupSide.caffeine.unit))
                }
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy, value: selection)
            }

            Button(action: onAdd) {
                Text("추가")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .accessibilityIdentifier("add-entry")
        }
        .padding()
        .background(.regularMaterial)
    }
}
