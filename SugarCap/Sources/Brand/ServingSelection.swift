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
    /// 반 잔. 수량 1에서 한 칸 더 내리면 켜진다(½ → 1 → 2 …). 켜져 있는 동안 quantity는 1이다.
    private(set) var isHalf = false

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

    /// 한 잔에 곱할 값. 반 잔이면 0.5.
    var cups: Double { isHalf ? 0.5 : Double(quantity) }

    var canStepDown: Bool { !isHalf }
    var canStepUp: Bool { quantity < 99 }

    mutating func stepDown() {
        if quantity > 1 { quantity -= 1 } else { isHalf = true }
    }

    mutating func stepUp() {
        if isHalf { isHalf = false } else if quantity < 99 { quantity += 1 }
    }

    /// 수량을 곱한 총량. 기록에는 이 값을 스냅샷한다(`Consumption` 주석 참고).
    var sugarG: Double? {
        serving.sugarG.map { $0 * cups }
    }

    /// 원두 선택이 있으면 그 값, 없으면 serving 값(prototype.html:347).
    var caffeineMg: Double? {
        (variant?.caffeineMg ?? serving.caffeineMg).map { $0 * cups }
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
            halfCup: isHalf,
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

    /// 같은 말의 다른 표기(2026-11-18 대표님). 검색어와 이름 양쪽을 앞의 표기로 바꿔 견준다. 접은 값, 긴 말부터.
    /// 카탈로그에 실제로 섞여 있는 표기만 넣는다. 말차·꿀처럼 다른 말은 묶지 않는다.
    static let spellings: [(variant: String, canonical: String)] = [
        ("쵸콜릿", "초코"), ("쵸콜렛", "초코"), ("초콜릿", "초코"), ("초콜렛", "초코"), ("쵸코", "초코"),
        ("그린티", "녹차"),
        ("캬라멜", "카라멜"), ("캐러멜", "카라멜"), ("캐라멜", "카라멜"),
        ("마끼아또", "마키아또"), ("마키야또", "마키아또"),
        ("라테", "라떼"),
        ("쥬스", "주스"),
        ("콜드브류", "콜드브루"),
        ("티라미슈", "티라미수"),
        ("애이드", "에이드"),
        ("요구르트", "요거트"),
    ]

    /// 띄어 쓴 낱말들(표기 묶기 후). 통째로 안 걸릴 때 순서 상관없이 낱말마다 견준다.
    let words: [String]
    /// 두벌식 자판 키 순서(`HangulKeys`). 통째·조각 일치가 하나도 없을 때 `typos`로 견준다.
    /// 영문 자판으로 친 글자("zhffk")는 키 그대로라 대소문자를 살린다(Shift 키 = 된소리·ㅒ·ㅖ).
    let keys: [UInt8]
    /// 검색어가 자음 낱자로만 돼 있으면 그 자음들("ㅋㅋㅋㄹ"). 이름의 첫소리(`DrinkSearchName.firstSounds`)와 견준다.
    let firstSounds: String?

    init(_ typed: String) {
        let text = Self.menuAliases[Self.fold(typed)] ?? typed
        needle = Self.normalize(text)
        let spaced = String(text.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) })
        keys = HangulKeys.typed(Self.spellings.reduce(spaced) { $0.replacingOccurrences(of: $1.variant, with: $1.canonical) })
        firstSounds = !spaced.isEmpty && spaced.unicodeScalars.allSatisfy { (0x3131...0x314E).contains($0.value) } ? spaced : nil
        let rawWords = text.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        words = rawWords.map(Self.normalize)
        if rawWords.count > 1, let temperature = Self.temperatureWords[rawWords[0]] {
            temperatureScope = TemperatureScope(temperature: temperature, needle: Self.normalize(rawWords.dropFirst().joined()))
        } else {
            temperatureScope = nil
        }
    }

    var isEmpty: Bool { needle.isEmpty }

    /// 자판 키 순서로 견준 틀린 키 수(2026-11-19 대표님 "검색 알고리즘이 별로면 금방 알아채").
    /// 오타("아메리카도"), 조합 중인 글자("콜ㄹ"), 한/영 자판 실수("zhffk")를 한 셈으로 잡는다.
    /// 이름 어디에 들어가도 되고, 키가 짧을수록 덜 봐준다: 4키 이하 0, 8키 이하 1, 그 위 2. 못 잡으면 nil.
    func typos(_ names: [DrinkSearchName]) -> Int? {
        guard keys.count >= 2 else { return nil }
        let allowed = keys.count <= 4 ? 0 : keys.count <= 8 ? 1 : 2
        return names.compactMap { HangulKeys.substringDistance(keys, in: $0.keys, allowed: allowed) }.min()
    }

    /// 초성 검색(2026-11-19 대표님). 걸리면 이름 첫소리가 검색어로 시작하는지, 안 걸리면 nil.
    /// 자음 하나는 이름 맨 앞만 본다. 가운데까지 보면 "ㅋ" 하나에 메뉴 수천 개가 걸린다.
    func firstSoundMatch(_ names: [DrinkSearchName]) -> (isPrefix: Bool, length: Int)? {
        guard let firstSounds else { return nil }
        let hits = names.filter { firstSounds.count == 1 ? $0.firstSounds.hasPrefix(firstSounds) : $0.firstSounds.contains(firstSounds) }
        guard let shortest = hits.map(\.firstSounds.count).min() else { return nil }
        return (hits.contains { $0.firstSounds.hasPrefix(firstSounds) }, shortest)
    }

    /// 검색 순위. 이름과 영문명 중 더 나은 쪽, 온도 말 검색이면 그쪽 일치까지 견줘 더 나은 쪽. 일치하지 않으면 nil.
    /// 온도 말 검색은 그 온도 메뉴와 온도를 나눠 싣지 않은(`both`) 메뉴만 잡고, `both`는 같은 순위 안에서 뒤로 보낸다.
    /// 통째 일치가 하나도 없을 때만 조각 일치(`scatteredRank`)를 본다.
    func rank(_ names: [DrinkSearchName], temperature: Drink.Temperature) -> DrinkSearchRank? {
        guard !needle.isEmpty else { return nil }
        let whole = names.compactMap { Self.rank(name: $0, needle: needle) }.min()
        let inScope = temperatureScope.map { temperature == $0.temperature || temperature == .both } ?? false
        let scoped = temperatureScope.flatMap { scope in
            inScope ? names.compactMap { Self.rank(name: $0, needle: scope.needle) }.min() : nil
        }
        .map { DrinkSearchRank(isExact: $0.isExact, extraLength: $0.extraLength, isPrefix: $0.isPrefix, isTemperatureGuess: temperature == .both) }
        if let best = [whole, scoped].compactMap({ $0 }).min() { return best }
        let scattered = names.compactMap { Self.scatteredRank(name: $0, pieces: words, needle: needle) }.min()
        let scopedScattered = inScope
            ? names.compactMap { Self.scatteredRank(name: $0, pieces: Array(words.dropFirst()), needle: needle) }.min()
                .map { DrinkSearchRank(isExact: false, extraLength: $0.extraLength, isPrefix: false, isTemperatureGuess: temperature == .both, isScattered: true) }
            : nil
        return [scattered, scopedScattered].compactMap { $0 }.min()
    }

    /// 조각 일치(2026-11-18 대표님 "허니자몽"으로 자몽 허니 블랙 티). 띄어 쓴 낱말마다, 그 낱말이 통째로
    /// 이름에 있거나 2글자 이상 조각으로 나눠 조각마다 이름에 있으면 걸린다. 순서는 상관없다.
    /// 1글자 조각은 쓰지 않는다("라"·"티"가 아무 메뉴에나 걸린다). 통째 일치보다 늘 아래다.
    private static func scatteredRank(name: DrinkSearchName, pieces: [String], needle: String) -> DrinkSearchRank? {
        guard !pieces.isEmpty, pieces.joined().allSatisfy(name.characters.contains) else { return nil }
        guard pieces.allSatisfy({ name.folded.contains($0) || covers(name.folded, $0) }) else { return nil }
        let length = pieces.joined().count
        return DrinkSearchRank(isExact: false, extraLength: max(0, name.folded.count - length), isPrefix: false, isScattered: true)
    }

    /// `piece`를 2글자 이상 조각들로 나눠 조각마다 `text` 안에 있게 할 수 있는가.
    private static func covers(_ text: String, _ piece: String) -> Bool {
        let chars = Array(piece)
        guard chars.count >= 4 else { return false }
        var reachable = [Bool](repeating: false, count: chars.count + 1)
        reachable[0] = true
        for start in 0..<chars.count where reachable[start] {
            for end in stride(from: start + 2, through: chars.count, by: 1) where !reachable[end] {
                if text.contains(String(chars[start..<end])) { reachable[end] = true }
            }
        }
        return reachable[chars.count]
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

    /// 접고 표기를 묶은 값. 메뉴 이름 견주기에만 쓴다(브랜드 이름은 `fold`).
    static func normalize(_ text: String) -> String {
        spellings.reduce(fold(text)) { $0.replacingOccurrences(of: $1.variant, with: $1.canonical) }
    }
}

