import Foundation
import SwiftData

/// 하루(경계 시각 기준) 정산 1행(SPEC §2.2). **앱을 연 날마다 만든다** — 행이 없는 날은
/// "앱을 안 연 날"이고, 가장 이른 행이 설치 날이다(`SettlementPlanner`).
///
/// `…AtClose`는 마감 연출용, 호감도는 `final…`(하루 경계가 지난 뒤의 최종 값)으로만 적립한다.
@Model
final class DaySettlement {
    /// `DayKey.rawValue`.
    @Attribute(.unique) var day: String
    var closedAt: Date?
    var sugarLeftAtCloseG: Double?
    var caffeineLeftAtCloseMg: Double?
    var finalSugarLeftG: Double?
    var finalCaffeineLeftMg: Double?
    /// 적립이 끝났거나(먹이기) 적립 없이 닫혔다("마셨어요"). 다시 묻지 않는다.
    var finalizedAt: Date?

    init(day: DayKey) {
        self.day = day.rawValue
    }

    var dayKey: DayKey? { DayKey(rawValue: day) }

    var isClosed: Bool { closedAt != nil }

    /// 마감 뒤에 마신 음료가 있었는지(§4.1 다음 날 배너 "어젯밤 이후 마신 만큼 빠졌어요").
    var shrankAfterClose: Bool {
        guard let sugarAtClose = sugarLeftAtCloseG, let caffeineAtClose = caffeineLeftAtCloseMg,
              let finalSugar = finalSugarLeftG, let finalCaffeine = finalCaffeineLeftMg
        else { return false }
        return finalSugar < sugarAtClose || finalCaffeine < caffeineAtClose
    }
}

/// 캐릭터별 누적 호감도(§2.2). points는 늘기만 한다. 단계는 저장하지 않고 `AffinityMath.level`로 계산한다.
@Model
final class Affinity {
    /// `CupSide.characterID` ("roshu" | "kain").
    @Attribute(.unique) var character: String
    var points: Int

    init(character: String, points: Int = 0) {
        self.character = character
        self.points = points
    }

    var level: Int { AffinityMath.level(points: points) }
}
