import Foundation
import SwiftData

/// 선물 종류(SPEC §4.9). 저장은 `rawValue`.
enum GiftKind: String, Sendable, CaseIterable {
    /// 첫 마감이 적립된 뒤 오는 첫 선물. 열면 추이가 열린다.
    case trendsUnlock
    /// 사이 단계 상승. 상자 없이 오늘 화면에서 조명·팡파레 무대 연출로 보인다(2026-10-11 대표님).
    case levelUp
    /// 달력 주(월~일) 7일 모두 기준 안에서 마감.
    case weekKept
    /// 감소 목표 최종 달성.
    case goalReached
}

/// 오늘 화면으로 오는 선물 1개(SPEC §4.9). 아직 안 연 것(`openedAt == nil`)이 큐다.
/// 당 쪽은 로슈, 카페인 쪽은 카인이 가져온다. 열어도 행은 남겨 "받은 적 있음"의 근거로 쓴다(추이 열림 판정).
@Model
final class GiftEvent {
    @Attribute(.unique) var id: UUID
    /// `GiftKind.rawValue`.
    var kind: String
    /// `CupSide.rawValue`. 어느 컵 면에 오는지 = 누가 가져오는지.
    var side: String
    /// 단계 상승이면 오른 단계.
    var level: Int?
    /// 상자에서 나온 것(`GiftContent`): 마음 · 병뚜껑 · 물건(`item:<id>`). 상자를 누를 때 정해진다(§4.9 2026-10-11).
    var payload: String?
    /// 기준 지킨 주 선물이면 그 주 월요일(`DayKey.rawValue`). 같은 주에 두 번 주지 않는다.
    var week: String?
    var createdAt: Date
    var openedAt: Date?

    init(
        kind: GiftKind, side: CupSide, level: Int? = nil, payload: String? = nil, week: DayKey? = nil,
        createdAt: Date, openedAt: Date? = nil
    ) {
        id = UUID()
        self.kind = kind.rawValue
        self.side = side.rawValue
        self.level = level
        self.payload = payload
        self.week = week?.rawValue
        self.createdAt = createdAt
        self.openedAt = openedAt
    }

    var giftKind: GiftKind? { GiftKind(rawValue: kind) }
    var cupSide: CupSide? { CupSide(rawValue: side) }
    var isOpened: Bool { openedAt != nil }
    var isHeart: Bool { payload == GiftContent.heart }
    var isCap: Bool { payload == GiftContent.cap }
}

/// 상자에서 나오는 것(§4.9 2026-10-11 회의). 확률은 `GiftMath.outcome`.
enum GiftContent {
    static let heart = "heart"
    /// 어디에 쓰는지 알려 주지 않는 재화. 개수는 추이 탭에 보인다.
    static let cap = "cap"
    static let itemPrefix = "item:"
    /// 물건 목록(id). 물건마다 놓아둔 그림이 들어오면 채운다. 비어 있으면 물건 몫은 병뚜껑으로 간다.
    static let items: [String] = []

    static func item(_ id: String) -> String { itemPrefix + id }
}
