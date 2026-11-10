import Foundation
import SwiftData

/// 앱과 위젯이 함께 쓰는 저장소(SPEC §4.6). App Group 컨테이너에 둬야 위젯이 기록을 읽는다.
///
/// App Group id는 개발자 계정에 등록된 값과 같아야 한다(2026-09-24 등록).
/// 바꾸면 기존 기기의 기록이 통째로 안 보인다.
enum SharedStore {
    static let appGroupID = "group.com.sugarcap.app"

    static let schema = Schema([
        Entry.self, AppSettings.self, DaySettlement.self, Affinity.self, ReductionGoal.self, FavoriteDrink.self,
        GiftEvent.self, TradeOffer.self, FavoriteBrand.self,
    ])

    /// App Group이 실제로 붙어 있는지. entitlement가 없으면 nil이다.
    ///
    /// **SwiftData는 없는 App Group을 지정하면 예외가 아니라 그 자리에서 죽는다**
    /// (`Unable to find App Group Container in Entitlements`). 그래서 만들기 전에 먼저 본다.
    /// CI 시뮬레이터처럼 entitlement가 안 박히는 환경에서는 앱 전용 저장소로 물러난다.
    static var groupContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    static func makeContainer() throws -> ModelContainer {
        let configuration =
            groupContainerURL == nil
            ? ModelConfiguration(schema: schema)
            : ModelConfiguration(schema: schema, groupContainer: .identifier(appGroupID))
        return try ModelContainer(for: schema, configurations: configuration)
    }
}

/// 위젯이 읽어야 하는 작은 값들. SwiftData에 넣을 만한 것이 아니라 공용 UserDefaults에 둔다.
enum SharedDefaults {
    private static let isProKey = "isPro"

    static var store: UserDefaults? {
        UserDefaults(suiteName: SharedStore.appGroupID)
    }

    /// 위젯은 Pro 기능이다(§6). 권한 판정은 앱이 하고 결과만 넘긴다. 출시 무료 기간(`LaunchPricing`)에는 늘 열린다.
    static var isPro: Bool {
        get { LaunchPricing.everythingFree || (store?.bool(forKey: isProKey) ?? false) }
        set { store?.set(newValue, forKey: isProKey) }
    }

    /// 면마다 고른 잔(`cupSet.<면>`, §4.10)을 두는 곳. 위젯도 같은 잔을 그려야 해서 공용 저장소에 둔다.
    /// App Group이 없으면(CI 시뮬레이터) 앱 기본 저장소.
    static var cupSetStore: UserDefaults {
        store ?? .standard
    }

    /// 고른 잔 id. Debug 실행 인자(`-cupSet.sugar choco-frappe`)는 앱 기본 저장소의 인자 도메인으로만 들어오니 먼저 본다.
    static func cupSet(forKey key: String) -> String? {
        if let argument = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)[key] as? String {
            return argument
        }
        return cupSetStore.string(forKey: key)
    }
}
