import Foundation

/// 선물 판정(SPEC §4.9). 전부 순수 함수다. 행을 읽고 쓰는 건 `GiftStore`.
enum GiftMath {
    /// 선물 행 하나의 상태. `GiftEvent`에서 뽑아 넘긴다.
    struct Record: Equatable, Sendable {
        let kind: GiftKind
        let isOpened: Bool
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
    static func adoptsExistingProgress(records: [SettlementRecord], gifts: [Record]) -> Bool {
        !gifts.contains { $0.kind == .trendsUnlock } && records.contains { $0.isClosed && $0.isFinalized }
    }
}
