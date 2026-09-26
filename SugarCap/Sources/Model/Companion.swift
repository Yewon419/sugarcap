import Foundation
import SwiftData

/// 즐겨찾기 음료(기록 시트 맨 위, 2026-09-26 HTML 프로토타입 확정). 카탈로그 serving을 가리킨다.
/// 별표를 다시 누르면 행을 지운다. 최근 마신 음료는 저장하지 않고 기록(`Entry`)에서 뽑는다(`RecentDrinks`).
@Model
final class FavoriteDrink {
    @Attribute(.unique) var servingID: String
    var addedAt: Date

    init(servingID: String, addedAt: Date) {
        self.servingID = servingID
        self.addedAt = addedAt
    }
}

/// 말걸기 한 번(§4.8, 캐릭터마다 하루 한 번). 무엇을 골랐고 어떤 몸짓이 나왔는지 남겨 그날 다시 열면 그대로 보인다.
@Model
final class TalkLog {
    /// `CupSide.characterID` ("roshu" | "kain").
    var character: String
    /// `DayKey.rawValue`.
    var day: String
    var choiceID: String
    /// 반응 애니메이션 이름(`TalkReaction.rawValue`).
    var reaction: String

    init(character: String, day: String, choiceID: String, reaction: String) {
        self.character = character
        self.day = day
        self.choiceID = choiceID
        self.reaction = reaction
    }
}

/// 로슈·카인 소개(첫 마감 때 한 번, §4.5)를 봤는지. 기기 단위 플래그라 온보딩 완료처럼 UserDefaults에 둔다.
enum CompanionIntro {
    static let seenKey = "companionIntroSeen"
}

/// 기록 시트의 "최근 마신 음료": 최근 기록 순으로 카탈로그 음료만, 즐겨찾기와 겹치지 않게, 중복 없이 최대 `limit`개.
enum RecentDrinks {
    static let limit = 5

    /// - Parameter servingIDsNewestFirst: 기록을 최신순으로 늘어놓은 serving id. 직접 입력(nil)은 넘기기 전에 뺀다.
    static func pick(servingIDsNewestFirst: [String], favorites: Set<String>, limit: Int = RecentDrinks.limit) -> [String] {
        var seen = favorites
        var picked: [String] = []
        for id in servingIDsNewestFirst where !seen.contains(id) {
            seen.insert(id)
            picked.append(id)
            if picked.count == limit { break }
        }
        return picked
    }
}
