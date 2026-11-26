import Foundation
import Observation
import OSLog

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
    /// 2는 1에 `caffeine_range`를, 3은 `estimated`를 더했다. 번들은 2026-11-18부터 세 나라 다 3이고, 1·2도 그대로 읽는다.
    static let supportedSchemaVersions: ClosedRange<Int> = 1...3
    static var supportedSchemaVersion: Int { supportedSchemaVersions.upperBound }

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

        guard supportedSchemaVersions.contains(catalog.schemaVersion) else {
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

    static func loadBundled(_ country: MenuCountry, from bundle: Bundle = .main) throws -> Catalog {
        let name = country.catalogResourceName
        guard let url = bundle.url(forResource: name, withExtension: resourceExtension) else {
            throw CatalogError.resourceMissing("\(name).\(resourceExtension)")
        }
        return try load(from: try Data(contentsOf: url))
    }

    /// 번들 파일 앞 1KB에서 `built_at`만 읽는다. 파이프라인이 `schema_version`·`built_at`을 맨 앞에 쓴다(`RemoteCatalogTests`가 지킨다).
    static func bundledBuiltAt(_ country: MenuCountry, from bundle: Bundle = .main) throws -> String {
        let name = country.catalogResourceName
        guard let url = bundle.url(forResource: name, withExtension: resourceExtension) else {
            throw CatalogError.resourceMissing("\(name).\(resourceExtension)")
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            do {
                try handle.close()
            } catch {
                RemoteCatalog.logger.error("번들 카탈로그 파일 닫기 실패: \(String(describing: error), privacy: .public)")
            }
        }
        let head = String(decoding: try handle.read(upToCount: 1024) ?? Data(), as: UTF8.self)
        guard let match = head.firstMatch(of: #/"built_at"\s*:\s*"([^"]+)"/#) else {
            throw RemoteCatalogError.missingBuiltAt("\(name).\(resourceExtension)")
        }
        return String(match.1)
    }
}

/// 지금 고른 나라의 카탈로그. 나라가 바뀌면 그 나라 파일을 다시 읽는다(한국 약 8.3MB라 둘 다 들고 있지 않는다).
/// 원격에서 받아 둔 더 새 파일이 있으면 그걸 쓴다(`RemoteCatalog`, SPEC §2.3).
@MainActor
@Observable
final class LoadedCatalog {
    private(set) var country: MenuCountry
    private(set) var result: Result<CatalogIndex, any Error>

    private static let logger = Logger(subsystem: "com.sugarcap.app", category: "catalog")

    init(country: MenuCountry) {
        self.country = country
        self.result = Self.load(country)
    }

    func show(_ next: MenuCountry) {
        guard next != country else { return }
        country = next
        result = Self.load(next)
    }

    private static func load(_ country: MenuCountry) -> Result<CatalogIndex, any Error> {
        let loaded = Result { CatalogIndex(catalog: try RemoteCatalog.live.loadNewest(country)) }
        if case .failure(let error) = loaded {
            logger.fault("카탈로그 로드 실패(\(country.rawValue, privacy: .public)): \(String(describing: error), privacy: .public)")
        }
        return loaded
    }
}

/// 기록 시트 검색에 걸린 브랜드. `menuQuery`는 브랜드 이름 뒤에 이어 친 말이고, 브랜드 메뉴 검색 칸에 미리 넣는다.
struct BrandMatch: Identifiable {
    let brand: Brand
    let menuQuery: String

    var id: String { brand.id }
}

/// 화면이 쓰는 조회용 색인. 카탈로그는 불변이라 한 번만 만든다.
struct CatalogIndex {
    let catalog: Catalog

    private let brandsByID: [String: Brand]
    private let drinksByBrandID: [String: [Drink]]
    private let servingsByID: [String: Serving]
    private let drinksByServingID: [String: Drink]
    private let searchNamesByDrinkID: [String: [DrinkSearchName]]
    private let flagshipDrinkIDs: Set<String>

