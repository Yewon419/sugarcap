import SwiftUI

/// 스토어·심사에 필요한 바깥 링크. 개인정보처리방침 URL은 배포 뒤에 채운다(docs/STORE.md §5).
enum AppLinks {
    /// Apple 표준 사용권 계약. 자체 약관이 없을 때 App Store가 인정하는 링크다.
    static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
    /// `site/privacy/`(한국어)·`site/zh-Hant/privacy/`(번체)·`site/en/privacy/`(그 외 언어)를 올린 주소(Vercel). nil이면 링크를 숨긴다.
    /// 앱이 실제로 고른 화면 언어를 따른다(기기 지역이 아니라).
    static let privacyPolicy: URL? = switch Bundle.main.preferredLocalizations.first {
    case "ko": URL(string: "https://sugarcap.vercel.app/privacy/")
    case "zh-Hant": URL(string: "https://sugarcap.vercel.app/zh-Hant/privacy/")
    default: URL(string: "https://sugarcap.vercel.app/en/privacy/")
    }
}

/// 페이월(SPEC §6). 2026-10-28 매거진 시안(`design/proto/paywall-mag.html`)을 옮겼다.
/// 머리글 → -8° 기운 지면(검은 띠 = 기능 탭, 탭마다 기사 두 개) → 제목·누르다 온 기능 → 엇갈린 요금 두 칸(평생 추천, 로슈·카인) → 시작 + 갱신 안내·약관.
/// 자동 갱신 구독이라 갱신·해지 안내와 약관 링크, 구매 복원을 빼면 심사에 걸린다.
/// 큰 글자(접근성 크기)에서는 요금 칸을 기울이지 않고 세로로 쌓는다. 지면은 그림이라 크기가 고정이다.
struct PaywallView: View {
    /// 어떤 기능을 누르다 왔는지. 첫 문장과 처음 열리는 탭이 그 기능이다. 설정의 "알아보기"처럼 특정 기능이 없으면 nil.
    let feature: ProFeature?

    @Environment(ProStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selectedPlanID = ProProduct.lifetime
    @State private var tab: PaywallTab

    init(feature: ProFeature?) {
        self.feature = feature
        _tab = State(initialValue: PaywallTab(feature: feature))
    }

    private var selectedPlan: ProPlan? {
        store.plans.first { $0.id == selectedPlanID } ?? store.plans.first
    }

    /// 누르다 온 기능 한 문장 + 같이 열리는 나머지(보조색).
    private var lead: (String, String?) {
        switch feature {
        case .monthlyTrends:
            return (String(localized: "월 추이는 Pro에서 열려요."), String(localized: "조금씩 줄이기·위젯·선물도 함께요."))
        case .reductionGoal:
            return (String(localized: "조금씩 줄이기는 Pro에서 열려요."), String(localized: "월 추이·위젯·선물도 함께요."))
        case .gifts:
            return (String(localized: "마음 말고 다른 선물은 Pro에서 와요."), String(localized: "월 추이·조금씩 줄이기·위젯도 함께요."))
        case nil:
            return (String(localized: "한 번 결제로 Pro 기능이 모두 열려요."), nil)
        }
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    masthead
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .zIndex(1)

                    PaywallSpread(tab: $tab, width: geo.size.width)

                    VStack(alignment: .leading, spacing: 0) {
                        Text("덜 마신 날을\n더 잘 보이게")
                            .font(AppFont.pretendard(28, .black, relativeTo: .title))
                            .tracking(AppFont.displayTracking(for: 28))
                            .foregroundStyle(Color.ink)

                        deck
                            .padding(.top, 6)

                        plans
                            .padding(.top, 18)

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
                    .padding(.top, -10)
                    .padding(.bottom, 8)
                }
            }
            .scrollIndicators(.hidden)
        }
        .background(Color.white.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { footer }
        .task { await store.loadPlans() }
        // 구매가 끝나면 원래 하려던 걸 하러 돌아간다.
        .onChange(of: store.isPro) { _, isPro in
            if isPro { dismiss() }
        }
    }

