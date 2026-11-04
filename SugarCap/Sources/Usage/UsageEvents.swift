import Foundation
import OSLog

/// 퍼널 이벤트 이름·값(SPEC §9.10 1~8). 화면은 `UsageReporter.shared?.log(...)` 한 줄만 부른다.
struct UsageEventDraft: Equatable, Sendable {
    let type: String
    let parameters: [String: String]
}

/// 기록 시트에서 음료를 고른 길.
enum EntryPath: String, Sendable {
    case search
    case brandMenu
    case favorite
    case recent
    case manual
}

/// 기록 시트를 연 화면. 정산 화면에서 넣은 잔은 깜빡한 음료다.
enum EntryPlace: String, Sendable {
    case today
    case feeding
    case dayLog
}

/// 하루를 닫은 방식. `drank`는 어젯밤 화면의 "마셨어요"(적립 없이 닫음).
enum DayCloseKind: String, Sendable {
    case closeToday
    case pastDay
    case drank
}

enum UsageEvents {
    static func entryLogged(path: EntryPath, place: EntryPlace, brandID: String?) -> UsageEventDraft {
        var parameters = ["path": path.rawValue, "place": place.rawValue]
        if let brandID { parameters["brandID"] = brandID }
        return UsageEventDraft(type: "entry_logged", parameters: parameters)
    }

    static func firstEntryLogged(daysSinceInstall: Int) -> UsageEventDraft {
        UsageEventDraft(type: "first_entry_logged", parameters: ["daysSinceInstall": String(daysSinceInstall)])
    }

    static func onboardingCompleted(reelSkipped: Bool, limits: DailyLimits) -> UsageEventDraft {
        UsageEventDraft(
            type: "onboarding_completed",
            parameters: [
                "reelSkipped": String(reelSkipped),
                "sugarLimitBand": String(DayBundle.band(limits.sugarG, width: 25)),
                "caffeineLimitBand": String(DayBundle.band(limits.caffeineMg, width: 100)),
            ])
    }

    static func dayClosed(_ kind: DayCloseKind) -> UsageEventDraft {
        UsageEventDraft(type: "day_closed", parameters: ["kind": kind.rawValue])
    }

    static func tradeOffer(itemID: String, accepted: Bool) -> UsageEventDraft {
        UsageEventDraft(type: "trade_offer", parameters: ["itemID": itemID, "accepted": String(accepted)])
    }
}

extension UsageReporter {
    /// 가장 이른 정산 행(앱을 처음 연 날)과 그때의 하루 경계 시각. "첫 기록이 설치 후 며칠째"에 쓴다.
    static let installDayKey = "usageInstallDay"
    static let installBoundaryKey = "usageInstallBoundaryHour"
    static let firstEntryKey = "usageFirstEntryLogged"

    private static let eventLogger = Logger(subsystem: "com.sugarcap.app", category: "usage")

    /// 퍼널 이벤트 하나. 실패해도 화면 동작은 그대로 두고 로그만 남긴다.
    func log(_ draft: UsageEventDraft) {
        do {
            try record(type: draft.type, scope: .install, parameters: draft.parameters)
        } catch {
            Self.eventLogger.error("\(draft.type, privacy: .public) 기록 실패: \(String(describing: error), privacy: .public)")
        }
    }

    /// 음료 기록 한 건. 이 설치에서 처음이면 `first_entry_logged`도 남긴다.
    func logEntry(path: EntryPath, place: EntryPlace, brandID: String?, now: Date) {
        log(UsageEvents.entryLogged(path: path, place: place, brandID: brandID))
        guard !defaults.bool(forKey: Self.firstEntryKey) else { return }
        defaults.set(true, forKey: Self.firstEntryKey)
        let installDay = defaults.string(forKey: Self.installDayKey).flatMap(DayKey.init(rawValue:))
        let boundary = defaults.object(forKey: Self.installBoundaryKey) as? Int ?? 4
        let today = DayKey(at: now, boundaryHour: boundary)
        log(UsageEvents.firstEntryLogged(daysSinceInstall: installDay.map { max(0, $0.days(until: today)) } ?? 0))
    }

    func noteInstallDay(records: [SettlementRecord], boundaryHour: Int) {
        guard let earliest = records.map(\.day).min() else { return }
        defaults.set(earliest.rawValue, forKey: Self.installDayKey)
        defaults.set(boundaryHour, forKey: Self.installBoundaryKey)
    }

    /// 이 기능 전부터 쓰던 설치는 이미 기록이 있으니 첫 기록을 보내지 않는다. 새 설치의 첫 잔은 `logEntry`가 저장 전에 표시한다.
    func noteExistingEntries(count: Int) {
        guard count > 0 else { return }
        defaults.set(true, forKey: Self.firstEntryKey)
    }
}
