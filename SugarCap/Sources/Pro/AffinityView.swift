import SwiftData
import SwiftUI

/// 호감도 화면(SPEC §4.8, Pro, 2026-09-24 디자인). 캐릭터 전환, 단계를 주인공 숫자로, 해금 목록.
///
/// v1은 정지 스프라이트 1장씩이라(§9.4) 해금 칸은 자리만 잡아 둔다. 표정 원화가 나오면 이미지를 끼운다.
struct AffinityView: View {
    @Query private var affinities: [Affinity]
    @Environment(\.dismiss) private var dismiss
    @State private var side: CupSide = .sugar

    private var points: Int {
        affinities.first { $0.character == side.characterID }?.points ?? 0
    }

    private var level: Int { AffinityMath.level(points: points) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("호감도")
                        .kicker()
                    Spacer()
                    Button("닫기") { dismiss() }
                        .font(.system(size: 15))
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
                    .padding(.top, 24)

                Divider()
                    .padding(.top, 24)

                unlocks
                    .padding(.top, 20)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }

    /// 왼쪽 캐릭터, 오른쪽 Lv 주인공 숫자와 다음 단계 캡션.
    @ViewBuilder
    private var portrait: some View {
        let current = AffinityMath.threshold(level: level)
        let next = AffinityMath.threshold(level: min(AffinityMath.maxLevel, level + 1))

        HStack(alignment: .center, spacing: 20) {
            Image(side.characterAsset)
                .resizable()
                .scaledToFit()
                .frame(width: 150, height: 170)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text("Lv")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("\(level)")
                    .heroNumber()
                    .contentTransition(.numericText())
                if level >= AffinityMath.maxLevel {
                    Text("마지막 단계예요")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.top, 4)
                } else {
                    Text("다음 단계까지 \(next - points)점")
                        .font(.system(size: 13, weight: .medium))
                        .monospacedDigit()
                        .padding(.top, 4)
                }
                Text("쌓은 호감도 \(points)점")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .padding(.top, 4)
            }
            .animation(.spring(response: 0.4), value: side)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(side.characterName) \(level)단계, 다음 단계까지 \(max(0, next - points))점, 쌓은 호감도 \(points)점")
        // 마지막 단계에서는 current가 next와 같아 남은 점수가 음수로 보일 수 있다. 위 분기가 막는다.
        .id(current)
    }

    private var unlocks: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("표정")
                .kicker()
            ForEach(2...AffinityMath.maxLevel, id: \.self) { step in
                let unlocked = step <= level
                HStack(spacing: 12) {
                    Circle()
                        .fill(unlocked ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(.separator)))
                        .frame(width: 8, height: 8)
                    Text("Lv \(step)")
                        .font(.system(size: 15, weight: unlocked ? .semibold : .medium))
                        .foregroundStyle(unlocked ? .primary : .secondary)
                        .monospacedDigit()
                    Spacer()
                    Text(unlocked ? "해금" : "\(AffinityMath.threshold(level: step))점")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(.vertical, 12)
                .overlay(alignment: .bottom) {
                    Divider().opacity(0.7)
                }
                .accessibilityElement(children: .combine)
            }
            Text("표정 그림은 준비 중이에요. 단계는 지금부터 쌓여요.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.top, 16)
        }
    }
}
