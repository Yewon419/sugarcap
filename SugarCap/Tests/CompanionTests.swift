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
        XCTAssertEqual(PokeMath.reaction(side: .caffeine, level: 1, combo: PokeMath.comboCount, tap: 4), .bounce)
    }

    func testKainVariesAcrossTapsAndIgnoresLevel() {
        let reactions = (0..<30).map { PokeMath.reaction(side: .caffeine, level: 1, combo: 1, tap: $0) }
        XCTAssertEqual(Set(reactions), [.tilt, .hop])
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

final class WidgetShelfTests: XCTestCase {
    private func drink(_ key: String) -> ShelfDrink {
        ShelfDrink(
            key: key, servingID: key, variantLabel: nil, name: key, brandName: "b", sizeLabel: "기본",
            sugarG: 1, caffeineMg: nil, estimated: false, liquidHex: nil
        )
    }

    func testFavoritesFirstThenRecentsWithoutDuplicates() {
        let keys = WidgetShelf.candidates(favoriteKeys: ["f1", "f2"], recentKeysNewestFirst: ["r1", "f1", "r1", "r2"])
        XCTAssertEqual(keys, ["f1", "f2", "r1", "r2"])
    }

    func testPickSkipsUnresolvedAndStopsAtFour() {
        let picked = WidgetShelf.pick(["a", "gone", "b", "c", "d", "e"]) { $0 == "gone" ? nil : self.drink($0) }
        XCTAssertEqual(picked.map(\.key), ["a", "b", "c", "d"])
    }

    func testSavedShelfRoundTrips() throws {
        let suite = "WidgetShelfTests"
        let store = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { store.removePersistentDomain(forName: suite) }
        XCTAssertEqual(try WidgetShelf.load(from: store), [])
        let drinks = [drink("a"), drink("b")]
        try WidgetShelf.save(drinks, to: store)
        XCTAssertEqual(try WidgetShelf.load(from: store), drinks)
    }

    /// 위젯 기록은 기록 시트 `+`(수량 1)와 같은 값이어야 한다. 실제 카탈로그로 본다(원두 선택 있는 더벤티 포함).
    func testShelfEntryMatchesQuickAddEntry() throws {
        let index = CatalogIndex(catalog: try CatalogStore.loadBundled(.kr, from: Bundle(for: Self.self)))
        let withVariant = try XCTUnwrap(
            index.catalog.drinks.lazy.flatMap(\.servings).first { $0.caffeineVariants.count > 1 })
        let keys = [
            DrinkKey.make(servingID: try XCTUnwrap(index.catalog.drinks.first?.servings.first?.id), variantLabel: nil),
            DrinkKey.make(servingID: withVariant.id, variantLabel: withVariant.caffeineVariants[1].label),
        ]
        let date = Date(timeIntervalSinceReferenceDate: 0)
        for key in keys {
            let quick = try XCTUnwrap(QuickDrink(key: key, catalog: index))
            let expected = quick.selection.makeEntry(brandName: quick.brand.name, at: date)
            let actual = ShelfDrink(quick).makeEntry(at: date)
            XCTAssertEqual(actual.drinkKey, expected.drinkKey)
            XCTAssertEqual(actual.quantity, expected.quantity)
            XCTAssertEqual(actual.sugarG, expected.sugarG)
            XCTAssertEqual(actual.caffeineMg, expected.caffeineMg)
            XCTAssertEqual(actual.estimated, expected.estimated)
            XCTAssertEqual(actual.drinkName, expected.drinkName)
            XCTAssertEqual(actual.brandName, expected.brandName)
            XCTAssertEqual(actual.sizeLabel, expected.sizeLabel)
        }
    }
}

/// 선반 이름 줄바꿈(시안 `wrapName`). 글자마다 폭 10, 칸 74 = 한 줄에 7글자.
final class ShelfNameTests: XCTestCase {
    private func lines(_ name: String) -> [String] {
        ShelfName.lines(name, width: 74) { Double($0.count * 10) }
    }

    func testShortNameStaysOnOneLine() {
        XCTAssertEqual(lines("레몬차"), ["레몬차"])
    }

    func testBreaksWhereTheLongerLineIsShortest() {
        XCTAssertEqual(lines("자몽 허니 블랙 티"), ["자몽 허니", "블랙 티"])
    }

    func testOverflowingSecondLineEndsWithEllipsis() {
        XCTAssertEqual(lines("가나 다라마바사아자차카타"), ["가나", "다라마바사아…"])
    }

    func testFirstWordWiderThanCellBreaksByCharacter() {
        XCTAssertEqual(lines("가나다라마바사아자차 카"), ["가나다라마바사", "아자차 카"])
    }
}
