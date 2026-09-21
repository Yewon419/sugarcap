import Foundation

enum CatalogError: Error, CustomStringConvertible {
    case resourceMissing(String)
    case unsupportedSchemaVersion(found: Int, supported: Int)
    case decodingFailed(Error)
    case duplicateIdentifier(kind: String, id: String)

    var description: String {
        switch self {
        case .resourceMissing(let name):
            return "번들에 \(name)이 없습니다."
        case .unsupportedSchemaVersion(let found, let supported):
            return "지원하지 않는 schema_version \(found) (지원: \(supported))."
        case .decodingFailed(let error):
            return "카탈로그 디코딩 실패: \(error)"
        case .duplicateIdentifier(let kind, let id):
            return "\(kind) id가 중복입니다: \(id)"
        }
    }
}

enum CatalogStore {
    /// 앱이 읽을 수 있는 스키마 버전. 깨는 변경이 오면 `data/SCHEMA.md`와 함께 올린다.
    static let supportedSchemaVersion = 1

    static let resourceName = "catalog"
    static let resourceExtension = "json"

    static func load(from data: Data) throws -> Catalog {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let catalog: Catalog
        do {
            catalog = try decoder.decode(Catalog.self, from: data)
        } catch {
            throw CatalogError.decodingFailed(error)
        }

        guard catalog.schemaVersion == supportedSchemaVersion else {
            throw CatalogError.unsupportedSchemaVersion(
                found: catalog.schemaVersion,
                supported: supportedSchemaVersion
            )
        }
        try assertUniqueIdentifiers(in: catalog)
        return catalog
    }

    /// `CatalogIndex`가 사전을 만들 때 중복 키로 트랩하기 전에 잡는다.
    /// 번들 파일은 `validate.py`가 보장하지만 원격 갱신(§2.3)은 손상된 파일을 줄 수 있다.
    private static func assertUniqueIdentifiers(in catalog: Catalog) throws {
        var brandIDs = Set<String>()
        for brand in catalog.brands where !brandIDs.insert(brand.id).inserted {
            throw CatalogError.duplicateIdentifier(kind: "brand", id: brand.id)
        }

        var drinkIDs = Set<String>()
        var servingIDs = Set<String>()
        for drink in catalog.drinks {
            guard drinkIDs.insert(drink.id).inserted else {
                throw CatalogError.duplicateIdentifier(kind: "drink", id: drink.id)
            }
            for serving in drink.servings where !servingIDs.insert(serving.id).inserted {
                throw CatalogError.duplicateIdentifier(kind: "serving", id: serving.id)
            }
        }
    }

    static func loadBundled(from bundle: Bundle = .main) throws -> Catalog {
        guard let url = bundle.url(forResource: resourceName, withExtension: resourceExtension) else {
            throw CatalogError.resourceMissing("\(resourceName).\(resourceExtension)")
        }
        return try load(from: try Data(contentsOf: url))
    }
}

/// 화면이 쓰는 조회용 색인. 카탈로그는 불변이라 한 번만 만든다.
struct CatalogIndex {
    let catalog: Catalog

    private let brandsByID: [String: Brand]
    private let drinksByBrandID: [String: [Drink]]
    private let servingsByID: [String: Serving]

    init(catalog: Catalog) {
        self.catalog = catalog
        self.brandsByID = Dictionary(uniqueKeysWithValues: catalog.brands.map { ($0.id, $0) })
        self.drinksByBrandID = Dictionary(grouping: catalog.drinks, by: \.brandId)
        self.servingsByID = Dictionary(
            uniqueKeysWithValues: catalog.drinks.flatMap(\.servings).map { ($0.id, $0) }
        )
    }

    func brand(id: String) -> Brand? { brandsByID[id] }
    func drinks(brandID: String) -> [Drink] { drinksByBrandID[brandID] ?? [] }
    func serving(id: String) -> Serving? { servingsByID[id] }
}
