import Foundation
import SwiftData

/// 선물 종류(SPEC §4.9). 저장은 `rawValue`.
enum GiftKind: String, Sendable, CaseIterable {
    /// 첫 마감이 적립된 뒤 오는 첫 선물. 열면 추이가 열린다.
    case trendsUnlock
    /// 사이 단계 상승: 새 사이 이름 + 새 대기 자세.
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
    /// 물건 id 또는 꽝 문구 id(§4.9, Phase 3).
    var payload: String?
    var createdAt: Date
    var openedAt: Date?

    init(kind: GiftKind, side: CupSide, level: Int? = nil, payload: String? = nil, createdAt: Date, openedAt: Date? = nil) {
        id = UUID()
        self.kind = kind.rawValue
        self.side = side.rawValue
        self.level = level
        self.payload = payload
        self.createdAt = createdAt
        self.openedAt = openedAt
    }

    var giftKind: GiftKind? { GiftKind(rawValue: kind) }
    var cupSide: CupSide? { CupSide(rawValue: side) }
    var isOpened: Bool { openedAt != nil }
}
