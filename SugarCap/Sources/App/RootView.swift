import OSLog
import SwiftData
import SwiftUI

/// 탭 식별자. 탭 간 슬라이드 없음, 각 탭이 자기 스택을 가진다(SPEC §4).
enum AppTab: String {
    case today
    case trends
    case settings

    /// CI 스크린샷이 `simctl launch … -initialTab settings`로 시작 탭을 고른다.
    /// 실행 인자 도메인이라 저장되지 않는다. 인자가 없으면 오늘 탭이다.
    static var initial: AppTab {
        UserDefaults.standard.string(forKey: "initialTab").flatMap(AppTab.init(rawValue:)) ?? .today
    }
}

/// 앱 루트. 온보딩을 마치기 전에는 온보딩만, 마친 뒤에는 탭만 그린다.
/// 온보딩은 스택에 쌓지 않고 통째로 갈아 끼우므로 뒤로 돌아갈 수 없다(§4.5).
struct RootView: View {
    let catalog: Result<CatalogIndex, any Error>

    @Environment(\.modelContext) private var context
    @AppStorage(OnboardingView.completedKey) private var onboardingCompleted = false
    @State private var tab = AppTab.initial

    private static let logger = Logger(subsystem: "com.sugarcap.app", category: "root")

    var body: some View {
        Group {
            switch catalog {
            case .success(let index):
                if onboardingCompleted {
                    tabs(index)
                } else {
                    OnboardingView {
                        withAnimation(.easeOut(duration: 0.25)) { onboardingCompleted = true }
                    }
                }
            case .failure(let error):
                // 번들 카탈로그가 깨졌다는 건 빌드가 잘못 나갔다는 뜻이다. 숨기지 않고 보여준다.
                ContentUnavailableView(
                    "메뉴 데이터를 읽지 못했어요",
                    systemImage: "exclamationmark.triangle",
                    description: Text(String(describing: error))
                )
            }
        }
        .task { ensureSettings() }
    }

    private func tabs(_ index: CatalogIndex) -> some View {
        TabView(selection: $tab) {
            TodayView(catalog: index)
                .tabItem { Label("오늘", systemImage: "cup.and.saucer") }
                .tag(AppTab.today)
            TrendsView()
                .tabItem { Label("추이", systemImage: "chart.bar") }
                .tag(AppTab.trends)
            SettingsView(catalog: index.catalog)
                .tabItem { Label("설정", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
    }

    /// 설정 행은 앱 전체에서 하나다. 오늘·설정 탭 둘 다 읽으므로 루트에서 한 번 만든다.
    private func ensureSettings() {
        do {
            _ = try AppSettings.current(in: context)
            try context.save()
        } catch {
            // 실패해도 화면은 기본 기준(§3)으로 돈다. 설정 저장만 안 되는 상태다.
            Self.logger.error("설정 행을 만들지 못함: \(String(describing: error), privacy: .public)")
        }
    }
}

#Preview {
    RootView(catalog: Result { CatalogIndex(catalog: try CatalogStore.loadBundled()) })
        .modelContainer(for: [Entry.self, AppSettings.self, DaySettlement.self, Affinity.self, ReductionGoal.self], inMemory: true)
}
