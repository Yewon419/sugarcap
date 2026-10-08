import Foundation

/// 메뉴 카탈로그의 나라(SPEC §9.9). 나라마다 번들 카탈로그가 따로 있고, 앱은 고른 나라 하나만 읽는다.
/// 앱 언어와는 따로 간다(미국에 사는 한국어 사용자도 미국 메뉴를 고를 수 있다).
enum MenuCountry: String, CaseIterable, Sendable {
    case kr
    case us
    case tw

    /// 번들 리소스 이름(`data/catalog.json`, `data/catalog-us.json`, `data/catalog-tw.json`). 한국은 기존 이름을 그대로 쓴다.
    var catalogResourceName: String {
        switch self {
        case .kr: "catalog"
        case .us: "catalog-us"
        case .tw: "catalog-tw"
        }
    }

    var name: String {
        switch self {
        case .kr: String(localized: "한국")
        case .us: String(localized: "미국")
        case .tw: String(localized: "대만")
        }
    }

    /// 카페인 하루 권고량 칩에 붙는 근거 기관(SPEC §3, 미국·대만은 §9.9). 당 50g은 세 나라 다 WHO.
    var caffeineAdviceNote: String {
        switch self {
        case .kr: String(localized: "식약처 권고")
        case .us: String(localized: "FDA 권고")
        case .tw: String(localized: "대만 식약서 권고")
        }
    }

    /// 그 기관이 권고하는 성인 하루 카페인. 한국 식약처·미국 FDA 400mg, 대만 식약서(食藥署) 300mg.
    var caffeineAdviceMg: Double {
        switch self {
        case .kr, .us: 400
        case .tw: 300
        }
    }

    /// 사용자가 고른 적이 없으면 기기 지역을 따른다. 카탈로그가 없는 지역은 한국이다.
    static func resolve(storedCode: String?, region: Locale.Region?) -> MenuCountry {
        if let storedCode, let stored = MenuCountry(rawValue: storedCode) {
            return stored
        }
        switch region {
        case .unitedStates: return .us
        case .taiwan: return .tw
        default: return .kr
        }
    }
}
