import Foundation

/// 말걸기(§4.8, 2026-09-26 HTML 프로토타입 확정). 순수 함수만 둔다.
/// 캐릭터는 말을 못 하고 몸짓으로만 반응한다. 반응 애니메이션은 캐릭터마다 3개(대표님 제작).
enum TalkMath {
    /// 말걸기 1회 적립(SPEC §2.2 예외). 먹이기(하루 1~10점)를 앞지르지 않는 크기.
    static let points = 2
    static let choicesPerDay = 3

    struct Choice: Equatable, Sendable {
        let id: String
        let text: String
    }

    static let choices: [Choice] = [
        Choice(id: "greet", text: "안녕, 좋은 밤"),
        Choice(id: "praise", text: "오늘 잘 참았어"),
        Choice(id: "pat", text: "머리 쓰다듬기"),
        Choice(id: "walk", text: "같이 산책 갈래?"),
        Choice(id: "ask", text: "오늘 뭐 했어?"),
        Choice(id: "five", text: "하이파이브"),
    ]

    /// 오늘의 선택지 3개. 날짜와 면으로 정해져서 그날 다시 열어도 같다.
    static func todaysChoices(day: DayKey, side: CupSide) -> [Choice] {
        var h = hash(day.rawValue + side.rawValue, seed: 7)
        var pool = choices
        var picked: [Choice] = []
        while picked.count < choicesPerDay {
            h = lcg(h)
            picked.append(pool.remove(at: Int(h % UInt32(pool.count))))
        }
        return picked
    }

    /// 로슈는 사이 단계로 정해진다(낯가림은 부끄럼이 아니라 경계, 대표님). 카인은 엉뚱해서 날짜·선택으로 셋 중 하나.
    static func reaction(side: CupSide, choiceID: String, level: Int, day: DayKey) -> TalkReaction {
        switch side {
        case .sugar:
            return level <= 3 ? .wary : level <= 6 ? .happy : .aegyo
        case .caffeine:
            let kain: [TalkReaction] = [.tilt, .spin, .hop]
            return kain[Int(hash(day.rawValue + choiceID, seed: 11) % 3)]
        }
    }

    // 프로토타입(JavaScript)과 같은 결과를 내려고 그 산술을 그대로 따른다.
    // `(h * 31 + c) >>> 0`: 곱이 2^53 아래라 정확하다. UTF-16 코드 단위 기준(문자열은 전부 ASCII).
    static func hash(_ text: String, seed: UInt32) -> UInt32 {
        text.utf16.reduce(seed) { h, c in UInt32(truncatingIfNeeded: UInt64(h) * 31 + UInt64(c)) }
    }

    // `(h * 1103515245 + 12345) >>> 0`: JavaScript에서는 곱이 2^53을 넘어 배정밀도로 반올림된 뒤 32비트로 잘린다.
    // 같은 반올림을 거쳐야 같은 선택지가 나온다.
    static func lcg(_ h: UInt32) -> UInt32 {
        let v = Double(h) * 1_103_515_245 + 12_345
        return UInt32(truncatingIfNeeded: Int64(v))
    }
}

/// 반응 몸짓. 값은 애니메이션 파일 이름이 된다.
enum TalkReaction: String, CaseIterable, Sendable {
    case wary, happy, aegyo
    case tilt, spin, hop

    /// 감정 이름이 아니라 보이는 모습으로 적는다(대표님: "경계한다" 대신 "멀찍이서 지켜보고 있어요").
    var line: String {
        switch self {
        case .wary: return "멀찍이서 지켜보고 있어요"
        case .happy: return "좋아해요"
        case .aegyo: return "애교를 부려요"
        case .tilt: return "고개를 갸웃해요"
        case .spin: return "갑자기 한 바퀴 돌아요"
        case .hop: return "폴짝 뛰어요"
        }
    }
}