    init(catalog: Catalog) {
        self.catalog = catalog
        self.brandsByID = Dictionary(uniqueKeysWithValues: catalog.brands.map { ($0.id, $0) })
        self.drinksByBrandID = Dictionary(grouping: catalog.drinks, by: \.brandId)
        self.servingsByID = Dictionary(
            uniqueKeysWithValues: catalog.drinks.flatMap(\.servings).map { ($0.id, $0) }
        )
        self.drinksByServingID = Dictionary(
            uniqueKeysWithValues: catalog.drinks.flatMap { drink in drink.servings.map { ($0.id, drink) } }
        )
        self.searchNamesByDrinkID = Dictionary(
            uniqueKeysWithValues: catalog.drinks.map { ($0.id, $0.searchNames) }
        )
        self.flagshipDrinkIDs = Set(
            catalog.drinks.filter { Self.flagshipMenus[$0.brandId]?.contains($0.name) == true }.map(\.id)
        )
    }

    func brand(id: String) -> Brand? { brandsByID[id] }
    func drinks(brandID: String) -> [Drink] { drinksByBrandID[brandID] ?? [] }
    func serving(id: String) -> Serving? { servingsByID[id] }
    func drink(servingID: String) -> Drink? { drinksByServingID[servingID] }

    /// 편의점은 같은 순위 안에서 카페 뒤에 둔다. 제품이 만 개가 넘어 카페 메뉴를 밀어낸다.
    static let convenienceStoreID = "cvs"

    /// 대표 메뉴(대표님 2026-11-19 "콜라 치면 코카콜라가 제일 위에", "카페 대표메뉴도"). 카탈로그에 인기 값이 없어
    /// 앱에 브랜드별 메뉴 이름으로 적는다(온도별로 따로 실린 메뉴는 둘 다). 이름이 검색어와 같은 메뉴 다음,
    /// 나머지보다 먼저다: "라떼"에 카페 라떼 → 돌체 라떼·토피넛 라떼 순. 한국 카탈로그만.
    static let flagshipMenus: [String: Set<String>] = [
        "cvs": [
            "코카콜라", "펩시", "펩시제로슈거", "칠성사이다", "칠성사이다제로", "스프라이트", "환타 오렌지", "밀키스",
            "포카리스웨트 이온워터", "바나나맛우유", "초코에몽", "박카스에이", "몬스터에너지", "핫식스", "솔의눈",
            "갈아만든배", "아침햇살", "옥수수수염차", "하늘보리", "닥터페퍼", "마운틴듀", "미에로화이바", "서울우유",
            "토레타!",
        ],
        "starbucks": [
            "카페 아메리카노", "아이스 카페 아메리카노", "카페 라떼", "아이스 카페 라떼", "자몽 허니 블랙 티",
            "아이스 자몽 허니 블랙 티", "스타벅스 돌체 라떼", "아이스 스타벅스 돌체 라떼", "자바 칩 프라푸치노",
            "바닐라 크림 콜드 브루", "쿨 라임 피지오",
        ],
        "mega": ["메가리카노", "왕메가카페라떼", "플레인퐁크러쉬", "쿠키프라페"],
        "compose": ["딥라떼"],
        "ediya": ["카페 아메리카노", "토피넛 라떼"],
        "paik": ["원조커피", "원조빽스치노(BASIC)", "달달연유라떼"],
        "twosome": ["아메리카노", "로얄 밀크티"],
        "hollys": ["아메리카노"],
        "theventi": ["아이스 아메리카노", "아인슈페너"],
        "gongcha": ["블랙 밀크티 + 펄", "브라운슈가 시그니처 밀크티 +펄", "타로 밀크티 + 펄"],
        "paulbassett": ["룽고", "아이스 룽고", "바닐라빈 카페라떼", "아이스 바닐라빈 카페라떼"],
        "coffeebean": ["바닐라 라떼", "아이스 바닐라 라떼", "헤이즐넛 아이스 블렌디드", "캐러멜 아이스 블렌디드"],
        "bluebottle": ["뉴올리언스", "지브롤터"],
        "amasvin": ["흑당 버블티"],
    ]

