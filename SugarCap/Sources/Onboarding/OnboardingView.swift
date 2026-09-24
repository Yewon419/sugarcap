import SwiftUI

/// 온보딩 1화면(SPEC §4.5, 2026-09-24 디자인). 컵 장면 위에 카피와 기본값 카드, "시작".
/// 계정·페이월 없음. 완료 여부는 기기 단위 플래그라 SwiftData가 아니라 UserDefaults에 둔다.
struct OnboardingView: View {
    static let completedKey = "onboardingCompleted"

    let onStart: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            CupView(step: 100)
                .ignoresSafeArea()

            // 위는 글자 자리, 아래는 카드·버튼 자리. 가운데만 컵이 보인다.
            LinearGradient(
                stops: [
                    .init(color: .white.opacity(0.94), location: 0),
                    .init(color: .white.opacity(0.55), location: 0.42),
                    .init(color: .white.opacity(0.88), location: 0.72),
                    .init(color: .white, location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 0) {
                Text("슈가캡")
                    .kicker()
                    .padding(.top, 40)
                Text("마실 때마다\n줄어드는 컵")
                    .font(.system(size: 40, weight: .bold))
                    .tracking(-0.8)
                    .lineSpacing(2)
                    .padding(.top, 16)
                Text("밤에 남은 만큼을 로슈와 카인에게 먹여요.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .padding(.top, 14)
            }
            .padding(.leading, 24)
        }
        .overlay(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .bottom) {
                    Image(CupSide.sugar.characterAsset)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 140)
                        .accessibilityLabel(CupSide.sugar.characterName)
                    Spacer()
                    Image(CupSide.caffeine.characterAsset)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 110)
                        .accessibilityLabel(CupSide.caffeine.characterName)
                        .padding(.trailing, 12)
                }
                .padding(.horizontal, 30)

                limitsCard
                    .padding(.top, 16)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: onStart) {
                Text("시작")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
            .accessibilityIdentifier("onboarding-start")
        }
    }

    /// 기본값 안내. 유리 카드에 두 기준을 나란히.
    private var limitsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("하루 기준")
                .kicker()
            HStack(alignment: .top, spacing: 0) {
                limitColumn(.sugar, value: DailyLimits.default.sugarG, source: "WHO 권고")
                    .frame(maxWidth: .infinity, alignment: .leading)
                limitColumn(.caffeine, value: DailyLimits.default.caffeineMg, source: "식약처 권고")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white, lineWidth: 1)
        )
    }

    private func limitColumn(_ side: CupSide, value: Double, source: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(side.label) \(Amount.number(value)) \(side.unit)")
                .font(.system(size: 17, weight: .semibold))
                .monospacedDigit()
            Text(source)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    OnboardingView(onStart: {})
}
