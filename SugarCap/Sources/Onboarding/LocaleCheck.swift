import SwiftUI
import UIKit

/// 첫 실행 맨 앞 단계(대표님 2026-11-06): 영상을 틀기 전에 앱 언어와 메뉴 국가를 확인한다.
/// 언어는 iOS가 정한다. "언어" 줄은 iOS 설정의 이 앱 화면을 열고, 거기서 언어를 바꾸면 iOS가 앱을 다시 띄워
/// 온보딩 전이라 이 화면으로 돌아온다(앱 안에서 바꾸지 않는다, 대표님 결정).
/// 메뉴 국가는 고르는 즉시 저장되고 카페인 하루 기준도 그 나라 권고량을 따른다(`OnboardingView.setCountry`).
struct LocaleCheck: View {
    let country: MenuCountry
    let onCountry: (MenuCountry) -> Void
    let onNext: () -> Void

    @Environment(\.openURL) private var openURL

    /// 지금 앱이 쓰는 언어를 그 언어로 적는다. 읽지 못하는 언어로 떠도 자기 언어 이름은 알아본다.
    static var languageName: String {
        switch Bundle.main.preferredLocalizations.first {
        case "ko": "한국어"
        case "zh-Hant": "繁體中文"
        default: "English"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("시작하기 전에").kicker()
                Text("언어와 메뉴 국가를\n확인해 주세요")
                    .font(AppFont.pretendard(30, .extraBold, relativeTo: .largeTitle))
                    .tracking(AppFont.displayTracking(for: 30))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 55)

            VStack(spacing: 10) {
                Button(action: openAppSettings) {
                    row(title: String(localized: "언어")) {
                        HStack(spacing: 6) {
                            Text(verbatim: Self.languageName)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("locale-language")

                row(title: String(localized: "메뉴 국가")) {
                    Picker(String(localized: "메뉴 국가"), selection: Binding(get: { country }, set: onCountry)) {
                        ForEach(MenuCountry.allCases, id: \.self) { country in
                            Text(country.name).tag(country)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .tint(Color.ink.opacity(0.72))
                    .accessibilityIdentifier("locale-country")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 32)

            Spacer(minLength: 16)

            Button(action: onNext) {
                Text("다음")
                    .ctaLabel()
                    .foregroundStyle(.white)
                    .background(Color.accentColor, in: Capsule())
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityIdentifier("onboarding-locale-next")
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
    }

    private func row(title: String, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(AppFont.pretendard(16, .semibold, relativeTo: .body))
                .foregroundStyle(Color.ink)
            Spacer(minLength: 8)
            trailing()
                .font(AppFont.pretendard(16, .regular, relativeTo: .body))
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 56)
        .background {
            let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
            shape.fill(.white.opacity(0.72)).overlay(shape.strokeBorder(.white.opacity(0.95)))
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}
