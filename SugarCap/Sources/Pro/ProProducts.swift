import Foundation

/// Pro 상품(SPEC §6). 가격 티어는 App Store Connect에서 정한다(연간 9,900원대, 평생 29,000원대).
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

    var isLifetime: Bool { id == ProProduct.lifetime }
}

/// Pro 권한 판정. 구독(연간)이든 평생이든 하나만 있으면 Pro다.
enum ProEntitlement {
    static func isPro(productIDs: some Sequence<String>) -> Bool {
        productIDs.contains { ProProduct.all.contains($0) }
    }
}

/// Pro로 잠그는 기능(SPEC §6). 무료가 쓸 수 있는 것은 여기에 없다.
enum ProFeature: String, CaseIterable, Identifiable, Sendable {
    case affinityDetail
    case monthlyTrends
    case weekOverWeek
    case reductionGoal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .affinityDetail: return "호감도 자세히 보기"
        case .monthlyTrends: return "추이 월 보기"
        case .weekOverWeek: return "지난주 대비"
        case .reductionGoal: return "감소 목표"
        }
    }

    func isLocked(isPro: Bool) -> Bool { !isPro }
}
