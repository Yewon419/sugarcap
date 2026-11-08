import AppIntents
import SwiftUI
import WidgetKit

/// 홈 화면 위젯(SPEC §4.6). Small = 고른 면 잔 하나, Medium = 켠 면 잔 전부. 그림은 `WidgetUI`(시안 v7).
/// 위젯은 Pro 기능이다(§6) — 무료 사용자에게는 잠금 안내를 보여 준다.
struct SugarCapWidget: Widget {
    var body: some WidgetConfiguration {
        // kind는 v1 Small 그대로 둔다. 바꾸면 이미 놓은 위젯이 사라진다.
        AppIntentConfiguration(kind: "SugarCapRemaining", intent: CupSideIntent.self, provider: SmallCupProvider()) { entry in
            SmallCupWidgetView(entry: entry)
        }
        .configurationDisplayName("남은 당·카페인")
        .description("오늘 남은 양을 보여 줍니다.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

struct SugarCapMediumWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SugarCapCups", provider: SugarCapProvider()) { entry in
            MediumCupWidgetView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("남은 당·카페인")
        .description("오늘 남은 양을 보여 줍니다.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

/// Small 위젯 편집의 "보일 컵".
enum CupSideOption: String, AppEnum {
    case sugar
    case caffeine

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "보일 컵" }

    static var caseDisplayRepresentations: [CupSideOption: DisplayRepresentation] {
        [.sugar: "당", .caffeine: "카페인"]
    }

    var side: CupSide {
        switch self {
        case .sugar: .sugar
        case .caffeine: .caffeine
        }
    }
}

struct CupSideIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "남은 당·카페인" }

    @Parameter(title: "보일 컵", default: .sugar)
    var side: CupSideOption
}

struct SugarCapEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct SmallCupEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let side: CupSide
}

enum WidgetTimeline {
    /// 기록은 앱에서만 늘어난다. 앱이 `WidgetCenter`로 갱신을 밀고, 그 사이에는 매시 한 번 본다.
    static func next(after now: Date) -> Date {
        WidgetSnapshotLoader.nextRefresh(after: now, boundaryHour: 4)
    }
}

struct SmallCupProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SmallCupEntry {
        SmallCupEntry(date: Date(), snapshot: .placeholder, side: .sugar)
    }

    func snapshot(for configuration: CupSideIntent, in context: Context) async -> SmallCupEntry {
        await entry(side: configuration.side.side, now: Date())
    }

    func timeline(for configuration: CupSideIntent, in context: Context) async -> Timeline<SmallCupEntry> {
        let now = Date()
        let current = await entry(side: configuration.side.side, now: now)
        return Timeline(entries: [current], policy: .after(WidgetTimeline.next(after: now)))
    }

    /// 고른 면을 껐으면 켠 면으로 그린다.
    @MainActor
    private func entry(side: CupSide, now: Date) -> SmallCupEntry {
        let snapshot = WidgetSnapshotLoader.load(now: AppClock.now)
        return SmallCupEntry(date: now, snapshot: snapshot, side: CupSide.visible(side, in: snapshot.tracked))
    }
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
        let entry = SugarCapEntry(date: now, snapshot: WidgetSnapshotLoader.load(now: AppClock.now))
        completion(Timeline(entries: [entry], policy: .after(WidgetTimeline.next(after: now))))
    }
}

extension WidgetSnapshot {
    func cup(_ side: CupSide) -> WidgetCupModel {
        WidgetCupModel(side: side, setID: cupSet(side), remaining: left(side), limit: side.limit(limits))
    }
}

/// 위젯 바탕(사진 벽 톤). 잠금 안내와 사진 가장자리 뒤에 깔린다.
private let widgetWall = Color(red: 0xF3 / 255, green: 0xF3 / 255, blue: 0xF3 / 255)

struct SmallCupWidgetView: View {
    let entry: SmallCupEntry

    var body: some View {
        Group {
            if entry.snapshot.isPro {
                WidgetSmallFace(cup: entry.snapshot.cup(entry.side))
            } else {
                WidgetLockedView()
            }
        }
        .containerBackground(widgetWall, for: .widget)
    }
}

struct MediumCupWidgetView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        Group {
            if snapshot.isPro {
                WidgetMediumFace(cups: snapshot.tracked.map(snapshot.cup))
            } else {
                WidgetLockedView()
            }
        }
        .containerBackground(widgetWall, for: .widget)
    }
}

struct WidgetLockedView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("슈가캡 Pro에서 열려요")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@main
struct SugarCapWidgetBundle: WidgetBundle {
    var body: some Widget {
        SugarCapWidget()
        SugarCapMediumWidget()
    }
}
