import Foundation

/// 호감도 적립·단계 계산(SPEC §9.5). 순수 함수만 둔다.
enum AffinityMath {
    static let maxLevel = 10
    /// 무료로 표정이 풀리는 마지막 단계(§9.5). 잠금은 Phase 3에서 StoreKit과 함께 건다.
    static let freeLevelCap = 3

    /// 먹이기 1회 적립 = `1 + round(남은 양 / 하루 기준 × 9)`, 1~10점.
    /// 기준을 넘긴 날(남은 0)도 먹이면 1점이다.
    static func points(left: Double, limit: Double) -> Int {
        guard limit > 0 else { return 1 }
        let ratio = min(1, max(0, left / limit))
        return 1 + Int((ratio * 9).rounded())
    }

    /// Lv n에 필요한 누적 points = 15·n·(n−1). Lv1 0, Lv2 30, Lv3 90 … Lv10 1350.
    static func threshold(level: Int) -> Int {
        15 * level * (level - 1)
    }

    static func level(points: Int) -> Int {
        var level = 1
        while level < maxLevel, points >= threshold(level: level + 1) {
            level += 1
        }
        return level
    }
}

/// "오늘 마감"을 열 수 있는지(§4.7). 마감 가능 시각부터 하루 경계 전까지다.
/// 설정 선택지가 마감 18~23시, 경계 0~6시라 두 구간은 겹치지 않는다(`HourChoices`).
enum CloseWindow {
    static func isOpen(
        at now: Date, closeFromHour: Int, boundaryHour: Int, calendar: Calendar = .current
    ) -> Bool {
        let hour = calendar.component(.hour, from: now)
        return hour >= closeFromHour || hour < boundaryHour
    }
}

/// 정산 행 하나의 상태. `DaySettlement`에서 뽑아 계획에 넘긴다.
struct SettlementRecord: Equatable, Sendable {
    let day: DayKey
    let isClosed: Bool
    let isFinalized: Bool
}

/// 오늘 첫 실행에 해야 할 정산(§4.7).
struct SettlementPlan: Equatable, Sendable {
    enum Prompt: Equatable, Sendable {
        /// 어제 앱은 열었지만 마감하지 않았다 → "어제 남은 음료 먹이기".
        case feedYesterday(DayKey)
        /// 어제 앱을 열지 않았다 → "음료를 안 마셨나요?"
        case askNoDrink(DayKey)
    }

    /// 마감했지만 아직 확정 안 된 지난 날. 하루 경계가 지났으니 최종 값으로 적립한다.
    let finalize: [DayKey]
    let prompt: Prompt?
}

enum SettlementPlanner {
    /// - Parameter records: 앱을 연 날마다 1행. 오늘 행도 포함해서 넘긴다.
    ///   가장 이른 행이 설치(첫 실행) 날이다. 그 전 날은 묻지 않는다.
    static func plan(today: DayKey, records: [SettlementRecord]) -> SettlementPlan {
        let finalize = records
            .filter { $0.day < today && $0.isClosed && !$0.isFinalized }
            .map(\.day)
            .sorted()

        let yesterday = today.shifted(by: -1)
        guard let firstDay = records.map(\.day).min(), firstDay <= yesterday else {
            return SettlementPlan(finalize: finalize, prompt: nil)
        }

        // 바로 어제만 묻는다. 그 이전 날은 제안 없이 넘어간다.
        let prompt: SettlementPlan.Prompt?
        if let record = records.first(where: { $0.day == yesterday }) {
            prompt = (record.isClosed || record.isFinalized) ? nil : .feedYesterday(yesterday)
        } else {
            prompt = .askNoDrink(yesterday)
        }
        return SettlementPlan(finalize: finalize, prompt: prompt)
    }
}
