import SwiftData
import SwiftUI

/// 호감도(Pro, SPEC §4.8). 단계 숫자·점수는 보이지 않는다.
/// 캐릭터 하나 + "로슈와" + 사이 이름 + 다음 사이까지 막대. 캐릭터를 건드리면 몸짓으로 반응하고,
/// 이어서 여러 번 건드리면 특이한 반응이 한 번 나온다(2026-10-03, 말걸기 대체, 점수 없음).
/// 반응 몸짓은 대표님 애니메이션이 오기 전까지 transform으로 흉내 낸다.
struct AffinityView: View {
    @Query private var affinities: [Affinity]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var side: CupSide = .sugar
    @State private var reaction: PokeReaction?
    @State private var reactionStart: Date?
    @State private var lastTap: Date?
    @State private var combo = 0
    @State private var taps = 0

    private var points: Int {
        affinities.first { $0.character == side.characterID }?.points ?? 0
    }

    private var level: Int { AffinityMath.level(points: points) }
    private var isLastStage: Bool { level >= AffinityMath.maxLevel }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "호감도") {
                Button("닫기") { dismiss() }
                    .tapTarget()
                    .accessibilityIdentifier("affinity-close")
            }
            ScrollView {
                VStack(spacing: 0) {
                    Picker("캐릭터", selection: $side) {
                        ForEach(CupSide.allCases) { cupSide in
                            Text(cupSide.characterName).tag(cupSide)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                    character
                        .padding(.top, 40)

                    portrait
                        .padding(.top, 28)
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
        .sensoryFeedback(trigger: taps) { _, _ in
            reaction == .squish || reaction == .flip ? .impact(weight: .heavy) : .impact(weight: .light)
        }
        .onChange(of: side) { _, _ in
            reaction = nil
            reactionStart = nil
            lastTap = nil
            combo = 0
        }
    }

    /// 건드릴 수 있는 캐릭터. 반응은 누를 때마다 처음부터 다시 재생한다.
    private var character: some View {
        TimelineView(.animation(paused: reactionStart == nil || reduceMotion)) { timeline in
            let elapsed = reactionStart.map { timeline.date.timeIntervalSince($0) } ?? .infinity
            let pose = ReactionMotion.pose(reaction, at: reduceMotion ? .infinity : elapsed)
            Image(side.characterAsset)
                .resizable()
                .scaledToFit()
                .frame(height: side == .sugar ? 250 : 210)
                .scaleEffect(x: pose.scaleX, y: pose.scaleY, anchor: .bottom)
                .rotationEffect(.degrees(pose.rotation), anchor: side == .sugar ? .bottom : UnitPoint(x: 0.5, y: 0.55))
                .offset(x: pose.x, y: pose.y)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 250, alignment: .bottom)
        .contentShape(Rectangle())
        .onTapGesture(perform: poke)
        .id(side)
        .transition(.opacity)
        .accessibilityElement()
        .accessibilityLabel("\(side.characterName) 건드리기")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, poke)
        .accessibilityIdentifier("affinity-character")
    }

    /// "로슈와" → 사이 이름 → 다음 사이까지 막대.
    private var portrait: some View {
        let stage = AffinityMath.stageName(level: level)
        let next = AffinityMath.stageName(level: level + 1)

        return VStack(spacing: 0) {
            Text(side.characterNameWithGwa)
                .font(AppFont.pretendard(15, .regular, relativeTo: .subheadline))
                .foregroundStyle(.secondary)

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

    private func poke() {
        let now = Date()
        combo = PokeMath.combo(previous: combo, lastTap: lastTap, now: now)
        reaction = PokeMath.reaction(side: side, level: level, combo: combo, tap: taps)
        reactionStart = now
        lastTap = now
        taps += 1
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

    static func pose(_ reaction: PokeReaction?, at t: Double) -> Pose {
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
        case .squish:
            // 연타: 납작하게 눌렸다가 튀어 올라 출렁이며 제자리로
            return track([
                (0.15, Pose(y: 6, scaleX: 1.3, scaleY: 0.62)), (0.3, Pose(y: 6, scaleX: 1.3, scaleY: 0.62)),
                (0.5, Pose(y: -46, scaleX: 0.88, scaleY: 1.14)), (0.68, Pose(scaleX: 1.12, scaleY: 0.88)),
                (0.84, Pose(y: -8, scaleX: 0.97, scaleY: 1.03)),
            ], duration: 1.3, t: t, ease: Ease.power2Out)
        case .flip:
            // 연타: 높이 뛰어 공중에서 두 바퀴
            let duration = 1.3
            guard t < duration else { return Pose() }
            let p: Double = max(0, t) / duration
            let lift: Double = -70 * sin(Double.pi * p)
            let turn: Double = -720 * Ease.power3InOut(p)
            return Pose(y: lift, rotation: turn)
        }
    }
}
