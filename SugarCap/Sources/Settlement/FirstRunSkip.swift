import Foundation

/// 온보딩 영상·캐릭터 소개·첫 먹이기의 "건너뛰기"는 뺐다(대표님 2026-11-06). UI 테스트만 Debug `-uiTestSkip YES`로
/// 버튼을 다시 띄워 지나간다(영상·튜토리얼을 매번 끝까지 보면 CI가 수십 분 늘어난다). Release에서는 늘 없다.
enum FirstRunSkip {
    static var isAllowed: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "uiTestSkip")
        #else
        return false
        #endif
    }
}
