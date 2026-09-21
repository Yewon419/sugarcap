import Foundation

/// 남은 비율을 컵 장면 단계로 내린다 (SPEC §9-10, 2026-09-20 확정).
///
/// 단계는 9장뿐이고 간격이 고르지 않다(60·90은 수위가 인접 단계와 구분되지 않아 제외).
/// 그래서 "남은 비율 이하 중 가장 높은 단계"로 내림한다 — 95% → 80, 65% → 50.
enum CupLevel {
    /// 세트마다 이 단계들의 이미지가 있어야 한다.
    static let steps = [0, 10, 20, 30, 40, 50, 70, 80, 100]

    /// 현재 세트. 컵 커스터마이징(§9-9)이 정해지면 설정에서 고르게 된다.
    static let defaultSetID = "iced-americano"

    static func assetName(setID: String = defaultSetID, step: Int) -> String {
        "cup-\(setID)-\(step)"
    }

    /// - Parameter remaining: 남은 양. `limit`과 같은 단위여야 한다.
    static func step(remaining: Double, limit: Double) -> Int {
        guard limit > 0 else { return 0 }
        return step(remainingRatio: remaining / limit)
    }

    static func step(remainingRatio ratio: Double) -> Int {
        // 0% 장면은 정확히 0일 때만 쓴다.
        guard ratio > 0 else { return 0 }
        // 100% 장면은 한 잔도 줄지 않았을 때만.
        guard ratio < 1 else { return 100 }

        let percent = ratio * 100
        // 남은 양이 0보다 크면 최소 첫 단계(10)까지는 채워 보인다.
        return steps.filter { $0 > 0 && Double($0) <= percent }.max() ?? 10
    }
}
