import XCTest

@testable import SugarCap

final class PokeMathTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    func testComboCountsQuickTapsAndResetsAfterGapOrSpecial() {
        XCTAssertEqual(PokeMath.combo(previous: 0, lastTap: nil, now: start), 1)
        XCTAssertEqual(PokeMath.combo(previous: 2, lastTap: start, now: start.addingTimeInterval(0.5)), 3)
        XCTAssertEqual(PokeMath.combo(previous: 2, lastTap: start, now: start.addingTimeInterval(0.7)), 1, "간격이 벌어지면 다시 1")
        XCTAssertEqual(
            PokeMath.combo(previous: PokeMath.comboCount, lastTap: start, now: start.addingTimeInterval(0.1)), 1,
            "특이한 반응 뒤에는 다시 1"
        )
    }

    func testRoshuWarmsUpByStage() {
        XCTAssertEqual(PokeMath.reaction(side: .sugar, level: 3, combo: 1, tap: 0), .wary)
        XCTAssertEqual(PokeMath.reaction(side: .sugar, level: 4, combo: 1, tap: 0), .happy)
        XCTAssertEqual(PokeMath.reaction(side: .sugar, level: 7, combo: 1, tap: 0), .aegyo)
    }

    func testComboTriggersSpecialReaction() {
        XCTAssertEqual(PokeMath.reaction(side: .sugar, level: 1, combo: PokeMath.comboCount, tap: 4), .squish)
        XCTAssertEqual(PokeMath.reaction(side: .caffeine, level: 1, combo: PokeMath.comboCount, tap: 4), .flip)
    }

    func testKainVariesAcrossTapsAndIgnoresLevel() {
        let reactions = (0..<30).map { PokeMath.reaction(side: .caffeine, level: 1, combo: 1, tap: $0) }
        XCTAssertEqual(Set(reactions), [.tilt, .spin, .hop])
        for tap in 0..<10 {
            XCTAssertEqual(
                PokeMath.reaction(side: .caffeine, level: 1, combo: 1, tap: tap),
                PokeMath.reaction(side: .caffeine, level: 9, combo: 1, tap: tap)
            )
        }
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

final class ReactionMotionTests: XCTestCase {
    func testEveryReactionReturnsHomeAndMovesInBetween() {
        for reaction in PokeReaction.allCases {
            XCTAssertEqual(ReactionMotion.pose(reaction, at: 0), ReactionMotion.Pose(), "\(reaction) 시작은 제자리")
            XCTAssertEqual(ReactionMotion.pose(reaction, at: 5), ReactionMotion.Pose(), "\(reaction) 끝은 제자리")
            XCTAssertNotEqual(ReactionMotion.pose(reaction, at: 0.4), ReactionMotion.Pose(), "\(reaction) 중간엔 움직인다")
        }
    }
}
