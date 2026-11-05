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
        shifted(Date(), by: dayOffset)
    }

    static func shifted(_ date: Date, by days: Int) -> Date {
        guard days != 0 else { return date }
        return Calendar.current.date(byAdding: .day, value: days, to: date) ?? date
    }
}
