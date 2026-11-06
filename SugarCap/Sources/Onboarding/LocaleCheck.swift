import SwiftUI
import UIKit

/// 첫 실행 맨 앞 단계(대표님 2026-11-06): 영상을 틀기 전에 메뉴 국가를 고르고 앱 언어를 확인한다.
/// 모양은 `design/proto/locale-check.html` v3(대표님 확정): 오른쪽에 같은 크기 국기 방울과 먹이기 방울이 한 줄로 끝없이 흐르고,
/// 국기를 누르면 그 나라가 된다. 왼쪽에 고른 나라의 코드·카페인 하루 기준·브랜드, 아래에 둥근 다음 버튼.
/// 언어는 iOS가 정한다. 언어 단추는 iOS 설정으로 안내하는 시트를 띄우고, 거기서 바꾸면 iOS가 앱을 다시 띄워
/// 온보딩 전이라 이 화면으로 돌아온다(앱 안에서 바꾸지 않는다, 대표님 결정).
/// 메뉴 국가는 고르는 즉시 저장되고 카페인 하루 기준도 그 나라 권고량을 따른다(`OnboardingView.setCountry`).
struct LocaleCheck: View {
    let country: MenuCountry
    let onCountry: (MenuCountry) -> Void
    let onNext: () -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAskingLanguage = false

    /// 지금 앱이 쓰는 언어를 그 언어로 적는다. 읽지 못하는 언어로 떠도 자기 언어 이름은 알아본다.
    static var languageName: String {
        switch Bundle.main.preferredLocalizations.first {
        case "ko": "한국어"
        case "zh-Hant": "繁體中文"
        default: "English"
        }
    }

