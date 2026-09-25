import OSLog
import SwiftData
import SwiftUI

/// 설정 탭(SPEC §4.4). Phase 2a 범위: 하루 기준 2개, 하루 경계 시각, 마감 가능 시각, 정보.
/// 즐겨찾기 정렬은 즐겨찾기 기능과 함께, Pro 구매·복원은 Phase 3에서 붙는다.
///
/// 2026-09-24 재설계: 큰 제목 `Form` 대신 다른 화면과 같은 글자 규칙(§5)으로 짠다.
/// 소제목 → 현재 기준 숫자 → 카드. 조작 컨트롤은 전부 네이티브 그대로다.
struct SettingsView: View {
    let catalog: Catalog

    @Query private var settingsRows: [AppSettings]
    @Query private var goals: [ReductionGoal]
    @Environment(\.modelContext) private var context

    var body: some View {
        NavigationStack {
            Group {
                // 설정 행은 루트가 첫 프레임에 만든다(`RootView.ensureSettings`).
                if let settings = settingsRows.first {
                    SettingsContent(settings: settings, catalog: catalog, goals: goals, context: context)
                } else {
                    ProgressView()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

/// 당 하루 기준 프리셋(§3·§9.1). 사용자가 고를 수 있는 값은 이 셋뿐이다.
enum SugarPreset {
    static let values: [Double] = [25, 50, 100]
}

/// 카페인 하루 기준 슬라이더 범위(§3). 감소 목표 반올림 단위(§9.5, 25mg)와 간격을 맞춘다.
enum CaffeineRange {
    static let bounds: ClosedRange<Double> = 100...600
    static let step: Double = 25
}

/// 시각 선택지. 하루 경계는 새벽, 마감 가능 시각은 저녁으로만 연다.
/// 경계를 낮으로 옮기면 "하루"의 뜻이 무너지고, 마감을 낮에 열면 이른 마감 방지(§4.7)가 무의미해진다.
enum HourChoices {
    static let dayBoundary = Array(0...6)
    static let closeFrom = Array(18...23)

    static func label(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return date.formatted(.dateTime.hour())
    }
}

private struct SettingsContent: View {
    @Bindable var settings: AppSettings
    let catalog: Catalog
    let goals: [ReductionGoal]
    let context: ModelContext

    @State private var editingSide: CupSide?
    @State private var paywall: ProFeature?
    @State private var showsOnboarding = false

    @Environment(ProStore.self) private var pro

    private func goal(_ side: CupSide) -> ReductionGoal? {
        goals.first { $0.side == side.rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    card { limitsRows }
                    footnote("기본값은 당 50 g(WHO 권고), 카페인 400 mg(식약처 성인 권고)이에요.")
                }

                section("감소 목표", footer: "한 주에 5일 이상 하루 기준 이내면 다음 주 기준이 조금 내려가요. 미달한 주는 기준을 그대로 둬요.") {
                    goalRow(.sugar)
                    rowDivider
                    goalRow(.caffeine)
                }

                section("시간", footer: "하루가 바뀌는 시각 전에 마신 음료는 전날 몫으로 들어가요.") {
                    hourRow("하루가 바뀌는 시각", selection: $settings.dayBoundaryHour, choices: HourChoices.dayBoundary)
                    rowDivider
                    hourRow("오늘 마감을 여는 시각", selection: $settings.closeFromHour, choices: HourChoices.closeFrom)
                }

                section("Pro") {
                    if pro.isPro {
                        valueRow("슈가캡 Pro", value: "사용 중")
                    } else {
                        Button {
                            paywall = .affinityDetail
                        } label: {
                            HStack {
                                Text("슈가캡 Pro 보기")
                                    .foregroundStyle(.tint)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .rowPadding()
                        }
                        .accessibilityIdentifier("open-paywall")
                    }
                    rowDivider
                    Button {
                        Task { await pro.restore() }
                    } label: {
                        Text("구매 복원")
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .rowPadding()
                    }
                }

                section("정보", footer: "기록은 이 기기에만 저장돼요. 수집하는 정보는 없어요.") {
                    Button {
                        showsOnboarding = true
                    } label: {
                        HStack {
                            Text("앱 소개 다시 보기")
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .rowPadding()
                    }
                    .accessibilityIdentifier("replay-onboarding")
                    rowDivider
                    valueRow(
                        "메뉴 데이터",
                        value: catalog.builtAtDate?.formatted(date: .abbreviated, time: .omitted) ?? catalog.builtAt
                    )
                    rowDivider
                    valueRow("버전", value: Self.appVersion)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .sheet(item: $paywall) { feature in
            PaywallView(feature: feature)
        }
        // 온보딩 화면을 그대로 전체 화면으로 띄운다. 완료 플래그는 건드리지 않는다.
        .fullScreenCover(isPresented: $showsOnboarding) {
            OnboardingView(
                brands: catalog.brands,
                onStart: { showsOnboarding = false },
                onClose: { showsOnboarding = false }
            )
        }
        .sheet(item: $editingSide) { side in
            ReductionGoalSheet(side: side, currentLimit: side.limit(settings.limits)) { target, weeks in
                start(side, target: target, weeks: weeks)
            }
        }
    }

    // MARK: 헤더

    /// 보조 라벨 → 소제목 → 현재 기준 두 개. 온보딩의 기준 카드와 같은 문법이라 첫 화면에서 본 값을
    /// 여기서 다시 만난다. 값이 둘이라 96pt 주인공 숫자는 쓰지 않는다.
    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("설정")
                .dateLabel()
                .padding(.top, 8)
            Text("하루 기준")
                .kicker()
                .padding(.top, 28)
            HStack(alignment: .firstTextBaseline, spacing: 24) {
                limitSummary(.sugar)
                limitSummary(.caffeine)
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 4)
    }

    private func limitSummary(_ side: CupSide) -> some View {
        let value = side.limit(settings.limits)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(Amount.number(value))
                    .font(.system(size: 40, weight: .bold))
                    .tracking(-1.6)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(side.unit)
                    .font(.system(size: 17, weight: .medium))
                    .opacity(0.85)
            }
            Text("\(side.label) · \(limitSource(side))")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .animation(.default, value: value)
    }

    /// 숫자 밑에 붙는 출처. 기본값이면 권고 기관, 바꿨으면 그 사실, 감소 목표 중이면 목표를 적는다.
    private func limitSource(_ side: CupSide) -> String {
        if let goal = goal(side) {
            return "목표 \(Amount.number(goal.target)) \(side.unit)까지"
        }
        let isDefault = side.limit(settings.limits) == side.limit(.default)
        switch side {
        case .sugar: return isDefault ? "WHO 권고" : "직접 설정"
        case .caffeine: return isDefault ? "식약처 권고" : "직접 설정"
        }
    }

    // MARK: 하루 기준 카드

    @ViewBuilder
    private var limitsRows: some View {
        // 감소 목표가 도는 동안에는 기준을 목표가 주마다 쓴다. 손으로 못 바꾸게 막는다.
        if goal(.sugar) != nil {
            managedLimitRow(.sugar, value: settings.sugarLimitG)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text(CupSide.sugar.label)
                Picker(CupSide.sugar.label, selection: $settings.sugarLimitG) {
                    ForEach(SugarPreset.values, id: \.self) { value in
                        Text("\(Amount.number(value)) \(CupSide.sugar.unit)").tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("sugar-limit")
            }
            .rowPadding()
        }

        rowDivider

        if goal(.caffeine) != nil {
            managedLimitRow(.caffeine, value: settings.caffeineLimitMg)
        } else {
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
                .accessibilityIdentifier("caffeine-limit")
            }
            .rowPadding()
        }
    }

    private func managedLimitRow(_ side: CupSide, value: Double) -> some View {
        HStack {
            Text(side.label)
            Spacer()
            Text("\(Amount.number(value)) \(side.unit)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Image(systemName: "lock")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .rowPadding()
        .accessibilityElement(children: .combine)
        .accessibilityHint("감소 목표가 이번 주 기준을 정해요")
    }

    // MARK: 감소 목표

    @ViewBuilder
    private func goalRow(_ side: CupSide) -> some View {
        if let goal = goal(side) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(side.label)
                    Spacer()
                    Text("이번 주 \(Amount.number(side.limit(settings.limits))) → 목표 \(Amount.number(goal.target)) \(side.unit)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("\(goal.weeks)주 계획 · \(goal.achievedWeeks)주 달성")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("그만두기", role: .destructive) { stop(side) }
                        .font(.footnote)
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                }
            }
            .rowPadding()
        } else {
            Button {
                // 감소 목표는 Pro다(§6).
                if pro.isPro {
                    editingSide = side
                } else {
                    paywall = .reductionGoal
                }
            } label: {
                HStack {
                    Text("\(side.label) 줄이기 시작")
                        .foregroundStyle(.tint)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: pro.isPro ? "chevron.right" : "lock")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .rowPadding()
            }
            .accessibilityIdentifier("start-goal-\(side.rawValue)")
        }
    }

    // MARK: 행·카드 부품

    /// 시각 행. 값은 메뉴 피커라 한 번에 고른다. 보조 조작이라 액센트를 쓰지 않는다.
    private func hourRow(_ title: String, selection: Binding<Int>, choices: [Int]) -> some View {
        HStack {
            Text(title)
            Spacer()
            Picker(title, selection: selection) {
                ForEach(choices, id: \.self) { hour in
                    Text(HourChoices.label(hour)).tag(hour)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(Color.secondary)
        }
        .rowPadding()
    }

    private func valueRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .rowPadding()
        .accessibilityElement(children: .combine)
    }

    private var rowDivider: some View {
        Divider().padding(.leading, 16)
    }

    private func section<Content: View>(
        _ title: String, footer: String? = nil, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .kicker()
                .padding(.leading, 4)
            card(content: content)
            if let footer {
                footnote(footer)
            }
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0, content: content)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
    }

    // MARK: 동작

    private func start(_ side: CupSide, target: Double, weeks: Int) {
        do {
            let today = DayKey(at: Date(), boundaryHour: settings.dayBoundaryHour)
            try ReductionStore.start(
                side: side, target: target, weeks: weeks, settings: settings, today: today,
                in: context
            )
            try context.save()
        } catch {
            Self.logger.error("감소 목표 시작 실패: \(String(describing: error), privacy: .public)")
        }
    }

    private func stop(_ side: CupSide) {
        do {
            try ReductionStore.stop(side: side, in: context)
            try context.save()
        } catch {
            Self.logger.error("감소 목표 중단 실패: \(String(describing: error), privacy: .public)")
        }
    }

    private static let logger = Logger(subsystem: "com.sugarcap.app", category: "settings")

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

private extension View {
    /// 카드 안 한 행의 여백. 행마다 같은 값이라야 카드가 한 덩어리로 읽힌다.
    func rowPadding() -> some View {
        padding(.horizontal, 16)
            .padding(.vertical, 14)
    }
}
