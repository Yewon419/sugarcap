import SwiftData
import SwiftUI

/// 온보딩 4페이지(SPEC §4.5, 2026-09-25 개정). 컵 → 기록 → 먹이기 → 하루 기준.
/// 앞 세 장은 컵 장면 위에 카피만, 넷째 장은 설정과 같은 네이티브 컨트롤로 기준을 정한다.
/// 계정·페이월 없음. 완료 여부는 기기 단위 플래그라 SwiftData가 아니라 UserDefaults에 둔다.
struct OnboardingView: View {
    static let completedKey = "onboardingCompleted"
    /// Debug 전용 실행 인자. CI가 각 페이지를 찍을 때 `-onboardingPage 3`처럼 넘긴다.
    static let pageArgumentKey = "onboardingPage"

    let brands: [Brand]
    let onStart: () -> Void

    @Query private var settingsRows: [AppSettings]
    @State private var page: Int = Self.initialPage
    /// 첫 장에서 컵이 100%에서 70%로 한 번 줄어든다. "마실 때마다 줄어드는 컵"을 말 대신 보여 준다.
    @State private var firstCupStep = 100

    private static var initialPage: Int {
        #if DEBUG
        let requested = UserDefaults.standard.integer(forKey: pageArgumentKey)
        return (1...Page.allCases.count).contains(requested) ? requested - 1 : 0
        #else
        return 0
        #endif
    }

