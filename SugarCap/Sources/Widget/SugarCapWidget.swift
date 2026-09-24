import SwiftUI
import WidgetKit

/// Small 위젯(SPEC §4.6). 남은 양 2개 + 캐릭터 정지 포즈. v1은 Small만 낸다.
/// 위젯은 Pro 기능이다(§6) — 무료 사용자에게는 잠금 안내를 보여 준다.
struct SugarCapWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SugarCapRemaining", provider: SugarCapProvider()) { entry in
            SugarCapWidgetView(snapshot: entry.snapshot)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("남은 당·카페인")
        .description("오늘 남은 양을 보여 줍니다.")
        .supportedFamilies([.systemSmall])
    }
}

struct SugarCapEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct SugarCapProvider: TimelineProvider {
    func placeholder(in context: Context) -> SugarCapEntry {
        SugarCapEntry(date: Date(), snapshot: .placeholder)
    }

    @MainActor
    func getSnapshot(in context: Context, completion: @escaping (SugarCapEntry) -> Void) {
        completion(SugarCapEntry(date: Date(), snapshot: WidgetSnapshotLoader.load()))
    }

    @MainActor
    func getTimeline(in context: Context, completion: @escaping (Timeline<SugarCapEntry>) -> Void) {
        let now = Date()
        let entry = SugarCapEntry(date: now, snapshot: WidgetSnapshotLoader.load(now: now))
        // 기록은 앱에서만 늘어난다. 앱이 `WidgetCenter`로 갱신을 밀고, 그 사이에는 매시 한 번 본다.
        let next = WidgetSnapshotLoader.nextRefresh(after: now, boundaryHour: 4)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct SugarCapWidgetView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        if snapshot.isPro {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(CupSide.allCases) { side in
                    row(side)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "lock")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("슈가캡 Pro에서 열려요")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func row(_ side: CupSide) -> some View {
        HStack(spacing: 8) {
            Image(side.characterAsset)
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(Amount.number(snapshot.left(side))) \(side.unit)")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("남은 \(side.label)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

@main
struct SugarCapWidgetBundle: WidgetBundle {
    var body: some Widget {
        SugarCapWidget()
    }
}
