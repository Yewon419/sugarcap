import Foundation

/// 선물 판정(SPEC §4.9). 전부 순수 함수다. 행을 읽고 쓰는 건 `GiftStore`.
enum GiftMath {
    /// 선물 행 하나의 상태. `GiftEvent`에서 뽑아 넘긴다.
    struct Record: Equatable, Sendable {
        let kind: GiftKind
        let isOpened: Bool
        /// 기준 지킨 주 선물이면 그 주 월요일.
        var week: DayKey? = nil
    }

    /// 기준 지킨 주 판정에 쓰는 하루. 마감 순간 넘긴 양(`DaySettlement.…OverAtClose`).
    struct ClosedDay: Equatable, Sendable {
        let day: DayKey
        let sugarOver: Double?
        let caffeineOver: Double?

        func kept(_ side: CupSide) -> Bool {
            switch side {
            case .sugar: return sugarOver == 0
            case .caffeine: return caffeineOver == 0
            }
        }
    }

    /// 첫 보상(추이 열림)을 지금 줄지. 적립이 한 번이라도 생겼고 아직 준 적 없을 때 한 번만.
    static func grantsFirstReward(credited: Bool, gifts: [Record]) -> Bool {
        credited && !gifts.contains { $0.kind == .trendsUnlock }
    }

    /// 추이가 열려 있는지 = 첫 보상 선물을 열었는지.
    static func isTrendsUnlocked(gifts: [Record]) -> Bool {
        gifts.contains { $0.kind == .trendsUnlock && $0.isOpened }
    }

    /// 선물이 생기기 전부터 쓰던 기기(테스터)인지. 적립된 날(마감하고 확정된 행)이 하나라도 있으면
    /// 추이를 이미 쓰던 사람이라 잠그지 않고, 열린 첫 보상을 소급해 넣는다.
    /// 그 날이 든 달력 주의 월요일.
    static func weekStart(of day: DayKey, calendar: Calendar = .current) -> DayKey {
        day.shifted(by: -((day.weekday(calendar: calendar) + 5) % 7), calendar: calendar)
    }

    /// 기준 지킨 주 선물을 지금 줄지. `closed`가 일요일이고, 그 주 월~일 7일을 모두 마감했고,
    /// 마감 순간 `sides`(기록하는 면) 전부 하루 기준 안이었고, 그 주 선물을 아직 안 줬을 때.
    /// 주 중간에 시작했거나 마감하지 않은 날이 있으면 행이 없어 자연히 빠진다.
    static func grantsWeekKept(
        closed: DayKey, days: [ClosedDay], sides: [CupSide], gifts: [Record], calendar: Calendar = .current
    ) -> Bool {
        guard !sides.isEmpty, closed.weekday(calendar: calendar) == 1 else { return false }
        let monday = weekStart(of: closed, calendar: calendar)
        guard !gifts.contains(where: { $0.kind == .weekKept && $0.week == monday }) else { return false }
        return (0 ..< 7).allSatisfy { offset in
            let day = monday.shifted(by: offset, calendar: calendar)
            guard let row = days.first(where: { $0.day == day }) else { return false }
            return sides.allSatisfy(row.kept)
        }
    }

    /// 마음 카드에 "다른 것도 받고 싶으시다고요?"(페이월)를 붙일지. 무료이고 로슈·카인 합쳐 마음을 이미 한 번 받았을 때.
    static func offersPro(heartsBefore: Int, isPro: Bool) -> Bool {
        !isPro && heartsBefore >= 1
    }

    static func adoptsExistingProgress(records: [SettlementRecord], gifts: [Record]) -> Bool {
        !gifts.contains { $0.kind == .trendsUnlock } && records.contains { $0.isClosed && $0.isFinalized }
    }
}
