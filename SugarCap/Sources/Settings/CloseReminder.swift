import OSLog
import UserNotifications

/// 마감 알림(2026-10-05 대표님 "밤에 먹이기 버튼 활성화될 때"). 매일 마감 가능 시각 정각에 한 번 울린다.
/// 마감은 그 시각 전에는 못 하므로 이미 마감한 날 울릴 일이 없어 매일 반복 알림 하나로 충분하다.
/// 기기 안에서만 예약하는 로컬 알림이다(서버 없음, §1).
@MainActor
enum CloseReminder {
    static let enabledKey = "closeReminderEnabled"
    /// 첫 마감 뒤 한 번만 묻는다. 답과 상관없이 물었으면 참.
    static let askedKey = "closeReminderAsked"

    private static let requestID = "close-reminder"
    private static let logger = Logger(subsystem: "com.sugarcap.app", category: "reminder")

    /// 권한을 묻고(이미 정했으면 그 값), 허락되면 켠다. 허락 여부를 돌려준다.
    static func enable(closeFromHour: Int) async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            guard try await center.requestAuthorization(options: [.alert, .sound]) else {
                UserDefaults.standard.set(false, forKey: enabledKey)
                return false
            }
        } catch {
            logger.error("알림 권한 요청 실패: \(String(describing: error), privacy: .public)")
            UserDefaults.standard.set(false, forKey: enabledKey)
            return false
        }
        UserDefaults.standard.set(true, forKey: enabledKey)
        await schedule(closeFromHour: closeFromHour)
        return true
    }

    static func disable() {
        UserDefaults.standard.set(false, forKey: enabledKey)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [requestID])
    }

    /// 마감 시각을 바꿨거나 앱을 열 때. 켜져 있지 않으면 아무것도 하지 않는다.
    /// iOS 설정에서 알림을 꺼 버렸으면 앱 쪽 스위치도 끈다.
    static func refresh(closeFromHour: Int) async {
        guard UserDefaults.standard.bool(forKey: enabledKey) else { return }
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            disable()
            return
        }
        await schedule(closeFromHour: closeFromHour)
    }

    private static func schedule(closeFromHour: Int) async {
        let content = UNMutableNotificationContent()
        content.title = "오늘 마감할 시간이에요"
        content.body = "남은 당과 카페인을 로슈와 카인에게 먹여 줘요."
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: DateComponents(hour: closeFromHour, minute: 0), repeats: true
        )
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [requestID])
        do {
            try await center.add(UNNotificationRequest(identifier: requestID, content: content, trigger: trigger))
        } catch {
            logger.error("마감 알림 예약 실패(\(closeFromHour)시): \(String(describing: error), privacy: .public)")
        }
    }
}
