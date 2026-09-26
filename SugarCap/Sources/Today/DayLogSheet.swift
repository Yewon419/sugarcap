import SwiftUI

/// 하루 기록 시트(2026-09-26 HTML 프로토타입 확정). 오늘 화면 큰 숫자를 누르면 열리고, 추이에서 날짜를 눌러도 같은 시트다.
/// 합계 둘(당·카페인, 하루 기준 대비) → 기록 줄. "편집"을 누르면 줄 앞에 지우기 버튼이 나온다.
/// 기록 시트에서 오늘 기록 목록을 뺀 대신 여기서 보고 지운다.
struct DayLogSheet: View {
    let day: DayKey
    let isToday: Bool
    /// 그날 기록, 최신순.
    let entries: [Entry]
    let limits: DailyLimits
    let onDelete: ([Entry]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isEditing = false

    private var title: String {
        let base = isToday ? "오늘 기록" : "\(day.month)월 \(day.day)일 기록"
        return entries.isEmpty ? base : "\(base) · \(entries.count)잔"
    }

    var body: some View {
        let totals = DayMath.totals(entries.map(\.consumption), limits: limits)
        VStack(spacing: 0) {
            SheetHeader(title: title) {
                if !entries.isEmpty {
                    Button(isEditing ? "완료" : "편집") { isEditing.toggle() }
                        .tapTarget()
                        .accessibilityIdentifier("daylog-edit")
                }
                Button("닫기") { dismiss() }
                    .tapTarget()
                    .accessibilityIdentifier("daylog-close")
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 32) { figures(totals) }
                        VStack(alignment: .leading, spacing: 14) { figures(totals) }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 14)
                    .padding(.bottom, 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .bottom) { Divider() }

                    if entries.isEmpty {
                        CaptionNote(text: isToday ? "아직 기록이 없어요. 컵은 가득 찬 채로 기다리고 있어요." : "이날은 기록이 없어요.")
                            .padding(.top, 8)
                    } else {
                        ForEach(entries) { entry in
                            row(entry)
                                .transition(reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity))
                        }
                        if isEditing {
                            CaptionNote(text: "지운 음료만큼 컵이 다시 차요.")
                                .padding(.top, 6)
                        }
                    }
                    Color.clear.frame(height: 40)
                }
                .animation(.easeOut(duration: 0.22), value: entries.map(\.id))
                .animation(.easeOut(duration: 0.18), value: isEditing)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(38)
        .presentationBackground(.regularMaterial)
        .onChange(of: entries.isEmpty) { _, isEmpty in
            if isEmpty { isEditing = false }
        }
    }

    @ViewBuilder
    private func figures(_ totals: DayTotals) -> some View {
        figure(totals.sugarG, side: .sugar)
        figure(totals.caffeineMg, side: .caffeine)
    }

    private func figure(_ value: Double, side: CupSide) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(Amount.number(value))
                    .font(AppFont.pretendard(40, .bold, relativeTo: .largeTitle))
                    .tracking(-1.6)
                    .monospacedDigit()
                Text(side.unit)
                    .font(AppFont.pretendard(17, .medium, relativeTo: .body))
                    .opacity(0.85)
            }
            Text("\(side.label) · 기준 \(Amount.number(side.limit(limits))) \(side.unit)")
                .font(AppFont.pretendard(12, .regular, relativeTo: .caption))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("daylog-\(side.rawValue)")
    }

    private func row(_ entry: Entry) -> some View {
        let name = entry.quantity > 1 ? "\(entry.drinkName) ×\(entry.quantity)" : entry.drinkName
        let size = [entry.sizeLabel, entry.variantLabel].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        let meta = [entry.loggedAt.formatted(date: .omitted, time: .shortened), entry.brandName, size]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        return DrinkLine(title: name, meta: meta, figure: DrinkFigure(sugarG: entry.sugarG, caffeineMg: entry.caffeineMg)) {
            if isEditing {
                Button {
                    onDelete([entry])
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Color.red, in: Circle())
                        .tapTarget()
                }
                .buttonStyle(.plain)
                .padding(.leading, -8)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
                .accessibilityLabel("\(name) 삭제")
                .accessibilityIdentifier("delete-entry")
            }
        } trailing: {
            EmptyView()
        }
        .accessibilityIdentifier("entry-row")
    }
}
