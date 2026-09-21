import Foundation

/// 브랜드 메뉴 하단 패널의 선택 상태. `design/prototype.html`의 `pickValues`/`addPicked`를 옮긴 것이다.
struct ServingSelection: Equatable {
    let drink: Drink

    /// 사이즈를 바꾸면 원두 선택은 첫 번째로 돌아간다(prototype.html:395).
    /// 사이즈마다 원두 선택지가 다를 수 있어서 이전 인덱스를 들고 가면 엉뚱한 값을 가리킨다.
    var servingIndex = 0 {
        didSet { variantIndex = 0 }
    }
    var variantIndex = 0
    var quantity = 1

    init(drink: Drink) {
        self.drink = drink
    }

    /// 카탈로그 검증이 drink마다 serving 1개 이상을 보장하므로 범위만 맞추면 된다.
    var serving: Serving {
        drink.servings[min(max(servingIndex, 0), drink.servings.count - 1)]
    }

    var variant: CaffeineVariant? {
        let variants = serving.caffeineVariants
        guard !variants.isEmpty else { return nil }
        return variants[min(max(variantIndex, 0), variants.count - 1)]
    }

    /// 수량을 곱한 총량. 기록에는 이 값을 스냅샷한다(`Consumption` 주석 참고).
    var sugarG: Double? {
        serving.sugarG.map { $0 * Double(quantity) }
    }

    /// 원두 선택이 있으면 그 값, 없으면 serving 값(prototype.html:347).
    var caffeineMg: Double? {
        (variant?.caffeineMg ?? serving.caffeineMg).map { $0 * Double(quantity) }
    }

    func makeEntry(brandName: String, at date: Date) -> Entry {
        Entry(
            servingID: serving.id,
            variantLabel: variant?.label,
            quantity: quantity,
            loggedAt: date,
            sugarG: sugarG,
            caffeineMg: caffeineMg,
            drinkName: drink.name,
            brandName: brandName,
            sizeLabel: serving.sizeLabel
        )
    }
}

extension Drink {
    /// 목록 행의 온도 표기. `both`는 브랜드가 온도를 구분하지 않았다는 뜻이라 비워 둔다.
    var temperatureLabel: String? {
        switch temperature {
        case .hot: return "HOT"
        case .iced: return "ICED"
        case .both: return nil
        }
    }

    /// 브랜드 안 검색. 이름과 영문명에서 부분 일치, 대소문자 무시(prototype.html:335).
    func matches(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return true }
        return name.lowercased().contains(needle)
            || (nameEn?.lowercased().contains(needle) ?? false)
    }
}