    /// 잡지 머리글. 아래 겹줄은 CSS `3px double`(1pt 선 두 줄, 사이 1pt).
    private var masthead: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: "SUGARCAP")
                    .font(.custom(PaywallStyle.mastheadFont, fixedSize: 20))
                    .tracking(2.4)
                Spacer(minLength: 8)
                Text(verbatim: "Pro Issue")
                    .font(AppFont.pretendardFixed(9.5, .bold))
                    .tracking(1.52)
                    .textCase(.uppercase)
                Spacer(minLength: 8)
                Button { dismiss() } label: {
                    Text("닫기")
                        .font(AppFont.pretendard(15, .regular, relativeTo: .subheadline))
                        .tapTarget()
                }
                .accessibilityIdentifier("paywall-close")
            }
            .foregroundStyle(Color.ink)
            .padding(.bottom, -12)

            VStack(spacing: 1) {
                Rectangle().frame(height: 1)
                Rectangle().frame(height: 1)
            }
            .foregroundStyle(Color.ink)
        }
        .background(Color.white)
    }

    private var deck: some View {
        let (first, rest) = lead
        return VStack(alignment: .leading, spacing: 0) {
            Text(first)
                .foregroundStyle(Color.ink)
                .accessibilityIdentifier("paywall-lead")
            if let rest {
                Text(rest)
                    .foregroundStyle(PaywallStyle.sub)
            }
        }
        .font(AppFont.pretendard(14, .regular, relativeTo: .subheadline))
        .lineSpacing(3)
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
                .tint(Color.ink)
                .frame(maxWidth: .infinity)
            }
        } else if typeSize.isAccessibilitySize {
            VStack(spacing: 12) {
                ForEach(store.plans) { plan in
                    planCard(plan, flat: true)
                }
            }
        } else {
            staggeredPlans
        }
    }

    /// 연간 왼쪽 위, 평생 오른쪽 아래. 둘 다 지면과 같은 기울기로 돌린다.
    private var staggeredPlans: some View {
        GeometryReader { geo in
            let cardWidth = min(196, geo.size.width * 0.56)
            ZStack(alignment: .topLeading) {
                ForEach(store.plans) { plan in
                    planCard(plan, flat: false)
                        .frame(width: cardWidth)
                        .rotationEffect(PaywallStyle.tilt)
                        .offset(x: plan.isLifetime ? geo.size.width - cardWidth : 0, y: plan.isLifetime ? 66 : 14)
                        .zIndex(plan.isLifetime ? 1 : 0)
                }
            }
        }
        .frame(height: 140)
    }

    /// 위아래 굵은 선 두 줄. 선택된 칸은 위 선이 4pt로 두꺼워지고 글자가 먹색이 된다. 누르면 선택만 바뀌고, 결제는 아래 버튼이 한다.
    private func planCard(_ plan: ProPlan, flat: Bool) -> some View {
        let selected = plan.id == selectedPlanID
        let alignment: HorizontalAlignment = plan.isLifetime && !flat ? .trailing : .leading
        let tone = selected ? Color.ink : PaywallStyle.sub
        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                selectedPlanID = plan.id
            }
        } label: {
            VStack(alignment: alignment, spacing: 1) {
                HStack(spacing: 0) {
                    Text(plan.title)
                    if plan.isLifetime {
                        Text(verbatim: " · ")
                        Text("추천").foregroundStyle(PaywallStyle.sugar)
                    }
                }
                .font(flat ? AppFont.pretendard(11, .bold, relativeTo: .caption) : AppFont.pretendardFixed(11, .bold))
                .tracking(0.22)
                .foregroundStyle(tone)

                priceLabel(plan.price, flat: flat)
                    .foregroundStyle(tone)

                if let note = plan.note {
                    Text(note)
                        .font(flat ? AppFont.pretendard(11, .regular, relativeTo: .caption) : AppFont.pretendardFixed(11, .regular))
                        .foregroundStyle(PaywallStyle.sub)
                }
            }
            .multilineTextAlignment(alignment == .trailing ? .trailing : .leading)
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 9)
            .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
            .background(Color.white)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.ink).frame(height: selected ? 4 : 1.5)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.ink).frame(height: 1.5)
            }
            .overlay(alignment: .topLeading) {
                if plan.isLifetime && !flat {
                    PlanDuo(isAnimated: !reduceMotion)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("plan-\(plan.id)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// 통화 기호(₩·$·NT$)는 숫자 절반 크기로 앞에 붙인다. 가격 글자는 StoreKit `displayPrice` 그대로다.
    private func priceLabel(_ price: String, flat: Bool) -> some View {
        let split = price.firstIndex(where: \.isNumber) ?? price.startIndex
        let symbol = String(price[..<split])
        let amount = String(price[split...])
        return HStack(alignment: .firstTextBaseline, spacing: 1) {
            if !symbol.isEmpty {
                Text(verbatim: symbol)
                    .font(flat ? Font.custom(CupHero.fontName, size: 20, relativeTo: .title3) : Font.custom(CupHero.fontName, fixedSize: 20))
            }
            Text(verbatim: amount)
                .font(flat ? Font.custom(CupHero.fontName, size: 40, relativeTo: .largeTitle) : Font.custom(CupHero.fontName, fixedSize: 40))
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Button {
                guard let plan = selectedPlan else { return }
                Task { await store.purchase(plan.id) }
            } label: {
                Group {
                    if store.purchasingID != nil {
                        ProgressView().tint(.white)
                    } else {
                        Text(selectedPlan.map { String(localized: "\($0.title)으로 시작") } ?? String(localized: "시작"))
                    }
                }
                .ctaLabel()
                .foregroundStyle(.white)
                .background(Color.ink.opacity(store.plans.isEmpty ? 0.4 : 1), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
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
        .background(Color.white)
    }

    /// 자동 갱신 안내와 약관 링크. 심사 필수라 어느 글자 크기에서도 빠지지 않는다.
    private var legal: some View {
        VStack(spacing: 7) {
            Text("연간 구독은 기간이 끝나기 24시간 전에 해지하지 않으면 자동으로 갱신돼요. 해지는 App Store 계정 설정에서 해요.")
                .font(AppFont.pretendard(10.5, .regular, relativeTo: .caption2))
                .lineSpacing(2)
                .foregroundStyle(PaywallStyle.sub)
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
            .tint(Color.ink)
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
            if separated { Text(verbatim: "·").foregroundStyle(PaywallStyle.sub) }
            Link("이용약관", destination: terms)
                .fixedSize()
        }
        if let privacy = AppLinks.privacyPolicy {
            if separated { Text(verbatim: "·").foregroundStyle(PaywallStyle.sub) }
            Link("개인정보처리방침", destination: privacy)
                .fixedSize()
        }
    }
}

/// 시안의 색·기울기. 앱 액센트와 별개로 이 지면에서만 쓴다.
private enum PaywallStyle {
    static let tilt = Angle.degrees(-8)
    static let sub = Color.ink.opacity(0.58)
    static let sugar = Color(red: 0x69 / 255, green: 0x83 / 255, blue: 0x94 / 255)
    static let caffeine = Color(red: 0x4A / 255, green: 0x32 / 255, blue: 0x26 / 255)
    /// Playfair Display Black 서브셋(이름 변경, OFL). `Resources/Fonts/LICENSE-SugarCapMasthead.txt`.
    static let mastheadFont = "SugarCapMasthead-Black"
}

/// 검은 띠의 탭. 위젯은 Pro 기능이지만 누르다 올 자리가 없어 `ProFeature`에는 없다.
enum PaywallTab: String, CaseIterable, Identifiable {
    case monthlyTrends, reductionGoal, widget, gifts

    var id: String { rawValue }

    /// 설정에서 오면(nil) 월 추이부터 연다.
    init(feature: ProFeature?) {
        switch feature {
        case .monthlyTrends, nil: self = .monthlyTrends
        case .reductionGoal: self = .reductionGoal
        case .gifts: self = .gifts
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .monthlyTrends: "월 추이"
        case .reductionGoal: "조금씩 줄이기"
        case .widget: "위젯"
        case .gifts: "선물"
        }
    }

    /// 띠 위 기사(사진 왼쪽)와 띠 아래 기사(사진 오른쪽).
    var stories: (PaywallStory, PaywallStory) {
        switch self {
        case .monthlyTrends:
            return (
                PaywallStory(tone: .sugar, label: "Monthly · 월 추이", word: "한 달", text: "**그날 먹은 양**이\n접시 사진으로 찍혀요.", visual: .month),
                PaywallStory(tone: .sugar, label: "Stats · 다양한 통계", word: "통계", text: "각설탕 환산, 지난달 대비까지\n**다양한 통계**를 보여 줘요.", visual: .photo("month-cell-sugar-100"))
            )
        case .reductionGoal:
            return (
                PaywallStory(tone: .sugar, label: "Step down · 조금씩 줄이기", word: "조금씩", text: "**주마다 기준**을\n조금씩 낮춰 가요.", visual: .photo("paywall-latte")),
                PaywallStory(tone: .caffeine, label: "Progress · 진행", word: "지킨 주", text: "**몇 주를 지켰는지**\n막대로 차올라요.", visual: .photo("paywall-americano"))
            )
        case .widget:
            return (
                PaywallStory(tone: .sugar, label: "Widget · 위젯", word: "홈 화면", text: "앱을 안 열어도\n**남은 양**이 보여요.", visual: .widget),
                PaywallStory(tone: .caffeine, label: "Together · 같이", word: "같이", text: "**로슈와 카인**도\n홈 화면에서 기다려요.", visual: .waiting)
            )
        case .gifts:
            return (
                PaywallStory(tone: .sugar, label: "Gifts · 선물", word: "선물", text: "로슈와 카인과\n**더 친해질 수 있어요.**", visual: .carrying),
                PaywallStory(tone: .caffeine, label: "Items · 물건", word: "물건", text: "**다양한 선물**을\n받을 수 있어요.", visual: .photo("paywall-items"))
            )
        }
    }
}

struct PaywallStory {
    enum Tone { case sugar, caffeine }
    enum Visual {
        case month, widget, waiting, carrying
        case photo(String)
    }

    let tone: Tone
    let label: LocalizedStringResource
    let word: LocalizedStringResource
    /// `**굵게**` 부분은 먹색 Bold, 나머지는 보조색.
    let text: LocalizedStringResource
    let visual: Visual
}

/// 기운 지면. 칸은 반듯하고 안쪽 판(폭 480)만 돌린다. 아래 가장자리도 같은 기울기로 자른다.
/// 판 크기와 글자는 고정(그림처럼 짜인 배치). 시안 기준 폭 393에서 판 중심이 (가운데, 146)이다.
private struct PaywallSpread: View {
    @Binding var tab: PaywallTab
    let width: CGFloat

    var body: some View {
        let stories = tab.stories
        VStack(spacing: 0) {
            StoryRow(story: stories.0, photoLeading: true)
                .frame(height: 160)
            ticker
                .padding(.top, 8)
            StoryRow(story: stories.1, photoLeading: false)
                .frame(height: 150)
                .padding(.top, 6)
        }
        .id(tab)
        .transition(.opacity)
        .frame(width: 480)
        .rotationEffect(PaywallStyle.tilt)
        .position(x: width / 2, y: 146)
        .frame(width: width, height: 326)
        .clipShape(SpreadEdge())
    }

    /// 판(480)보다 양옆 40씩 긴 검은 띠. 글자가 화면 밖으로 나가면 한 단계씩 줄인다(영어 탭 이름이 길다).
    private var ticker: some View {
        ViewThatFits(in: .horizontal) {
            tabRow(size: 12.5, gap: 14)
            tabRow(size: 11, gap: 9)
            tabRow(size: 10, gap: 6)
        }
        // 띠 왼쪽 끝은 화면 기준 x ≈ -84, 첫 글자는 +100. 오른쪽 화면 끝 16pt 안에서 끝나야 한다.
        .frame(width: max(width - 32, 240), alignment: .leading)
        .padding(.leading, 100)
        .frame(width: 560, height: 32, alignment: .leading)
        .background(Color.ink)
    }

    private func tabRow(size: CGFloat, gap: CGFloat) -> some View {
        HStack(spacing: gap) {
            Text(verbatim: "Pro")
                .font(AppFont.pretendardFixed(10, .bold))
                .tracking(2)
                .textCase(.uppercase)
                .foregroundStyle(.white)
            ForEach(PaywallTab.allCases) { item in
                Rectangle().fill(.white).frame(width: 4, height: 4)
                let on = item == tab
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { tab = item }
                } label: {
                    Text(item.title)
                        .font(AppFont.pretendardFixed(size, .bold))
                        .foregroundStyle(.white.opacity(on ? 1 : 0.72))
                        .padding(.vertical, 8)
                        .overlay(alignment: .bottom) {
                            if on { Rectangle().fill(.white).frame(height: 2).padding(.bottom, 6) }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .fixedSize()
                .accessibilityIdentifier("paywall-tab-\(item.rawValue)")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .fixedSize()
    }
}

/// 지면 아래 가장자리: 왼쪽 끝은 바닥, 오른쪽 끝은 높이 83%.
private struct SpreadEdge: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.83))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}

/// 기사 한 줄. 위 기사는 사진이 왼쪽(왼쪽 여백 52), 아래 기사는 오른쪽(오른쪽 여백 58)이다.
private struct StoryRow: View {
    let story: PaywallStory
    let photoLeading: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if photoLeading {
                photo
                copy
            } else {
                copy
                photo
            }
        }
        .padding(.leading, photoLeading ? 52 : 0)
        .padding(.trailing, photoLeading ? 0 : 58)
    }

    private var photo: some View {
        StoryVisual(visual: story.visual)
            .frame(width: 150)
            .frame(maxHeight: .infinity)
            .clipped()
            .accessibilityHidden(true)
    }

    private var toneColor: Color {
        story.tone == .sugar ? PaywallStyle.sugar : PaywallStyle.caffeine
    }

    private var copy: some View {
        let align: HorizontalAlignment = photoLeading ? .leading : .trailing
        return VStack(alignment: align, spacing: 0) {
            Text(story.label)
                .font(AppFont.pretendardFixed(9.5, .bold))
                .tracking(1.52)
                .textCase(.uppercase)
                .foregroundStyle(toneColor)
                .lineLimit(1)
            TexturedWord(word: story.word, tone: story.tone)
                .padding(.top, 3)
                .padding(.bottom, 5)
            Text(bodyText)
                .font(AppFont.pretendardFixed(12.5, .regular))
                .lineSpacing(2.5)
                .foregroundStyle(PaywallStyle.sub)
                .multilineTextAlignment(photoLeading ? .leading : .trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: align, vertical: .top))
        .padding(.horizontal, 12)
        .padding(.top, photoLeading ? 40 : 14)
        .accessibilityElement(children: .combine)
    }

    private var bodyText: AttributedString {
        var text = AttributedString(localized: story.text)
        let strong = text.runs
            .filter { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true }
            .map(\.range)
        for range in strong {
            text[range].inlinePresentationIntent = nil
            text[range].font = AppFont.pretendardFixed(12.5, .bold)
            text[range].foregroundColor = Color.ink
        }
        return text
    }
}

/// 사진 결을 채운 큰 단어(CSS `background-clip: text`). 당은 각설탕 사진에 회청색을 곱하고, 카페인은 원두 사진 그대로.
private struct TexturedWord: View {
    let word: LocalizedStringResource
    let tone: PaywallStory.Tone

    var body: some View {
        label
            .foregroundStyle(.clear)
            .overlay {
                texture
                    .mask { label }
            }
            .accessibilityLabel(Text(word))
    }

    private var label: some View {
        Text(word)
            .font(AppFont.pretendardFixed(54, .black))
            .tracking(AppFont.displayTracking(for: 54))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    @ViewBuilder
    private var texture: some View {
        switch tone {
        case .sugar:
            ZStack {
                PaywallStyle.sugar
                Image("paywall-tex-sugar")
                    .resizable()
                    .scaledToFill()
                    .blendMode(.multiply)
            }
            .compositingGroup()
        case .caffeine:
            ZStack {
                PaywallStyle.caffeine
                Image("paywall-tex-beans")
                    .resizable()
                    .scaledToFill()
            }
        }
    }
}

/// 기사 사진 칸 안의 그림. 벽 색은 오늘 화면과 같은 `CupView.wallColor`.
private struct StoryVisual: View {
    let visual: PaywallStory.Visual

    var body: some View {
        switch visual {
        case .photo(let name):
            Image(name)
                .resizable()
                .scaledToFill()
        case .month:
            month
        case .widget:
            widget
        case .waiting:
            CupView.wallColor
                .overlay(alignment: .bottomLeading) {
                    HStack(alignment: .bottom, spacing: 6) {
                        character("paywall-roshu-watch", height: 70, outlined: true)
                        character("paywall-kain-sit", height: 64, outlined: false)
                    }
                    .padding(.leading, 14)
                    .padding(.bottom, 26)
                }
        case .carrying:
            CupView.wallColor
                .overlay(alignment: .bottomTrailing) {
                    HStack(alignment: .bottom, spacing: -4) {
                        character("paywall-roshu-gift", height: 72, outlined: true)
                        character("paywall-kain-gift", height: 60, outlined: false)
                    }
                    .padding(.trailing, 8)
                    .padding(.bottom, 22)
                }
        }
    }

    /// 그날 접시 사진 아홉 칸(월 추이 달력 칸 그대로).
    private var month: some View {
        let cells = ["sugar-30", "sugar-80", "caffeine-30", "sugar-0", "caffeine-50", "sugar-50", "caffeine-80", "sugar-100", "sugar-30"]
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)
        return GeometryReader { geo in
            let cellHeight = (geo.size.height - 4 - 4) / 3
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                    Color.clear
                        .frame(height: cellHeight)
                        .overlay {
                            Image("month-cell-\(cell)")
                                .resizable()
                                .scaledToFill()
                        }
                        .clipped()
                }
            }
            .padding(2)
        }
        .background(Color.white)
    }

    /// 홈 화면 위 Small 위젯 모형.
    private var widget: some View {
        // 넘치는 배경 사진 폭이 아니라 칸 폭을 기준으로 위젯을 오른쪽에 붙인다.
        Color.clear
            .background {
                Image("month-bg-sugar-01")
                    .resizable()
                    .scaledToFill()
            }
            .overlay(alignment: .trailing) {
                HStack(spacing: 0) {
                    widgetColumn("cutout-strawberry-latte-50", amount: "18", unit: "g", caption: "남은 당")
                    widgetColumn("cutout-iced-americano-50", amount: "95", unit: "mg", caption: "남은 카페인")
                }
                .padding(.horizontal, 6)
                .padding(.top, 10)
                .padding(.bottom, 9)
                .frame(width: 112, height: 112)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .shadow(color: Color.ink.opacity(0.18), radius: 4, y: 2)
                .padding(.trailing, 10)
            }
    }

    private func widgetColumn(_ image: String, amount: String, unit: String, caption: LocalizedStringResource) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Image(image)
                .resizable()
                .scaledToFit()
                .frame(height: 54)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(verbatim: amount).font(.custom(CupHero.fontName, fixedSize: 21))
                Text(verbatim: unit).font(AppFont.pretendardFixed(9, .bold))
            }
            .foregroundStyle(Color.ink)
            .padding(.top, 3)
            Text(caption)
                .font(AppFont.pretendardFixed(8.5, .semibold))
                .foregroundStyle(PaywallStyle.sub)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    /// 로슈는 흰 몸이라 벽 위에서 윤곽이 사라진다. 아주 얇은 먹색 테를 두른다(번짐 없는 0.6pt).
    private func character(_ name: String, height: CGFloat, outlined: Bool) -> some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .shadow(color: outlined ? Color.ink.opacity(0.55) : .clear, radius: 0.6)
            .shadow(color: outlined ? Color.ink.opacity(0.35) : .clear, radius: 0.6)
    }
}

