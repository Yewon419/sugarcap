import Foundation
import SwiftData

/// 음료 기록 한 건. **기록 시점 값을 스냅샷한다** — 카탈로그가 갱신돼도 과거 기록은 변하지 않는다
/// (SPEC §2.2, `data/SCHEMA.md`).
@Model
final class Entry {
    var id: UUID
    /// 카탈로그 serving 참조. 직접 입력은 카탈로그에 없으므로 nil이다
    /// (`design/prototype.html:407`).
    var servingID: String?
    /// 원두 선택(더벤티). 선택지가 없으면 nil.
    var variantLabel: String?
    var quantity: Int
    var loggedAt: Date

    /// **수량이 이미 곱해진 총량이다.** 합계에서 다시 곱하면 안 된다(`DayMath.Consumption`).
    /// nil은 0이 아니라 "브랜드 미공개"다.
    var sugarG: Double?
    var caffeineMg: Double?

    /// 표시용 스냅샷. 카탈로그를 다시 조회하지 않고도 기록 리스트를 그릴 수 있어야 한다.
    var drinkName: String
    var brandName: String
    var sizeLabel: String

    init(
        id: UUID = UUID(),
        servingID: String?,
        variantLabel: String? = nil,
        quantity: Int,
        loggedAt: Date,
        sugarG: Double?,
        caffeineMg: Double?,
        drinkName: String,
        brandName: String,
        sizeLabel: String
    ) {
        self.id = id
        self.servingID = servingID
        self.variantLabel = variantLabel
        self.quantity = quantity
        self.loggedAt = loggedAt
        self.sugarG = sugarG
        self.caffeineMg = caffeineMg
        self.drinkName = drinkName
        self.brandName = brandName
        self.sizeLabel = sizeLabel
    }

    var consumption: Consumption {
        Consumption(sugarG: sugarG, caffeineMg: caffeineMg)
    }

    func dayKey(boundaryHour: Int, calendar: Calendar = .current) -> DayKey {
        DayKey(at: loggedAt, boundaryHour: boundaryHour, calendar: calendar)
    }
}
