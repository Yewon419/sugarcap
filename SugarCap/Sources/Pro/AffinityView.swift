import SwiftData
import SwiftUI

/// 호감도 화면(SPEC §4.8, Pro). 카인·로슈 전환, 단계와 다음 단계까지 남은 정도, 해금 목록.
///
/// v1은 정지 스프라이트 1장씩이라(§9.4) 해금 칸은 자리만 잡아 둔다. 표정 원화가 나오면 이미지를 끼운다.
struct AffinityView: View {
    @Query private var affinities: [Affinity]
    @State private var side: CupSide = .sugar

    private var points: Int {
        affinities.first { $0.character == side.characterID }?.points ?? 0
    }

    private var level: Int { AffinityMath.level(points: points) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Picker("캐릭터", selection: $side) {
                        ForEach(CupSide.allCases) { cupSide in
                            Text(cupSide.characterName).tag(cupSide)
                        }
                    }
                    .pickerStyle(.segmented)

                    portrait
                    progress
                    unlocks
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .navigationTitle("호감도")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var portrait: some View {
        VStack(spacing: 8) {
            Image(side.characterAsset)
                .resizable()
                .scaledToFit()
                .frame(height: 140)
                .accessibilityHidden(true)
            Text("\(side.characterName) · Lv \(level)")
                .font(.title3.bold())
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private var progress: some View {
        let current = AffinityMath.threshold(level: level)
        let next = AffinityMath.threshold(level: min(AffinityMath.maxLevel, level + 1))

        VStack(alignment: .leading, spacing: 8) {
            if level >= AffinityMath.maxLevel {
                Text("마지막 단계예요")
                    .font(.subheadline)
            } else {
                ProgressView(value: Double(points - current), total: Double(max(1, next - current)))
                Text("다음 단계까지 \(next - points)점")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Text("쌓은 호감도 \(points)점")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            Color(.secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }

    private var unlocks: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("표정")
                .font(.headline)
            ForEach(2...AffinityMath.maxLevel, id: \.self) { step in
                HStack {
                    Image(systemName: step <= level ? "checkmark.circle.fill" : "lock")
                        .foregroundStyle(step <= level ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    Text("Lv \(step)")
                        .monospacedDigit()
                    Spacer()
                    Text(step <= level ? "해금" : "\(AffinityMath.threshold(level: step))점")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
            Text("표정 그림은 준비 중이에요. 단계는 지금부터 쌓여요.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            Color(.secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }
}