/// 평생 칸 위에 앉은 로슈·카인. 로슈는 좌우로 까딱, 카인은 통통 뛰다 오른쪽으로 갸웃(한 바퀴 회전 금지).
/// 위치는 시안(`.duo` top -50 · left 14, 원본 높이 54·49)을 크롭한 그림 기준으로 환산했다: 칸 위 선에서 로슈 6.2pt, 카인 3pt 위.
private struct PlanDuo: View {
    let isAnimated: Bool

    private struct Key {
        let at: Double
        let y: Double
        let scaleY: Double
        let angle: Double
    }

    /// 시안 `@keyframes kain-hop`(3.2s, 0.6s 늦게 시작).
    nonisolated private static let kainKeys = [
        Key(at: 0, y: 0, scaleY: 1, angle: 0),
        Key(at: 0.08, y: -9, scaleY: 1, angle: 0),
        Key(at: 0.16, y: 0, scaleY: 0.94, angle: 0),
        Key(at: 0.22, y: -5, scaleY: 1, angle: 0),
        Key(at: 0.30, y: 0, scaleY: 1, angle: 0),
        Key(at: 0.60, y: 0, scaleY: 1, angle: 12),
        Key(at: 0.80, y: 0, scaleY: 1, angle: 12),
        Key(at: 1, y: 0, scaleY: 1, angle: 0),
    ]

