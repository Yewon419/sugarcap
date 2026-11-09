import Foundation

/// Large 위젯 아래 선반의 음료 한 칸(SPEC §4.6, 시안 design/proto/widget-large.html A 대표님 2026-11-09 확정).
/// 위젯은 카탈로그를 읽지 않는다(1.7만 행). 앱이 카탈로그로 풀어 둔 값을 공용 저장소에 쓰고, 위젯은 이 값으로 1잔을 기록한다.
struct ShelfDrink: Codable, Equatable, Identifiable {
    /// `DrinkKey.make`.
    let key: String
    let servingID: String
    let variantLabel: String?
    let name: String
    let brandName: String
    let sizeLabel: String
    /// 1잔 값. nil은 브랜드 미공개.
    let sugarG: Double?
    let caffeineMg: Double?
    let estimated: Bool
    /// 액체 색 "#RRGGBB". 옛 카탈로그엔 없다.
    let liquidHex: String?

    var id: String { key }

    /// 앱 기록 시트의 즐겨찾기 `+`와 같은 기록(`ServingSelection.makeEntry`, 수량 1).
    func makeEntry(at date: Date) -> Entry {
        Entry(
            servingID: servingID,
            variantLabel: variantLabel,
            quantity: 1,
            loggedAt: date,
            sugarG: sugarG,
            caffeineMg: caffeineMg,
            estimated: estimated,
            drinkName: name,
            brandName: brandName,
            sizeLabel: sizeLabel
        )
    }
}

enum WidgetShelf {
    static let limit = 4
    private static let storeKey = "widgetShelf"

    /// 선반 후보 키: 즐겨찾기(별표한 순) → 최근 마신 음료(최신순), 겹치지 않게.
    /// 카탈로그에서 안 풀리는 키(사라진 메뉴)가 섞여도 4칸이 차게 최근은 넉넉히 둔다.
    static func candidates(favoriteKeys: [String], recentKeysNewestFirst: [String]) -> [String] {
        favoriteKeys
            + RecentDrinks.pick(keysNewestFirst: recentKeysNewestFirst, favorites: Set(favoriteKeys), limit: limit * 2)
    }

    /// 후보를 앞에서부터 풀어 최대 `limit`칸. 풀리지 않는 키는 `resolve`가 nil로 뺀다.
    static func pick(_ candidates: [String], resolve: (String) -> ShelfDrink?) -> [ShelfDrink] {
        Array(candidates.lazy.compactMap(resolve).prefix(limit))
    }

    static func load(from store: UserDefaults) throws -> [ShelfDrink] {
        guard let data = store.data(forKey: storeKey) else { return [] }
        return try JSONDecoder().decode([ShelfDrink].self, from: data)
    }

    static func save(_ drinks: [ShelfDrink], to store: UserDefaults) throws {
        store.set(try JSONEncoder().encode(drinks), forKey: storeKey)
    }
}
