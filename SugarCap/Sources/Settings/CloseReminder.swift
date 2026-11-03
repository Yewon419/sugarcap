import OSLog
import UserNotifications

/// 하루 알림 네 개(2026-11-03 대표님, 설정 스위치 하나로 켜고 끈다). 기기 안에서만 예약하는 로컬 알림이다(서버 없음, §1).
/// 아침 8:30·오후 2시는 커피 사는 시간에 기록을, 저녁 8시는 마감이 열렸다고, 밤 10시는 아직 안 먹였으면 먹이라고 알린다.
/// 밤 10시는 먹인 날 울리면 안 되는데 로컬 알림은 울릴 때 조건을 못 보므로, 앞으로 `horizonDays`일치를 날짜별로 예약해 두고
/// 먹이면 그날 것만 지운다. 문구는 날마다 돌려 쓴다. 앱을 열 때마다 다시 예약하므로 그 기간 넘게 안 열면 알림도 멈춘다.
/// 이름은 처음 마감 알림만 있던 때(2026-10-05) 그대로다. 켜짐 저장 키도 그대로라 그때 켠 사람은 네 개를 다 받는다.
@MainActor
enum CloseReminder {
    static let enabledKey = "closeReminderEnabled"
    /// 첫 마감 뒤 한 번만 묻는다. 답과 상관없이 물었으면 참.
    static let askedKey = "closeReminderAsked"

    /// 마지막으로 오늘 마감(먹이기)을 한 날(`DayKey.rawValue`). 그날 밤 10시 알림을 다시 예약하지 않는다.
    private static let fedDayKey = "reminderFedDay"
    private static let horizonDays = 7
    private static let requestPrefix = "reminder-"
    /// 2026-11-03 전 매일 반복 마감 알림. 다시 예약할 때 같이 지운다.
    private static let legacyRequestID = "close-reminder"
    private static let testRequestID = "close-reminder-test"
    private static let logger = Logger(subsystem: "com.sugarcap.app", category: "reminder")

    /// 권한을 묻고(이미 정했으면 그 값), 허락되면 켠다. 허락 여부를 돌려준다.
    static func enable() async -> Bool {
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
        await schedule(now: Date())
        return true
    }

    static func disable() {
        UserDefaults.standard.set(false, forKey: enabledKey)
        Task { await removeScheduled() }
    }

    /// 앱이 앞으로 올 때마다. 켜져 있지 않으면 아무것도 하지 않는다.
    /// iOS 설정에서 알림을 꺼 버렸으면 앱 쪽 스위치도 끈다.
    static func refresh() async {
        guard UserDefaults.standard.bool(forKey: enabledKey) else { return }
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            disable()
            return
        }
        await schedule(now: Date())
    }

    /// 오늘 마감(먹이기)을 했다. 그날 밤 10시 "아직 안 먹였어요"를 지운다(테스트 카드 먹이기는 부르지 않는다).
    static func markFed(_ day: DayKey) {
        UserDefaults.standard.set(day.rawValue, forKey: fedDayKey)
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [requestID(day, .notFed)]
        )
    }

    /// 설정 테스트 카드(TestFlight·Debug): 저녁 8시 문구의 알림을 10초 뒤 한 번 보낸다. 알림 스위치와 따로다.
    /// 권한이 없으면 묻는다. 거절됐거나 예약에 실패하면 거짓.
    static func sendTest() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            guard try await center.requestAuthorization(options: [.alert, .sound]) else { return false }
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)
            let content = ReminderSlot.close.content(variant: 0)
            try await center.add(UNNotificationRequest(identifier: testRequestID, content: content, trigger: trigger))
            return true
        } catch {
            logger.error("테스트 알림 예약 실패: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    private static func requestID(_ day: DayKey, _ slot: ReminderSlot) -> String {
        "\(requestPrefix)\(day.rawValue)-\(slot.rawValue)"
    }

    private static func removeScheduled() async {
        let center = UNUserNotificationCenter.current()
        let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(requestPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids + [legacyRequestID])
    }

    /// 오늘부터 `horizonDays`일, 아직 안 지난 시각만 날짜별로 예약한다. 이미 먹인 날의 밤 10시는 뺀다.
    private static func schedule(now: Date) async {
        await removeScheduled()
        let calendar = Calendar.current
        let center = UNUserNotificationCenter.current()
        let fedDay = UserDefaults.standard.string(forKey: fedDayKey)
        let today = calendar.startOfDay(for: now)
        for offset in 0..<horizonDays {
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else {
                logger.fault("알림 날짜 계산 실패(+\(offset)일)")
                continue
            }
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            let day = DayKey(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0)
            let ordinal = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
            for slot in ReminderSlot.allCases {
                if slot == .notFed && day.rawValue == fedDay { continue }
                var components = parts
                components.hour = slot.hour
                components.minute = slot.minute
                guard let fireDate = calendar.date(from: components), fireDate > now else { continue }
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let request = UNNotificationRequest(
                    identifier: requestID(day, slot), content: slot.content(variant: ordinal), trigger: trigger
                )
                do {
                    try await center.add(request)
                } catch {
                    logger.error("알림 예약 실패(\(request.identifier, privacy: .public)): \(String(describing: error), privacy: .public)")
                }
            }
        }
    }
}

