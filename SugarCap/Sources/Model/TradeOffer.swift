import Foundation
import SwiftData

/// 캐릭터가 들고 온 거래 제안 1건(SPEC §4.10). 병뚜껑을 내고 잔 세트를 받는다.
/// 수락한 행이 "가진 잔"과 "쓴 병뚜껑"의 근거다. 결정해도 행은 남긴다.
@Model
final class TradeOffer {
    @Attribute(.unique) var id: UUID
    /// `TradeItem.id`(= 잔 세트 id).
    var itemID: String
    /// `CupSide.rawValue`. 상품 주인 면.
    var side: String
    /// 병뚜껑 개수. 제안할 때 정해 둔다.
    var price: Int
    var offeredAt: Date
    var decidedAt: Date?
    /// nil = 아직 안 정함.
    var accepted: Bool?
    /// 결정할 때 한 번 정해 저장한다(거절 3~4일, 수락 2~4주 뒤). 다시 계산하지 않는다.
    var nextOfferAt: Date?

    init(itemID: String, side: CupSide, price: Int, offeredAt: Date) {
        id = UUID()
        self.itemID = itemID
        self.side = side.rawValue
        self.price = price
        self.offeredAt = offeredAt
    }

    var cupSide: CupSide? { CupSide(rawValue: side) }
    var isAccepted: Bool { accepted == true }
}

/// 거래 상품 = 잔 세트. 주인 면에서만 쓴다(대표님 2026-10-24 "산 잔은 주인 면만").
struct TradeItem: Sendable, Identifiable {
    /// 잔 세트 id(`cup-<id>-<단계>` 에셋).
    let id: String
    let side: CupSide

    var dropAsset: String { "drop-\(id)" }

    var name: String {
        switch id {
        case "choco-frappe": return String(localized: "초코 프라페")
        default: return id
        }
    }
}

/// 상품 목록(§4.10). 상품은 여기에만 더한다.
enum TradeCatalog {
    static let items = [TradeItem(id: "choco-frappe", side: .sugar)]

    static func item(_ id: String) -> TradeItem? {
        items.first { $0.id == id }
    }
}
