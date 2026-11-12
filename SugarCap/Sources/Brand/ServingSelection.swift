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

    func amount(_ side: CupSide) -> Double? {
        switch side {
        case .sugar: return sugarG
        case .caffeine: return caffeineMg
        }
    }

    /// 한 잔 값으로 가른다. 수량을 곱해서 가르면 잔 수를 바꿀 때 패널이 당↔카페인으로 뒤집힌다.
    var primarySide: CupSide {
        CupSide.primary(name: drink.name, sugarG: serving.sugarG, caffeineMg: variant?.caffeineMg ?? serving.caffeineMg)
    }

    func makeEntry(brandName: String, at date: Date) -> Entry {
        Entry(
            servingID: serving.id,
            variantLabel: variant?.label,
            quantity: quantity,
            loggedAt: date,
            sugarG: sugarG,
            caffeineMg: caffeineMg,
            estimated: serving.isEstimated,
            drinkName: drink.name,
            brandName: brandName,
            sizeLabel: serving.sizeLabel
        )
    }
}

extension Serving {
    /// 사이즈 선택이 없는 한국 카탈로그의 "기본"은 데이터 값이라, 화면에 찍을 때만 언어에 맞춘다.
    static func displaySize(_ label: String) -> String {
        label == "기본" ? String(localized: "기본") : label
    }
}

extension Brand {
    /// 브랜드 메뉴 수. 영어 단수("1 item")를 따로 두고, 그 밖은 천 단위 구분을 살린다.
    static func menuCount(_ count: Int) -> String {
        count == 1 ? String(localized: "메뉴 1") : String(localized: "메뉴 \(count.formatted())")
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

    func matches(_ query: String) -> Bool {
        let query = DrinkQuery(query)
        return query.isEmpty || query.rank(searchNames, temperature: temperature) != nil
    }

    var searchNames: [DrinkSearchName] {
        [name, nameEn].compactMap { $0 }.map(DrinkSearchName.init)
    }
}

/// 메뉴 검색어. 이름과 영문명에서 부분 일치, 대소문자·띄어쓰기 무시(prototype.html:335).
/// 띄어쓰기는 편의점 제품명이 "핫식스 제로"·"핫식스제로"처럼 섞여 있어서 무시한다(2026-10-01).
/// 메뉴마다 다시 접지 않게 검색어는 한 번만 접는다.
struct DrinkQuery {
    let needle: String
    /// "아이스 라떼"처럼 첫 낱말이 온도 말이고 뒤에 말이 더 있으면, 그 온도와 나머지 검색어(2026-11-12).
    /// 대부분 브랜드는 이름에 "아이스"를 붙이지 않고 온도 칸에만 적어서, 이름만 보면 "아이스 라떼"가 하나도 안 걸렸다.
    let temperatureScope: TemperatureScope?

    struct TemperatureScope {
        let temperature: Drink.Temperature
        let needle: String
    }

    /// 띄어 쓴 첫 낱말일 때만 온도 말로 본다. 붙여 쓰면 "아이스크림"·"핫식스"가 갈라진다.
    static let temperatureWords: [String: Drink.Temperature] = ["아이스": .iced, "iced": .iced, "핫": .hot, "hot": .hot]

    /// 메뉴 줄임말. 검색어 전체가 이 말이면 풀어 쓴 말로 찾는다(2026-11-12 대표님 "아아", "아바라").
    /// 줄임말 그대로 이름에 든 메뉴가 있는 말("아샷추"·"아인슈"·"디카")은 넣지 않는다. 풀어 쓰면 그 메뉴를 놓친다.
    static let menuAliases: [String: String] = [
        "아아": "아이스 아메리카노",
        "뜨아": "핫 아메리카노",
        "따아": "핫 아메리카노",
        "아라": "아이스 라떼",
        "뜨라": "핫 라떼",
        "아바라": "아이스 바닐라 라떼",
        "뜨바라": "핫 바닐라 라떼",
        "카마": "카라멜 마키아또",
        "캐마": "카라멜 마키아또",
        "아캐마": "아이스 카라멜 마키아또",
        "콜브": "콜드 브루",
        "바콜": "바닐라 크림 콜드 브루",
        "자허블": "자몽 허니 블랙 티",
        "민초": "민트 초코",
        "딸라": "딸기 라떼",
        "밀티": "밀크티",
        "블글라": "블랙 글레이즈드 라떼",
        "화모": "화이트 초콜릿 모카",
        "제말크프": "제주 말차 크림 프라푸치노",
    ]

