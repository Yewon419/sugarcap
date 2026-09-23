#if DEBUG
import Foundation
import OSLog
import SwiftData

/// 스토어 스크린샷용 데모 기록(Debug 빌드만). `simctl launch … -seedDemo YES`로 켠다.
///
/// 빈 앱을 찍으면 컵이 가득 차고 추이가 비어 있어 화면이 뭘 하는 앱인지 보여 주지 못한다.
/// 출시 빌드(Release)에는 이 파일 자체가 들어가지 않는다.
///
/// `SettlementStore`가 MainActor라 여기도 MainActor다(화면에서만 부른다).
@MainActor
enum DemoData {
    private static let logger = Logger(subsystem: "com.sugarcap.app", category: "demo")

    static var isRequested: Bool {
        UserDefaults.standard.bool(forKey: "seedDemo")
    }

    /// 이미 기록이 있으면 아무것도 하지 않는다.
    static func seed(into context: ModelContext, boundaryHour: Int, now: Date = Date()) {
        do {
            guard try context.fetch(FetchDescriptor<Entry>()).isEmpty else { return }

            let calendar = Calendar.current
            let today = DayKey(at: now, boundaryHour: boundaryHour)

            // 오늘: 두 잔. 당 30 g / 카페인 245 mg이 빠져 컵이 반쯤 줄어 보인다.
            insert(context, "아메리카노", "스타벅스", "Tall", sugar: 0, caffeine: 150, at: hour(9, now, calendar))
            insert(context, "카페모카", "투썸플레이스", "레귤러", sugar: 30, caffeine: 95, at: hour(14, now, calendar))

            // 지난 12일. 배열의 0번이 **어제**다. 최근으로 올수록 적게 마신 값이어야
            // 추이 막대와 "지난주 대비"가 줄어드는 그림이 된다.
            let sugarByDay: [Double] = [30, 28, 33, 35, 38, 40, 44, 51, 48, 55, 58, 62]
            let caffeineByDay: [Double] = [200, 195, 210, 225, 240, 250, 265, 290, 300, 330, 355, 390]
            for offset in 0..<sugarByDay.count {
                let day = today.shifted(by: -(offset + 1), calendar: calendar)
                guard let date = calendar.date(
                    from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 13)
                ) else { continue }
                insert(
                    context, "그날의 음료", "직접 입력", "",
                    sugar: sugarByDay[offset], caffeine: caffeineByDay[offset], at: date
                )

                // 앱을 매일 열고 마감한 것으로 둔다(다음 날 배너가 뜨지 않게).
                let row = try SettlementStore.row(for: day, in: context)
                row.closedAt = date
                row.sugarLeftAtCloseG = max(0, 50 - sugarByDay[offset])
                row.caffeineLeftAtCloseMg = max(0, 400 - caffeineByDay[offset])
                row.finalSugarLeftG = row.sugarLeftAtCloseG
                row.finalCaffeineLeftMg = row.caffeineLeftAtCloseMg
                row.finalizedAt = date
            }

            // 호감도: 로슈 Lv3, 카인 Lv2 언저리.
            context.insert(Affinity(character: CupSide.sugar.characterID, points: 96))
            context.insert(Affinity(character: CupSide.caffeine.characterID, points: 41))

            try context.save()
        } catch {
            logger.error("데모 데이터 주입 실패: \(String(describing: error), privacy: .public)")
        }
    }

    private static func hour(_ hour: Int, _ now: Date, _ calendar: Calendar) -> Date {
        calendar.date(bySettingHour: hour, minute: 10, second: 0, of: now) ?? now
    }

    private static func insert(
        _ context: ModelContext, _ name: String, _ brand: String, _ size: String,
        sugar: Double, caffeine: Double, at date: Date
    ) {
        context.insert(
            Entry(
                servingID: nil, quantity: 1, loggedAt: date, sugarG: sugar, caffeineMg: caffeine,
                drinkName: name, brandName: brand, sizeLabel: size
            )
        )
    }
}
#endif
