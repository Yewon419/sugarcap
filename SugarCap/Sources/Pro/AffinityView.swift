import SwiftData
import SwiftUI

/// 호감도 화면(SPEC §4.8, Pro, 2026-09-26 개편). 단계 숫자와 점수는 보여 주지 않는다.
/// 지금 사이의 이름, 다음 사이까지의 진행 막대, 해금 표정 9칸만 둔다.
///
/// v1은 표정 원화가 없어(§9.4) 열린 칸에도 기본 그림을 끼운다. 원화가 나오면 칸마다 바꾼다.
struct AffinityView: View {
    @Query private var affinities: [Affinity]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var side: CupSide = .sugar

    private var points: Int {
        affinities.first { $0.character == side.characterID }?.points ?? 0
    }

    private var level: Int { AffinityMath.level(points: points) }

    private var isLastStage: Bool { level >= AffinityMath.maxLevel }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("호감도")
                        .kicker()
                    Spacer()
                    Button { dismiss() } label: {
                        Text("닫기").font(.subheadline).tapTarget()
                    }
                    .accessibilityIdentifier("affinity-close")
                }
                .padding(.top, 20)

                Picker("캐릭터", selection: $side) {
                    ForEach(CupSide.allCases) { cupSide in
                        Text(cupSide.characterName).tag(cupSide)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.top, 20)

                portrait
                    .padding(.top, 28)

                Divider()
                    .padding(.top, 32)

                expressions
                    .padding(.top, 20)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: side)
        }
    }

    /// 캐릭터 → "로슈와" → 사이 이름 → 다음 사이까지 막대.
    private var portrait: some View {
        let stage = AffinityMath.stageName(level: level)
        let next = AffinityMath.stageName(level: level + 1)

        return VStack(spacing: 0) {
            Image(side.characterAsset)
                .resizable()
                .scaledToFit()
                .frame(height: 180)
                .id(side)
                .transition(.opacity)
                .accessibilityHidden(true)

            Text(side.characterNameWithGwa)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 20)

            Text(stage)
                .font(.system(.title, weight: .bold))
                .tracking(-0.6)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
                .padding(.top, 4)
                .accessibilityIdentifier("affinity-stage")

            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: AffinityMath.progressToNext(points: points))
                    .tint(.accentColor)
                Text(isLastStage ? "가장 가까운 사이가 됐어요" : "다음은 \(next)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 24)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            isLastStage
                ? "\(side.characterNameWithGwa) \(stage). 가장 가까운 사이예요"
                : "\(side.characterNameWithGwa) \(stage). 다음은 \(next)"
        )
    }

    /// 해금 표정 9칸(단계 2~10, §9.5). 기본 표정은 위 초상이 맡는다.
    private var expressions: some View {
        let count = typeSize.isAccessibilitySize ? 2 : 3
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: count)

        return VStack(alignment: .leading, spacing: 0) {
            Text("표정")
                .kicker()
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(2...AffinityMath.maxLevel, id: \.self) { step in
                    expressionCard(step)
                }
            }
            .padding(.top, 14)
            Text("표정 그림은 준비 중이에요. 친해질수록 하나씩 열려요.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 16)
        }
    }

    /// 열린 칸은 그림과 그 사이 이름, 바로 다음 칸은 "곧 열려요", 나머지는 실루엣만.
    private func expressionCard(_ step: Int) -> some View {
        let unlocked = step <= level
        let caption: String
        if unlocked {
            caption = AffinityMath.stageName(level: step)
        } else if step == level + 1 {
            caption = "곧 열려요"
        } else {
            caption = ""
        }

        return VStack(spacing: 8) {
            Image(side.characterAsset)
                .resizable()
                .scaledToFit()
                .frame(height: 64)
                .colorMultiply(unlocked ? .white : .black)
                .opacity(unlocked ? 1 : 0.12)
                .overlay(alignment: .bottomTrailing) {
                    if !unlocked {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            Text(caption)
                .font(.system(.caption2, weight: unlocked ? .semibold : .regular))
                .foregroundStyle(unlocked ? .primary : .secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .top)
        }
        .padding(.top, 14)
        .padding(.bottom, 10)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(unlocked ? "\(AffinityMath.stageName(level: step)) 표정" : "잠긴 표정")
    }
}
