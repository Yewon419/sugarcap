import Foundation

/// 월 추이 달력(2026-10-27 이식, 프로토 `design/proto/trends-month-dump.html`). 순수 계산만 둔다.
/// 칸 = 그날 **먹은** 양(남긴 양 아님, 2026-10-27 대표님), 사진 5단계. 합계 = 실물 환산 + 지난달 하루 평균 비교.
struct MonthPage: Equatable, Sendable {
    struct Cell: Equatable, Sendable, Identifiable {
        let day: DayKey
        /// 그날 먹은 양. 기록 없는 지난날과 오늘 이후는 nil(사진 없음). 오늘은 기록이 없어도 0이다.
        let used: Double?
        let isFuture: Bool
        let isToday: Bool
        var id: String { day.rawValue }
    }

    let year: Int
    let month: Int
    let cells: [Cell]
    /// 1일이 무슨 요일인지(일=0). 달력 앞 빈칸 수.
    let leadingBlanks: Int
    /// 이 달 먹은 양의 합(기록한 날과 오늘).
    let eaten: Double
    /// 기록한 날 하루 평균. 기록이 하루도 없으면 nil.
    let dailyAverage: Double?

    /// 칸 사진 단계(프로토 `step`): 0 · 30 · 50 · 80 · 100. 기준에 대한 비율로 나눈다.
    static func step(used: Double, limit: Double) -> Int {
        guard limit > 0 else { return used > 0 ? 100 : 0 }
        let ratio = used / limit
        switch ratio {
        case ...0: return 0
        case 1...: return 100
        case ..<0.4: return 30
        case ..<0.65: return 50
        default: return 80
        }
    }

    /// `upto`일까지만 본 하루 평균. 이번 달을 지난달 같은 날까지와 비교할 때 쓴다(지난달 이맘때).
    static func make(
        entries: [Entry], boundaryHour: Int, year: Int, month: Int, today: DayKey, side: CupSide,
        upto: Int? = nil, calendar: Calendar = .current
    ) -> MonthPage {
        let first = DayKey(year: year, month: month, day: 1)
        let next = month == 12 ? DayKey(year: year + 1, month: 1, day: 1) : DayKey(year: year, month: month + 1, day: 1)
        let count = first.days(until: next, calendar: calendar)
        var totals: [DayKey: Double] = [:]
        for entry in entries {
            let key = entry.dayKey(boundaryHour: boundaryHour, calendar: calendar)
            guard key.year == year, key.month == month else { continue }
            totals[key, default: 0] += side == .sugar ? (entry.sugarG ?? 0) : (entry.caffeineMg ?? 0)
        }
        let cells = (0..<count).map { offset -> Cell in
            let day = first.shifted(by: offset, calendar: calendar)
            let isFuture = day > today
            let used: Double? = isFuture ? nil : (totals[day] ?? (day == today ? 0 : nil))
            return Cell(day: day, used: used, isFuture: isFuture, isToday: day == today)
        }
        let counted = cells.filter { cell in cell.used != nil && (upto.map { cell.day.day <= $0 } ?? true) }
        let eaten = cells.compactMap(\.used).reduce(0, +)
        let average = counted.isEmpty ? nil : counted.compactMap(\.used).reduce(0, +) / Double(counted.count)
        return MonthPage(
            year: year, month: month, cells: cells, leadingBlanks: first.weekday(calendar: calendar) - 1,
            eaten: eaten, dailyAverage: average
        )
    }
}

/// 월 합계 두 줄(2026-10-27 대표님 "1번이랑 2번 같이"): 실물 환산 + 지난달 비교.
enum MonthStats {
    /// 실물 환산값(SPEC §4.3 2026-10-27 확정): 각설탕 1개 = 4 g, 에스프레소 1샷 = 75 mg.
    static func perThing(_ side: CupSide) -> Double {
        switch side {
        case .sugar: return 4
        case .caffeine: return 75
        }
    }

    static func things(eaten: Double, side: CupSide) -> Int {
        Int((eaten / perThing(side)).rounded())
    }

    /// 지난달 대비 하루 평균 변화(%, 반올림). 이번 달이면 지난달도 오늘 날짜까지만 본다.
    /// 지난달 기록이 없거나 평균이 0이면 비교하지 않는다.
    static func change(
        entries: [Entry], boundaryHour: Int, year: Int, month: Int, today: DayKey, side: CupSide,
        calendar: Calendar = .current
    ) -> Int? {
        let live = year == today.year && month == today.month
        let upto = live ? today.day : nil
        let now = MonthPage.make(
            entries: entries, boundaryHour: boundaryHour, year: year, month: month, today: today, side: side,
            upto: upto, calendar: calendar
        )
        let (py, pm) = month == 1 ? (year - 1, 12) : (year, month - 1)
        let before = MonthPage.make(
            entries: entries, boundaryHour: boundaryHour, year: py, month: pm, today: today, side: side,
            upto: upto, calendar: calendar
        )
        guard let current = now.dailyAverage, let previous = before.dailyAverage, previous > 0 else { return nil }
        return Int(((current - previous) / previous * 100).rounded())
    }
}

/// 월 추이 셰이커 = 면 주인의 보관함(2026-10-27 대표님 "인벤토리처럼").
/// 마음 = 그해 1월부터 보는 달까지 **연** 마음(연 날 기준, 1월에 새로 쌓인다). 병뚜껑 = 지금 보유량(두 면 공통).
/// 물건 = 그 면 주인이 가져온 것 중 연 것 전부(초기화 없음).
struct MonthInventory: Equatable, Sendable {
    let hearts: Int
    let caps: Int
    /// 물건 id(`GiftContent.items`).
    let items: [String]

    static func make(
        gifts: [GiftEvent], capBalance: Int, side: CupSide, year: Int, month: Int, boundaryHour: Int,
        calendar: Calendar = .current
    ) -> MonthInventory {
        let mine = gifts.filter { $0.cupSide == side }
        let hearts = mine.filter { gift in
            guard gift.isHeart, let opened = gift.openedAt else { return false }
            let day = DayKey(at: opened, boundaryHour: boundaryHour, calendar: calendar)
            return day.year == year && day.month <= month
        }.count
        let owned = Set(GiftContent.items.filter { $0.owner == side }.map(\.id))
        let items = mine
            .filter(\.isOpened)
            .sorted { ($0.openedAt ?? $0.createdAt) < ($1.openedAt ?? $1.createdAt) }
            .compactMap { gift -> String? in
                guard let payload = gift.payload, payload.hasPrefix(GiftContent.itemPrefix) else { return nil }
                let id = String(payload.dropFirst(GiftContent.itemPrefix.count))
                return owned.contains(id) ? id : nil
            }
        return MonthInventory(hearts: hearts, caps: capBalance, items: items)
    }
}
