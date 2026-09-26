import OSLog
import SwiftData
import SwiftUI
import UIKit

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

        Self.scaleSegmentedControlTitles()

        if SharedStore.groupContainerURL == nil {
            // 실기기에서 이 로그가 보이면 entitlement가 빠진 빌드다. 위젯이 기록을 못 읽는다.
            Logger(subsystem: "com.sugarcap.app", category: "store")
                .error("App Group이 없어 앱 전용 저장소를 쓴다(위젯은 빈 값으로 보인다).")
        }
    }

    /// 세그먼트 컨트롤(`.pickerStyle(.segmented)`) 글자는 기본이 13pt 고정이라 큰 글자에서 혼자 작게 남는다.
    /// 같은 13pt를 footnote 비율로 키우되 24pt에서 멈춘다(세 칸짜리 "100 g"이 잘리지 않는 선). 실행 중에 글자 크기를 바꾸면 다음 실행부터 반영된다.
    private static func scaleSegmentedControlTitles() {
        let metrics = UIFontMetrics(forTextStyle: .footnote)
        let appearance = UISegmentedControl.appearance()
        appearance.setTitleTextAttributes(
            [.font: metrics.scaledFont(for: .systemFont(ofSize: 13, weight: .regular), maximumPointSize: 24)], for: .normal
        )
        appearance.setTitleTextAttributes(
            [.font: metrics.scaledFont(for: .systemFont(ofSize: 13, weight: .semibold), maximumPointSize: 24)], for: .selected
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView(catalog: catalog)
        }
        .modelContainer(container)
    }
}
