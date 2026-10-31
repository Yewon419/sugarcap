import Foundation

/// Pro 상품(SPEC §6). 가격 티어는 App Store Connect에서 정한다(연간 ₩20,000·$19.99·NT$390, 평생 ₩30,000·$29.99·NT$690.
/// 미국만 수동 지정, 대만은 한국 가격의 자동 환산). 연간에는 7일 무료 체험(도입 혜택)이 붙는다.
enum ProProduct {
    static let yearly = "com.sugarcap.app.pro.yearly"
    static let lifetime = "com.sugarcap.app.pro.lifetime"

    static let all: Set<String> = [yearly, lifetime]

    /// 페이월에 세울 순서. 연간을 먼저 보여 준다.
    static let order = [yearly, lifetime]
}

/// 페이월이 그릴 한 줄. StoreKit `Product`를 그대로 뷰에 넘기지 않는다
/// (목 데이터로 화면을 찍고 테스트할 수 있어야 한다).
struct ProPlan: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let price: String
    let note: String?
    /// 무료 체험 일수. 체험이 없거나 이 Apple ID가 이미 체험했으면 nil.
    let trialDays: Int?

    var isLifetime: Bool { id == ProProduct.lifetime }
}

/// 연간 구독의 무료 체험(App Store 도입 혜택). 자격은 Apple ID·구독 그룹당 한 번이라 StoreKit이 판정한다.
enum ProTrial {
    /// 체험이 무료이고 자격이 있을 때만 일수를 준다. 기간을 일로 못 바꾸면(월·년 단위) nil.
    static func days(isFreeTrial: Bool, isEligible: Bool, unitDays: Int?, value: Int) -> Int? {
        guard isFreeTrial, isEligible, let unitDays, value > 0 else { return nil }
        return unitDays * value
    }
}

/// Pro 권한 판정. 구독(연간)이든 평생이든 하나만 있으면 Pro다.
enum ProEntitlement {
    static func isPro(productIDs: some Sequence<String>) -> Bool {
        productIDs.contains { ProProduct.all.contains($0) }
    }
}

/// Pro로 잠그는 기능(SPEC §6). 무료가 쓸 수 있는 것은 여기에 없다.
enum ProFeature: String, CaseIterable, Identifiable, Sendable {
    case monthlyTrends
    case reductionGoal
    /// 선물 마음 카드의 "다른 것도 받고 싶으시다고요?"(§4.9).
    case gifts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .monthlyTrends: return String(localized: "추이 월 보기")
        case .reductionGoal: return String(localized: "감소 목표")
        case .gifts: return String(localized: "선물")
        }
    }

    func isLocked(isPro: Bool) -> Bool { !isPro }
}
