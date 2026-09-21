import XCTest

@testable import SugarCap

/// 목을 쓰지 않고 실제 `data/catalog.json`을 읽는다.
/// 여기서 깨지면 수집 파이프라인이 계약을 어긴 것이다(`data/SCHEMA.md` 불변식).
final class CatalogTests: XCTestCase {
    private static let brandsWithSizeChoice: Set<String> = ["ediya", "twosome"]

    private func loadCatalog() throws -> Catalog {
        try CatalogStore.loadBundled(from: Bundle(for: Self.self))
    }

    func testBundledCatalogLoadsWithSupportedSchema() throws {
        let catalog = try loadCatalog()

        XCTAssertEqual(catalog.schemaVersion, CatalogStore.supportedSchemaVersion)
        XCTAssertNotNil(catalog.builtAtDate, "built_at이 ISO 8601이 아님: \(catalog.builtAt)")
        XCTAssertEqual(catalog.brands.count, 8)
        XCTAssertFalse(catalog.drinks.isEmpty)
    }

    func testEveryDrinkPointsAtAKnownBrand() throws {
        let catalog = try loadCatalog()
        let brandIDs = Set(catalog.brands.map(\.id))

        for drink in catalog.drinks {
            XCTAssertTrue(
                brandIDs.contains(drink.brandId),
                "\(drink.id)의 brand_id \(drink.brandId)가 brands에 없음"
            )
        }
    }

    func testIdentifiersAreUnique() throws {
        let catalog = try loadCatalog()

        let drinkIDs = catalog.drinks.map(\.id)
        XCTAssertEqual(Set(drinkIDs).count, drinkIDs.count, "drink.id 중복")

        let servingIDs = catalog.drinks.flatMap(\.servings).map(\.id)
        XCTAssertEqual(Set(servingIDs).count, servingIDs.count, "serving.id 중복")
    }

    func testServingIdentifiersAreNamespacedByDrink() throws {
        let catalog = try loadCatalog()

        for drink in catalog.drinks {
            for serving in drink.servings {
                XCTAssertTrue(
                    serving.id.hasPrefix(drink.id + ":"),
                    "\(serving.id)가 \(drink.id) 접두사를 따르지 않음"
                )
            }
        }
    }

    func testOnlySizeChoiceBrandsHaveMultipleServings() throws {
        let catalog = try loadCatalog()
        let sizeChoice = Set(catalog.brands.filter(\.hasSizeChoice).map(\.id))

        XCTAssertEqual(sizeChoice, Self.brandsWithSizeChoice)

        for drink in catalog.drinks where !sizeChoice.contains(drink.brandId) {
            XCTAssertEqual(
                drink.servings.count, 1,
                "\(drink.id)는 사이즈 선택이 없는 브랜드인데 serving이 \(drink.servings.count)개"
            )
        }
    }

    func testEveryDrinkHasAtLeastOneServing() throws {
        let catalog = try loadCatalog()

        for drink in catalog.drinks {
            XCTAssertFalse(drink.servings.isEmpty, "\(drink.id)에 serving이 없음")
        }
    }

    func testCaffeineMatchesTheFirstVariantWhenVariantsExist() throws {
        let catalog = try loadCatalog()
        var withVariants = 0

        for serving in catalog.drinks.flatMap(\.servings) where !serving.caffeineVariants.isEmpty {
            withVariants += 1
            XCTAssertEqual(
                serving.caffeineMg, serving.caffeineVariants[0].caffeineMg,
                "\(serving.id)의 caffeine_mg가 첫 변형과 다름"
            )
        }

        // 현재 더벤티 원두별 값만 해당한다(SPEC §10).
        XCTAssertGreaterThan(withVariants, 0)
    }

    func testMissingValuesAreKeptRatherThanDropped() throws {
        // SPEC §9.2: 카페인 미공개를 이유로 행을 버리지 않는다.
        // 당류를 가진 논커피 메뉴가 통째로 빠지는 걸 막는 규칙이다.
        let catalog = try loadCatalog()
        let servings = catalog.drinks.flatMap(\.servings)

        let caffeineMissing = servings.filter { $0.caffeineMg == nil }
        XCTAssertGreaterThan(caffeineMissing.count, 0)
        XCTAssertTrue(
            caffeineMissing.contains { $0.sugarG != nil },
            "카페인 미공개인데 당류는 있는 행이 하나도 없음 — 드롭 규칙이 잘못 적용된 듯"
        )
    }

