import SwiftUI

/// 스토어·심사에 필요한 바깥 링크. 개인정보처리방침 URL은 배포 뒤에 채운다(docs/STORE.md §5).
enum AppLinks {
    /// Apple 표준 사용권 계약. 자체 약관이 없을 때 App Store가 인정하는 링크다.
    static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
    /// `site/privacy/index.html`을 올린 주소(Vercel, 2026-09-24 배포). nil이면 링크를 숨긴다.
    static let privacyPolicy = URL(string: "https://sugarcap.vercel.app/privacy/")
}

/// 페이월(SPEC §6, 2026-09-24 디자인). Pro 기능을 탭한 자리에서 시트로 열고, 구매하면 그 화면으로 돌아간다.
/// 온보딩에는 넣지 않는다. 자동 갱신 구독이라 갱신·해지 안내와 약관 링크를 빼면 심사에 걸린다.
struct PaywallView: View {
    /// 어떤 기능을 누르다 왔는지. 소제목이 그 기능을 말한다. 설정의 "Pro 보기"처럼 특정 기능이 없으면 nil.
    let feature: ProFeature?

    @Environment(ProStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPlanID = ProProduct.yearly
    @Environment(\.dynamicTypeSize) private var typeSize

    private var selectedPlan: ProPlan? {
        store.plans.first { $0.id == selectedPlanID } ?? store.plans.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("슈가캡 PRO")
                        .kicker()
                    Spacer()
                    Button { dismiss() } label: {
                        Text("닫기").font(.subheadline).tapTarget()
                    }
                    .accessibilityIdentifier("paywall-close")
                }
                .padding(.top, 20)

                Text("덜 마신 날을\n더 잘 보이게")
                    .font(.system(size: 34, weight: .bold))
                    .tracking(-0.7)
                    .lineSpacing(2)
                    .padding(.top, 20)

                Text(feature.map { "\($0.title)는 Pro에서 열려요" } ?? "한 번 결제로 아래 기능이 모두 열려요")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)

                benefits
                    .padding(.top, 24)

                plans
                    .padding(.top, 28)

                if let failure = store.failure {
                    Text(failure)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.top, 12)
                }

                // 큰 글자에서는 안내가 하단 고정 영역의 절반을 먹어 기능 목록이 잘린다. 본문으로 내린다.
                if typeSize.isAccessibilitySize {
                    legal
                        .padding(.top, 28)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) { footer }
        .task { await store.loadPlans() }
        // 구매가 끝나면 원래 하려던 걸 하러 돌아간다.
        .onChange(of: store.isPro) { _, isPro in
            if isPro { dismiss() }
        }
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(ProFeature.allCases, id: \.self) { item in
                benefitRow(item.title)
            }
            benefitRow("위젯")
        }
    }

    private func benefitRow(_ title: String) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(.tint)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.subheadline)
        }
    }

    @ViewBuilder
    private var plans: some View {
        if store.plans.isEmpty {
            if store.isLoadingPlans {
                ProgressView()
                    .frame(maxWidth: .infinity)
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
                    planCard(plan)
                }
            }
        }
    }

    /// 큰 글자에서는 이름·설명 옆에 가격을 두면 둘 다 "₩9,9…"처럼 잘린다. 가격을 아래로 내린다.
    private var planLayout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center))
    }

    /// 선택된 카드만 액센트를 쓴다. 누르면 선택만 바뀌고, 결제는 아래 버튼이 한다.
    private func planCard(_ plan: ProPlan) -> some View {
        let selected = plan.id == selectedPlanID
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                selectedPlanID = plan.id
            }
        } label: {
            planLayout {
                VStack(alignment: .leading, spacing: 6) {
                    Text(plan.title)
                        .font(.system(size: 17, weight: .semibold))
                    if let note = plan.note {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if !typeSize.isAccessibilitySize {
                    Spacer(minLength: 8)
                }
                Text(plan.price)
                    .font(.system(.title3, weight: .bold))
                    .tracking(-0.4)
                    .monospacedDigit()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(minHeight: 84)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selected ? Color.accentColor.opacity(0.08) : Color.clear,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        selected ? Color.accentColor : Color(.separator),
                        lineWidth: selected ? 2 : 1
                    )
            )
            .overlay(alignment: .topTrailing) {
                if !plan.isLifetime {
                    Text("추천")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.accentColor, in: Capsule())
                        .offset(x: -16, y: -10)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("plan-\(plan.id)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Button {
                guard let plan = selectedPlan else { return }
                Task { await store.purchase(plan.id) }
            } label: {
                Group {
                    if store.purchasingID != nil {
                        ProgressView().tint(.white)
                    } else {
                        Text(selectedPlan.map { "\($0.title)으로 시작" } ?? "시작")
                    }
                }
                .ctaLabel()
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .disabled(store.plans.isEmpty || store.purchasingID != nil)
            .accessibilityIdentifier("paywall-purchase")

            if !typeSize.isAccessibilitySize {
                legal
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(.background)
    }

    /// 자동 갱신 안내와 약관 링크. 심사 필수라 어느 글자 크기에서도 빠지지 않는다.
    private var legal: some View {
        VStack(spacing: 12) {
            Text("연간 구독은 기간이 끝나기 24시간 전에 해지하지 않으면 자동으로 갱신됩니다. 해지는 App Store 계정 설정에서 합니다.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // 한 줄에 안 들어가면 세로로 쌓는다. 가로로 욱여넣으면 "이용약/관"처럼 단어가 깨진다.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    links(separated: true)
                }
                VStack(spacing: 10) {
                    links(separated: false)
                }
            }
            .font(.system(.caption, weight: .medium))
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func links(separated: Bool) -> some View {
        Button("구매 복원") {
            Task { await store.restore() }
        }
        .fixedSize()
        if let terms = AppLinks.termsOfUse {
            if separated { Text("·").foregroundStyle(.secondary) }
            Link("이용약관", destination: terms)
                .fixedSize()
        }
        if let privacy = AppLinks.privacyPolicy {
            if separated { Text("·").foregroundStyle(.secondary) }
            Link("개인정보처리방침", destination: privacy)
                .fixedSize()
        }
    }
}

#Preview {
    PaywallView(feature: .affinityDetail)
        .environment(ProStore(previewPlans: ProStore.mockPlans, isPro: false))
}
