import Foundation

/// 남은 비율을 컵 장면 단계로 바꾼다 (SPEC §9-10).
///
/// 2026-09-28 대표님: 단계마다 대기 영상을 뽑아야 해서 9단계를 5단계(0·30·50·80·100)로 줄였다.
/// 구간: 다 마심·넘김 → 0, 0 초과~40% 미만 → 30, 40~65% 미만 → 50, 65~100% 미만 → 80, 안 마심 → 100.
enum CupLevel {
    /// 세트마다 이 단계들의 이미지가 있어야 한다.
    static let steps = [0, 30, 50, 80, 100]

    /// 현재 세트. 컵 커스터마이징(§9-9)이 정해지면 설정에서 고르게 된다.
    static let defaultSetID = "iced-americano"

    static func assetName(setID: String = defaultSetID, step: Int) -> String {
        "cup-\(setID)-\(step)"
    }

    /// 같은 단계의 오린 컵(배경 없음). 추이 선반·영향 미리보기용(`design/assets/cups/make_cutouts.py`).
    static func cutoutName(setID: String = defaultSetID, step: Int) -> String {
        "cutout-\(setID)-\(step)"
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

        // 남은 양이 0보다 크면 최소 첫 단계(30)까지는 채워 보인다.
        if ratio < 0.40 { return 30 }
        if ratio < 0.65 { return 50 }
        return 80
    }
}
