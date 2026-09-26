import SwiftUI

/// 조금씩 줄이기 만들기(SPEC §4.3·§9.5, 2026-09-26 HTML 프로토타입 확정). 목표치와 기간만 고른다.
/// "어디까지 줄여 볼까요?" → 목표 칩 → 기간 → 미리보기(주마다 얼마씩, 몇 주 뒤 얼마) → 시작.
struct ReductionGoalSheet: View {
    let side: CupSide
    let currentLimit: Double
    let onSave: (_ target: Double, _ weeks: Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var target: Double?
    @State private var weeks = 8

    static let weekChoices = [4, 8, 12]

    /// 고를 수 있는 목표. 지금 기준보다 낮은 것만.
    static func targets(for side: CupSide, currentLimit: Double) -> [Double] {
        let all: [Double] = side == .sugar ? [40, 30, 25, 20] : [300, 250, 200, 150]
        return all.filter { $0 < currentLimit }
    }

    init(side: CupSide, currentLimit: Double, onSave: @escaping (Double, Int) -> Void) {
        self.side = side
        self.currentLimit = currentLimit
        self.onSave = onSave
        let targets = Self.targets(for: side, currentLimit: currentLimit)
        // 기본 제안은 가운데 목표.
        _target = State(initialValue: targets.isEmpty ? nil : targets[targets.count / 2])
    }

    var body: some View {
        let targets = Self.targets(for: side, currentLimit: currentLimit)
        VStack(spacing: 0) {
            SheetHeader(title: "\(side.label) 조금씩 줄이기") {
                Button("닫기") { dismiss() }
                    .tapTarget()
                    .accessibilityIdentifier("goal-close")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("어디까지\n줄여 볼까요?")
                        .font(AppFont.pretendard(34, .bold, relativeTo: .largeTitle))
                        .tracking(-0.7)
                        .lineSpacing(2)
                        .padding(.horizontal, 24)
                        .padding(.top, 14)
                    CaptionNote(text: "지금 하루 기준은 \(Amount.number(currentLimit)) \(side.unit)이에요.")
                        .padding(.top, 6)

                    if let target {
                        SectionKicker(title: "목표", topPadding: 14)
                        FlowLayout(spacing: 8) {
                            ForEach(targets, id: \.self) { value in
                                let isOn = value == target
                                Button {
                                    self.target = value
                                } label: {
                                    Text("\(Amount.number(value)) \(side.unit)")
                                        .font(AppFont.pretendard(14, .medium, relativeTo: .subheadline))
                                        .foregroundStyle(isOn ? Color.white : Color.primary)
                                        .padding(.horizontal, 14)
                                        .frame(minHeight: 32)
                                        .background(isOn ? Color(white: 0.11) : Color(.tertiarySystemFill), in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(isOn ? .isSelected : [])
                                .accessibilityIdentifier("goal-target-\(Amount.number(value))")
                            }
                        }
                        .padding(.horizontal, 20)

                        SectionKicker(title: "기간", topPadding: 18)
                        Picker("기간", selection: $weeks) {
                            ForEach(Self.weekChoices, id: \.self) { count in
                                Text("\(count)주").tag(count)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 20)

                        preview(target: target)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 24)

                        Button {
                            onSave(target, weeks)
                            dismiss()
                        } label: {
                            Text("시작")
                                .ctaLabel()
                                .foregroundStyle(.white)
                                .background(Color.accentColor, in: Capsule())
                        }
                        .buttonStyle(PressScaleStyle())
                        .padding(.horizontal, 20)
                        .accessibilityIdentifier("goal-start")
                    } else {
                        CaptionNote(text: "이미 가장 낮은 기준이에요.")
                    }
                    Color.clear.frame(height: 40)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: target)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(38)
        .presentationBackground(.regularMaterial)
    }

    private func preview(target: Double) -> some View {
        let perWeek = (currentLimit - target) / Double(weeks)
        return HStack(spacing: 14) {
            Image(side.characterAsset)
                .resizable()
                .scaledToFit()
                .frame(height: 64)
                .accessibilityHidden(true)
            (Text("주마다 약 ")
                + Text("\(Amount.number(perWeek)) \(side.unit)").foregroundColor(.accentColor).bold()
                + Text("씩 내려가서\n\(weeks)주 뒤 하루 ")
                + Text("\(Amount.number(target)) \(side.unit)").foregroundColor(.accentColor).bold()
                + Text("가 돼요."))
                .font(AppFont.pretendard(14, .regular, relativeTo: .subheadline))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ReductionGoalSheet(side: .sugar, currentLimit: 50, onSave: { _, _ in })
}
