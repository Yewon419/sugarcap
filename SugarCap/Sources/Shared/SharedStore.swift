import Foundation
import SwiftData

/// 앱과 위젯이 함께 쓰는 저장소(SPEC §4.6). App Group 컨테이너에 둬야 위젯이 기록을 읽는다.
///
/// App Group id는 개발자 계정에 등록된 값과 같아야 한다(2026-09-24 등록).
/// 바꾸면 기존 기기의 기록이 통째로 안 보인다.
enum SharedStore {
    static let appGroupID = "group.com.sugarcap.app"

    static let schema = Schema([
        Entry.self, AppSettings.self, DaySettlement.self, Affinity.self, ReductionGoal.self,
    ])

    static func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema, groupContainer: .identifier(appGroupID)
        )
        return try ModelContainer(for: schema, configurations: configuration)
    }
}

/// 위젯이 읽어야 하는 작은 값들. SwiftData에 넣을 만한 것이 아니라 공용 UserDefaults에 둔다.
enum SharedDefaults {
    private static let isProKey = "isPro"

    static var store: UserDefaults? {
        UserDefaults(suiteName: SharedStore.appGroupID)
    }

    /// 위젯은 Pro 기능이다(§6). 권한 판정은 앱이 하고 결과만 넘긴다.
    static var isPro: Bool {
        get { store?.bool(forKey: isProKey) ?? false }
        set { store?.set(newValue, forKey: isProKey) }
    }
}