    private var isLast: Bool { page == Page.allCases.count - 1 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            background

            TabView(selection: $page) {
                ForEach(Page.allCases) { item in
                    pageContent(item)
                        .tag(item.rawValue)
                }
            }
            // 하단 인셋(점·버튼) 위에서 끝나야 장식(타일·캐릭터)이 바에 가려지지 않는다.
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .overlay(alignment: .topTrailing) {
            if !isLast {
                Button("건너뛰기") {
                    withAnimation(.easeInOut(duration: 0.3)) { page = Page.allCases.count - 1 }
                }
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .padding(.top, 20)
                .padding(.trailing, 24)
                .accessibilityIdentifier("onboarding-skip")
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 18) {
                pageDots
                Button {
                    if isLast {
                        onStart()
                    } else {
                        withAnimation(.easeInOut(duration: 0.3)) { page += 1 }
                    }
                } label: {
                    Text(isLast ? "시작" : "다음")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .accessibilityIdentifier(isLast ? "onboarding-start" : "onboarding-next")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
            .background(.white)
        }
        .onChange(of: page) { _, newValue in
            if newValue == 0 { firstCupStep = 100; scheduleFirstCupDrop() }
        }
        .onAppear(perform: scheduleFirstCupDrop)
    }

    // MARK: 배경

    /// 앞 세 장은 컵 장면. 넷째 장은 컨트롤 판독성을 위해 그룹 배경만 둔다(설정 화면과 같은 이유).
    @ViewBuilder
    private var background: some View {
        if isLast {
            Color(.systemGroupedBackground).ignoresSafeArea()
        } else {
            CupView(step: cupStep)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.6), value: cupStep)

            // 위는 글자 자리, 아래는 버튼 자리. 가운데만 컵이 보인다.
            LinearGradient(
                stops: [
                    .init(color: .white.opacity(0.96), location: 0),
                    .init(color: .white.opacity(0.9), location: 0.3),
                    .init(color: .white.opacity(0.5), location: 0.48),
                    .init(color: .white.opacity(0.88), location: 0.72),
                    .init(color: .white, location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }

    private var cupStep: Int {
        switch Page(rawValue: page) ?? .cup {
        case .cup: return firstCupStep
        case .record: return 50
        case .feeding, .limits: return 0
        }
    }

    private func scheduleFirstCupDrop() {
        guard page == 0 else { return }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if page == 0 { firstCupStep = 70 }
        }
    }

    // MARK: 페이지

    @ViewBuilder
    private func pageContent(_ item: Page) -> some View {
        switch item {
        case .cup:
            copyPage(
                kicker: "슈가캡",
                headline: "마실 때마다\n줄어드는 컵",
                caption: "하루 기준만큼 채워진 컵으로 하루가 시작돼요."
            )
        case .record:
            copyPage(
                kicker: "기록",
                headline: "탭 두 번이면\n기록 끝",
                caption: "카페 8곳 메뉴 1,300여 개가 들어 있어요."
            ) {
                brandPreview
            }
        case .feeding:
            copyPage(
                kicker: "밤에",
                headline: "남은 만큼을\n로슈와 카인에게",
                caption: "덜 마신 날일수록 많이 먹고, 그만큼 친해져요."
            ) {
                characters
            }
        case .limits:
            limitsPage
        }
    }

    /// 장식 없는 장. 제네릭 기본 인자는 타입 추론이 안 돼 따로 둔다.
    private func copyPage(kicker: String, headline: String, caption: String) -> some View {
        copyPage(kicker: kicker, headline: headline, caption: caption) { EmptyView() }
    }

    /// 소제목 → 40pt 헤드라인 → 15pt 캡션. 아래에 페이지별 장식 하나.
    private func copyPage<Decoration: View>(
        kicker: String, headline: String, caption: String,
        @ViewBuilder decoration: () -> Decoration
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(kicker)
                .kicker()
                .padding(.top, 40)
            Text(headline)
                .font(.system(size: 40, weight: .bold))
                .tracking(-0.8)
                .lineSpacing(2)
                .padding(.top, 16)
            Text(caption)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .padding(.top, 14)
            Spacer(minLength: 0)
            decoration()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    /// 기록 시트의 브랜드 타일을 축소해 보여 준다. 누를 수 없다.
    private var brandPreview: some View {
        let shown = Array(brands.prefix(4))
        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(shown) { brand in
                Text(brand.name)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .background(.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(.white, lineWidth: 1)
                    )
            }
        }
        .accessibilityHidden(true)
    }

    private var characters: some View {
        HStack(alignment: .bottom) {
            Image(CupSide.sugar.characterAsset)
                .resizable()
                .scaledToFit()
                .frame(height: 150)
                .accessibilityLabel(CupSide.sugar.characterName)
            Spacer()
            Image(CupSide.caffeine.characterAsset)
                .resizable()
                .scaledToFit()
                .frame(height: 118)
                .accessibilityLabel(CupSide.caffeine.characterName)
                .padding(.trailing, 12)
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 12)
    }

    // MARK: 하루 기준

    /// 설정 화면의 머리글·컨트롤과 같은 문법. 값은 설정 행에 바로 저장된다.
    @ViewBuilder
    private var limitsPage: some View {
        if let settings = settingsRows.first {
            LimitsForm(settings: settings)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(Page.allCases) { item in
                Capsule()
                    .fill(item.rawValue == page ? Color.accentColor : Color(.systemFill))
                    .frame(width: item.rawValue == page ? 20 : 8, height: 8)
                    .animation(.easeInOut(duration: 0.25), value: page)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(page + 1) / \(Page.allCases.count) 페이지")
    }
}

private enum Page: Int, CaseIterable, Identifiable {
    case cup, record, feeding, limits
    var id: Int { rawValue }
}

/// 넷째 장. 설정 화면의 하루 기준 카드와 같은 컨트롤이라 규칙(프리셋·범위)도 같은 정의를 쓴다.
private struct LimitsForm: View {
    @Bindable var settings: AppSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("하루 기준")
                        .kicker()
                        .padding(.top, 40)
                    Text("얼마나 마실지\n정해 두세요")
                        .font(.system(size: 40, weight: .bold))
                        .tracking(-0.8)
                        .lineSpacing(2)
                        .padding(.top, 16)
                    Text("나중에 설정에서 언제든 바꿀 수 있어요.")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .padding(.top, 14)
                }
                .padding(.leading, 4)

                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(CupSide.sugar.label)
                            Spacer()
                            Text("WHO 권고 50 g")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        Picker(CupSide.sugar.label, selection: $settings.sugarLimitG) {
                            ForEach(SugarPreset.values, id: \.self) { value in
                                Text("\(Amount.number(value)) \(CupSide.sugar.unit)").tag(value)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .accessibilityIdentifier("onboarding-sugar-limit")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                    Divider().padding(.leading, 16)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(CupSide.caffeine.label)
                            Spacer()
                            Text("\(Amount.number(settings.caffeineLimitMg)) \(CupSide.caffeine.unit)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: $settings.caffeineLimitMg,
                            in: CaffeineRange.bounds,
                            step: CaffeineRange.step
                        ) {
                            Text(CupSide.caffeine.label)
                        } minimumValueLabel: {
                            Text(Amount.number(CaffeineRange.bounds.lowerBound))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } maximumValueLabel: {
                            Text(Amount.number(CaffeineRange.bounds.upperBound))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityIdentifier("onboarding-caffeine-limit")
                        Text("식약처 성인 권고 400 mg")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .background(
                    Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }
}

#Preview {
    OnboardingView(brands: [], onStart: {})
        .modelContainer(for: [AppSettings.self], inMemory: true)
}
