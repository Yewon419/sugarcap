import XCTest

@testable import SugarCap

/// 실제 카탈로그의 메뉴로 패널 선택 → 기록 스냅샷까지 검증한다(목 없음).
final class ServingSelectionTests: XCTestCase {
    private func catalog() throws -> Catalog {
        try CatalogStore.loadBundled(from: Bundle(for: Self.self))
    }

    private func firstDrink(in catalog: Catalog, where predicate: (Drink) -> Bool) throws -> Drink {
        try XCTUnwrap(catalog.drinks.first(where: predicate), "조건에 맞는 메뉴가 카탈로그에 없음")
    }

    func testQuantityMultipliesBothValuesIntoTheSnapshot() throws {
        let drink = try firstDrink(in: catalog()) {
            $0.servings[0].sugarG != nil && $0.servings[0].caffeineMg != nil
                && $0.servings[0].caffeineVariants.isEmpty
        }
        let serving = drink.servings[0]

        var selection = ServingSelection(drink: drink)
        selection.quantity = 3
        let entry = selection.makeEntry(brandName: "브랜드", at: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(try XCTUnwrap(entry.sugarG), try XCTUnwrap(serving.sugarG) * 3, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(entry.caffeineMg), try XCTUnwrap(serving.caffeineMg) * 3, accuracy: 1e-9)
        XCTAssertEqual(entry.quantity, 3)
        XCTAssertEqual(entry.servingID, serving.id)
        XCTAssertEqual(entry.drinkName, drink.name)
        XCTAssertEqual(entry.sizeLabel, serving.sizeLabel)
        XCTAssertNil(entry.variantLabel)
    }

    func testUndisclosedValuesStayNilAfterMultiplying() throws {
        let drink = try firstDrink(in: catalog()) { $0.servings[0].caffeineMg == nil }

        var selection = ServingSelection(drink: drink)
        selection.quantity = 2

        XCTAssertNil(selection.caffeineMg, "미공개가 0으로 바뀌면 안 됨")
    }

    func testCaffeineVariantOverridesTheServingValue() throws {
        let drink = try firstDrink(in: catalog()) { $0.servings[0].caffeineVariants.count >= 2 }
        let variants = drink.servings[0].caffeineVariants

        var selection = ServingSelection(drink: drink)
        selection.variantIndex = 1

        XCTAssertEqual(selection.caffeineMg, variants[1].caffeineMg)
        let entry = selection.makeEntry(brandName: "더벤티", at: Date())
        XCTAssertEqual(entry.variantLabel, variants[1].label)
    }

    func testChangingSizeResetsTheVariant() throws {
        let drink = try firstDrink(in: catalog()) { $0.servings.count >= 2 }

        var selection = ServingSelection(drink: drink)
        selection.variantIndex = 1
        selection.servingIndex = 1

        XCTAssertEqual(selection.variantIndex, 0)
        XCTAssertEqual(selection.serving.id, drink.servings[1].id)
    }

    func testOutOfRangeIndicesAreClampedInsteadOfTrapping() throws {
        let drink = try firstDrink(in: catalog()) { $0.servings.count == 1 }

        var selection = ServingSelection(drink: drink)
        selection.servingIndex = 5

        XCTAssertEqual(selection.serving.id, drink.servings[0].id)
    }

    func testSearchMatchesKoreanAndEnglishNamesIgnoringCase() throws {
        let drink = try firstDrink(in: catalog()) { $0.nameEn != nil }
        let english = try XCTUnwrap(drink.nameEn)

        XCTAssertTrue(drink.matches(""))
        XCTAssertTrue(drink.matches(String(drink.name.prefix(2))))
        XCTAssertTrue(drink.matches(english.uppercased()))
        XCTAssertFalse(drink.matches("존재하지않는메뉴명zzz"))
    }

    func testSearchIgnoresSpacesOnBothSides() throws {
        // 편의점 제품명은 "핫식스 제로"·"핫식스제로"처럼 띄어쓰기가 섞여 있다(2026-10-01).
        let drink = try firstDrink(in: catalog()) { $0.name.contains(" ") }
        let joined = drink.name.replacingOccurrences(of: " ", with: "")
        let spaced = joined.map(String.init).joined(separator: " ")

        XCTAssertTrue(drink.matches(joined))
        XCTAssertTrue(drink.matches(spaced))
        XCTAssertTrue(drink.matches("   "), "공백만 친 검색어는 빈 검색어와 같다")
    }
}

final class ManualAmountTests: XCTestCase {
    func testBlankMeansUnknownNotZero() {
        XCTAssertEqual(ManualAmount(""), .empty)
        XCTAssertEqual(ManualAmount("   "), .empty)
        XCTAssertNil(ManualAmount("").number)
    }

    func testNumbersAreParsed() {
        XCTAssertEqual(ManualAmount("30"), .value(30))
        XCTAssertEqual(ManualAmount(" 12.5 "), .value(12.5))
        XCTAssertEqual(ManualAmount("0"), .value(0))
    }

    func testNegativeAndGarbageAreRejected() {
        XCTAssertEqual(ManualAmount("-3"), .invalid)
        XCTAssertEqual(ManualAmount("abc"), .invalid)
        XCTAssertEqual(ManualAmount("inf"), .invalid)
    }
}
