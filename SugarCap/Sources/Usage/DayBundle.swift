import Foundation

/// 음료 통계 하루 묶음(SPEC §9.10). 앱을 연 지난 날마다 한 번, 설치 ID 없이 보낸다.
/// 확정된 날은 바로, 확정 안 된 날은 이틀 지나서(어제는 어젯밤 화면에서 음료를 더 넣을 수 있다).
enum DayBundle {
    static let eventType = "day_bundle"
    /// 이 날까지는 다 처리했다(`DayKey.rawValue`).
    static let watermarkKey = "usageBundleWatermark"
    /// 워터마크 뒤인데 확정돼서 먼저 보낸 날.
    static let recentKey = "usageBundleRecent"

    struct Plan: Equatable {
        let days: [DayKey]
        let watermark: DayKey
        let recent: Set<DayKey>
    }

    struct Settings: Equatable {
        let menuCountry: MenuCountry
        let sides: [CupSide]
        let limits: DailyLimits
        let boundaryHour: Int
    }

    private struct Cup: Encodable {
        let servingID: String
        let quantity: Int
        let hour: Int
    }

    /// 처음 도는 날은 지난 기록을 소급하지 않고 워터마크만 놓는다.
    static func plan(records: [SettlementRecord], today: DayKey, watermark: DayKey?, recent: Set<DayKey>) -> Plan {
        let settled = today.shifted(by: -2)
        guard let watermark else {
            return Plan(days: [], watermark: settled, recent: [])
        }
        let days = records
            .filter { record in
                record.day > watermark && record.day < today && (record.isFinalized || record.day <= settled)
                    && !recent.contains(record.day)
            }
            .map(\.day)
            .sorted()
        let next = max(watermark, settled)
        return Plan(days: days, watermark: next, recent: recent.union(days).filter { $0 > next })
    }

    /// 보낼 값. 직접 입력 잔은 이름·양 없이 잔 수만 남긴다.
    /// "기준 안에서 끝냈는지"는 `MonthDigest`처럼 그날 기록 전부(직접 입력 포함)의 합을 지금 기준과 견준다.
    static func parameters(day: DayKey, entries: [Entry], settings: Settings, calendar: Calendar) throws -> [String: String] {
        let mine = entries.filter { $0.dayKey(boundaryHour: settings.boundaryHour, calendar: calendar) == day }
        let sugar = mine.reduce(0) { $0 + ($1.sugarG ?? 0) }
        let caffeine = mine.reduce(0) { $0 + ($1.caffeineMg ?? 0) }
        let cups = mine
            .sorted { $0.loggedAt < $1.loggedAt }
            .compactMap { entry in
                entry.servingID.map {
                    Cup(servingID: $0, quantity: entry.quantity, hour: calendar.component(.hour, from: entry.loggedAt))
                }
            }
        let manualCups = mine.filter { $0.servingID == nil }.reduce(0) { $0 + $1.quantity }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let cupsJSON = String(decoding: try encoder.encode(cups), as: UTF8.self)

        return [
            "weekday": String(day.weekday(calendar: calendar)),
            "menuCountry": settings.menuCountry.rawValue,
            "sides": settings.sides.map(\.rawValue).joined(separator: ","),
            "sugarLimitBand": String(band(settings.limits.sugarG, width: 25)),
            "caffeineLimitBand": String(band(settings.limits.caffeineMg, width: 100)),
            "keptSugar": String(sugar <= settings.limits.sugarG),
            "keptCaffeine": String(caffeine <= settings.limits.caffeineMg),
            "manualCups": String(manualCups),
            "cups": cupsJSON,
        ]
    }

    /// 구간 아래 끝. 당 25 g, 카페인 100 mg 단위(대표님 2026-11-04).
    static func band(_ value: Double, width: Int) -> Int {
        Int((value / Double(width)).rounded(.down)) * width
    }
}

extension UsageReporter {
    /// 보낼 날의 묶음을 대기열에 넣고 워터마크를 옮긴다. 거절했어도 워터마크는 옮긴다(기록은 `record`가 버린다).
    func recordDayBundles(
        records: [SettlementRecord], entries: [Entry], today: DayKey, settings: DayBundle.Settings, calendar: Calendar
    ) throws {
        let watermark = defaults.string(forKey: DayBundle.watermarkKey).flatMap(DayKey.init(rawValue:))
        let recent = Set((defaults.stringArray(forKey: DayBundle.recentKey) ?? []).compactMap(DayKey.init(rawValue:)))
        let plan = DayBundle.plan(records: records, today: today, watermark: watermark, recent: recent)
        for day in plan.days {
            try record(
                type: DayBundle.eventType, scope: .anonymous,
                parameters: try DayBundle.parameters(day: day, entries: entries, settings: settings, calendar: calendar))
        }
        defaults.set(plan.watermark.rawValue, forKey: DayBundle.watermarkKey)
        defaults.set(plan.recent.map(\.rawValue).sorted(), forKey: DayBundle.recentKey)
    }
}
