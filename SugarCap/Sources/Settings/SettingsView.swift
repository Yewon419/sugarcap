import OSLog
import SwiftData
import SwiftUI

/// 설정 탭(SPEC §4.4). 2026-09-26 HTML 프로토타입 확정 = 추이 캐주얼과 같은 문법(흰 유리 카드, 큰 숫자, 방울·캐릭터).
/// 하루 기준 → 조금씩 줄이기 → 시간 → Pro → 기타. 조작 컨트롤(프리셋·슬라이더·시각 메뉴·확인 창)은 네이티브 그대로다.
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
    /// 특정 기능이 아니라 "Pro 보기"로 연 페이월. 부제에 기능 이름을 붙이지 않는다.
    @State private var showsGeneralPaywall = false
    /// 감소 목표를 누르다 페이월로 간 쪽. 구매하고 닫히면 목표 시트를 이어서 연다.
    @State private var pendingGoalSide: CupSide?
    @State private var showsOnboarding = false
    @State private var stoppingSide: CupSide?
    @State private var isRestoring = false
    @State private var alertMessage: String?

    @Environment(ProStore.self) private var pro

    private func goal(_ side: CupSide) -> ReductionGoal? {
        goals.first { $0.side == side.rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("설정")
                    .dateLabel()
                    .padding(.top, 8)
                    .padding(.horizontal, 4)

                limitsCard
                goalsCard
                timeCard
                proCard
                etcCard

                Text("슈가캡 \(Self.appVersion) · 메뉴 데이터 \(catalog.builtAtDate?.formatted(date: .abbreviated, time: .omitted) ?? catalog.builtAt)")
                    .font(AppFont.pretendard(11, .regular, relativeTo: .caption2))
                    .tracking(0.5)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 110)
        }
        .background(Color.wall.ignoresSafeArea())
        .sheet(item: $paywall, onDismiss: {
            if pro.isPro, let side = pendingGoalSide { editingSide = side }
            pendingGoalSide = nil
        }) { feature in
            PaywallView(feature: feature)
        }
        .sheet(isPresented: $showsGeneralPaywall) {
            PaywallView(feature: nil)
        }
        // 목표를 그만두면 쌓은 주 진행이 사라지고 되돌릴 수 없다. 한 번 더 묻는다.
        .confirmationDialog(
            "\(stoppingSide?.label ?? "") 줄이기를 그만둘까요?",
            isPresented: Binding(
                get: { stoppingSide != nil },
                set: { if !$0 { stoppingSide = nil } }
            ),
            titleVisibility: .visible,
            presenting: stoppingSide
        ) { side in
            Button("그만두기", role: .destructive) { stop(side) }
                .accessibilityIdentifier("confirm-stop-goal")
            Button("계속하기", role: .cancel) {}
        } message: { _ in
            Text("지금까지 달성한 주 기록이 사라지고, 하루 기준은 이번 주 값으로 남아요.")
        }
        .alert(
            alertMessage ?? "",
            isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )
        ) {
            Button("확인", role: .cancel) {}
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

    // MARK: 하루 기준

    /// 현재 기준 두 값(방울 + 숫자) → 당 프리셋 → 카페인 슬라이더. 줄이기 목표가 돌면 그쪽은 목표가 맡는다.
    private var limitsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("하루 기준").kicker()
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { limitFigure(.sugar); limitFigure(.caffeine) }
                VStack(alignment: .leading, spacing: 12) { limitFigure(.sugar); limitFigure(.caffeine) }
            }
            .padding(.top, 14)
            .padding(.bottom, 4)

            controlLabel(CupSide.sugar.label)
            if goal(.sugar) != nil {
                managedNote(.sugar)
            } else {
                Picker(CupSide.sugar.label, selection: $settings.sugarLimitG) {
                    ForEach(SugarPreset.values, id: \.self) { value in
                        Text("\(Amount.number(value)) \(CupSide.sugar.unit)").tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.top, 10)
                .accessibilityIdentifier("sugar-limit")
            }

            controlLabel(CupSide.caffeine.label)
            if goal(.caffeine) != nil {
                managedNote(.caffeine)
            } else {
                Slider(
                    value: $settings.caffeineLimitMg,
                    in: CaffeineRange.bounds,
                    step: CaffeineRange.step
                ) {
                    Text(CupSide.caffeine.label)
                } minimumValueLabel: {
                    Text(Amount.number(CaffeineRange.bounds.lowerBound)).cardNote()
                } maximumValueLabel: {
                    Text(Amount.number(CaffeineRange.bounds.upperBound)).cardNote()
                }
                .padding(.top, 6)
                .accessibilityIdentifier("caffeine-limit")
            }

            Text("기본값은 당 50 g(WHO 권고), 카페인 400 mg(식약처 성인 권고)이에요.")
                .cardNote()
                .padding(.top, 14)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsCard(radius: 28)
        .padding(.top, 4)
    }

    private func limitFigure(_ side: CupSide) -> some View {
        let value = side.limit(settings.limits)
        return HStack(spacing: 10) {
            Image(side.dropAsset)
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(Amount.number(value))
                        .font(AppFont.pretendard(28, .bold, relativeTo: .title))
                        .tracking(-1)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(side.unit)
                        .font(AppFont.pretendard(13, .medium, relativeTo: .footnote))
                }
                Text("\(side.label) · \(limitSource(side))")
                    .cardNote()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .animation(.default, value: value)
    }

    /// 숫자 밑에 붙는 출처. 기본값이면 권고 기관, 바꿨으면 "지금 기준", 줄이기 목표 중이면 그 사실.
    private func limitSource(_ side: CupSide) -> String {
        if goal(side) != nil { return "줄이기 진행 중" }
        let isDefault = side.limit(settings.limits) == side.limit(.default)
        switch side {
        case .sugar: return isDefault ? "WHO 권고" : "지금 기준"
        case .caffeine: return isDefault ? "식약처 권고" : "지금 기준"
        }
    }

    private func controlLabel(_ text: String) -> some View {
        Text(text)
            .font(AppFont.pretendard(13, .semibold, relativeTo: .footnote))
            .padding(.top, 14)
    }

    private func managedNote(_ side: CupSide) -> some View {
        Label("줄이기 목표가 \(side.label) 기준을 맡고 있어요", systemImage: "lock.fill")
            .font(AppFont.pretendard(13, .regular, relativeTo: .footnote))
            .foregroundStyle(.secondary)
            .padding(.top, 10)
            .accessibilityHint("감소 목표가 이번 주 기준을 정해요")
    }

    // MARK: 조금씩 줄이기

    private var goalsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("조금씩 줄이기").kicker()
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            goalRow(.sugar)
            Divider().padding(.horizontal, 8)
            goalRow(.caffeine)
            Text("한 주에 5일 이상 기준 안이면 다음 주 기준이 조금 내려가요. 못 지킨 주는 그대로예요.")
                .cardNote()
                .padding(.horizontal, 8)
                .padding(.top, 10)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsCard(radius: 28)
    }

    private func goalRow(_ side: CupSide) -> some View {
        HStack(spacing: 12) {
            Image(side.characterAsset)
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 48)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(side.label) 조금씩 줄이기")
                    .font(AppFont.pretendard(16, .bold, relativeTo: .callout))
                    .tracking(-0.2)
                if let goal = goal(side) {
                    Text("이번 주 \(Amount.number(side.limit(settings.limits))) \(side.unit) → 목표 \(Amount.number(goal.target)) \(side.unit) · \(goal.weeks)주 중 \(goal.achievedWeeks)주 달성")
                        .cardNote()
                        .monospacedDigit()
                    GeometryReader { bar in
                        Capsule().fill(Color(.systemFill))
                            .overlay(alignment: .leading) {
                                Capsule().fill(Color.accentColor)
                                    .frame(width: max(4, bar.size.width * Double(goal.achievedWeeks) / Double(max(1, goal.weeks))))
                            }
                    }
                    .frame(height: 4)
                    .padding(.top, 5)
                } else {
                    Text("4~12주에 걸쳐 하루 기준을 낮춰요")
                        .cardNote()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if goal(side) != nil {
                Button("그만두기") { stoppingSide = side }
                    .font(AppFont.pretendard(15, .regular, relativeTo: .subheadline))
                    .tapTarget()
            } else {
                Button {
                    // 감소 목표는 Pro다(§6).
                    if pro.isPro {
                        editingSide = side
                    } else {
                        pendingGoalSide = side
                        paywall = .reductionGoal
                    }
                } label: {
                    HStack(spacing: 4) {
                        if !pro.isPro { Image(systemName: "lock.fill").font(.system(size: 10)) }
                        Text(pro.isPro ? "시작" : "Pro")
                    }
                    .font(AppFont.pretendard(14, .semibold, relativeTo: .subheadline))
                    .foregroundStyle(.tint)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 34)
                    .background(.white, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.4)))
                    .tapTarget()
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel("\(side.label) 줄이기 시작")
                .accessibilityIdentifier("start-goal-\(side.rawValue)")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
    }

    // MARK: 시간

    private var timeCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("시간").kicker()
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            hourRow("하루가 바뀌는 시각", selection: $settings.dayBoundaryHour, choices: HourChoices.dayBoundary)
            Divider().padding(.horizontal, 8)
            hourRow("오늘 마감을 여는 시각", selection: $settings.closeFromHour, choices: HourChoices.closeFrom)
            Text("하루가 바뀌는 시각 전에 마신 음료는 전날 몫으로 들어가요.")
                .cardNote()
                .padding(.horizontal, 8)
                .padding(.top, 10)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsCard(radius: 28)
    }

    /// 시각 행. 값은 메뉴 피커라 한 번에 고른다.
    private func hourRow(_ title: String, selection: Binding<Int>, choices: [Int]) -> some View {
        HStack {
            Text(title)
                .font(AppFont.pretendard(15, .regular, relativeTo: .subheadline))
            Spacer()
            Picker(title, selection: selection) {
                ForEach(choices, id: \.self) { hour in
                    Text(HourChoices.label(hour)).tag(hour)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .background(Color.accentColor.opacity(0.1), in: Capsule())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: Pro

    @ViewBuilder
    private var proCard: some View {
        if pro.isPro {
            HStack(spacing: 12) {
                proCharacters
                VStack(alignment: .leading, spacing: 2) {
                    Text("슈가캡 Pro 사용 중")
                        .font(AppFont.pretendard(16, .bold, relativeTo: .callout))
                    Text("로슈·카인과 친해지기·월 추이·조금씩 줄이기").cardNote()
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(minHeight: 96)
            .settingsCard(radius: 24)
            .accessibilityElement(children: .combine)
        } else {
            Button {
                showsGeneralPaywall = true
            } label: {
                HStack(spacing: 12) {
                    proCharacters
                    VStack(alignment: .leading, spacing: 2) {
                        Text("슈가캡 Pro")
                            .font(AppFont.pretendard(16, .bold, relativeTo: .callout))
                            .foregroundStyle(.primary)
                        Text("로슈·카인과 친해지기, 월 추이, 조금씩 줄이기").cardNote()
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Text("알아보기")
                        .font(AppFont.pretendard(13, .semibold, relativeTo: .footnote))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.accentColor, in: Capsule())
                }
                .padding(16)
                .frame(minHeight: 96)
                .settingsCard(radius: 24)
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityIdentifier("open-paywall")
        }
    }

    private var proCharacters: some View {
        HStack(alignment: .bottom, spacing: -6) {
            Image(CupSide.sugar.characterAsset).resizable().scaledToFit().frame(height: 50)
            Image(CupSide.caffeine.characterAsset).resizable().scaledToFit().frame(height: 42)
        }
        .accessibilityHidden(true)
    }

    // MARK: 기타

    private var etcCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                showsOnboarding = true
            } label: {
                etcRow("앱 소개 다시 보기", trailing: Image(systemName: "chevron.right"))
            }
            .accessibilityIdentifier("replay-onboarding")
            Divider().padding(.horizontal, 8)
            Button {
                restore()
            } label: {
                HStack {
                    Text("구매 복원")
                    Spacer()
                    if isRestoring { ProgressView() }
                }
                .etcPadding()
            }
            .disabled(isRestoring)
            .accessibilityIdentifier("restore-purchases")
            if let privacy = AppLinks.privacyPolicy {
                Divider().padding(.horizontal, 8)
                Link(destination: privacy) {
                    etcRow("개인정보처리방침", trailing: Image(systemName: "arrow.up.right"))
                }
            }
            Text("기록은 이 기기에만 저장돼요. 수집하는 정보는 없어요.")
                .cardNote()
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 8)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .settingsCard(radius: 28)
    }

    private func etcRow(_ title: String, trailing: Image) -> some View {
        HStack {
            Text(title)
            Spacer()
            trailing
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .etcPadding()
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
            context.rollback()
            alertMessage = "감소 목표를 시작하지 못했어요. 다시 시도해 주세요."
        }
    }

    private func stop(_ side: CupSide) {
        do {
            try ReductionStore.stop(side: side, in: context)
            try context.save()
        } catch {
            Self.logger.error("감소 목표 중단 실패: \(String(describing: error), privacy: .public)")
            context.rollback()
            alertMessage = "감소 목표를 그만두지 못했어요. 다시 시도해 주세요."
        }
    }

    /// 결과를 이 화면에서 바로 알린다. 페이월 밖에서는 `store.failure`가 그려지지 않는다.
    private func restore() {
        isRestoring = true
        Task {
            await pro.restore()
            isRestoring = false
            alertMessage = pro.isPro ? "구매를 복원했어요." : (pro.failure ?? "복원할 구매가 없어요.")
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
    /// 흰 유리 카드(추이 캐주얼과 같은 문법).
    func settingsCard(radius: CGFloat) -> some View {
        background {
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            shape.fill(.white.opacity(0.78))
                .overlay(shape.strokeBorder(.white))
                .shadow(color: Color(red: 20 / 255, green: 30 / 255, blue: 50 / 255).opacity(0.05), radius: 15, y: 10)
        }
    }

    func cardNote() -> some View {
        font(AppFont.pretendard(12, .regular, relativeTo: .caption))
            .foregroundStyle(.secondary)
            .lineSpacing(3)
    }

    func etcPadding() -> some View {
        font(AppFont.pretendard(15, .regular, relativeTo: .subheadline))
            .padding(.horizontal, 8)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
    }
}
