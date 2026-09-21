import SwiftUI

/// 앱 루트. Phase 1은 오늘 화면 하나다.
/// 탭 바(오늘·추이·설정)와 온보딩 분기는 Phase 2에서 여기에 붙는다(SPEC §4·§4.5).
struct RootView: View {
    var body: some View {
        TodayView()
    }
}

#Preview {
    RootView()
        .modelContainer(for: [Entry.self, AppSettings.self], inMemory: true)
}