    /// 기록 시트 검색(브랜드 전체). 브랜드 안 검색과 같은 순위 규칙(`DrinkSearchRank`), 최대 `limit`개.
    /// 같은 순위 안에서는 카페 → 편의점, 그다음 브랜드 격자 순서다.
    func search(_ query: String, limit: Int = 60) -> [Drink] {
        let query = DrinkQuery(query)
        guard !query.isEmpty else { return [] }
        return Array(ranked(catalog.brands.flatMap { drinks(brandID: $0.id) }, query).prefix(limit))
    }

    /// 기록 시트 검색어에 걸린 브랜드(2026-11-10). 띄어쓰기·대소문자는 무시하고 브랜드 격자 순서다.
    /// "스타벅" → 스타벅스, "스타벅스 라떼" → 스타벅스 + 메뉴 검색어 "라떼".
    /// 한 글자는 이름 앞부분만 잡는다("라"가 이름 가운데에 든 브랜드까지 끌어오지 않게).
    func brandMatches(_ text: String) -> [BrandMatch] {
        let needle = DrinkQuery.fold(text)
        guard !needle.isEmpty else { return [] }
        return catalog.brands.compactMap { brand -> BrandMatch? in
            let name = DrinkQuery.fold(brand.name)
            if name.hasPrefix(needle) || (needle.count >= 2 && name.contains(needle)) {
                return BrandMatch(brand: brand, menuQuery: "")
            }
            let aliases = Self.brandAliases[brand.id] ?? []
            if needle.count >= 2, aliases.contains(where: { $0.hasPrefix(needle) }) {
                return BrandMatch(brand: brand, menuQuery: "")
            }
            for prefix in [name] + aliases where needle.hasPrefix(prefix) {
                if let rest = Self.remainder(of: text, afterFolded: prefix) {
                    return BrandMatch(brand: brand, menuQuery: rest)
                }
            }
            return nil
        }
    }

    /// 브랜드 줄임말·흔한 오타(2026-11-12). 카탈로그는 파이프라인 산출물이라 앱에 둔다. 접은 값으로 적는다.
    /// 이름 앞부분·가운데로 이미 잡히는 말("메가"·"투썸"·"벤티")은 넣지 않는다.
    static let brandAliases: [String: [String]] = [
        "starbucks": ["스벅"],
        "mega": ["메가커피"],
        "paik": ["백다방"],
        "baskin": ["배라", "베라", "베스킨라빈스"],
        "coffeebean": ["커빈"],
        "parisbaguette": ["파바", "파리바게트"],
    ]

    /// 원래 글에서 접은 브랜드 이름만큼 걷어 낸 나머지. 메뉴 검색어의 띄어쓰기를 그대로 둔다.
    private static func remainder(of text: String, afterFolded name: String) -> String? {
        var consumed = ""
        var index = text.startIndex
        while index < text.endIndex, consumed.count < name.count {
            consumed += DrinkQuery.fold(String(text[index]))
            index = text.index(after: index)
        }
        guard consumed == name else { return nil }
        let rest = text[index...].trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.isEmpty ? nil : rest
    }

    /// 브랜드 안 검색. 빈 검색어면 브랜드 메뉴 전체. 같은 순위 안에서는 카탈로그 순서다.
    func drinks(brandID: String, matching query: DrinkQuery) -> [Drink] {
        guard !query.isEmpty else { return drinks(brandID: brandID) }
        return ranked(drinks(brandID: brandID), query)
    }

    /// 검색 이름은 색인을 만들 때 한 번만 접어 둔다.
    private func searchNames(_ drink: Drink) -> [DrinkSearchName] {
        searchNamesByDrinkID[drink.id] ?? drink.searchNames
    }

    /// 순서가 같으면 들어온 순서를 지키도록 위치를 마지막 기준으로 쓴다.
    /// 글자로 하나도 안 걸리면 자음만 친 검색어는 초성으로, 나머지는 자판 키로 다시 찾는다(`DrinkQuery.typos`).
    /// 글자로 걸린 결과는 건드리지 않는다.
    private func ranked(_ drinks: [Drink], _ query: DrinkQuery) -> [Drink] {
        let found = rankedByText(drinks, query)
        guard found.isEmpty else { return found }
        return query.firstSounds == nil ? rankedByKeys(drinks, query) : rankedByFirstSounds(drinks, query)
    }

