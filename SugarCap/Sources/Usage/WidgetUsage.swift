import OSLog
import WidgetKit

/// 위젯을 몇 개 올려 두었는지(SPEC §9.10 8). 앱이 앞으로 올 때 확인하고, 지난번과 다를 때만 남긴다.
extension UsageReporter {
    static let widgetCountKey = "usageWidgetCount"

    private static let widgetLogger = Logger(subsystem: "com.sugarcap.app", category: "usage")

    func noteWidgets() async {
        let count: Int
        do {
            count = try await Self.installedWidgetCount()
        } catch {
            Self.widgetLogger.error("위젯 목록 확인 실패: \(String(describing: error), privacy: .public)")
            return
        }
        guard defaults.object(forKey: Self.widgetCountKey) as? Int != count else { return }
        defaults.set(count, forKey: Self.widgetCountKey)
        log(UsageEvents.widgetState(count: count))
    }

    /// 배포 대상이 iOS 17이라 async `currentConfigurations()`(iOS 18+) 대신 완료 처리기판을 감싼다.
    private static func installedWidgetCount() async throws -> Int {
        try await withCheckedThrowingContinuation { continuation in
            WidgetCenter.shared.getCurrentConfigurations { result in
                continuation.resume(with: result.map(\.count))
            }
        }
    }
}
