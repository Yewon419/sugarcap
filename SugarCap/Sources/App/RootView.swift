import SwiftUI

/// 앱 루트. Phase 1은 오늘 화면 하나다.
/// 탭 바(오늘·추이·설정)와 온보딩 분기는 Phase 2에서 여기에 붙는다(SPEC §4·§4.5).
struct RootView: View {
    let catalog: Result<CatalogIndex, any Error>

    var body: some View {
        switch catalog {
        case .success(let index):
            TodayView(catalog: index)
        case .failure(let error):
            // 번들 카탈로그가 깨졌다는 건 빌드가 잘못 나갔다는 뜻이다. 숨기지 않고 보여준다.
            ContentUnavailableView(
                "메뉴 데이터를 읽지 못했어요",
                systemImage: "exclamationmark.triangle",
                description: Text(String(describing: error))
            )
        }
    }
}

#Preview {
    RootView(catalog: Result { CatalogIndex(catalog: try CatalogStore.loadBundled()) })
        .modelContainer(for: [Entry.self, AppSettings.self], inMemory: true)
}
