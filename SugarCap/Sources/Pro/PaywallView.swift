import SwiftUI

/// 스토어·심사에 필요한 바깥 링크. 개인정보처리방침 URL은 배포 뒤에 채운다(docs/STORE.md §5).
enum AppLinks {
    /// Apple 표준 사용권 계약. 자체 약관이 없을 때 App Store가 인정하는 링크다.
    static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
    /// `site/privacy/index.html`을 올린 주소(Vercel, 2026-09-24 배포). nil이면 링크를 숨긴다.
    static let privacyPolicy = URL(string: "https://sugarcap.vercel.app/privacy/")
}

/// 페이월(SPEC §6, 2026-09-26 HTML 프로토타입 확정 = 캐주얼). Pro 기능을 누른 자리에서 시트로 열고, 구매하면 그 화면으로 돌아간다.
/// 방울 두 개 머리 그림 → 제목 → 누르다 온 기능의 한 문장 → 기능 네 칸 → 요금 두 장(첫 화면에 보이게) → 시작 + 갱신 안내·약관.
/// 자동 갱신 구독이라 갱신·해지 안내와 약관 링크, 구매 복원을 빼면 심사에 걸린다.
struct PaywallView: View {
    /// 어떤 기능을 누르다 왔는지. 첫 문장과 강조 칸이 그 기능을 말한다. 설정의 "알아보기"처럼 특정 기능이 없으면 nil.
    let feature: ProFeature?

