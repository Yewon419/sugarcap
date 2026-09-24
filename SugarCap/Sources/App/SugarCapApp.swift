import OSLog
import SwiftData
import SwiftUI

@main
struct SugarCapApp: App {
    /// 번들 카탈로그는 앱 수명 동안 한 번만 읽는다(약 620KB, 1,583 servings).
    private let catalog: Result<CatalogIndex, any Error>
    /// App Group 컨테이너에 둔다(§4.6). 위젯이 같은 파일을 읽는다.
    private let container: ModelContainer

    init() {
        do {
            container = try SharedStore.makeContainer()
        } catch {
            Logger(subsystem: "com.sugarcap.app", category: "store")
                .fault("저장소를 열지 못함: \(String(describing: error), privacy: .public)")
            fatalError("SwiftData 저장소를 열 수 없습니다: \(error)")
        }

        let loaded = Result { CatalogIndex(catalog: try CatalogStore.loadBundled()) }
        if case .failure(let error) = loaded {
            Logger(subsystem: "com.sugarcap.app", category: "catalog")
                .fault("번들 카탈로그 로드 실패: \(String(describing: error), privacy: .public)")
        }
        catalog = loaded

        if SharedStore.groupContainerURL == nil {
            // 실기기에서 이 로그가 보이면 entitlement가 빠진 빌드다. 위젯이 기록을 못 읽는다.
            Logger(subsystem: "com.sugarcap.app", category: "store")
                .error("App Group이 없어 앱 전용 저장소를 쓴다(위젯은 빈 값으로 보인다).")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(catalog: catalog)
        }
        .modelContainer(container)
    }
}