    func testValuesStayInsideSanityBounds() throws {
        // `validate.py`의 이상치 범위와 같다. 걸리면 신메뉴가 아니라 파싱 버그다.
        let catalog = try loadCatalog()

        for serving in catalog.drinks.flatMap(\.servings) {
            if let sugar = serving.sugarG {
                XCTAssertTrue((0...200).contains(sugar), "\(serving.id) 당류 \(sugar)g")
            }
            if let caffeine = serving.caffeineMg {
                XCTAssertTrue((0...800).contains(caffeine), "\(serving.id) 카페인 \(caffeine)mg")
            }
            if let volume = serving.volumeMl {
                XCTAssertTrue((20...1200).contains(volume), "\(serving.id) 용량 \(volume)ml")
            }
        }
    }

    func testUnsupportedSchemaVersionIsRejected() throws {
        let payload = Data(
            #"{"schema_version": 2, "built_at": "2026-09-16T04:06:26+00:00", "brands": [], "drinks": []}"#
                .utf8
        )

        XCTAssertThrowsError(try CatalogStore.load(from: payload)) { error in
            guard case CatalogError.unsupportedSchemaVersion(let found, let supported) = error else {
                return XCTFail("예상과 다른 에러: \(error)")
            }
            XCTAssertEqual(found, 2)
            XCTAssertEqual(supported, 1)
        }
    }

    func testDuplicateServingIdentifierIsRejected() throws {
        // 중복 id는 CatalogIndex의 사전 생성에서 트랩한다. 그 전에 에러로 잡아야 한다.
        let payload = Data(
            """
            {"schema_version": 1, "built_at": "2026-09-16T04:06:26+00:00", "brands": [],
             "drinks": [{"id": "x:a:hot", "brand_id": "x", "name": "A", "name_en": null,
              "category": "c", "temperature": "hot", "servings": [
               {"id": "x:a:hot:r", "size_label": "R", "volume_ml": null, "sugar_g": 1,
                "caffeine_mg": null, "caffeine_variants": []},
               {"id": "x:a:hot:r", "size_label": "L", "volume_ml": null, "sugar_g": 2,
                "caffeine_mg": null, "caffeine_variants": []}]}]}
            """.utf8
        )

        XCTAssertThrowsError(try CatalogStore.load(from: payload)) { error in
            guard case CatalogError.duplicateIdentifier(let kind, let id) = error else {
                return XCTFail("예상과 다른 에러: \(error)")
            }
            XCTAssertEqual(kind, "serving")
            XCTAssertEqual(id, "x:a:hot:r")
        }
    }

    func testDuplicateBrandIdentifierIsRejected() throws {
        let payload = Data(
            """
            {"schema_version": 1, "built_at": "2026-09-16T04:06:26+00:00", "drinks": [],
             "brands": [
              {"id": "x", "name": "X", "serving_note": "", "has_size_choice": false},
              {"id": "x", "name": "X2", "serving_note": "", "has_size_choice": false}]}
            """.utf8
        )

        XCTAssertThrowsError(try CatalogStore.load(from: payload)) { error in
            guard case CatalogError.duplicateIdentifier(let kind, _) = error else {
                return XCTFail("예상과 다른 에러: \(error)")
            }
            XCTAssertEqual(kind, "brand")
        }
    }

    func testMalformedJSONIsRejected() throws {
        XCTAssertThrowsError(try CatalogStore.load(from: Data("{ not json".utf8))) { error in
            guard case CatalogError.decodingFailed = error else {
                return XCTFail("예상과 다른 에러: \(error)")
            }
        }
    }
}

final class CatalogIndexTests: XCTestCase {
    func testLookupsResolveAgainstTheRealCatalog() throws {
        let catalog = try CatalogStore.loadBundled(from: Bundle(for: Self.self))
        let index = CatalogIndex(catalog: catalog)

        for brand in catalog.brands {
            XCTAssertEqual(index.brand(id: brand.id)?.id, brand.id)
            XCTAssertFalse(index.drinks(brandID: brand.id).isEmpty, "\(brand.id) 메뉴가 비었음")
        }

        guard let anyServing = catalog.drinks.first?.servings.first else {
            return XCTFail("카탈로그에 serving이 없음")
        }
        XCTAssertEqual(index.serving(id: anyServing.id)?.id, anyServing.id)
        XCTAssertNil(index.serving(id: "없는:아이디:regular"))
    }
}