    @Environment(ProStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedPlanID = ProProduct.yearly
    @Environment(\.dynamicTypeSize) private var typeSize

    private var selectedPlan: ProPlan? {
        store.plans.first { $0.id == selectedPlanID } ?? store.plans.first
    }

    /// 기능 이름 대신 얻는 것을 말한다(대표님 문구: "로슈, 카인과 더 친해질 수 있어요").
    private var lead: String {
        switch feature {
        case .affinityDetail: return "로슈, 카인과 더 친해질 수 있어요"
        case .monthlyTrends: return "월 추이는 Pro에서 열려요"
        case .reductionGoal: return "조금씩 줄이기는 Pro에서 열려요"
        case .weekOverWeek: return "지난주 대비는 Pro에서 열려요"
        case nil: return "한 번 결제로 아래 기능이 모두 열려요"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack {
                    Text("슈가캡 PRO")
                        .kicker()
                    Spacer()
                    Button { dismiss() } label: {
                        Text("닫기")
                            .font(AppFont.pretendard(15, .regular, relativeTo: .subheadline))
                            .tapTarget()
                    }
                    .accessibilityIdentifier("paywall-close")
                }
                .padding(.top, 20)

                PaywallHero(isAnimated: !reduceMotion)
                    .frame(height: 104)

                Text("덜 마신 날을\n더 잘 보이게")
                    .font(AppFont.pretendard(28, .extraBold, relativeTo: .title))
                    .tracking(-0.8)
                    .lineSpacing(2)
                    .multilineTextAlignment(.center)

                Text(lead)
                    .font(AppFont.pretendard(14, .regular, relativeTo: .subheadline))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                    .accessibilityIdentifier("paywall-lead")

                features
                    .padding(.top, 18)

                plans
                    .padding(.top, 16)

                if let failure = store.failure {
                    Text(failure)
                        .font(AppFont.pretendard(13, .regular, relativeTo: .footnote))
                        .foregroundStyle(.red)
                        .padding(.top, 12)
                }

                // 큰 글자에서는 안내가 하단 고정 영역의 절반을 먹어 요금이 잘린다. 본문으로 내린다.
                if typeSize.isAccessibilitySize {
                    legal
                        .padding(.top, 28)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Color.wall.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { footer }
        .task { await store.loadPlans() }
        // 구매가 끝나면 원래 하려던 걸 하러 돌아간다.
        .onChange(of: store.isPro) { _, isPro in
            if isPro { dismiss() }
        }
    }

    /// 기능 네 칸. 누르다 온 기능 칸은 액센트 테두리.
    private var features: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: typeSize.isAccessibilitySize ? 2 : 4)
        return LazyVGrid(columns: columns, spacing: 8) {
            featureCard("로슈·카인과 친해지기", focus: feature == .affinityDetail) {
                HStack(alignment: .bottom, spacing: 2) {
                    Image(CupSide.sugar.characterAsset).resizable().scaledToFit().frame(height: 40)
                    Image(CupSide.caffeine.characterAsset).resizable().scaledToFit().frame(height: 32)
                }
            }
            featureCard("월 추이", focus: feature == .monthlyTrends) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(10), spacing: 5), count: 4), spacing: 4) {
                    ForEach(Array([0.9, 0.5, 0.7, 0.3, 1, 0.6, 0.8, 0.4].enumerated()), id: \.offset) { _, size in
                        Circle().fill(Color.sugarPink).frame(width: 10 * size, height: 10 * size).frame(width: 10, height: 10)
                    }
                }
            }
            featureCard("조금씩 줄이기", focus: feature == .reductionGoal) {
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach([0.9, 0.72, 0.56, 0.4], id: \.self) { height in
                        UnevenRoundedRectangle(
                            topLeadingRadius: 6, bottomLeadingRadius: 3, bottomTrailingRadius: 3, topTrailingRadius: 6,
                            style: .continuous
                        )
                        .fill(Color.sugarPink)
                        .frame(width: 11, height: 40 * height)
                    }
                }
            }
            featureCard("위젯", focus: false) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.white)
                        .shadow(color: .black.opacity(0.12), radius: 6, y: 4)
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("4").font(AppFont.numeralFixed(16))
                        Text("g").font(AppFont.numeralFixed(8))
                    }
                    .padding(.leading, 6)
                    .padding(.top, 4)
                    Image(CupSide.sugar.dropAsset)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 17, height: 17)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(4)
                }
                .frame(width: 42, height: 42)
            }
        }
    }

    private func featureCard(_ title: String, focus: Bool, @ViewBuilder art: () -> some View) -> some View {
        VStack(spacing: 6) {
            art()
                .frame(height: 42, alignment: .bottom)
            Text(title)
                .font(AppFont.pretendard(11.5, .bold, relativeTo: .caption))
                .tracking(-0.3)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 92)
        .background {
            let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
            shape.fill(.white.opacity(0.78))
                .overlay(shape.strokeBorder(focus ? Color.accentColor : .white, lineWidth: focus ? 2 : 1))
        }
        .accessibilityElement(children: .combine)
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
                        .font(AppFont.pretendard(17, .bold, relativeTo: .headline))
                    if let note = plan.note {
                        Text(note)
                            .font(AppFont.pretendard(12, .regular, relativeTo: .caption))
                            .foregroundStyle(.secondary)
                    }
                }
                if !typeSize.isAccessibilitySize {
                    Spacer(minLength: 8)
                }
                Text(plan.price)
                    .font(AppFont.numeral(22, relativeTo: .title3))
                    .tracking(-0.6)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(minHeight: 76)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selected ? Color.accentColor.opacity(0.08) : Color.white.opacity(0.72),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(
                        selected ? Color.accentColor : Color.ink.opacity(0.12),
                        lineWidth: selected ? 2 : 1.5
                    )
            )
            .overlay(alignment: .topTrailing) {
                if !plan.isLifetime {
                    Text("추천")
                        .font(AppFont.pretendard(11, .bold, relativeTo: .caption2))
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
                .foregroundStyle(.white)
                .background(Color.accentColor.opacity(store.plans.isEmpty ? 0.4 : 1), in: Capsule())
            }
            .buttonStyle(PressScaleStyle())
            .disabled(store.plans.isEmpty || store.purchasingID != nil)
            .accessibilityIdentifier("paywall-purchase")

            if !typeSize.isAccessibilitySize {
                legal
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Color.wall)
    }

    /// 자동 갱신 안내와 약관 링크. 심사 필수라 어느 글자 크기에서도 빠지지 않는다.
    private var legal: some View {
        VStack(spacing: 12) {
            Text("연간 구독은 기간이 끝나기 24시간 전에 해지하지 않으면 자동으로 갱신돼요. 해지는 App Store 계정 설정에서 해요.")
                .font(AppFont.pretendard(11, .regular, relativeTo: .caption2))
                .lineSpacing(2)
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
            .font(AppFont.pretendard(12, .semibold, relativeTo: .caption))
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

/// 방울 두 개 + 퍼지는 링 두 겹(또렷한 선, 번짐 없음). 방울은 천천히 둥실거린다.
private struct PaywallHero: View {
    let isAnimated: Bool

    var body: some View {
        TimelineView(.animation(paused: !isAnimated)) { timeline in
            let t = isAnimated ? timeline.date.timeIntervalSinceReferenceDate : 0
            ZStack {
                ForEach(0..<2, id: \.self) { index in
                    let phase = ((t + Double(index) * 1.4) / 2.8).truncatingRemainder(dividingBy: 1)
                    let k = isAnimated ? Ease.power2Out(phase) : 0.5
                    Circle()
                        .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 2)
                        .frame(width: 124, height: 124)
                        .scaleEffect(Motion.lerp(0.55, 1.35, k))
                        .opacity(isAnimated ? 0.9 * (1 - k) : 0.5)
                }
                HStack(spacing: 8) {
                    ForEach(CupSide.allCases) { side in
                        let bob = isAnimated ? sin((t / 3 + (side == .sugar ? 0 : 0.5)) * 2 * .pi) : 0
                        Image(side.dropAsset)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 56, height: 56)
                            .offset(y: -3 + 3 * bob)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    PaywallView(feature: .affinityDetail)
        .environment(ProStore(previewPlans: ProStore.mockPlans, isPro: false))
}
