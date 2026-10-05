import SwiftUI
import XCTest

@testable import SugarCap

/// 목을 쓰지 않고 실제 `data/catalog.json`을 읽는다.
/// 여기서 깨지면 수집 파이프라인이 계약을 어긴 것이다(`data/SCHEMA.md` 불변식).
final class CatalogTests: XCTestCase {
    private static let brandsWithSizeChoice: Set<String> = ["ediya", "twosome", "gongcha", "cvs"]

    private func loadCatalog() throws -> Catalog {
        try CatalogStore.loadBundled(from: Bundle(for: Self.self))
    }

    func testBundledCatalogLoadsWithSupportedSchema() throws {
        let catalog = try loadCatalog()

        XCTAssertEqual(catalog.schemaVersion, CatalogStore.supportedSchemaVersion)
        XCTAssertNotNil(catalog.builtAtDate, "built_at이 ISO 8601이 아님: \(catalog.builtAt)")
        XCTAssertEqual(catalog.brands.count, 10)
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

    func testEveryDrinkHasAReadableLiquidColor() throws {
        // 썸네일 색(SPEC §9.7). 빠지면 기본색으로 그려지지만 번들 카탈로그에선 빠지면 안 된다.
        let catalog = try loadCatalog()

        for drink in catalog.drinks {
            let hex = try XCTUnwrap(drink.liquidColor, "\(drink.id)에 liquid_color가 없음")
            XCTAssertNotNil(Color(liquidHex: hex), "\(drink.id)의 liquid_color 형식이 틀림: \(hex)")
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

    func testBundledCatalogLoadTime() throws {
        // 편의점이 들어와 카탈로그가 약 8.3MB가 됐고, 앱은 `App.init`에서 동기로 읽는다(2026-10-01).
        // 시뮬레이터 값이라 실기기와 다르다. 크게 늘면 비동기 로드·포맷 변경을 다시 검토한다.
        let start = Date()
        let catalog = try CatalogStore.loadBundled(from: Bundle(for: Self.self))
        let decoded = Date()
        _ = CatalogIndex(catalog: catalog)
        let indexed = Date()

        let decode = decoded.timeIntervalSince(start)
        let index = indexed.timeIntervalSince(decoded)
        print("catalog load: decode \(decode)s, index \(index)s, drinks \(catalog.drinks.count)")
        XCTAssertLessThan(decode + index, 5, "카탈로그 로드가 너무 느림: decode \(decode)s, index \(index)s")
    }

    func testLatteSearchPutsCafeLatteAboveFlavoredLattes() throws {
        let catalog = try CatalogStore.loadBundled(from: Bundle(for: Self.self))
        let index = CatalogIndex(catalog: catalog)

        // 2026-10-04: "라떼"에 딸기 콜드폼 딸기 라떼·편의점 "라떼는 말이야…"가 카페 라떼보다 먼저 왔다.
        let hits = index.search("라떼")
        let first = try XCTUnwrap(hits.first)
        XCTAssertNotEqual(first.brandId, CatalogIndex.convenienceStoreID)
        XCTAssertTrue(DrinkQuery.fold(first.name).hasSuffix("카페라떼"), "맨 위가 카페 라떼가 아님: \(first.name)")
        XCTAssertFalse(hits.prefix(10).contains { $0.name.contains("딸기") }, "딸기라떼가 카페 라떼 묶음에 섞임")

        let starbucks = index.drinks(brandID: "starbucks", matching: DrinkQuery("라떼"))
        XCTAssertTrue(["카페 라떼", "아이스 카페 라떼"].contains(starbucks.first?.name ?? "-"), "브랜드 안 검색 맨 위: \(starbucks.first?.name ?? "-")")
    }

    func testSearchOrderFollowsRankThenCafeBeforeStoreThenBrandGrid() throws {
        let catalog = try CatalogStore.loadBundled(from: Bundle(for: Self.self))
        let index = CatalogIndex(catalog: catalog)
        let order = Dictionary(uniqueKeysWithValues: catalog.brands.enumerated().map { ($1.id, $0) })

        for text in ["라떼", "아메리카노", "콜라", "커피"] {
            let query = DrinkQuery(text)
            let hits = index.search(text, limit: 5_000)
            XCTAssertFalse(hits.isEmpty, text)
            let keys = try hits.map { drink -> [Int] in
                let rank = try XCTUnwrap(query.rank(drink.searchNames))
                return [
                    rank.isExact ? 0 : 1,
                    drink.brandId == CatalogIndex.convenienceStoreID ? 1 : 0,
                    rank.extraLength,
                    rank.isPrefix ? 0 : 1,
                    order[drink.brandId] ?? -1,
                ]
            }
            XCTAssertEqual(keys, keys.sorted { $0.lexicographicallyPrecedes($1) }, "\(text) 검색 순서가 규칙과 다름")
        }
    }

    func testShorterNamesBeatPrefixMatches() throws {
        let index = CatalogIndex(catalog: try CatalogStore.loadBundled(from: Bundle(for: Self.self)))

        // 앞부분 일치를 길이보다 앞에 두면 콜라겐 제품이 코카콜라를 덮는다.
        let hits = index.search("콜라", limit: 100).map(\.name)
        let cola = try XCTUnwrap(hits.firstIndex(of: "코카콜라"), "코카콜라가 상위 100개에 없음")
        XCTAssertLessThan(cola, 10, "코카콜라가 너무 아래: \(hits.prefix(cola + 1))")

        // 떼어 내는 앞말은 띄어 쓴 낱말만: "아이스크림"의 본체는 "크림"이 아니다.
        XCTAssertEqual(DrinkSearchName("아이스크림 카페라떼").core, "아이스크림카페라떼")
        XCTAssertEqual(DrinkSearchName("아이스 카페 라떼").core, "라떼")
        XCTAssertEqual(DrinkSearchName("Caffe Latte").core, "latte")
        XCTAssertEqual(DrinkSearchName("카페").core, "카페", "이름 전체를 떼지는 않는다")
    }

    func testConvenienceStoreSearchIgnoresSpaces() throws {
        let catalog = try CatalogStore.loadBundled(from: Bundle(for: Self.self))
        let index = CatalogIndex(catalog: catalog)

        let spaced = index.drinks(brandID: "cvs", matching: DrinkQuery("바나나 맛 우유"))
        XCTAssertTrue(spaced.contains { $0.name == "바나나맛우유" }, "띄어 쓴 검색어로 바나나맛우유를 못 찾음")

        let all = index.drinks(brandID: "cvs", matching: DrinkQuery("  "))
        XCTAssertEqual(all.count, index.drinks(brandID: "cvs").count, "공백만 친 검색어는 전체여야 함")
    }
}
