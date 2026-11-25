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

    /// 기준 지킨 주에 필요한 지킨 날 수(7일 중, 대표님 2026-11-19).
    static let requiredKeptDays = 5

    /// 주 진행 칸 하나. 마감 안 한 날은 못 지킨 날로 센다(감소 목표와 다르다).
    enum WeekSlot: Equatable, Sendable {
        case kept, missed, upcoming
    }

    /// `closed`가 든 달력 주 월~일 7칸. `closed` 뒤의 날은 `upcoming`.
    /// 마감 순간 `sides`(기록하는 면) 전부 하루 기준 안이었던 날만 `kept`.
    static func weekSlots(
        closed: DayKey, days: [ClosedDay], sides: [CupSide], calendar: Calendar = .current
    ) -> [WeekSlot] {
        let monday = weekStart(of: closed, calendar: calendar)
        return (0 ..< 7).map { offset in
            let day = monday.shifted(by: offset, calendar: calendar)
            if day > closed { return .upcoming }
            guard !sides.isEmpty, let row = days.first(where: { $0.day == day }) else { return .missed }
            return sides.allSatisfy(row.kept) ? .kept : .missed
        }
    }

    /// 기준 지킨 주 선물을 지금 줄지. `closed`가 든 주(월~일)에 지킨 날이 `requiredKeptDays`에 닿았고,
    /// 그 주 선물을 아직 안 줬을 때. 다섯 번째 지킨 날을 마감한 그 자리에서 준다(일요일을 기다리지 않는다).
    static func grantsWeekKept(
        closed: DayKey, days: [ClosedDay], sides: [CupSide], gifts: [Record], calendar: Calendar = .current
    ) -> Bool {
        guard !sides.isEmpty else { return false }
        let monday = weekStart(of: closed, calendar: calendar)
        guard !gifts.contains(where: { $0.kind == .weekKept && $0.week == monday }) else { return false }
        let sunday = monday.shifted(by: 6, calendar: calendar)
        let slots = weekSlots(closed: sunday, days: days, sides: sides, calendar: calendar)
        return slots.filter { $0 == .kept }.count >= requiredKeptDays
    }

    /// 튜토리얼 상자(병뚜껑 1개) 수(§4.10 초반 보상 고정).
    static let starterCaps = 2

    /// 마감 직후 튜토리얼 상자를 줄지. 첫 마감(추이 열림) 다음부터 마감마다 하나씩, 두 개까지.
    /// `closedDays`는 방금 마감한 날을 포함한 마감한 날 수. 업데이트 전에 많이 마감한 기기도 마감마다 하나씩 받는다.
    static func grantsStarterCap(closedDays: Int, gifts: [Record]) -> Bool {
        let given = gifts.filter { $0.kind == .starterCap }.count
        return given < starterCaps && given < closedDays - 1
    }

    /// 상자에서 나오는 것의 종류.
    enum Outcome: Equatable, Sendable {
        case heart, item, cap
    }

    /// 상자 내용 뽑기(2026-10-11 대표님). `roll`은 0..<1 난수.
    /// 무료 = 마음 85 · 병뚜껑 15(물건 없음), Pro = 마음 40 · 물건 10 · 병뚜껑 50.
    /// 물건을 다 모았으면(`itemsLeft` 거짓) 물건 몫은 병뚜껑으로 간다.
    static func outcome(roll: Double, isPro: Bool, itemsLeft: Bool) -> Outcome {
        if !isPro { return roll < 0.85 ? .heart : .cap }
        if roll < 0.40 { return .heart }
        if roll < 0.50 { return itemsLeft ? .item : .cap }
        return .cap
    }

    /// 마음 카드에 "다른 것도 받고 싶으시다고요?"(페이월)를 붙일지. 무료이고 로슈·카인 합쳐 마음을 이미 한 번 받았을 때.
    static func offersPro(heartsBefore: Int, isPro: Bool) -> Bool {
        !isPro && heartsBefore >= 1
    }

    static func adoptsExistingProgress(records: [SettlementRecord], gifts: [Record]) -> Bool {
        !gifts.contains { $0.kind == .trendsUnlock } && records.contains { $0.isClosed && $0.isFinalized }
    }
}
