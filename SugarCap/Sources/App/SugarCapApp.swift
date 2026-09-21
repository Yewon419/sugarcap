import OSLog
import SwiftData
import SwiftUI

@main
struct SugarCapApp: App {
    /// 번들 카탈로그는 앱 수명 동안 한 번만 읽는다(약 620KB, 1,583 servings).
    private let catalog: Result<CatalogIndex, any Error>

    init() {
        let loaded = Result { CatalogIndex(catalog: try CatalogStore.loadBundled()) }
        if case .failure(let error) = loaded {
            Logger(subsystem: "com.sugarcap.app", category: "catalog")
                .fault("번들 카탈로그 로드 실패: \(String(describing: error), privacy: .public)")
        }
        catalog = loaded
    }

    var body: some Scene {
        WindowGroup {
            RootView(catalog: catalog)
        }
        .modelContainer(for: [Entry.self, AppSettings.self])
    }
}
