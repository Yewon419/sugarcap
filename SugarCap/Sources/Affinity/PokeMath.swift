import Foundation

/// 호감도 화면에서 캐릭터 건드리기(§4.8, 2026-10-03 말걸기 대체). 점수는 주지 않는다. 순수 함수만 둔다.
/// 한 번 건드리면 평소 반응, 짧은 간격으로 이어 누르면 연타로 세어 특이한 반응이 한 번 나온다.
enum PokeMath {
    /// 이 간격 안에 다시 누르면 연타로 이어 센다.
    static let comboWindow: TimeInterval = 0.6
    /// 연타가 이 횟수에 닿으면 특이한 반응.
    static let comboCount = 5

    /// 이번 누름까지 이어진 연타 횟수. 간격이 벌어졌거나 직전에 특이한 반응이 나왔으면 1부터 다시.
    static func combo(previous: Int, lastTap: Date?, now: Date) -> Int {
        guard let lastTap, now.timeIntervalSince(lastTap) <= comboWindow, previous < comboCount else { return 1 }
        return previous + 1
    }

    /// 로슈는 사이 단계로 정해진다(낯가림은 부끄럼이 아니라 경계, 대표님). 카인은 엉뚱해서 누를 때마다 둘 중 하나.
    /// 카인 반응에 한 바퀴 회전은 넣지 않는다(대표님 2026-10-06 "360도 회전 절대 넣지 마").
    /// - Parameter tap: 화면을 연 뒤 몇 번째 누름인지. 카인의 반응을 고르는 데만 쓴다.
    static func reaction(side: CupSide, level: Int, combo: Int, tap: Int) -> PokeReaction {
        switch side {
        case .sugar:
            if combo >= comboCount { return .squish }
            return level <= 3 ? .wary : level <= 6 ? .happy : .aegyo
        case .caffeine:
            if combo >= comboCount { return .bounce }
            let kain: [PokeReaction] = [.tilt, .hop]
            return kain[Int(IdleMotion.unitHash(UInt64(tap), seed: 11) * Double(kain.count))]
        }
    }
}

/// 반응 몸짓. 대표님 애니메이션이 오기 전까지 transform으로 흉내 낸다(`ReactionMotion`).
enum PokeReaction: String, CaseIterable, Sendable {
    case wary, happy, aegyo, squish
    case tilt, hop, bounce
}
