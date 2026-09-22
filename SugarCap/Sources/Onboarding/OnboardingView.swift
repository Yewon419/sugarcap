import SwiftUI

/// 온보딩 1화면(SPEC §4.5). 앱 설명 한 줄 + 하루 기준 기본값 안내 + "시작".
/// 계정·페이월 없음. 완료 여부는 기기 단위 플래그라 SwiftData가 아니라 UserDefaults에 둔다.
struct OnboardingView: View {
    static let completedKey = "onboardingCompleted"

    let onStart: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                HStack(alignment: .bottom, spacing: 20) {
                    Image(CupSide.sugar.characterAsset)
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel(CupSide.sugar.characterName)
                    Image(CupSide.caffeine.characterAsset)
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel(CupSide.caffeine.characterName)
                }
                .frame(height: 120)
                .padding(.top, 48)

                VStack(spacing: 12) {
                    Text("마실 때마다 줄어드는\n하루치 컵")
                        .font(.title.bold())
                    Text("밤에 남은 만큼을 로슈와 카인에게 먹여 주세요.")
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)

                limitsCard
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            Button(action: onStart) {
                Text("시작")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
            .background(.background)
            .accessibilityIdentifier("onboarding-start")
        }
    }

    private var limitsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("하루 기준")
                .font(.headline)
            limitRow(.sugar, value: DailyLimits.default.sugarG, source: "WHO 권고")
            limitRow(.caffeine, value: DailyLimits.default.caffeineMg, source: "식약처 권고")
            Text("설정에서 바꿀 수 있어요.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(.secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }

    private func limitRow(_ side: CupSide, value: Double, source: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(side.label)
            Spacer()
            Text("\(Amount.number(value)) \(side.unit)")
                .font(.body.weight(.semibold))
                .monospacedDigit()
            Text(source)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    OnboardingView(onStart: {})
}
