import Foundation

/// 2주 스탬프판(대표님 2026-11-05, 시안 `design/proto/stamp-card.html`). 전부 순수 함수다. 행은 `GiftStore.grantStamp`.
/// 마감한 날마다 한 칸, 빠진 날이 있어도 이어서 센다. 기존 선물과 따로 더 준다.
/// 14칸이 다 차면 다음 판이 이어진다(대표님 2026-11-27). 칸 번호는 판을 넘어 15, 16…으로 이어 센다.
enum StampMath {
    static let cells = 14
    /// 잔 세트를 다 가졌을 때 14칸 대신 주는 병뚜껑 수(대표님 2026-11-05).
    static let finalCaps = 3
    /// 얼리버드 선물 칸(`EarlyBird`). 첫 판에서만 늘 마음이고, 대상이면 유리 공예 잔 두 개를 더 받는다.
    static let earlyBirdCell = 7

    enum Prize: Equatable, Sendable {
        case heart, cap
    }

    /// 판 안 1~13칸 내용. 병뚜껑 1~2개, 나머지는 마음. 첫 판은 7칸을 뺀 곳 중 무작위, 둘째 판부터는 7칸도 일반 칸.
    /// 기기마다 한 번 정한 `seed`와 판 번호로 정해져 다시 계산해도 같다. 첫 판은 판 반복 전과 같은 배치다.
    static func layout(seed: UInt64, board: Int) -> [Prize] {
        guard board > 1 else {
            var generator = SeededGenerator(state: seed)
            let caps = generator.next() % 2 == 0 ? 1 : 2
            var prizes = (0 ..< cells - 2).map { $0 < caps ? Prize.cap : Prize.heart }
            prizes.shuffle(using: &generator)
            prizes.insert(.heart, at: earlyBirdCell - 1)
            return prizes
        }
        var generator = SeededGenerator(state: seed ^ (UInt64(board) &* 0xD1B5_4A32_D192_ED03))
        let caps = generator.next() % 2 == 0 ? 1 : 2
        var prizes = (0 ..< cells - 1).map { $0 < caps ? Prize.cap : Prize.heart }
        prizes.shuffle(using: &generator)
        return prizes
    }

    /// 찍은 칸 수 = 스탬프 행의 가장 큰 칸 번호(판을 넘어 누적).
    static func stamped(cellNumbers: [Int]) -> Int {
        cellNumbers.max() ?? 0
    }

    /// 칸 번호가 속한 판(1부터).
    static func board(of cell: Int) -> Int {
        (cell - 1) / cells + 1
    }

    /// 칸 번호의 판 안 자리(1~14).
    static func cellInBoard(_ cell: Int) -> Int {
        (cell - 1) % cells + 1
    }

    /// 14칸 잔 세트 후보: 기록하는 면의 상품 중 아직 안 가진 것(목록 순서).
    static func finalCandidates(catalog: [TradeItem], sides: [CupSide], owned: Set<String>) -> [TradeItem] {
        catalog.filter { sides.contains($0.side) && !owned.contains($0.id) }
    }
}

/// 같은 seed면 같은 수열(SplitMix64). 스탬프 배치를 저장 없이 다시 만든다.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// 기기 단위 스탬프 값(UserDefaults). 배치 seed와 칸 공개 연출을 본 칸 수.
enum StampProgress {
    static let seedKey = "stampSeed"
    /// 찍는 연출까지 본 칸 수. 이보다 큰 칸은 다음에 스탬프판이 열릴 때 찍힌다.
    static let seenKey = "stampSeen"

    static func seed(_ defaults: UserDefaults = .standard) -> UInt64 {
        if defaults.object(forKey: seedKey) == nil {
            defaults.set(Int.random(in: Int.min ... Int.max), forKey: seedKey)
        }
        return UInt64(bitPattern: Int64(defaults.integer(forKey: seedKey)))
    }
}
