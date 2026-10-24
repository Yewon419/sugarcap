import Foundation
import OSLog

/// 거래 계산(SPEC §4.10). 전부 순수 함수다. 잔액은 저장하지 않고 늘 여기서 계산한다.
enum TradeMath {
    /// 거래 행 하나의 상태. `TradeOffer`에서 뽑아 넘긴다.
    struct Record: Equatable, Sendable {
        let itemID: String
        let price: Int
        let accepted: Bool?
    }

    static let firstPrice = 2
    static let laterPrice = 5
    /// 거절 뒤 다음 제안까지(일).
    static let afterRefusalDays: ClosedRange<Double> = 3 ... 4
    /// 수락 뒤 다음 제안까지(일, 대표님 2026-10-24 "2-4주 뒤").
    static let afterAcceptanceDays: ClosedRange<Double> = 14 ... 28

    /// 병뚜껑 잔액 = 열어 본 병뚜껑 선물 수 − 수락한 거래 가격 합. 음수면 기록이 어긋난 것이라 호출 쪽이 제안을 멈춘다.
    static func balance(openedCaps: Int, trades: [Record]) -> Int {
        openedCaps - trades.filter { $0.accepted == true }.reduce(0) { $0 + $1.price }
    }

    /// 다음 제안 가격. 수락한 거래가 하나도 없으면 첫 거래 값(거절만 했어도 그대로).
    static func price(trades: [Record]) -> Int {
        trades.contains { $0.accepted == true } ? laterPrice : firstPrice
    }

    /// 가진 잔 = 수락한 거래의 상품.
    static func ownedSets(trades: [Record]) -> Set<String> {
        Set(trades.filter { $0.accepted == true }.map(\.itemID))
    }

    /// 다음 제안 시각. `roll`은 0..<1 무작위 값이고 그 사이 아무 시각이 된다.
    static func nextOfferAt(decidedAt: Date, accepted: Bool, roll: Double) -> Date {
        let range = accepted ? afterAcceptanceDays : afterRefusalDays
        let days = range.lowerBound + (range.upperBound - range.lowerBound) * min(max(roll, 0), 1)
        return decidedAt.addingTimeInterval(days * 86_400)
    }
}

extension TradeOffer {
    var record: TradeMath.Record { TradeMath.Record(itemID: itemID, price: price, accepted: accepted) }
}

/// 병뚜껑 잔액(보관함·설정·추이가 같은 값을 보인다).
enum CapBalance {
    private static let logger = Logger(subsystem: "com.sugarcap.app", category: "trade")

    /// Debug `-screenshotCaps <n>`이면 그 값.
    static func current(gifts: [GiftEvent], trades: [TradeOffer]) -> Int {
        #if DEBUG
        if UserDefaults.standard.object(forKey: "screenshotCaps") != nil {
            return UserDefaults.standard.integer(forKey: "screenshotCaps")
        }
        #endif
        let opened = gifts.filter { $0.isCap && $0.isOpened }.count
        let value = TradeMath.balance(openedCaps: opened, trades: trades.map(\.record))
        if value < 0 {
            logger.error("병뚜껑 잔액이 음수: opened=\(opened) trades=\(trades.count)")
        }
        return max(value, 0)
    }
}

/// 면마다 고른 잔(UserDefaults `cupSet.<면>`). 그리는 쪽은 `CupSide.cupSetID`가 읽는다.
enum CupSetChoice {
    static func select(_ setID: String, for side: CupSide) {
        if setID == side.defaultCupSetID {
            UserDefaults.standard.removeObject(forKey: side.cupSetKey)
        } else {
            UserDefaults.standard.set(setID, forKey: side.cupSetKey)
        }
    }

    /// 가진 잔이 아닌 선택을 지운다(앱 시작 때). 그 면은 기본 잔으로 돌아간다.
    static func dropUnowned(owned: Set<String>) {
        for side in CupSide.allCases {
            guard let chosen = UserDefaults.standard.string(forKey: side.cupSetKey), !owned.contains(chosen) else {
                continue
            }
            UserDefaults.standard.removeObject(forKey: side.cupSetKey)
        }
    }
}
