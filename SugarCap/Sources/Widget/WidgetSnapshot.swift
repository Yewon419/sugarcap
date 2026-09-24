import Foundation
import SwiftData

/// 위젯 한 칸이 그리는 값(SPEC §4.6). 계산은 앱과 같은 `DayMath`를 쓴다.
struct WidgetSnapshot: Equatable, Sendable {
    let leftSugarG: Double
    let leftCaffeineMg: Double
    let limits: DailyLimits
    let isPro: Bool

    func left(_ side: CupSide) -> Double {
        switch side {
        case .sugar: return leftSugarG
        case .caffeine: return leftCaffeineMg
        }
    }

    static let placeholder = WidgetSnapshot(
        leftSugarG: 32, leftCaffeineMg: 240, limits: .default, isPro: true
    )
}

enum WidgetSnapshotLoader {
    /// 오늘(하루 경계 기준) 남은 양을 읽는다. 저장소를 못 열면 기본 기준의 가득 찬 컵을 돌려준다.
    @MainActor
    static func load(now: Date = Date(), isPro: Bool = SharedDefaults.isPro) -> WidgetSnapshot {
        guard let container = try? SharedStore.makeContainer() else {
            return WidgetSnapshot(
                leftSugarG: DailyLimits.default.sugarG,
                leftCaffeineMg: DailyLimits.default.caffeineMg,
                limits: .default,
                isPro: isPro
            )
        }
        let context = ModelContext(container)
        let settings = (try? context.fetch(FetchDescriptor<AppSettings>()))?.first
        let limits = settings?.limits ?? .default
        let boundaryHour = settings?.dayBoundaryHour ?? 4
        let today = DayKey(at: now, boundaryHour: boundaryHour)

        let entries = (try? context.fetch(FetchDescriptor<Entry>())) ?? []
        let totals = DayMath.totals(
            entries.filter { $0.dayKey(boundaryHour: boundaryHour) == today }.map(\.consumption),
            limits: limits
        )
        return WidgetSnapshot(
            leftSugarG: totals.leftSugarG,
            leftCaffeineMg: totals.leftCaffeineMg,
            limits: limits,
            isPro: isPro
        )
    }

    /// 다음 갱신 시각. 하루가 바뀔 때와 매시 정각 중 이른 쪽이다.
    static func nextRefresh(after now: Date, boundaryHour: Int, calendar: Calendar = .current) -> Date {
        let nextHour = calendar.date(byAdding: .hour, value: 1, to: now) ?? now.addingTimeInterval(3600)
        let hourStart = calendar.date(
            bySettingHour: calendar.component(.hour, from: nextHour), minute: 0, second: 0, of: nextHour
        ) ?? nextHour
        return hourStart
    }
}
