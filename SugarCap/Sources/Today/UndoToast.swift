import SwiftUI

/// 즐겨찾기 `+`로 바로 기록한 뒤 4초 동안 뜨는 되돌리기 안내(2026-09-26 HTML 프로토타입 확정).
/// 한 번에 기록되는 만큼 잘못 누른 잔을 곧바로 지울 수 있어야 한다.
struct UndoToast: Equatable, Identifiable {
    let id = UUID()
    let entryID: UUID
    let text: String
}

struct UndoToastView: View {
    let toast: UndoToast
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Text(toast.text)
                .font(AppFont.pretendard(14, .medium, relativeTo: .subheadline))
                .lineLimit(1)
            Button(action: onUndo) {
                Text("되돌리기")
                    .font(AppFont.pretendard(13, .semibold, relativeTo: .footnote))
                    .padding(.horizontal, 12)
                    .frame(minHeight: 32)
                    .background(.white.opacity(0.16), in: Capsule())
                    .tapTarget()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("toast-undo")
        }
        .foregroundStyle(.white)
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .frame(minHeight: 44)
        .background(Color(white: 0.11, opacity: 0.88), in: Capsule())
        .padding(.horizontal, 20)
        .accessibilityElement(children: .contain)
    }
}
