import SwiftData
import SwiftUI

/// 호감도(Pro, 2026-09-26 HTML 프로토타입 확정, SPEC §4.8). 단계 숫자·점수는 보이지 않는다.
/// 초상(캐릭터 + "로슈와" + 사이 이름 + 다음 사이까지 막대) → 말걸기.
/// 말걸기: 캐릭터마다 하루 한 번, 오늘의 선택지 3개 중 하나. 캐릭터는 말을 못 하고 몸짓으로만 반응한다(+2점).
/// 표정 칸은 뺐다(대표님). 반응 몸짓은 대표님 애니메이션이 오기 전까지 transform으로 흉내 낸다.
struct AffinityView: View {
    @Query private var affinities: [Affinity]
    @Query private var talkLogs: [TalkLog]
    @Query private var settingsRows: [AppSettings]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var side: CupSide = .sugar
    /// 이번에 말을 걸어 단계가 올랐는지(다시 열면 모른다 → "조금 더 가까워졌어요").
    @State private var leveledUp: Set<CupSide> = []
    @State private var reactionStart: Date?
    @State private var failureMessage: String?

    private var points: Int {
        affinities.first { $0.character == side.characterID }?.points ?? 0
    }

    private var level: Int { AffinityMath.level(points: points) }
    private var isLastStage: Bool { level >= AffinityMath.maxLevel }
    private var today: DayKey { DayKey(at: Date(), boundaryHour: settingsRows.first?.dayBoundaryHour ?? 4) }
    private var todaysLog: TalkLog? { TalkStore.log(for: side, day: today, in: talkLogs) }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "호감도") {
                Button("닫기") { dismiss() }
                    .tapTarget()
                    .accessibilityIdentifier("affinity-close")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Picker("캐릭터", selection: $side) {
                        ForEach(CupSide.allCases) { cupSide in
                            Text(cupSide.characterName).tag(cupSide)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                    portrait
                        .padding(.top, 26)
                        .padding(.horizontal, 24)

                    SectionKicker(title: "말 걸기")
                    talk
                        .padding(.horizontal, 24)
                    Color.clear.frame(height: 40)
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: side)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(38)
        .presentationBackground(.regularMaterial)
        .onChange(of: side) { _, _ in reactionStart = nil }
        .alert(failureMessage ?? "", isPresented: Binding(get: { failureMessage != nil }, set: { if !$0 { failureMessage = nil } })) {
            Button("확인", role: .cancel) {}
        }
    }

    /// 캐릭터 → "로슈와" → 사이 이름 → 다음 사이까지 막대.
    private var portrait: some View {
        let stage = AffinityMath.stageName(level: level)
        let next = AffinityMath.stageName(level: level + 1)
        let reaction = todaysLog.flatMap { TalkReaction(rawValue: $0.reaction) }

        return VStack(spacing: 0) {
            TimelineView(.animation(paused: reactionStart == nil || reduceMotion)) { timeline in
                let elapsed = reactionStart.map { timeline.date.timeIntervalSince($0) } ?? .infinity
                let pose = ReactionMotion.pose(reaction, at: reduceMotion ? .infinity : elapsed)
                Image(side.characterAsset)
                    .resizable()
                    .scaledToFit()
                    .frame(height: side == .sugar ? 190 : 160)
                    .scaleEffect(x: pose.scaleX, y: pose.scaleY, anchor: .bottom)
                    .rotationEffect(.degrees(pose.rotation), anchor: side == .sugar ? .bottom : UnitPoint(x: 0.5, y: 0.55))
                    .offset(x: pose.x, y: pose.y)
            }
            .frame(height: 190, alignment: .bottom)
            .id(side)
            .transition(.opacity)
            .accessibilityHidden(true)

            Text(side.characterNameWithGwa)
                .font(AppFont.pretendard(15, .regular, relativeTo: .subheadline))
                .foregroundStyle(.secondary)
                .padding(.top, 20)

            Text(stage)
                .font(AppFont.pretendard(34, .bold, relativeTo: .largeTitle))
                .tracking(-0.7)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
                .padding(.top, 4)
                .accessibilityIdentifier("affinity-stage")

            VStack(alignment: .leading, spacing: 8) {
                GeometryReader { bar in
                    Capsule().fill(Color(.systemFill))
                        .overlay(alignment: .leading) {
                            Capsule().fill(Color.accentColor)
                                .frame(width: max(6, bar.size.width * AffinityMath.progressToNext(points: points)))
                                .animation(.spring(response: 0.6, dampingFraction: 1), value: points)
                        }
                }
                .frame(height: 6)
                Text(isLastStage ? "가장 가까운 사이가 됐어요" : "다음은 \(next)")
                    .font(AppFont.pretendard(12, .regular, relativeTo: .caption))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 22)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            isLastStage
                ? "\(side.characterNameWithGwa) \(stage). 가장 가까운 사이예요"
                : "\(side.characterNameWithGwa) \(stage). 다음은 \(next)"
        )
    }

    @ViewBuilder
    private var talk: some View {
        if let log = todaysLog, let reaction = TalkReaction(rawValue: log.reaction) {
            let said = TalkMath.choices.first { $0.id == log.choiceID }?.text ?? ""
            VStack(alignment: .leading, spacing: 0) {
                Text("\"\(said)\"")
                    .font(AppFont.pretendard(13, .semibold, relativeTo: .footnote))
                    .foregroundStyle(.tint)
                Text("\(side.characterNameWithIga) \(reaction.line)")
                    .font(AppFont.pretendard(18, .semibold, relativeTo: .headline))
                    .tracking(-0.3)
                    .lineSpacing(4)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                Text(
                    (leveledUp.contains(side)
                        ? "\(side.characterNameWithGwa) \(AffinityMath.stageName(level: level))가 됐어요."
                        : "조금 더 가까워졌어요.") + " 내일 또 말 걸어 주세요."
                )
                .font(AppFont.pretendard(12, .regular, relativeTo: .caption))
                .foregroundStyle(.secondary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
                shape.fill(.white.opacity(0.72)).overlay(shape.strokeBorder(.white.opacity(0.95)))
            }
            .transition(.scale(scale: 0.95).combined(with: .opacity))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("talk-result")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(side.characterName)에게 뭐라고 할까요?")
                    .font(AppFont.pretendard(20, .bold, relativeTo: .title3))
                    .tracking(-0.3)
                    .padding(.bottom, 6)
                ForEach(TalkMath.todaysChoices(day: today, side: side), id: \.id) { choice in
                    Button {
                        say(choice)
                    } label: {
                        Text(choice.text)
                            .font(AppFont.pretendard(16, .medium, relativeTo: .callout))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 20)
                            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                            .background {
                                Capsule().fill(.white.opacity(0.72)).overlay(Capsule().strokeBorder(.white.opacity(0.95)))
                            }
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityIdentifier("talk-\(choice.id)")
                }
                Text("\(side.characterName)는 말은 못 하지만 몸으로 대답해요. 하루에 한 번 말 걸 수 있어요.")
                    .font(AppFont.pretendard(13, .regular, relativeTo: .footnote))
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
            }
        }
    }

    private func say(_ choice: TalkMath.Choice) {
        do {
            let outcome = try TalkStore.talk(side: side, choiceID: choice.id, day: today, logs: talkLogs, in: context)
            if outcome.leveledUp { leveledUp.insert(side) }
            reactionStart = Date()
        } catch {
            failureMessage = "저장하지 못했어요. 다시 시도해 주세요."
        }
    }
}