    init(_ typed: String) {
        let text = Self.menuAliases[Self.fold(typed)] ?? typed
        needle = Self.fold(text)
        let words = text.lowercased().split(whereSeparator: \.isWhitespace)
        if words.count > 1, let temperature = Self.temperatureWords[String(words[0])] {
            temperatureScope = TemperatureScope(temperature: temperature, needle: Self.fold(words.dropFirst().joined()))
        } else {
            temperatureScope = nil
        }
    }

    var isEmpty: Bool { needle.isEmpty }

    /// 검색 순위. 이름과 영문명 중 더 나은 쪽, 온도 말 검색이면 그쪽 일치까지 견줘 더 나은 쪽. 일치하지 않으면 nil.
    /// 온도 말 검색은 그 온도 메뉴와 온도를 나눠 싣지 않은(`both`) 메뉴만 잡고, `both`는 같은 순위 안에서 뒤로 보낸다.
    func rank(_ names: [DrinkSearchName], temperature: Drink.Temperature) -> DrinkSearchRank? {
        guard !needle.isEmpty else { return nil }
        let whole = names.compactMap { Self.rank(name: $0, needle: needle) }.min()
        guard let scope = temperatureScope, temperature == scope.temperature || temperature == .both else {
            return whole
        }
        let scoped = names.compactMap { Self.rank(name: $0, needle: scope.needle) }.min()
            .map { DrinkSearchRank(isExact: $0.isExact, extraLength: $0.extraLength, isPrefix: $0.isPrefix, isTemperatureGuess: temperature == .both) }
        return [whole, scoped].compactMap { $0 }.min()
    }

    private static func rank(name: DrinkSearchName, needle: String) -> DrinkSearchRank? {
        guard name.folded.contains(needle) else { return nil }
        let isExact = name.core == needle || name.core == "카페" + needle
        // 검색어가 떼어 낸 앞말에만 걸리면("아이스") 본체 대신 전체 이름 길이로 잰다.
        let body = name.core.contains(needle) ? name.core : name.folded
        return DrinkSearchRank(
            isExact: isExact,
            extraLength: isExact ? 0 : body.count - needle.count,
            isPrefix: name.core.hasPrefix(needle) || name.folded.hasPrefix(needle)
        )
    }

    static func fold(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) })
    }
}

/// 검색 순위를 매길 이름 하나. 맨 앞의 온도·"카페" 낱말을 뗀 본체(`core`)를 같이 들고 있다.
/// "아이스 카페 라떼"·"카페라떼"의 본체는 "라떼"라서 "라떼" 검색의 맨 위에 온다.
struct DrinkSearchName {
    let folded: String
    let core: String

    /// 띄어 쓴 낱말 단위로만 뗀다. 붙여 쓴 이름까지 떼면 "아이스크림"이 "크림", "핫식스"가 "식스"가 된다.
    static let leadingWords: Set<String> = ["아이스", "핫", "카페", "iced", "hot", "caffe", "cafe", "café"]

    init(_ name: String) {
        folded = DrinkQuery.fold(name)
        var words = name.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        while words.count > 1, let first = words.first, Self.leadingWords.contains(first) {
            words.removeFirst()
        }
        core = words.joined()
    }
}

/// 작을수록 위. 본체가 검색어와 같은 이름 → 검색어 밖 글자가 적은 이름 → 검색어로 시작하는 이름 순
/// (2026-10-04, "라떼"에 딸기 콜드폼 딸기 라떼가 카페 라떼보다 먼저 오던 문제).
/// 앞부분 일치를 길이보다 앞에 두면 "콜라"에 콜라겐 제품이 코카콜라보다 먼저 온다.
struct DrinkSearchRank: Comparable {
    let isExact: Bool
    let extraLength: Int
    let isPrefix: Bool
    /// 온도 말 검색에서 온도를 나눠 싣지 않은(`both`) 메뉴로 잡혔다. "아이스 라떼"에 카페 라떼보다 아이스 카페 라떼가 먼저.
    var isTemperatureGuess = false

    static func < (lhs: DrinkSearchRank, rhs: DrinkSearchRank) -> Bool {
        (lhs.isExact ? 0 : 1, lhs.isTemperatureGuess ? 1 : 0, lhs.extraLength, lhs.isPrefix ? 0 : 1)
            < (rhs.isExact ? 0 : 1, rhs.isTemperatureGuess ? 1 : 0, rhs.extraLength, rhs.isPrefix ? 0 : 1)
    }
}
