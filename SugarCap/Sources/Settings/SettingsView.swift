import OSLog
import SwiftData
import SwiftUI

/// 설정 탭(SPEC §4.4). Phase 2a 범위: 하루 기준 2개, 하루 경계 시각, 마감 가능 시각, 정보.
/// 즐겨찾기 정렬은 즐겨찾기 기능과 함께, Pro 구매·복원은 Phase 3에서 붙는다.
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
                    SettingsForm(settings: settings, catalog: catalog, goals: goals, context: context)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("설정")
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

private struct SettingsForm: View {
    @Bindable var settings: AppSettings
    let catalog: Catalog
    let goals: [ReductionGoal]
    let context: ModelContext

    @State private var editingSide: CupSide?

    private func goal(_ side: CupSide) -> ReductionGoal? {
        goals.first { $0.side == side.rawValue }
    }

    var body: some View {
        Form {
            Section {
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
                    .padding(.vertical, 4)
                }

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
                    .padding(.vertical, 4)
                }
            } header: {
                Text("하루 기준")
            } footer: {
                Text("기본값은 당 50 g(WHO 권고), 카페인 400 mg(식약처 성인 권고)이에요.")
            }

            Section {
                ForEach(CupSide.allCases) { side in
                    goalRow(side)
                }
            } header: {
                Text("감소 목표")
            } footer: {
                Text("한 주에 5일 이상 하루 기준 이내면 다음 주 기준이 조금 내려가요. 미달한 주는 기준을 그대로 둬요.")
            }

            Section {
                Picker("하루가 바뀌는 시각", selection: $settings.dayBoundaryHour) {
                    ForEach(HourChoices.dayBoundary, id: \.self) { hour in
                        Text(HourChoices.label(hour)).tag(hour)
                    }
                }
                Picker("오늘 마감을 여는 시각", selection: $settings.closeFromHour) {
                    ForEach(HourChoices.closeFrom, id: \.self) { hour in
                        Text(HourChoices.label(hour)).tag(hour)
                    }
                }
            } header: {
                Text("시간")
            } footer: {
                Text("하루가 바뀌는 시각 전에 마신 음료는 전날 몫으로 들어가요.")
            }

            Section {
                LabeledContent("메뉴 데이터") {
                    Text(catalog.builtAtDate?.formatted(date: .abbreviated, time: .omitted) ?? catalog.builtAt)
                }
                LabeledContent("버전", value: Self.appVersion)
            } header: {
                Text("정보")
            } footer: {
                Text("기록은 이 기기에만 저장돼요. 수집하는 정보는 없어요.")
            }
        }
        .sheet(item: $editingSide) { side in
            ReductionGoalSheet(side: side, currentLimit: side.limit(settings.limits)) { target, weeks in
                start(side, target: target, weeks: weeks)
            }
        }
    }

    private func managedLimitRow(_ side: CupSide, value: Double) -> some View {
        LabeledContent(side.label) {
            Text("\(Amount.number(value)) \(side.unit)")
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private func goalRow(_ side: CupSide) -> some View {
        if let goal = goal(side) {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent(side.label) {
                    Text("이번 주 \(Amount.number(side.limit(settings.limits))) → 목표 \(Amount.number(goal.target)) \(side.unit)")
                        .monospacedDigit()
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
            .padding(.vertical, 4)
        } else {
            Button("\(side.label) 줄이기 시작") { editingSide = side }
                .accessibilityIdentifier("start-goal-\(side.rawValue)")
        }
    }

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
