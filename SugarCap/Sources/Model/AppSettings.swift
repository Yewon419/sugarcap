import Foundation
import SwiftData

/// 사용자 설정. 행이 하나만 존재한다(`current(in:)`가 보장).
/// 기본값 근거는 SPEC §3(식약처 400mg, WHO 50g)과 §9.1(하루 경계 새벽 4시).
@Model
final class AppSettings {
    var sugarLimitG: Double
    var caffeineLimitMg: Double
    /// 하루가 바뀌는 시각. 기본 새벽 4시(SPEC §9.1).
    var dayBoundaryHour: Int
    /// "오늘 마감"을 열 수 있는 시각. 기본 저녁 8시(SPEC §4.7). Phase 2에서 쓴다.
    var closeFromHour: Int

    init(
        sugarLimitG: Double = DailyLimits.default.sugarG,
        caffeineLimitMg: Double = DailyLimits.default.caffeineMg,
        dayBoundaryHour: Int = 4,
        closeFromHour: Int = 20
    ) {
        self.sugarLimitG = sugarLimitG
        self.caffeineLimitMg = caffeineLimitMg
        self.dayBoundaryHour = dayBoundaryHour
        self.closeFromHour = closeFromHour
    }

    var limits: DailyLimits {
        DailyLimits(sugarG: sugarLimitG, caffeineMg: caffeineLimitMg)
    }

    /// 없으면 기본값으로 만들어 넣는다. 설정 화면이 없는 Phase 1에서도 기본값이 필요하다.
    static func current(in context: ModelContext) throws -> AppSettings {
        let existing = try context.fetch(FetchDescriptor<AppSettings>())
        if let first = existing.first {
            return first
        }
        let created = AppSettings()
        context.insert(created)
        return created
    }
}
