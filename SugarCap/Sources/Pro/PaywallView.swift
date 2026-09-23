import SwiftUI

/// 페이월(SPEC §6). Pro 기능을 탭한 자리에서 시트로 열고, 구매하면 그 화면으로 돌아간다.
/// 온보딩에는 넣지 않는다.
struct PaywallView: View {
    /// 어떤 기능을 누르다 왔는지. 맨 위 한 줄이 그 기능을 말한다.
    let feature: ProFeature

    @Environment(ProStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    benefits
                    plans
                    if let failure = store.failure {
                        Text(failure)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                    Button("구매 복원") {
                        Task { await store.restore() }
                    }
                    .font(.footnote)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
            }
            .navigationTitle("슈가캡 Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                        .accessibilityIdentifier("paywall-close")
                }
            }
            .task { await store.loadPlans() }
            // 구매가 끝나면 원래 하려던 걸 하러 돌아간다.
            .onChange(of: store.isPro) { _, isPro in
                if isPro { dismiss() }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                ForEach(CupSide.allCases) { side in
                    Image(side.characterAsset)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 72)
                        .accessibilityHidden(true)
                }
            }
            Text("\(feature.title)는 Pro 기능이에요")
                .font(.title3.bold())
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(ProFeature.allCases, id: \.self) { item in
                Label {
                    Text(item.title)
                } icon: {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
                .font(.subheadline)
            }
            Label {
                Text("위젯")
            } icon: {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
            }
            .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            Color(.secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }

    @ViewBuilder
    private var plans: some View {
        if store.plans.isEmpty {
            if store.isLoadingPlans {
                ProgressView()
                    .padding(.vertical, 24)
            } else {
                Button("다시 불러오기") {
                    Task { await store.loadPlans() }
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }
        } else {
            VStack(spacing: 12) {
                ForEach(store.plans) { plan in
                    planButton(plan)
                }
            }
        }
    }

    private func planButton(_ plan: ProPlan) -> some View {
        Button {
            Task { await store.purchase(plan.id) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.title)
                        .font(.headline)
                    if let note = plan.note {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if store.purchasingID == plan.id {
                    ProgressView()
                } else {
                    Text(plan.price)
                        .font(.headline)
                        .monospacedDigit()
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(plan.isLifetime ? Color.secondary.opacity(0.3) : Color.accentColor, lineWidth: plan.isLifetime ? 1 : 2)
        )
        .disabled(store.purchasingID != nil)
        .accessibilityIdentifier("plan-\(plan.id)")
    }
}

#Preview {
    PaywallView(feature: .affinityDetail)
        .environment(
            ProStore(
                previewPlans: [
                    ProPlan(id: ProProduct.yearly, title: "연간", price: "₩9,900", note: "해지할 때까지 매년"),
                    ProPlan(id: ProProduct.lifetime, title: "평생", price: "₩29,000", note: "한 번만 결제"),
                ],
                isPro: false
            )
        )
}
