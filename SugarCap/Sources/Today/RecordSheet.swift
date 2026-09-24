import SwiftUI

/// 기록 시트. 오늘 화면이 컵 전면 구성으로 바뀌면서(2026-09-24 디자인) 브랜드 선택과
/// 오늘 기록 리스트가 화면에서 빠졌다. 둘을 `+` 버튼이 여는 이 시트로 옮겼다.
struct RecordSheet: View {
    let brands: [Brand]
    let entries: [Entry]
    let onBrand: (String) -> Void
    let onManualEntry: () -> Void
    let onDelete: ([Entry]) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    FlowLayout {
                        ForEach(brands) { brand in
                            Button(brand.name) { onBrand(brand.id) }
                                .accessibilityIdentifier("brand-\(brand.id)")
                        }
                        Button {
                            onManualEntry()
                        } label: {
                            Label("직접 입력", systemImage: "square.and.pencil")
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .accessibilityIdentifier("manual-entry")
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowSeparator(.hidden)
                } header: {
                    Text("어디서 마셨나요")
                }

                Section {
                    if entries.isEmpty {
                        Text("첫 잔을 기록해 보세요")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(entries) { entry in
                            EntryRow(entry: entry)
                                .accessibilityIdentifier("entry-row")
                        }
                        .onDelete { offsets in
                            onDelete(offsets.map { entries[$0] })
                        }
                    }
                } header: {
                    Text("오늘 기록")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("기록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                        .accessibilityIdentifier("record-close")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