/// 검색 순위를 매길 이름 하나. 맨 앞의 온도·"카페" 낱말을 뗀 본체(`core`)를 같이 들고 있다.
/// "아이스 카페 라떼"·"카페라떼"의 본체는 "라떼"라서 "라떼" 검색의 맨 위에 온다.
struct DrinkSearchName {
    let folded: String
    let core: String
    /// 조각 일치 앞단 거르기용. 검색어 글자가 하나라도 없으면 조각을 나눠 보지 않는다.
    let characters: Set<Character>
    let keys: [UInt8]
    /// 글자마다 첫소리("코카콜라" → "ㅋㅋㅋㄹ"). 한글이 아닌 글자는 그대로.
    let firstSounds: String

    /// 띄어 쓴 낱말 단위로만 뗀다. 붙여 쓴 이름까지 떼면 "아이스크림"이 "크림", "핫식스"가 "식스"가 된다.
    static let leadingWords: Set<String> = ["아이스", "핫", "카페", "iced", "hot", "caffe", "cafe", "café"]

    init(_ name: String) {
        folded = DrinkQuery.normalize(name)
        var words = name.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        while words.count > 1, let first = words.first, Self.leadingWords.contains(first) {
            words.removeFirst()
        }
        core = DrinkQuery.normalize(words.joined())
        characters = Set(folded)
        keys = HangulKeys.typed(folded)
        firstSounds = HangulKeys.firstSounds(folded)
    }
}

