import XCTest

@testable import SugarCap

/// 기대값은 HTML 프로토타입(`design/proto/screens-affinity.js`)을 node로 돌려 뽑았다.
/// 프로토타입에서 본 선택지·반응이 앱에서도 같게 나와야 한다.
final class TalkMathTests: XCTestCase {
    private let sep26 = DayKey(year: 2026, month: 9, day: 26)
    private let oct1 = DayKey(year: 2026, month: 10, day: 1)

    func testTodaysChoicesMatchPrototype() {
        XCTAssertEqual(TalkMath.todaysChoices(day: sep26, side: .sugar).map(\.id), ["ask", "walk", "greet"])
        XCTAssertEqual(TalkMath.todaysChoices(day: sep26, side: .caffeine).map(\.id), ["pat", "ask", "greet"])
        XCTAssertEqual(TalkMath.todaysChoices(day: oct1, side: .sugar).map(\.id), ["ask", "five", "greet"])
        XCTAssertEqual(TalkMath.todaysChoices(day: oct1, side: .caffeine).map(\.id), ["ask", "greet", "praise"])
    }

    func testKainReactionMatchesPrototypeAndIgnoresLevel() {
        let expected: [String: TalkReaction] = [
            "greet": .spin, "praise": .tilt, "pat": .spin, "walk": .hop, "ask": .spin, "five": .tilt,
        ]
        for (choice, reaction) in expected {
            XCTAssertEqual(TalkMath.reaction(side: .caffeine, choiceID: choice, level: 1, day: sep26), reaction, choice)
            XCTAssertEqual(TalkMath.reaction(side: .caffeine, choiceID: choice, level: 9, day: sep26), reaction, choice)
        }
    }

    func testRoshuWarmsUpByStage() {
        XCTAssertEqual(TalkMath.reaction(side: .sugar, choiceID: "greet", level: 3, day: sep26), .wary)
        XCTAssertEqual(TalkMath.reaction(side: .sugar, choiceID: "greet", level: 4, day: sep26), .happy)
        XCTAssertEqual(TalkMath.reaction(side: .sugar, choiceID: "greet", level: 7, day: sep26), .aegyo)
    }

    func testTalkNeverOutpacesFeeding() {
        XCTAssertLessThan(TalkMath.points, AffinityMath.points(left: 50, limit: 50))
    }
}

final class RecentDrinksTests: XCTestCase {
    func testSkipsFavoritesAndDuplicatesAndStopsAtLimit() {
        let ids = ["a", "b", "a", "fav", "c", "d", "e", "f", "g"]
        XCTAssertEqual(RecentDrinks.pick(servingIDsNewestFirst: ids, favorites: ["fav"]), ["a", "b", "c", "d", "e"])
    }

    func testEmptyWhenEverythingIsFavorite() {
        XCTAssertEqual(RecentDrinks.pick(servingIDsNewestFirst: ["a", "a"], favorites: ["a"]), [])
    }
}
