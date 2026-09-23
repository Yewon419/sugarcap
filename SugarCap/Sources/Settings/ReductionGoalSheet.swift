import SwiftUI

/// 감소 목표 만들기(SPEC §4.3·§9.5). 목표치와 기간만 고른다.
struct ReductionGoalSheet: View {
    let side: CupSide
    let currentLimit: Double
    let onSave: (_ target: Double, _ weeks: Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var target: Double
    @State private var weeks = 8

    static let weekChoices = [4, 8, 12]

    init(side: CupSide, currentLimit: Double, onSave: @escaping (Double, Int) -> Void) {
        self.side = side
        self.currentLimit = currentLimit
        self.onSave = onSave
        // 기본 제안은 지금 기준의 절반. 반올림 단위에 맞춘다.
        let step = side.reductionStep
        let half = ((currentLimit / 2) / step).rounded() * step
        _target = State(initialValue: max(step, min(currentLimit - step, half)))
    }

    private var lowerBound: Double { side.reductionStep }
    private var upperBound: Double { max(side.reductionStep, currentLimit - side.reductionStep) }
    private var perWeek: Double {
        (currentLimit - target) / Double(weeks)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("지금 하루 기준") {
                        Text("\(Amount.number(currentLimit)) \(side.unit)")
                            .monospacedDigit()
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("목표")
                            Spacer()
                            Text("\(Amount.number(target)) \(side.unit)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $target, in: lowerBound...upperBound, step: side.reductionStep)
                            .accessibilityIdentifier("goal-target")
                    }
                    .padding(.vertical, 4)

                    Picker("기간", selection: $weeks) {
                        ForEach(Self.weekChoices, id: \.self) { count in
                            Text("\(count)주").tag(count)
                        }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(
                        "한 주에 5일 이상 기준 이내면 다음 주 기준이 \(Amount.number(perWeek)) \(side.unit)씩 내려가요. 미달한 주는 기준을 그대로 둬요."
                    )
                }
            }
            .navigationTitle("\(side.label) 줄이기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("시작") {
                        onSave(target, weeks)
                        dismiss()
                    }
                    .disabled(target >= currentLimit)
                    .accessibilityIdentifier("goal-start")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    ReductionGoalSheet(side: .sugar, currentLimit: 50, onSave: { _, _ in })
}