/// 반응 몸짓(프로토타입 `.react-*` 자리 채움). 한 번만 재생하고 제자리로 돌아온다. 시각 t의 순수 함수.
enum ReactionMotion {
    struct Pose: Equatable {
        var x: Double = 0
        var y: Double = 0
        var rotation: Double = 0
        var scaleX: Double = 1
        var scaleY: Double = 1
    }

    /// 키프레임 [(진행 0~1, 자세)] 사이를 곡선으로 잇는다. 처음과 끝은 제자리.
    private static func track(_ frames: [(Double, Pose)], duration: Double, t: Double, ease: (Double) -> Double) -> Pose {
        guard t < duration else { return Pose() }
        let p = max(0, t) / duration
        let points = [(0.0, Pose())] + frames + [(1.0, Pose())]
        guard let upper = points.firstIndex(where: { $0.0 >= p }), upper > 0 else { return Pose() }
        let (p0, a) = points[upper - 1]
        let (p1, b) = points[upper]
        let k = ease(p1 > p0 ? (p - p0) / (p1 - p0) : 1)
        return Pose(
            x: Motion.lerp(a.x, b.x, k), y: Motion.lerp(a.y, b.y, k), rotation: Motion.lerp(a.rotation, b.rotation, k),
            scaleX: Motion.lerp(a.scaleX, b.scaleX, k), scaleY: Motion.lerp(a.scaleY, b.scaleY, k)
        )
    }

    static func pose(_ reaction: TalkReaction?, at t: Double) -> Pose {
        guard let reaction else { return Pose() }
        switch reaction {
        case .wary:
            // 움찔 → 옆으로 비켜서 등을 살짝 돌리고 멀찍이서 지켜본다
            return track([
                (0.2, Pose(y: 4, scaleX: 1.02, scaleY: 0.94)),
                (0.4, Pose(x: 18, y: 3, rotation: 6, scaleX: 0.95, scaleY: 0.95)),
                (0.75, Pose(x: 18, y: 3, rotation: 6, scaleX: 0.95, scaleY: 0.95)),
            ], duration: 1.4, t: t, ease: Ease.sineInOut)
        case .happy:
            return track([(0.4, Pose(y: -22, scaleX: 1.05, scaleY: 1.05))], duration: 0.8, t: t, ease: Ease.power2Out)
        case .aegyo:
            return track([
                (0.2, Pose(rotation: 8, scaleX: 1.04, scaleY: 1.04)), (0.4, Pose(rotation: -4)),
                (0.6, Pose(rotation: 8, scaleX: 1.04, scaleY: 1.04)), (0.8, Pose(rotation: -4)),
            ], duration: 1.2, t: t, ease: Ease.sineInOut)
        case .tilt:
            return track([(0.3, Pose(rotation: -38)), (0.8, Pose(rotation: -38))], duration: 1.4, t: t, ease: Ease.sineInOut)
        case .spin:
            guard t < 1 else { return Pose() }
            return Pose(rotation: 360 * Ease.power3InOut(max(0, t)))
        case .hop:
            return track([(0.4, Pose(y: -28))], duration: 0.8, t: t, ease: Ease.power2Out)
        }
    }
}
