import SwiftData
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
        XCTAssertEqual(RecentDrinks.pick(keysNewestFirst: ids, favorites: ["fav"]), ["a", "b", "c", "d", "e"])
    }

    func testKeySeparatesBeanVariantsAndRoundTrips() {
        let plain = DrinkKey.make(servingID: "theventi:americano:iced:large", variantLabel: nil)
        let bean = DrinkKey.make(servingID: "theventi:americano:iced:large", variantLabel: "디카페인")
        XCTAssertNotEqual(plain, bean)
        XCTAssertEqual(DrinkKey.parse(bean)?.servingID, "theventi:americano:iced:large")
        XCTAssertEqual(DrinkKey.parse(bean)?.variantLabel, "디카페인")
        XCTAssertNil(DrinkKey.parse(plain)?.variantLabel)
    }

    func testEmptyWhenEverythingIsFavorite() {
        XCTAssertEqual(RecentDrinks.pick(keysNewestFirst: ["a", "a"], favorites: ["a"]), [])
    }
}

@MainActor
final class TalkStoreTests: XCTestCase {
    func testTalkAddsTwoPointsOncePerDayAndLogsReaction() throws {
        let container = try ModelContainer(
            for: Affinity.self, TalkLog.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let day = DayKey(year: 2026, month: 9, day: 26)

        let outcome = try TalkStore.talk(side: .sugar, choiceID: "greet", day: day, logs: [], in: context)
        XCTAssertEqual(outcome.reaction, .wary, "처음 만난 사이의 로슈는 멀찍이서 지켜본다")
        XCTAssertEqual(try SettlementStore.affinity(for: .sugar, in: context).points, TalkMath.points)

        let logs = try context.fetch(FetchDescriptor<TalkLog>())
        XCTAssertEqual(logs.count, 1)
        XCTAssertThrowsError(try TalkStore.talk(side: .sugar, choiceID: "pat", day: day, logs: logs, in: context)) { error in
            XCTAssertEqual(error as? TalkStore.TalkError, .alreadyTalkedToday)
        }
        XCTAssertEqual(try SettlementStore.affinity(for: .sugar, in: context).points, TalkMath.points, "두 번째는 오르지 않는다")

        _ = try TalkStore.talk(side: .caffeine, choiceID: "walk", day: day, logs: logs, in: context)
        XCTAssertEqual(try SettlementStore.affinity(for: .caffeine, in: context).points, TalkMath.points, "카인은 따로 하루 한 번")
    }
}

final class ReactionMotionTests: XCTestCase {
    func testEveryReactionReturnsHomeAndMovesInBetween() {
        for reaction in TalkReaction.allCases {
            XCTAssertEqual(ReactionMotion.pose(reaction, at: 0), ReactionMotion.Pose(), "\(reaction) 시작은 제자리")
            XCTAssertEqual(ReactionMotion.pose(reaction, at: 5), ReactionMotion.Pose(), "\(reaction) 끝은 제자리")
            XCTAssertNotEqual(ReactionMotion.pose(reaction, at: 0.4), ReactionMotion.Pose(), "\(reaction) 중간엔 움직인다")
        }
    }
}
