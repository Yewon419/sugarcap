import Foundation
import OSLog
import StoreKit

/// 얼리버드 선물(2026 특전, 대표님 2026-11-05). 2026년(한국 시각)에 앱을 처음 받은 사람은 스탬프 7칸에서
/// 유리 공예 잔 두 개(`TradeCatalog.perks`)를 받는다. 지급은 `GiftStore.grantEarlyBird`.
enum EarlyBird {
    static let year = 2026
    /// 판정 결과(UserDefaults Bool). 한 번 확인하면 다시 묻지 않는다. Debug·CI는 실행 인자 `-earlyBird YES|NO`로 덮는다.
    static let key = "earlyBird"
    /// 스탬프판에서 받는 무대(`StampCardView`)를 본 적 있는지. 판정이 늦게 와 7칸을 지나서 받은 사람도 한 번은 본다.
    static let seenKey = "earlyBirdSeen"
    private static let logger = Logger(subsystem: "com.sugarcap.app", category: "gift")

    /// 처음 받은 날이 한국 시각으로 2026년인지.
    static func isEarly(firstDownload: Date) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        return calendar.component(.year, from: firstDownload) == year
    }

    /// 저장된 판정. 아직 모르면 nil.
    static func known(_ defaults: UserDefaults = .standard) -> Bool? {
        defaults.object(forKey: key) == nil ? nil : defaults.bool(forKey: key)
    }

    /// 저장된 판정, 없으면 앱 영수증(`AppTransaction`)으로 정해 저장한다. 못 읽으면 nil(다음에 다시 본다).
    /// 샌드박스(TestFlight)·Xcode 실행은 처음 받은 날이 늘 2013-08-01로 와서 날짜로 못 가린다. App Store 빌드가 아니면 대상으로 본다.
    static func resolve(_ defaults: UserDefaults = .standard) async -> Bool? {
        if let known = known(defaults) { return known }
        #if DEBUG
        // 시뮬레이터에서 앱 영수증을 읽으면 Apple 계정 로그인 창이 떠 CI 스크린샷을 덮는다(빌드 407 무렵 전 장).
        // Debug는 CI 전용이라 `-earlyBird` 인자로만 정한다.
        return nil
        #else
        do {
            switch try await AppTransaction.shared {
            case .verified(let transaction):
                let early = transaction.environment != .production || isEarly(firstDownload: transaction.originalPurchaseDate)
                defaults.set(early, forKey: key)
                return early
            case .unverified(_, let error):
                logger.error("얼리버드 판정: 앱 영수증 검증 실패 \(String(describing: error), privacy: .public)")
                return nil
            }
        } catch {
            logger.error("얼리버드 판정: 앱 영수증 읽기 실패 \(String(describing: error), privacy: .public)")
            return nil
        }
        #endif
    }
}