/// 한글을 두벌식 자판에서 누르는 키 순서로 푼다("콜라" → `zhffk`, "뗴" → `EP`). 겹받침·겹모음은 두 키로.
/// 한글이 아닌 글자는 그대로 둔다. 영문 자판으로 친 검색어는 키 순서 자체라 이 셈에서 한글 이름과 맞는다.
enum HangulKeys {
    private static let initials = ["r", "R", "s", "e", "E", "f", "a", "q", "Q", "t", "T", "d", "w", "W", "c", "z", "x", "v", "g"]
    private static let medials = [
        "k", "o", "i", "O", "j", "p", "u", "P", "h", "hk", "ho", "hl", "y", "n", "nj", "np", "nl", "b", "m", "ml", "l",
    ]
    private static let finals = [
        "", "r", "R", "rt", "s", "sw", "sg", "e", "f", "fr", "fa", "fq", "ft", "fx", "fv", "fg", "a", "q", "qt", "t", "T",
        "d", "w", "c", "z", "x", "v", "g",
    ]
    /// 호환 자모(ㄱ U+3131 ~ ㅣ U+3163). 조합 중인 글자가 낱자로 들어온다.
    private static let jamo = [
        "r", "R", "rt", "s", "sw", "sg", "e", "E", "f", "fr", "fa", "fq", "ft", "fx", "fv", "fg", "a", "q", "Q", "qt", "t",
        "T", "d", "w", "W", "c", "z", "x", "v", "g",
    ] + medials
    /// Shift로 치는 키. 나머지 대문자는 소문자와 같은 키다.
    private static let shifted: Set<Character> = ["Q", "W", "E", "R", "T", "O", "P"]

    static func typed(_ text: String) -> [UInt8] {
        var out = ""
        for scalar in text.unicodeScalars {
            let value = Int(scalar.value)
            if (0xAC00...0xD7A3).contains(value) {
                let index = value - 0xAC00
                out += initials[index / 588] + medials[(index % 588) / 28] + finals[index % 28]
            } else if (0x3131...0x3163).contains(value) {
                out += jamo[value - 0x3131]
            } else if scalar.isASCII, scalar.properties.isUppercase {
                let letter = Character(scalar)
                out += shifted.contains(letter) ? String(letter) : letter.lowercased()
            } else {
                out.unicodeScalars.append(scalar)
            }
        }
        return Array(out.utf8)
    }

    private static let firstSoundJamo = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ".unicodeScalars)

    static func firstSounds(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            let value = Int(scalar.value)
            out.append((0xAC00...0xD7A3).contains(value) ? firstSoundJamo[(value - 0xAC00) / 588] : scalar)
        }
        return String(out)
    }

    /// `needle`이 `text` 안 어딘가와 몇 키 다른가(삽입·삭제·바꿈 하나가 1). `allowed`보다 크면 nil.
    static func substringDistance(_ needle: [UInt8], in text: [UInt8], allowed: Int) -> Int? {
        guard !needle.isEmpty, text.count + allowed >= needle.count else { return nil }
        var previous = Array(0...needle.count)
        var current = previous
        var best = previous[needle.count]
        for byte in text {
            current[0] = 0
            for i in 1...needle.count {
                let replace = previous[i - 1] + (needle[i - 1] == byte ? 0 : 1)
                current[i] = min(replace, previous[i] + 1, current[i - 1] + 1)
            }
            best = min(best, current[needle.count])
            if best == 0 { return 0 }
            swap(&previous, &current)
        }
        return best <= allowed ? best : nil
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
    /// 검색어가 통째로가 아니라 조각으로 걸렸다("허니자몽" → 자몽 허니 블랙 티). 통째 일치보다 늘 아래.
    var isScattered = false

    static func < (lhs: DrinkSearchRank, rhs: DrinkSearchRank) -> Bool {
        (lhs.isScattered ? 1 : 0, lhs.isExact ? 0 : 1, lhs.isTemperatureGuess ? 1 : 0, lhs.extraLength, lhs.isPrefix ? 0 : 1)
            < (rhs.isScattered ? 1 : 0, rhs.isExact ? 0 : 1, rhs.isTemperatureGuess ? 1 : 0, rhs.extraLength, rhs.isPrefix ? 0 : 1)
    }
}
