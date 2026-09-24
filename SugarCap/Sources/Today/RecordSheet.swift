import SwiftUI

/// 기록 시트(2026-09-24 디자인). 오늘 화면이 컵 전면 구성으로 바뀌면서 브랜드 선택과
/// 오늘 기록 리스트가 화면에서 빠졌다. 둘을 `+` 버튼이 여는 이 시트로 옮겼다.
///
/// 구성: 소제목 → 브랜드 2열 타일 → 직접 입력(점선) → 소제목 → 오늘 기록.
struct RecordSheet: View {
    let brands: [Brand]
    let entries: [Entry]
    let onBrand: (String) -> Void
    let onManualEntry: () -> Void
    let onDelete: ([Entry]) -> Void

    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(brands) { brand in
                            Button {
                                onBrand(brand.id)
                            } label: {
                                Text(brand.name)
                                    .font(.system(size: 15, weight: .medium))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 16)
                                    .frame(height: 52)
                                    .background(
                                        Color(.secondarySystemBackground),
                                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("brand-\(brand.id)")
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                    Button {
                        onManualEntry()
                    } label: {
                        Label("직접 입력", systemImage: "plus")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .frame(height: 48)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                                    .foregroundStyle(Color(.separator))
                            )
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 12, trailing: 20))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .accessibilityIdentifier("manual-entry")
                } header: {
                    Text("어디서 마셨나요")
                        .kicker()
                        .textCase(nil)
                }

                Section {
                    if entries.isEmpty {
                        Text("첫 잔을 기록해 보세요")
                            .foregroundStyle(.secondary)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(entries) { entry in
                            EntryRow(entry: entry)
                                .accessibilityIdentifier("entry-row")
                                .listRowBackground(Color.clear)
                        }
                        .onDelete { offsets in
                            onDelete(offsets.map { entries[$0] })
                        }
                    }
                } header: {
                    Text("오늘 기록")
                        .kicker()
                        .textCase(nil)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .navigationTitle("기록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                        .accessibilityIdentifier("record-close")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }
}
