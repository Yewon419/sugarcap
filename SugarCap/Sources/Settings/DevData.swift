import Foundation
import OSLog
import SwiftData

/// 설정 테스트 카드(개발자 모드)의 앱 초기화·데이터 채우기(대표님 2026-11-05). TestFlight에서도 써야 해서 Debug 전용이 아니다.
@MainActor
enum DevData {
    private static let logger = Logger(subsystem: "com.sugarcap.app", category: "settings")

    /// 기록·마감·호감도·선물·거래·스탬프·즐겨찾기·감소 목표와 앱 설정값을 전부 지운다. 개발자 모드는 켜 둔다.
    /// 마지막에 온보딩 완료 플래그를 내려 루트가 온보딩부터 다시 띄운다.
    static func reset(in context: ModelContext) throws {
        try context.delete(model: Entry.self)
        try context.delete(model: DaySettlement.self)
        try context.delete(model: Affinity.self)
        try context.delete(model: GiftEvent.self)
        try context.delete(model: TradeOffer.self)
        try context.delete(model: ReductionGoal.self)
        try context.delete(model: FavoriteDrink.self)
        try context.delete(model: FavoriteBrand.self)
        try context.delete(model: AppSettings.self)
        _ = try AppSettings.current(in: context)
        try context.save()

        CloseReminder.disable()
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        SharedDefaults.store?.removePersistentDomain(forName: SharedStore.appGroupID)
        UserDefaults.standard.set(true, forKey: DeveloperMode.key)
        UserDefaults.standard.set(false, forKey: OnboardingView.completedKey)
        logger.info("앱 초기화")
    }

    /// 어제부터 `days`일 전까지 하루 1~3잔을 기록하고 그날 밤 먹이기로 마감한 것처럼 채운다.
    /// 마감은 어젯밤 먹이기와 같은 길(`SettlementStore.feedPastDay`)이라 호감도·선물·튜토리얼 병뚜껑·스탬프가 실제 규칙대로 쌓인다.
    /// 쌓인 상자·단계 상승 무대는 연 것으로, 스탬프판은 본 것으로 둔다. 이미 마감한 날은 건너뛴다. 채운 날 수.
    static func fill(
        days: Int, catalog: Catalog, sides: [CupSide], limits: DailyLimits, boundaryHour: Int, isPro: Bool,
        now: Date, in context: ModelContext
    ) throws -> Int {
        let calendar = Calendar.current
        let brands = Dictionary(uniqueKeysWithValues: catalog.brands.map { ($0.id, $0.name) })
        let drinks = catalog.drinks.filter { drink in
            drink.servings.contains { $0.sugarG != nil && $0.caffeineMg != nil }
        }
        guard !drinks.isEmpty else { return 0 }
        let closed = Set(try context.fetch(FetchDescriptor<DaySettlement>()).filter(\.isClosed).map(\.day))
        let today = DayKey(at: now, boundaryHour: boundaryHour)
        let seed = StampProgress.seed()
        var filled = 0

        for offset in stride(from: days, through: 1, by: -1) {
            let day = today.shifted(by: -offset, calendar: calendar)
            guard !closed.contains(day.rawValue),
                  let closeAt = calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 22))
            else { continue }
            for index in 0 ..< Int.random(in: 1 ... 3) {
                guard let drink = drinks.randomElement(),
                      let at = calendar.date(
                          from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 9 + index * 4)
                      )
                else { continue }
                var selection = ServingSelection(drink: drink)
                selection.servingIndex = Int.random(in: 0 ..< drink.servings.count)
                context.insert(selection.makeEntry(brandName: brands[drink.brandId] ?? "", at: at))
            }
            let results = try SettlementStore.feedPastDay(
                day, entries: try context.fetch(FetchDescriptor<Entry>()), limits: limits, boundaryHour: boundaryHour,
                sides: sides, isPro: isPro, now: closeAt, in: context
            )
            _ = try GiftStore.grantFirstReward(credited: results, now: closeAt, in: context)
            _ = GiftStore.queueLevelUps(credited: results, now: closeAt, in: context)
            _ = try GiftStore.grantWeekKept(closed: day, sides: sides, isPro: isPro, now: closeAt, in: context)
            _ = try GiftStore.queueFirstMeeting(sides: sides, now: closeAt, in: context)
            _ = try GiftStore.grantStarterCap(sides: sides, now: closeAt, in: context)
            _ = try GiftStore.grantStamp(sides: sides, seed: seed, now: closeAt, in: context)
            filled += 1
        }

        for gift in try GiftStore.pending(in: context) {
            GiftStore.open(gift, now: now)
        }
        let stamped = StampMath.stamped(cellNumbers: try GiftStore.all(in: context).filter { $0.giftKind == .stamp }.compactMap(\.level))
        UserDefaults.standard.set(stamped, forKey: StampProgress.seenKey)
        try context.save()
        logger.info("데이터 채우기: \(filled)일")
        return filled
    }
}
