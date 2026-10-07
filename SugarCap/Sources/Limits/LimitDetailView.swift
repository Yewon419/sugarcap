import OSLog
import SwiftData
import SwiftUI

/// 하루 기준 화면(2026-10-05 프로토타입 v4 확정, SPEC §4.4). 추이의 "하루 기준" 줄을 누르면 한쪽(당·카페인)만 연다.
/// 온보딩 하루 기준 단계와 같은 컵을 쓰고, 고르면 바로 저장한다. 아래 흰 줄이 조금씩 줄이기(Pro).
/// 줄이기 목표가 돌면 컵은 이번 주 기준만 보여 주고, 칩 자리에 진행 막대, 맨 아래 그만두기가 온다.
struct LimitDetailView: View {
    let side: CupSide

    @Query private var settingsRows: [AppSettings]
    @Query private var goals: [ReductionGoal]
    @Environment(\.modelContext) private var context

    var body: some View {
        Group {
            if let settings = settingsRows.first {
                LimitDetailContent(
                    side: side,
                    settings: settings,
                    goal: goals.first { $0.side == side.rawValue },
                    context: context
                )
            } else {
                ProgressView()
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LimitDetailContent: View {
    let side: CupSide
    @Bindable var settings: AppSettings
    let goal: ReductionGoal?
    let context: ModelContext

    @State private var isEditingGoal = false
    @State private var paywall: ProFeature?
    /// 목표 정하기를 누르다 페이월로 갔다. 구매하고 닫히면 목표 시트를 이어서 연다.
    @State private var pendingGoal = false
    @State private var isStopping = false
    @State private var alertMessage: String?

    @Environment(ProStore.self) private var pro

    private static let logger = Logger(subsystem: "com.sugarcap.app", category: "limits")

    private var value: Binding<Double> {
        switch side {
        case .sugar: return $settings.sugarLimitG
        case .caffeine: return $settings.caffeineLimitMg
        }
    }

    private var title: String {
        // 숫자는 컵 안에 이미 있다. 제목은 지금 하는 일만 말한다(대표님 2026-10-05 "제목은 바꾸고").
        if goal != nil { return String(localized: "\(side.label)을\n조금씩 줄이는 중이에요") }
        return side == .sugar
            ? String(localized: "하루에 당은\n얼마까지 마실래요?")
            : String(localized: "카페인은\n얼마까지 마실래요?")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("하루 기준").kicker()
                    Text(title)
                        .font(AppFont.pretendard(30, .extraBold, relativeTo: .largeTitle))
                        .tracking(AppFont.displayTracking(for: 30))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 8)

                LimitCupPicker(side: side, value: value, isLocked: goal != nil, identifierPrefix: "limit")
                    .padding(.top, 24)

                if let goal {
                    progress(goal)
                        .padding(.horizontal, 28)
                        .padding(.top, 28)
                }
            }
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color.wall.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            Group {
                if goal != nil {
                    stopButton
                } else {
                    goalRow
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .sheet(item: $paywall, onDismiss: {
            if pro.isPro, pendingGoal { isEditingGoal = true }
            pendingGoal = false
        }) { feature in
            PaywallView(feature: feature)
        }
        .sheet(isPresented: $isEditingGoal) {
            ReductionGoalSheet(side: side, currentLimit: side.limit(settings.limits)) { target, weeks in
                start(target: target, weeks: weeks)
            }
        }
        // 목표를 그만두면 쌓은 주 진행이 사라지고 되돌릴 수 없다. 한 번 더 묻는다.
        .confirmationDialog("\(side.label) 줄이기를 그만둘까요?", isPresented: $isStopping, titleVisibility: .visible) {
            Button("그만두기", role: .destructive) { stop() }
                .accessibilityIdentifier("confirm-stop-goal")
            Button("계속하기", role: .cancel) {}
        } message: {
            Text("지금까지 달성한 주 기록이 사라지고, 하루 기준은 이번 주 값으로 남아요.")
        }
        .alert(
            alertMessage ?? "",
            isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })
        ) {
            Button("확인", role: .cancel) {}
        }
    }

    // MARK: 줄이기

    private func progress(_ goal: ReductionGoal) -> some View {
        VStack(spacing: 8) {
            GeometryReader { bar in
                Capsule().fill(Color.ink.opacity(0.1))
                    .overlay(alignment: .leading) {
                        Capsule().fill(Color.ink)
                            .frame(width: max(6, bar.size.width * Double(goal.achievedWeeks) / Double(max(1, goal.weeks))))
                    }
            }
            .frame(height: 6)
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("\(goal.weeks)주 중 \(goal.achievedWeeks)주 지킴")
                    Spacer()
                    Text("목표 \(Amount.number(goal.target)) \(side.unit)")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(goal.weeks)주 중 \(goal.achievedWeeks)주 지킴")
                    Text("목표 \(Amount.number(goal.target)) \(side.unit)")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(AppFont.pretendard(13, .regular, relativeTo: .footnote))
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("goal-progress")
    }

    private var goalRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { goalText; goalButton }
            VStack(alignment: .leading, spacing: 12) { goalText; goalButton }
        }
        .padding(.vertical, 14)
        .padding(.leading, 18)
        .padding(.trailing, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var goalText: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("조금씩 줄이기")
                .font(AppFont.pretendard(15, .semibold, relativeTo: .subheadline))
            Text("4~12주에 걸쳐 기준을 낮춰요")
                .font(AppFont.pretendard(12, .regular, relativeTo: .caption))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var goalButton: some View {
        Button {
            // 감소 목표는 Pro다(§6).
            if pro.isPro {
                isEditingGoal = true
            } else {
                pendingGoal = true
                paywall = .reductionGoal
            }
        } label: {
            HStack(spacing: 5) {
                if !pro.isPro { Image(systemName: "lock.fill").font(.system(size: 11)) }
                Text("목표 정하기")
            }
            .font(AppFont.pretendard(14, .semibold, relativeTo: .subheadline))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(minHeight: 40)
            .background(Color.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(pro.isPro ? Text("\(side.label) 목표 정하기") : Text("\(side.label) 목표 정하기, Pro"))
        .accessibilityIdentifier("start-goal-\(side.rawValue)")
    }

    private var stopButton: some View {
        VStack(spacing: 2) {
            Button(role: .destructive) {
                isStopping = true
            } label: {
                Text("줄이기 그만두기")
                    .font(AppFont.pretendard(16, .medium, relativeTo: .callout))
                    .foregroundStyle(Color.red)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("stop-goal")
            Text("그만두면 기준은 이번 주 값으로 남아요")
                .font(AppFont.pretendard(12, .regular, relativeTo: .caption))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: 동작

    private func start(target: Double, weeks: Int) {
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
            alertMessage = String(localized: "감소 목표를 시작하지 못했어요. 다시 시도해 주세요.")
        }
    }

    private func stop() {
        do {
            try ReductionStore.stop(side: side, in: context)
            try context.save()
        } catch {
            Self.logger.error("감소 목표 중단 실패: \(String(describing: error), privacy: .public)")
            context.rollback()
            alertMessage = String(localized: "감소 목표를 그만두지 못했어요. 다시 시도해 주세요.")
        }
    }
}