    /// 대표 메뉴 → 첫소리가 검색어로 시작 → 카페 → 짧은 이름 순. "ㅋㅋㄹ"에 코코리치보다 코카콜라가 먼저.
    private func rankedByFirstSounds(_ drinks: [Drink], _ query: DrinkQuery) -> [Drink] {
        drinks.enumerated()
            .compactMap { offset, drink -> (isFlagship: Bool, isPrefix: Bool, isStore: Bool, length: Int, offset: Int, drink: Drink)? in
                guard let match = query.firstSoundMatch(searchNames(drink)) else { return nil }
                return (flagshipDrinkIDs.contains(drink.id), match.isPrefix, drink.brandId == Self.convenienceStoreID, match.length, offset, drink)
            }
            .sorted { lhs, rhs in
                if lhs.isFlagship != rhs.isFlagship { return lhs.isFlagship }
                if lhs.isPrefix != rhs.isPrefix { return lhs.isPrefix }
                if lhs.isStore != rhs.isStore { return !lhs.isStore }
                if lhs.length != rhs.length { return lhs.length < rhs.length }
                return lhs.offset < rhs.offset
            }
            .map(\.drink)
    }

    private func rankedByText(_ drinks: [Drink], _ query: DrinkQuery) -> [Drink] {
        drinks.enumerated()
            .compactMap { offset, drink -> (rank: DrinkSearchRank, isFlagship: Bool, isStore: Bool, offset: Int, drink: Drink)? in
                guard let rank = query.rank(searchNames(drink), temperature: drink.temperature) else { return nil }
                return (rank, flagshipDrinkIDs.contains(drink.id), drink.brandId == Self.convenienceStoreID, offset, drink)
            }
            .sorted { lhs, rhs in
                if lhs.rank.isScattered != rhs.rank.isScattered { return !lhs.rank.isScattered }
                if lhs.rank.isExact != rhs.rank.isExact { return lhs.rank.isExact }
                if lhs.isFlagship != rhs.isFlagship { return lhs.isFlagship }
                if lhs.isStore != rhs.isStore { return !lhs.isStore }
                if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
                return lhs.offset < rhs.offset
            }
            .map(\.drink)
    }

    /// 틀린 키가 적은 것 → 대표 메뉴 → 카페 → 짧은 이름 순.
    private func rankedByKeys(_ drinks: [Drink], _ query: DrinkQuery) -> [Drink] {
        drinks.enumerated()
            .compactMap { offset, drink -> (typos: Int, isFlagship: Bool, isStore: Bool, length: Int, offset: Int, drink: Drink)? in
                let names = searchNames(drink)
                guard let typos = query.typos(names) else { return nil }
                let length = names.map(\.keys.count).min() ?? 0
                return (typos, flagshipDrinkIDs.contains(drink.id), drink.brandId == Self.convenienceStoreID, length, offset, drink)
            }
            .sorted { lhs, rhs in
                if lhs.typos != rhs.typos { return lhs.typos < rhs.typos }
                if lhs.isFlagship != rhs.isFlagship { return lhs.isFlagship }
                if lhs.isStore != rhs.isStore { return !lhs.isStore }
                if lhs.length != rhs.length { return lhs.length < rhs.length }
                return lhs.offset < rhs.offset
            }
            .map(\.drink)
    }

    /// 브랜드 메뉴 분류 칩: 메뉴가 많은 분류부터. 같은 수면 이름순(화면이 실행마다 흔들리지 않게).
    func categories(brandID: String) -> [String] {
        let counts = Dictionary(grouping: drinks(brandID: brandID), by: \.category).mapValues(\.count)
        return counts.keys.sorted { (counts[$0] ?? 0, $1) > (counts[$1] ?? 0, $0) }
    }
}