    nonisolated private static func kainPose(_ phase: Double) -> Key {
        for (a, b) in zip(kainKeys, kainKeys.dropFirst()) where phase <= b.at {
            let k = Ease.power2Out((phase - a.at) / (b.at - a.at))
            return Key(
                at: phase,
                y: Motion.lerp(a.y, b.y, k),
                scaleY: Motion.lerp(a.scaleY, b.scaleY, k),
                angle: Motion.lerp(a.angle, b.angle, k)
            )
        }
        return kainKeys[0]
    }

    var body: some View {
        TimelineView(.animation(paused: !isAnimated)) { timeline in
            let t = isAnimated ? timeline.date.timeIntervalSinceReferenceDate : 0
            let roshuAngle = isAnimated ? -5 * cos(t / 2.4 * 2 * .pi) : 0
            let kain = isAnimated ? Self.kainPose(((t - 0.6) / 3.2).truncatingRemainder(dividingBy: 1)) : Self.kainKeys[0]
            ZStack(alignment: .topLeading) {
                Image("paywall-roshu-wave")
                    .resizable()
                    .frame(width: 24.6, height: 28.5)
                    .shadow(color: Color.ink.opacity(0.55), radius: 0.6)
                    .shadow(color: Color.ink.opacity(0.35), radius: 0.6)
                    .rotationEffect(.degrees(roshuAngle), anchor: .bottom)
                    .offset(x: 27.2, y: -34.7)
                Image("paywall-kain-rim-stand")
                    .resizable()
                    .frame(width: 16.7, height: 34.3)
                    .scaleEffect(x: 1, y: kain.scaleY, anchor: .bottom)
                    .rotationEffect(.degrees(kain.angle), anchor: .bottom)
                    .offset(x: 53.3, y: -37.3 + kain.y)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview {
    PaywallView(feature: .monthlyTrends)
        .environment(ProStore(previewPlans: ProStore.mockPlans, isPro: false))
}
