import Foundation

/// 달력 기준 "지금". 개발자 모드 "하루 넘기기"(대표님 2026-11-05)가 쌓은 날 수만큼 앞당긴다.
/// 기록 시각·하루 경계·마감처럼 날짜를 정하는 곳만 쓴다. 연출 타이머·알림 예약은 실제 시각(`Date()`)을 쓴다.
/// 위젯도 같은 날을 보도록 App Group에 둔다. 앱 초기화가 App Group 값을 지우면 0으로 돌아온다.
enum AppClock {
    static let dayOffsetKey = "devDayOffset"

    static var dayOffset: Int {
        SharedDefaults.store?.integer(forKey: dayOffsetKey) ?? 0
    }

    static var now: Date {
        shifted(base, by: dayOffset)
    }

    /// UI 테스트 시계(`-uiClockStart <테스트 시작 epoch 초>`, Debug만). 테스트 시작이 속한 하루의 정오에서 실제로 흐른 만큼만 간다.
    /// CI가 하루 경계(04시)를 지나면 테스트 도중 날이 바뀌어 선물 상자가 생기고, 뒤 테스트가 잠긴 버튼에 막혔다(2026-11-22 04:00 UTC).
    /// 정오부터 다음 경계까지 16시간이라 CI 한 번(2시간 안쪽)에는 날이 안 바뀐다.
    private static let uiTestStart: Date? = {
        #if DEBUG
        let seconds = UserDefaults.standard.double(forKey: "uiClockStart")
        return seconds > 0 ? Date(timeIntervalSince1970: seconds) : nil
        #else
        return nil
        #endif
    }()

    private static var base: Date {
        guard let start = uiTestStart else { return Date() }
        let calendar = Calendar.current
        // 경계 전 새벽에 시작하면 앱의 "오늘"은 전날이다. 기본 경계 4시 기준으로 그날 정오를 잡는다.
        let day = calendar.startOfDay(for: start.addingTimeInterval(-4 * 3600))
        let noon = calendar.date(byAdding: .hour, value: 12, to: day) ?? start
        return noon.addingTimeInterval(Date().timeIntervalSince(start))
    }

    static func shifted(_ date: Date, by days: Int) -> Date {
        guard days != 0 else { return date }
        return Calendar.current.date(byAdding: .day, value: days, to: date) ?? date
    }
}
