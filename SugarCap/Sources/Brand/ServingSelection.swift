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

    func matches(_ query: String) -> Bool {
        DrinkQuery(query).matches(searchKey)
    }

    /// 검색 비교용 이름: 이름과 영문명을 각각 접어서 줄바꿈으로 잇는다(두 이름에 걸친 일치를 막는다).
    var searchKey: String {
        [name, nameEn].compactMap { $0 }.map(DrinkQuery.fold).joined(separator: "\n")
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

    init(_ text: String) {
        needle = Self.fold(text)
    }

    var isEmpty: Bool { needle.isEmpty }

    func matches(_ searchKey: String) -> Bool {
        needle.isEmpty || searchKey.contains(needle)
    }

    /// 검색 순위. 이름과 영문명 중 더 나은 쪽. 일치하지 않으면 nil.
    func rank(_ names: [DrinkSearchName]) -> DrinkSearchRank? {
        guard !needle.isEmpty else { return nil }
        return names.compactMap { rank(name: $0) }.min()
    }

    private func rank(name: DrinkSearchName) -> DrinkSearchRank? {
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

    static func < (lhs: DrinkSearchRank, rhs: DrinkSearchRank) -> Bool {
        (lhs.isExact ? 0 : 1, lhs.extraLength, lhs.isPrefix ? 0 : 1)
            < (rhs.isExact ? 0 : 1, rhs.extraLength, rhs.isPrefix ? 0 : 1)
    }
}
