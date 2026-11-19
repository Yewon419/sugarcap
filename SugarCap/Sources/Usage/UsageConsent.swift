import Foundation

/// 이용 기록 제공 동의(SPEC §9.10, 문구 `docs/CONSENT.md`). 퍼널과 음료 통계를 한 번에 묻는다.
/// 값이 없으면 아직 안 물은 것이다. 그동안 기록은 기기 안에만 쌓는다.
enum UsageConsent: Equatable, Sendable {
    case undecided
    case granted
    case declined

    static let key = "usageConsentGranted"

    /// 저장된 값(`key`)에서. 화면은 `@AppStorage(UsageConsent.key)`로 받은 `Bool?`을 넘긴다.
    init(stored: Bool?) {
        switch stored {
        case nil: self = .undecided
        case true?: self = .granted
        case false?: self = .declined
        }
    }

    static func load(from defaults: UserDefaults) -> UsageConsent {
        UsageConsent(stored: defaults.object(forKey: key) as? Bool)
    }

    static func store(granted: Bool, in defaults: UserDefaults) {
        defaults.set(granted, forKey: key)
    }
}
