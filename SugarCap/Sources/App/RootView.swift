import OSLog
import SwiftData
import SwiftUI

/// 시작 화면. 하단 탭은 없다(2026-10-05 대표님): 오늘이 집이고, 추이는 오늘 위로 밀어 넣고, 설정은 시트로 연다.
enum AppTab: String {
    case today
    case trends
    case settings

    /// CI 스크린샷이 `simctl launch … -initialTab settings`로 시작 화면을 고른다(추이는 밀어 넣은 채, 설정은 시트를 연 채).
    /// 실행 인자 도메인이라 저장되지 않는다. 인자가 없으면 오늘이다.
    static var initial: AppTab {
        UserDefaults.standard.string(forKey: "initialTab").flatMap(AppTab.init(rawValue:)) ?? .today
    }
}

/// 앱 루트. 온보딩을 마치기 전에는 온보딩만, 마친 뒤에는 오늘 화면만 그린다.
/// 온보딩은 스택에 쌓지 않고 통째로 갈아 끼우므로 뒤로 돌아갈 수 없다(§4.5).
struct RootView: View {
    let catalog: Result<CatalogIndex, any Error>

    @Environment(\.modelContext) private var context
    @AppStorage(OnboardingView.completedKey) private var onboardingCompleted = false
    @State private var pro = ProStore.make()

    private static let logger = Logger(subsystem: "com.sugarcap.app", category: "root")

    var body: some View {
        Group {
            switch catalog {
            case .success(let index):
                if onboardingCompleted {
                    TodayView(catalog: index)
                } else {
                    OnboardingView(brands: index.catalog.brands) {
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
        .environment(pro)
        .task {
            ensureSettings()
            seedDemoIfRequested()
            pro.start()
        }
    }

    /// 스토어 스크린샷용 데모 기록(Debug 빌드만). 어느 화면으로 시작하든 돌아야 해서 루트에 둔다.
    private func seedDemoIfRequested() {
        #if DEBUG
        do {
            let settings = try AppSettings.current(in: context)
            DemoData.seedGoalIfRequested(into: context, settings: settings)
            guard DemoData.isRequested else { return }
            DemoData.seed(into: context, boundaryHour: settings.dayBoundaryHour)
        } catch {
            Self.logger.error("데모 시드 실패: \(String(describing: error), privacy: .public)")
        }
        #endif
    }

    /// 설정 행은 앱 전체에서 하나다. 오늘·설정 둘 다 읽으므로 루트에서 한 번 만든다.
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
        .modelContainer(for: [Entry.self, AppSettings.self, DaySettlement.self, Affinity.self, ReductionGoal.self, FavoriteDrink.self], inMemory: true)
}
