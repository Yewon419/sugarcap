import SwiftUI

/// 직접 입력 수치 파싱. 빈 칸은 "모름"이라 nil이고, 0으로 채우지 않는다(SPEC §9.2와 같은 규칙).
enum ManualAmount: Equatable {
    case empty
    case value(Double)
    case invalid

    init(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            self = .empty
        } else if let number = Double(trimmed), number.isFinite, number >= 0 {
            self = .value(number)
        } else {
            self = .invalid
        }
    }

    var number: Double? {
        if case .value(let number) = self { return number }
        return nil
    }
}

/// 직접 입력 시트(SPEC §4.2, `design/prototype.html:404-408`). 이름·당·카페인만 받는다.
struct ManualEntrySheet: View {
    let onSave: (Entry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var sugarText = ""
    @State private var caffeineText = ""

    private var sugar: ManualAmount { ManualAmount(sugarText) }
    private var caffeine: ManualAmount { ManualAmount(caffeineText) }
    private var canSave: Bool { sugar != .invalid && caffeine != .invalid }

    var body: some View {
        NavigationStack {
            Form {
                TextField("이름", text: $name)
                    .accessibilityIdentifier("manual-name")
                amountField(
                    "당", unit: CupSide.sugar.unit, text: $sugarText,
                    isInvalid: sugar == .invalid, identifier: "manual-sugar"
                )
                amountField(
                    "카페인", unit: CupSide.caffeine.unit, text: $caffeineText,
                    isInvalid: caffeine == .invalid, identifier: "manual-caffeine"
                )
                Section {
                    Text("모르는 값은 비워 두세요. 합계에는 0으로 더하고 기록에는 \"미공개\"로 남아요.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("직접 입력")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장", action: save)
                        .disabled(!canSave)
                        .accessibilityIdentifier("manual-save")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func amountField(
        _ title: String, unit: String, text: Binding<String>, isInvalid: Bool, identifier: String
    ) -> some View {
        HStack {
            TextField(title, text: text)
                .keyboardType(.decimalPad)
                .accessibilityIdentifier(identifier)
            Text(unit)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(isInvalid ? Color.red : Color.primary)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(
            Entry(
                servingID: nil,
                quantity: 1,
                loggedAt: Date(),
                sugarG: sugar.number,
                caffeineMg: caffeine.number,
                drinkName: trimmed.isEmpty ? "직접 입력" : trimmed,
                brandName: "직접 입력",
                sizeLabel: ""
            )
        )
        dismiss()
    }
}