    var body: some View {
        GeometryReader { proxy in
            // 방울 열 가운데는 오른쪽 끝에서 126pt(402pt 화면 시안 기준). 왼쪽 글은 열과 8pt 띄운다.
            let leftWidth = min(172, proxy.size.width - DropColumn.centerInset - DropColumn.diameter / 2 - 24 - 8)
            ZStack(alignment: .topLeading) {
                DropColumn(selected: country, isMoving: !reduceMotion, onPick: onCountry)
                    .frame(width: DropColumn.diameter + 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .padding(.trailing, DropColumn.centerInset - DropColumn.diameter / 2 - 8)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 0) {
                    languageButton
                    VStack(alignment: .leading, spacing: 10) {
                        Text("메뉴 국가").kicker()
                        Text("어디에서\n마셔요?")
                            .font(AppFont.pretendard(30, .extraBold, relativeTo: .largeTitle))
                            .tracking(AppFont.displayTracking(for: 30))
                            .lineSpacing(3)
                            .minimumScaleFactor(0.7)
                    }
                    .padding(.top, 14)
                    Spacer(minLength: 24)
                    pick
                    Spacer(minLength: 24)
                    Text("나중에 설정에서 언제든 바꿀 수 있어요.")
                        .font(AppFont.pretendard(12, .regular, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    nextButton
                        .padding(.top, 18)
                }
                .frame(width: leftWidth, alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.leading, 24)
                .padding(.bottom, 8)
            }
        }
        // 왼쪽 글 폭이 방울 열에 막혀 있어 아주 큰 글자에서는 제목이 열을 넘는다. 이 화면만 글자 상한을 둔다.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .sheet(isPresented: $isAskingLanguage) {
            LanguageSheet(onOpen: openAppSettings, onCancel: { isAskingLanguage = false })
        }
    }

    private var languageButton: some View {
        Button {
            isAskingLanguage = true
        } label: {
            HStack(spacing: 5) {
                Text(verbatim: Self.languageName)
                    .font(AppFont.pretendard(14, .bold, relativeTo: .footnote))
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(Color.ink)
            .tapTarget()
        }
        .padding(.top, 4)
        .accessibilityIdentifier("locale-language")
    }

    /// 고른 나라. VoiceOver에서는 방울 열 대신 여기서 위아래로 쓸어 나라를 바꾼다.
    private var pick: some View {
        VStack(alignment: .leading, spacing: 0) {
            OutlineText(text: country.rawValue.uppercased(), font: AppFont.numeralFixed(64), color: .ink, lineWidth: 2.5)
            Text(country.name)
                .font(AppFont.pretendard(17, .bold, relativeTo: .headline))
                .padding(.top, 10)
            Text("카페인 하루 기준")
                .font(AppFont.pretendard(11, .semibold, relativeTo: .caption2))
                .tracking(1.3)
                .foregroundStyle(.secondary)
                .padding(.top, 18)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(Amount.number(country.caffeineAdviceMg))
                    .font(AppFont.numeral(26, relativeTo: .title2))
                Text(verbatim: "mg")
                    .font(AppFont.numeral(13, relativeTo: .footnote))
            }
            .padding(.top, 6)
            Text(Self.brands(for: country))
                .font(AppFont.pretendard(12, .regular, relativeTo: .caption))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
        }
        .foregroundStyle(Color.ink)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "메뉴 국가"))
        .accessibilityValue(country.name)
        .accessibilityAdjustableAction { direction in
            let all = MenuCountry.allCases
            guard let index = all.firstIndex(of: country) else { return }
            switch direction {
            case .increment: onCountry(all[(index + 1) % all.count])
            case .decrement: onCountry(all[(index + all.count - 1) % all.count])
            @unknown default: break
            }
        }
        .accessibilityIdentifier("locale-country")
    }

    private var nextButton: some View {
        Button(action: onNext) {
            Image(systemName: "arrow.right")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(Color.ink, in: Circle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(String(localized: "다음"))
        .accessibilityIdentifier("onboarding-locale-next")
    }

    /// 그 나라 카탈로그의 앞쪽 브랜드(`data/catalog*.json` 표기 그대로). 한국은 17곳이라 셋만 적고 나머지는 "외".
    private static func brands(for country: MenuCountry) -> String {
        switch country {
        case .kr: String(localized: "\("스타벅스 · 메가MGC커피 · 컴포즈커피") 외")
        case .us: "Starbucks · Dutch Bros"
        case .tw: "cama café · 可不可熟成紅茶"
        }
    }

    private func openAppSettings() {
        isAskingLanguage = false
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}

/// 국기 방울과 먹이기 방울(`drop-*`)이 같은 크기로 한 줄에 서서 끝없이 위로 흐른다. 끌면 따라오고,
/// 놓으면 손가락 속도 그대로 관성으로 가다가 원래 흐르던 속도로 돌아온다(대표님 2026-11-06 "뚝 멈추면 애플 문법 아님").
/// 칸 번호로 위치를 바로 계산해서 감아 돌릴 필요가 없다(위로든 아래로든 끝이 없다).
private struct DropColumn: View {
    let selected: MenuCountry
    let isMoving: Bool
    let onPick: (MenuCountry) -> Void

    static let diameter: CGFloat = 108
    static let centerInset: CGFloat = 126
    private static let step: CGFloat = 130
    private static let speed: CGFloat = 22
    /// 감속 시간상수. UIScrollView 기본 감속(1ms마다 0.998배)과 같다: −1/ln(0.998) ≈ 0.5초.
    private static let decay: Double = 0.5
    private static let maxFling: CGFloat = 5000

    private enum Item {
        case flag(MenuCountry)
        case drink(String)
    }

    private static let items: [Item] = [.flag(.kr), .drink("drop-matcha"), .flag(.us), .drink("drop-mango"), .flag(.tw), .drink("drop-grape")]

    @State private var anchorOffset: CGFloat = 30
    @State private var anchorTime = Date()
    /// 기준 시각의 속도(pt/s, 위로 흐르는 쪽이 +). 놓을 때 손가락 속도, 평소에는 흐르는 속도.
    @State private var anchorVelocity: CGFloat = DropColumn.speed
    @State private var dragBase: CGFloat?
    @State private var dragOffset: CGFloat?
    /// 동작 줄이기에서는 흐르지 않지만, 던진 관성은 스크롤처럼 끝까지 보여 준다.
    @State private var isFlinging = false

    private var drift: CGFloat { isMoving ? Self.speed : 0 }

    var body: some View {
        TimelineView(.animation(paused: !isMoving && !isFlinging)) { timeline in
            let now = timeline.date
            let offset = currentOffset(at: now)
            let t = isMoving ? now.timeIntervalSinceReferenceDate : 0
            GeometryReader { proxy in
                let first = Int((offset / Self.step).rounded(.down)) - 1
                let count = Int((proxy.size.height / Self.step).rounded(.up)) + 2
                ZStack(alignment: .top) {
                    ForEach(first..<(first + count), id: \.self) { slot in
                        drop(Self.items[((slot % Self.items.count) + Self.items.count) % Self.items.count], slot: slot, time: t)
                            .offset(y: CGFloat(slot) * Self.step - offset)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .contentShape(Rectangle())
        .sensoryFeedback(.selection, trigger: selected)
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { drag in
                    let base = dragBase ?? currentOffset(at: Date())
                    dragBase = base
                    dragOffset = base - drag.translation.height
                }
                .onEnded { drag in
                    anchorOffset = dragOffset ?? anchorOffset
                    anchorTime = Date()
                    // 손가락이 위로 가면(velocity.height < 0) 열도 위로 흐르는 쪽(+)이다.
                    anchorVelocity = min(Self.maxFling, max(-Self.maxFling, -drag.velocity.height))
                    dragBase = nil
                    dragOffset = nil
                    isFlinging = true
                }
        )
        .task(id: anchorTime) {
            guard isFlinging else { return }
            try? await Task.sleep(for: .seconds(Self.decay * 6))
            isFlinging = false
        }
    }

    /// 속도가 손가락 속도에서 흐르는 속도로 지수로 줄어든다: v(t) = drift + (v₀ − drift)·e^(−t/τ). 위치는 그 적분.
    private func currentOffset(at now: Date) -> CGFloat {
        if let dragOffset { return dragOffset }
        let dt = max(0, now.timeIntervalSince(anchorTime))
        let settle = CGFloat(Self.decay * (1 - exp(-dt / Self.decay)))
        return anchorOffset + drift * CGFloat(dt) + (anchorVelocity - drift) * settle
    }

    /// 국기 방울은 모양이 살짝 출렁이고(가로세로가 엇갈려 늘었다 줄었다), 먹이기 방울은 원래 공 그림이라 위아래로만 뜬다.
    @ViewBuilder
    private func drop(_ item: Item, slot: Int, time: TimeInterval) -> some View {
        let period = 12 + Double(slot.magnitude % 4) * 2
        let phase = sin(time * 2 * .pi / period + Double(slot) * 1.3)
        switch item {
        case let .flag(country):
            Image("flag-\(country.rawValue)")
                .resizable()
                .scaledToFill()
                .frame(width: Self.diameter, height: Self.diameter)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.ink.opacity(0.12), lineWidth: 1.5))
                .scaleEffect(x: 1 + 0.018 * phase, y: 1 - 0.018 * phase)
                .overlay {
                    if country == selected {
                        // 방울과 3pt 띄운 3pt 먹색 테두리.
                        Circle().stroke(Color.ink, lineWidth: 3).padding(-4.5)
                    }
                }
                .offset(y: -2.5 * phase)
                .contentShape(Circle())
                .onTapGesture { onPick(country) }
        case let .drink(asset):
            Image(asset)
                .resizable()
                .scaledToFit()
                .frame(width: Self.diameter, height: Self.diameter)
                .offset(y: -2.5 * phase)
                .allowsHitTesting(false)
        }
    }
}

/// 언어는 앱 안에서 바꾸지 않는다. iOS 설정의 이 앱 화면으로 보낸다.
private struct LanguageSheet: View {
    let onOpen: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("언어는\niOS 설정에서 바꿔요")
                .font(AppFont.pretendard(22, .extraBold, relativeTo: .title2))
                .tracking(AppFont.displayTracking(for: 22))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Text("설정 › 슈가캡 › 언어")
                .font(AppFont.pretendard(14, .regular, relativeTo: .subheadline))
                .foregroundStyle(.secondary)
                .padding(.top, 10)
            Button(action: onOpen) {
                Text("설정 열기")
                    .ctaLabel()
                    .foregroundStyle(.white)
                    .background(Color.ink, in: Capsule())
            }
            .buttonStyle(PressScaleStyle())
            .padding(.top, 22)
            .accessibilityIdentifier("locale-open-settings")
            Button(action: onCancel) {
                Text("그대로 두기")
                    .font(AppFont.pretendard(14, .medium, relativeTo: .footnote))
                    .foregroundStyle(Color.ink.opacity(0.72))
                    .frame(maxWidth: .infinity)
                    .tapTarget()
            }
            .padding(.top, 4)
        }
        .foregroundStyle(Color.ink)
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .presentationDetents([.height(300)])
        .presentationBackground(Color.wall)
    }
}
