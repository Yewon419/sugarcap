import OSLog
import StoreKit
import SwiftUI

/// 구매 상태(SPEC §6). StoreKit 2를 직접 쓰고 서버 영수증 검증은 두지 않는다(서버 없음, §1).
@Observable
@MainActor
final class ProStore {
    private(set) var isPro = false
    private(set) var plans: [ProPlan] = []
    private(set) var isLoadingPlans = false
    private(set) var purchasingID: String?
    private(set) var failure: String?

    private var products: [String: Product] = [:]
    private var updatesTask: Task<Void, Never>?
    /// 목 상태에서는 StoreKit을 건드리지 않는다.
    private var isPreview = false

    private static let logger = Logger(subsystem: "com.sugarcap.app", category: "pro")

    init() {}

    /// 스크린샷·프리뷰용. StoreKit을 건드리지 않는다.
    init(previewPlans: [ProPlan], isPro: Bool) {
        self.plans = previewPlans
        self.isPro = isPro
        self.isPreview = true
    }

    /// CI 스크린샷·UI 테스트 전용(Debug 빌드만). 실행 인자로 구매 상태를 흉내 낸다.
    /// `-mockPro YES`는 미구매 + 가짜 상품, `-mockProOwned YES`는 구매 완료 상태다.
    static func make() -> ProStore {
        #if DEBUG
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "mockProOwned") {
            return ProStore(previewPlans: mockPlans, isPro: true)
        }
        if defaults.bool(forKey: "mockPro") {
            return ProStore(previewPlans: mockPlans, isPro: false)
        }
        #endif
        return ProStore()
    }

    static let mockPlans = [
        ProPlan(id: ProProduct.yearly, title: "연간", price: "₩9,900", note: "해지할 때까지 매년"),
        ProPlan(id: ProProduct.lifetime, title: "평생", price: "₩29,000", note: "한 번만 결제"),
    ]

    /// 앱이 뜰 때 한 번. 권한을 읽고 갱신 스트림을 연다.
    func start() {
        guard !isPreview, updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self.refreshEntitlement()
            }
        }
        Task { await refreshEntitlement() }
    }

    func refreshEntitlement() async {
        var owned: [String] = []
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlement, transaction.revocationDate == nil {
                owned.append(transaction.productID)
            }
        }
        isPro = ProEntitlement.isPro(productIDs: owned)
    }

    func loadPlans() async {
        guard !isPreview, plans.isEmpty, !isLoadingPlans else { return }
        isLoadingPlans = true
        defer { isLoadingPlans = false }
        do {
            let loaded = try await Product.products(for: ProProduct.all)
            products = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
            plans = ProProduct.order.compactMap { id in
                guard let product = products[id] else { return nil }
                return ProPlan(
                    id: id,
                    title: product.displayName,
                    price: product.displayPrice,
                    note: id == ProProduct.lifetime ? "한 번만 결제" : "해지할 때까지 매년"
                )
            }
            failure = plans.isEmpty ? "상품을 불러오지 못했어요." : nil
        } catch {
            Self.logger.error("상품 로드 실패: \(String(describing: error), privacy: .public)")
            failure = "상품을 불러오지 못했어요."
        }
    }

    /// 구매. 성공하면 권한을 다시 읽는다. 취소는 실패가 아니라 조용히 끝난다.
    func purchase(_ planID: String) async {
        guard let product = products[planID] else {
            failure = "상품을 불러오지 못했어요."
            return
        }
        purchasingID = planID
        defer { purchasingID = nil }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await refreshEntitlement()
                } else {
                    failure = "영수증을 확인하지 못했어요."
                }
            case .pending:
                failure = "승인을 기다리는 중이에요."
            case .userCancelled:
                failure = nil
            @unknown default:
                failure = nil
            }
        } catch {
            Self.logger.error("구매 실패: \(String(describing: error), privacy: .public)")
            failure = "구매하지 못했어요. 잠시 뒤 다시 시도해 주세요."
        }
    }

    /// 복원. 기기를 바꿨거나 앱을 지웠다 깔았을 때 쓴다.
    func restore() async {
        do {
            try await AppStore.sync()
            await refreshEntitlement()
            failure = isPro ? nil : "복원할 구매가 없어요."
        } catch {
            Self.logger.error("복원 실패: \(String(describing: error), privacy: .public)")
            failure = "복원하지 못했어요."
        }
    }
}
