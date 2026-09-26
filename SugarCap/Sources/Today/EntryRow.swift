import SwiftUI

/// 오늘 기록 한 줄. 시간·음료·당·카페인(SPEC §4.1).
struct EntryRow: View {
    let entry: Entry

    @Environment(\.dynamicTypeSize) private var typeSize

    /// 큰 글자에서는 수치를 이름 옆에 두면 둘 다 세 줄로 부서진다. 이름 아래로 내린다.
    private var layout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
    }

    private var title: String {
        entry.quantity > 1 ? "\(entry.drinkName) ×\(entry.quantity)" : entry.drinkName
    }

    private var detail: String {
        let time = entry.loggedAt.formatted(date: .omitted, time: .shortened)
        let size = [entry.sizeLabel, entry.variantLabel]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return [time, entry.brandName, size]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    var body: some View {
        layout {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.callout, weight: .semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !typeSize.isAccessibilitySize {
                Spacer(minLength: 8)
            }
            Text(
                "\(Amount.text(entry.sugarG, unit: CupSide.sugar.unit)) · \(Amount.text(entry.caffeineMg, unit: CupSide.caffeine.unit))"
            )
            .font(.system(.footnote, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .padding(.top, typeSize.isAccessibilitySize ? 0 : 3)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}
