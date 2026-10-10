import SwiftUI

/// 선물 상자를 누르면 뜨는 내용 카드(SPEC §4.9). 상자 열림 그림이 아직 없어 카드로 연다(2026-10-09 대표님).
/// 컵 사진 위에 뜨므로 안내 카드(`TodayView.notice`)처럼 흰 막을 깔되 글이 많아 더 불투명하게.
struct GiftCardView: View {
    let gift: GiftEvent
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("선물")
                .kicker()
            Text(title)
                .font(AppFont.pretendard(24, .bold, relativeTo: .title2))
                .tracking(-0.3)
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .font(AppFont.pretendard(15, .regular, relativeTo: .subheadline))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onConfirm) {
                Text("확인")
                    .ctaLabel()
                    .foregroundStyle(.white)
                    .background(Color.accentColor, in: Capsule())
            }
            .buttonStyle(PressScaleStyle())
            .padding(.top, 10)
            .accessibilityIdentifier("gift-confirm")
        }
        .padding(22)
        .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white.opacity(0.7)))
        .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gift-card")
    }

    /// 단계 상승·주·목표 카드는 Phase 2·3에서 채운다(SPEC §4.9). 첫 보상(추이 열림)은 카드 대신 열림 연출이라 여기 오지 않는다.
    private var title: String {
        switch gift.giftKind {
        case .trendsUnlock, .levelUp, .weekKept, .goalReached, nil: return String(localized: "선물을 받았어요")
        }
    }

    private var message: String {
        switch gift.giftKind {
        case .trendsUnlock, .levelUp, .weekKept, .goalReached, nil: return ""
        }
    }
}
