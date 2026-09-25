import SwiftUI

/// 오늘 기록 한 줄. 시간·음료·당·카페인(SPEC §4.1).
struct EntryRow: View {
    let entry: Entry

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
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.callout, weight: .semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(
                "\(Amount.text(entry.sugarG, unit: CupSide.sugar.unit)) · \(Amount.text(entry.caffeineMg, unit: CupSide.caffeine.unit))"
            )
            .font(.system(.footnote, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .padding(.top, 3)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}