/// 하루 알림 시각. 저녁 8시는 마감이 열리는 시각(`AppSettings.closeFromHour` 기본값, 설정에서 못 바꾼다)과 같다.
enum ReminderSlot: String, CaseIterable {
    case morning
    case afternoon
    case close
    case notFed

    var hour: Int {
        switch self {
        case .morning: 8
        case .afternoon: 14
        case .close: 20
        case .notFed: 22
        }
    }

    var minute: Int { self == .morning ? 30 : 0 }

    /// 날마다 문구를 돌려 쓴다(`variant`는 날짜 순번).
    func content(variant: Int) -> UNMutableNotificationContent {
        let lines = copies
        let (title, body) = lines[((variant % lines.count) + lines.count) % lines.count]
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        // 전용 알림음(대표님 2026-11-03): 아이스 커피 잔 속 얼음이 구르는 0.7초. ElevenLabs SFX v2로 만든 `Resources/Sounds`.
        content.sound = UNNotificationSound(named: UNNotificationSoundName("notification-ice.caf"))
        return content
    }

    private var copies: [(String, String)] {
        switch self {
        case .morning:
            [
                (String(localized: "커피 사러 가는 길이에요?"), String(localized: "주문하기 전에 오늘 남은 양부터 봐요.")),
                (String(localized: "아침 커피 한 잔 했어요?"), String(localized: "마셨으면 슈가캡에 담아 둬요.")),
                (String(localized: "오늘 첫 잔은 뭐예요?"), String(localized: "고르기 전에 남은 당과 카페인을 한 번 봐요.")),
                (String(localized: "출근길에 카페 들를 거예요?"), String(localized: "샷 추가 전에 오늘 기준을 확인해요.")),
            ]
        case .afternoon:
            [
                (String(localized: "오후 카페 시간이에요"), String(localized: "마시기 전에 남은 양부터 봐요.")),
                (String(localized: "점심 먹고 한 잔 할 거예요?"), String(localized: "달달한 음료면 당이 얼마나 남았는지 먼저 봐요.")),
                (String(localized: "졸린 오후죠"), String(localized: "커피 한 잔 더 마셔도 되는지 슈가캡에서 봐요.")),
                (String(localized: "오전에 마신 건 다 담았어요?"), String(localized: "빠뜨린 음료가 있으면 지금 기록해요.")),
            ]
        case .close:
            [
                (
                    String(localized: "오늘 마감할 시간이에요"),
                    String(localized: "남은 당과 카페인을 \(CupSide.sugar.characterNameWithGwa) \(CupSide.caffeine.characterName)에게 먹여 줘요.")
                ),
                (String(localized: "먹이기가 열렸어요"), String(localized: "오늘 남긴 당과 카페인을 먹여 줘요.")),
                (String(localized: "오늘 하루 어땠어요?"), String(localized: "마감하고 남은 만큼 먹여 줘요.")),
            ]
        case .notFed:
            [
                (String(localized: "아직 안 먹였어요"), String(localized: "자기 전에 오늘 남은 걸 먹여 줘요.")),
                (
                    String(localized: "\(CupSide.sugar.characterNameWithGwa) \(CupSide.caffeine.characterNameWithIga) 기다려요"),
                    String(localized: "오늘 마감을 아직 안 했어요. 남은 당과 카페인을 먹여 줘요.")
                ),
                (String(localized: "잊은 거 없죠?"), String(localized: "오늘 마감이 아직 열려 있어요. 남은 양을 먹여 줘요.")),
            ]
        }
    }
}
