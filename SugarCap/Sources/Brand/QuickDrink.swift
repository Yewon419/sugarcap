import Foundation

/// 기록 시트의 즐겨찾기·최근 음료 한 줄(`DrinkKey`를 카탈로그로 풀어 둔 것). `+`를 누르면 1잔을 바로 기록한다.
/// 카탈로그 갱신으로 메뉴가 사라졌으면 만들지 않는다(행을 숨긴다).
struct QuickDrink: Identifiable, Equatable {
    let key: String
    let brand: Brand
    let selection: ServingSelection

    var id: String { key }
    var name: String { selection.drink.name }

    init?(key: String, catalog: CatalogIndex) {
        guard let parts = DrinkKey.parse(key),
            let drink = catalog.drink(servingID: parts.servingID),
            let brand = catalog.brand(id: drink.brandId),
            let servingIndex = drink.servings.firstIndex(where: { $0.id == parts.servingID })
        else { return nil }
        var selection = ServingSelection(drink: drink)
        selection.servingIndex = servingIndex
        if let label = parts.variantLabel {
            guard let variantIndex = selection.serving.caffeineVariants.firstIndex(where: { $0.label == label }) else {
                return nil
            }
            selection.variantIndex = variantIndex
        }
        self.key = key
        self.brand = brand
        self.selection = selection
    }

    /// 브랜드 · 온도 · 사이즈 · 원두. 사이즈 선택이 없는 브랜드의 "기본"은 적지 않는다.
    var meta: String {
        let size = selection.serving.sizeLabel == "기본" ? nil : selection.serving.sizeLabel
        return [brand.name, selection.drink.temperatureLabel, size, selection.variant?.label]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

extension ServingSelection {
    /// 즐겨찾기 별표가 가리키는 키. 수량은 키에 들어가지 않는다.
    var drinkKey: String {
        DrinkKey.make(servingID: serving.id, variantLabel: variant?.label)
    }
}

extension Entry {
    /// 카탈로그에서 고른 기록만 키가 있다. 직접 입력은 nil.
    var drinkKey: String? {
        servingID.map { DrinkKey.make(servingID: $0, variantLabel: variantLabel) }
    }
}
