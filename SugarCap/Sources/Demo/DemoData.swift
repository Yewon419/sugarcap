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
    /// 메뉴 국가에 맞는 음료로 채운다. 미국 값은 `catalog-us.json`의 Starbucks Tall, 대만은 `catalog-tw.json`의 cama café M 그대로다.
    static func seed(into context: ModelContext, boundaryHour: Int, country: MenuCountry, now: Date = Date()) {
        do {
            guard try context.fetch(FetchDescriptor<Entry>()).isEmpty else { return }

            let calendar = Calendar.current
            let today = DayKey(at: now, boundaryHour: boundaryHour)

            // 오늘: 두 잔. 당 30 g(미국 27 g) / 카페인 245 mg이 빠져 컵이 반쯤 줄어 보인다.
            //
            // **지금 시각에서 뒤로 잡는다.** 달력 시각(9시·14시)으로 박으면 CI가 도는 새벽에는
            // 하루 경계(4시) 기준으로 그 시각이 아직 오지 않아 오늘 합계에 안 잡힌다.
            switch country {
            case .kr:
                insert(context, "아메리카노", "스타벅스", "Tall", sugar: 0, caffeine: 150, at: now.addingTimeInterval(-5400))
                insert(context, "카페모카", "투썸플레이스", "레귤러", sugar: 30, caffeine: 95, at: now.addingTimeInterval(-1800))
            case .us:
                insert(context, "Caffè Americano", "Starbucks", "Tall", sugar: 0, caffeine: 150, at: now.addingTimeInterval(-5400))
                insert(context, "Caffè Mocha", "Starbucks", "Tall", sugar: 27, caffeine: 95, at: now.addingTimeInterval(-1800))
            case .tw:
                // `catalog-tw.json`의 cama café M 그대로(美式 熱, 輕拿鐵 冰).
                insert(context, "微韻輕美式", "cama café", "M", sugar: 0.2, caffeine: 103.9, at: now.addingTimeInterval(-5400))
                insert(context, "CAMA金獎拿鐵", "cama café", "M", sugar: 10.2, caffeine: 207.8, at: now.addingTimeInterval(-1800))
            }
            let pastName = switch country {
            case .kr: "그날의 음료"
            case .us: "Drink of the day"
            case .tw: "當日飲品"
            }

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
                    context, pastName, String(localized: "직접 입력"), "",
                    sugar: sugarByDay[offset], caffeine: caffeineByDay[offset], at: date
                )

                // 앱을 매일 열고 마감한 것으로 둔다(다음 날 배너가 뜨지 않게).
                let row = try SettlementStore.row(for: day, in: context)
                row.closedAt = date
                row.sugarLeftAtCloseG = max(0, 50 - sugarByDay[offset])
                row.caffeineLeftAtCloseMg = max(0, country.caffeineAdviceMg - caffeineByDay[offset])
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

    /// 하루 기준 화면의 "줄이는 중" 스크린샷용. `-seedGoal caffeine`이면 카페인 목표(8주 중 3주 지킴)를 만든다.
    static func seedGoalIfRequested(into context: ModelContext, settings: AppSettings, now: Date = Date()) {
        guard let raw = UserDefaults.standard.string(forKey: "seedGoal"), let side = CupSide(rawValue: raw) else { return }
        do {
            let today = DayKey(at: now, boundaryHour: settings.dayBoundaryHour)
            let goal = try ReductionStore.start(
                side: side, target: side == .sugar ? 25 : 200, weeks: 8, settings: settings, today: today, in: context
            )
            goal.achievedWeeks = 3
            try context.save()
        } catch {
            logger.error("데모 목표 주입 실패: \(String(describing: error), privacy: .public)")
        }
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
