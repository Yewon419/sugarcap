import Foundation

/// 메뉴 카탈로그의 나라(SPEC §9.9). 나라마다 번들 카탈로그가 따로 있고, 앱은 고른 나라 하나만 읽는다.
/// 앱 언어와는 따로 간다(미국에 사는 한국어 사용자도 미국 메뉴를 고를 수 있다).
enum MenuCountry: String, CaseIterable, Sendable {
    case kr
    case us

    /// 번들 리소스 이름(`data/catalog.json`, `data/catalog-us.json`). 한국은 기존 이름을 그대로 쓴다.
    var catalogResourceName: String {
        switch self {
        case .kr: "catalog"
        case .us: "catalog-us"
        }
    }

    /// 사용자가 고른 적이 없으면 기기 지역을 따른다. 카탈로그가 없는 지역은 한국이다.
    static func resolve(storedCode: String?, region: Locale.Region?) -> MenuCountry {
        if let storedCode, let stored = MenuCountry(rawValue: storedCode) {
            return stored
        }
        return region == .unitedStates ? .us : .kr
    }
}
