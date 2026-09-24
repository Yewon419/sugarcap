import SwiftUI

/// 오늘 화면에서 정한 글자 규칙(2026-09-24 디자인)을 다른 화면이 같이 쓴다.
/// 서체는 시스템 하나뿐이고, 위계는 크기 대비와 자간으로만 만든다(SPEC §5).
extension View {
    /// 자간을 벌린 11pt 소제목. 숫자나 목록이 무엇인지 먼저 말한다. 액센트 색.
    func kicker() -> some View {
        font(.system(size: 11, weight: .semibold))
            .tracking(1.3)
            .foregroundStyle(.tint)
    }

    /// 자간을 벌린 11pt 날짜·보조 라벨. 보조색.
    func dateLabel() -> some View {
        font(.system(size: 11, weight: .medium))
            .tracking(1.5)
            .foregroundStyle(.secondary)
    }

    /// 화면의 주인공 숫자. 자간을 좁혀 덩어리로 읽힌다.
    func heroNumber() -> some View {
        font(.system(size: 96, weight: .bold))
            .tracking(-5.8)
            .monospacedDigit()
    }

    /// 주인공 숫자 옆에 붙는 단위.
    func heroUnit() -> some View {
        font(.system(size: 30, weight: .medium))
            .opacity(0.85)
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
