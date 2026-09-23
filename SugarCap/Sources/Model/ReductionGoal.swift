import Foundation
import SwiftData

/// 감소 목표 1개(SPEC §4.3·§9.5). 당·카페인 각각 최대 하나다.
///
/// 진행 중인 목표는 **그 주의 하루 기준을 `AppSettings`에 직접 써넣는다.**
/// 기준을 두 군데 두면 컵 높이(§4.1)와 정산(§4.7)이 서로 다른 수를 보게 된다.
@Model
final class ReductionGoal {
    /// `CupSide.rawValue`.
    @Attribute(.unique) var side: String
    /// 목표를 만든 날(`DayKey.rawValue`). 주는 이 날부터 7일씩 끊는다.
    var startDay: String
    var startLimit: Double
    var target: Double
    var weeks: Int
    var achievedWeeks: Int
    /// 판정이 끝난 주 수. 끝난 주만 판정하므로 진행 중인 주는 포함하지 않는다.
    var evaluatedWeeks: Int

    init(side: CupSide, startDay: DayKey, startLimit: Double, target: Double, weeks: Int) {
        self.side = side.rawValue
        self.startDay = startDay.rawValue
        self.startLimit = startLimit
        self.target = target
        self.weeks = weeks
        self.achievedWeeks = 0
        self.evaluatedWeeks = 0
    }

    var cupSide: CupSide? { CupSide(rawValue: side) }
    var startDayKey: DayKey? { DayKey(rawValue: startDay) }

    var state: ReductionState {
        get { ReductionState(achievedWeeks: achievedWeeks, evaluatedWeeks: evaluatedWeeks) }
        set {
            achievedWeeks = newValue.achievedWeeks
            evaluatedWeeks = newValue.evaluatedWeeks
        }
    }

    /// 지금 주에 적용되는 하루 기준.
    func currentLimit(step: Double) -> Double {
        ReductionMath.weeklyLimit(
            start: startLimit, target: target, weeks: weeks, achievedWeeks: achievedWeeks, step: step
        )
    }
}
