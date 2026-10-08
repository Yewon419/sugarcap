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
    /// 기록할 것(2026-10-06 대표님: 카페인을 아예 안 먹는 사람도 있다). 끈 쪽도 값은 계속 저장하고 화면에서만 숨긴다.
    /// 둘 다 끄지는 못한다(설정 화면이 막는다). 선언에 기본값이 있어야 기존 저장소가 가볍게 옮겨진다.
    var tracksSugar: Bool = true
    var tracksCaffeine: Bool = true
    /// 메뉴 국가(`MenuCountry.rawValue`). nil이면 기기 지역을 따른다(SPEC §9.9). 선언 기본값은 위와 같은 이유.
    var menuCountryCode: String? = nil

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

    /// 화면에 보일 면. 둘 다 꺼진 값이 들어와도 빈 화면이 되지 않게 둘 다 보인다.
    /// CI 스크린샷은 `-screenshotTracks sugar|caffeine`으로 한 면만 켠 화면을 찍는다(Debug, 저장하지 않는다).
    var trackedSides: [CupSide] {
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: "screenshotTracks"), let only = CupSide(rawValue: raw) {
            return [only]
        }
        #endif
        return CupSide.tracked(sugar: tracksSugar, caffeine: tracksCaffeine)
    }

    func tracks(_ side: CupSide) -> Bool {
        trackedSides.contains(side)
    }

    func setTracks(_ isOn: Bool, for side: CupSide) {
        switch side {
        case .sugar: tracksSugar = isOn
        case .caffeine: tracksCaffeine = isOn
        }
    }

    /// CI 스크린샷은 `-screenshotMenuCountry us|kr|tw`로 고른다(Debug, 저장하지 않는다). UI 테스트가 저장한 나라가 남아 있어도 덮는다.
    var menuCountry: MenuCountry {
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: "screenshotMenuCountry"), let forced = MenuCountry(rawValue: raw) {
            return forced
        }
        #endif
        return MenuCountry.resolve(storedCode: menuCountryCode, region: Locale.current.region)
    }

    var limits: DailyLimits {
        DailyLimits(sugarG: sugarLimitG, caffeineMg: caffeineLimitMg)
    }

    /// 감소 목표가 주마다 하루 기준을 낮출 때 쓴다(SPEC §9.5).
    func setLimit(_ value: Double, for side: CupSide) {
        switch side {
        case .sugar: sugarLimitG = value
        case .caffeine: caffeineLimitMg = value
        }
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
