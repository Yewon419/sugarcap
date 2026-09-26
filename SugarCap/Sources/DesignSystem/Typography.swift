import SwiftUI

/// 오늘 화면에서 정한 글자 규칙(2026-09-24 디자인)을 다른 화면이 같이 쓴다.
/// 서체는 Pretendard 하나(`AppFont`, 2026-09-26)이고, 위계는 크기 대비와 자간으로만 만든다(SPEC §5).
extension View {
    /// 자간을 벌린 11pt 소제목. 숫자나 목록이 무엇인지 먼저 말한다. 액센트 색.
    func kicker() -> some View {
        font(AppFont.pretendard(11, .semibold, relativeTo: .caption2))
            .tracking(1.3)
            .foregroundStyle(.tint)
    }

    /// 자간을 벌린 11pt 날짜·보조 라벨. 보조색.
    func dateLabel() -> some View {
        font(AppFont.pretendard(11, .medium, relativeTo: .caption2))
            .tracking(1.5)
            .foregroundStyle(.secondary)
    }

    /// 화면의 주인공 숫자. 자간을 좁혀 덩어리로 읽힌다.
    func heroNumber() -> some View {
        font(AppFont.pretendardFixed(96, .bold))
            .tracking(-5.8)
            .monospacedDigit()
    }

    /// 주인공 숫자 옆에 붙는 단위.
    func heroUnit() -> some View {
        font(AppFont.pretendardFixed(30, .medium))
            .opacity(0.85)
    }

    /// 화면 하단 주 동작 버튼(다음·시작·먹이기·구매)의 글자와 크기.
    /// 큰 글자 설정을 따라 커지되 접근성 3단계에서 멈추고, 한 줄을 지킨다. 높이는 최소 56pt.
    func ctaLabel() -> some View {
        font(AppFont.pretendard(17, .semibold, relativeTo: .headline))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .dynamicTypeSize(...DynamicTypeSize.accessibility3)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 56)
    }

    /// 글자만 있는 버튼(닫기·건너뛰기·잠금 링크)의 누르는 영역을 44pt 이상으로 넓힌다.
    /// 보이는 모양은 그대로 두고 판정 영역만 키운다.
    func tapTarget() -> some View {
        frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }

    /// 조작부 유리 알약. 액센트는 주 동작 하나에만 쓰고 나머지는 이걸로 조용히 둔다.
    func glassPill() -> some View {
        padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.45), lineWidth: 1))
            .shadow(color: .black.opacity(0.10), radius: 8, y: 3)
    }
}
