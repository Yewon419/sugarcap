import SwiftUI

/// 선물 상자를 누르면 뜨는 내용 카드(SPEC §4.9). 상자 열림 그림이 아직 없어 카드로 연다(2026-10-09 대표님).
/// 컵 사진 위에 뜨므로 안내 카드(`TodayView.notice`)처럼 흰 막을 깔되 글이 많아 더 불투명하게.
struct GiftCardView: View {
    let gift: GiftEvent
    /// 두 번째 마음부터(무료) "다른 것도 받고 싶으시다고요?" 줄을 붙인다(`GiftMath.offersPro`).
    let offersPro: Bool
    let onConfirm: () -> Void
    let onPro: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("선물")
                .kicker()
            Text(title)
                .font(AppFont.pretendard(24, .bold, relativeTo: .title2))
                .tracking(-0.3)
                .fixedSize(horizontal: false, vertical: true)
            if !message.isEmpty {
                Text(message)
                    .font(AppFont.pretendard(15, .regular, relativeTo: .subheadline))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: onConfirm) {
                Text("확인")
                    .ctaLabel()
                    .foregroundStyle(.white)
                    .background(Color.accentColor, in: Capsule())
            }
            .buttonStyle(PressScaleStyle())
            .padding(.top, 10)
            .accessibilityIdentifier("gift-confirm")
            if offersPro && isHeart {
                Button(action: onPro) {
                    Text("이제 마음 말고 슬슬 다른 것도 받고 싶으시다고요?")
                        .underline()
                        .font(AppFont.pretendard(14, .semibold, relativeTo: .subheadline))
                        .foregroundStyle(Color.ink)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("gift-pro")
            }
        }
        .padding(22)
        .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white.opacity(0.7)))
        .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gift-card")
    }

    /// 주·목표 선물은 지금 마음뿐이다(무료는 늘 마음, Pro 내용물은 대표님 구상 후). 첫 보상(추이 열림)은 카드 대신 열림 연출이라 여기 오지 않는다.
    private var isHeart: Bool {
        switch gift.giftKind {
        case .weekKept, .goalReached: return true
        case .trendsUnlock, .levelUp, nil: return false
        }
    }

    private var title: String {
        guard isHeart, let side = gift.cupSide else { return String(localized: "선물을 받았어요") }
        return String(localized: "'\(side.characterName)의 마음'을 받았어요!")
    }

    private var message: String {
        isHeart ? String(localized: "기쁘시죠?") : ""
    }
}
