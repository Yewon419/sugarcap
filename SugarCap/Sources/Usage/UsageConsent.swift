import Foundation

/// 이용 기록 제공 동의(SPEC §9.10, 문구 `docs/CONSENT.md`). 퍼널과 음료 통계를 한 번에 묻는다.
/// 값이 없으면 아직 안 물은 것이다. 그동안 기록은 기기 안에만 쌓는다.
enum UsageConsent: Equatable, Sendable {
    case undecided
    case granted
    case declined

    static let key = "usageConsentGranted"

    static func load(from defaults: UserDefaults) -> UsageConsent {
        guard let granted = defaults.object(forKey: key) as? Bool else {
            return .undecided
        }
        return granted ? .granted : .declined
    }

    static func store(granted: Bool, in defaults: UserDefaults) {
        defaults.set(granted, forKey: key)
    }
}
