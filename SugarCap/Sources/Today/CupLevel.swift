import Foundation

/// 남은 비율을 컵 장면 단계로 바꾼다 (SPEC §9-10).
///
/// 2026-09-28 대표님: 단계마다 대기 영상을 뽑아야 해서 9단계를 5단계(0·30·50·80·100)로 줄였다.
/// 구간: 다 마심·넘김 → 0, 0 초과~50% 미만 → 30, 50~80% 미만 → 50, 80~100% 미만 → 80, 안 마심 → 100.
/// 2026-10-27 대표님: 가까운 쪽이 아니라 무조건 더 적은 쪽 사진(50 중 23 남으면 46%라 30). 단, 조금이라도 남으면 0은 아니다.
enum CupLevel {
    /// 세트마다 이 단계들의 이미지가 있어야 한다.
    static let steps = [0, 30, 50, 80, 100]

    /// 현재 세트. 컵 커스터마이징(§9-9)이 정해지면 설정에서 고르게 된다.
    static let defaultSetID = "iced-americano"

    static func assetName(setID: String = defaultSetID, step: Int) -> String {
        "cup-\(setID)-\(step)"
    }

    /// 같은 단계 사진을 원본에서 좌우로 넓게 자른 것. 오늘 화면 넘기기 이음매용(`design/assets/cups/make_wide.py`).
    static func wideName(setID: String = defaultSetID, step: Int) -> String {
        "cupwide-\(setID)-\(step)"
    }

    /// 같은 단계의 오린 컵(배경 없음). 추이 선반·영향 미리보기용(`design/assets/cups/make_cutouts.py`).
    static func cutoutName(setID: String = defaultSetID, step: Int) -> String {
        "cutout-\(setID)-\(step)"
    }

    /// 같은 단계의 유리 선(입구 앞·뒤 호, 벽). 오늘 화면 큰 숫자를 끊는 지우개(`design/assets/cups/make_rim_lines.py`).
    static func rimLineName(setID: String = defaultSetID, step: Int) -> String {
        "rimline-\(setID)-\(step)"
    }

    /// 같은 단계의 토핑(입구 위로 솟거나 입구를 채운 과일·잎·크림). 큰 숫자를 통째로 가린다
    /// (`design/assets/cups/make_hero_toppings.py`). 토핑이 숫자 자리에 안 닿는 단계는 에셋이 없다.
    static func toppingName(setID: String = defaultSetID, step: Int) -> String {
        "topping-\(setID)-\(step)"
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
        if ratio < 0.50 { return 30 }
        if ratio < 0.80 { return 50 }
        return 80
    }
}
