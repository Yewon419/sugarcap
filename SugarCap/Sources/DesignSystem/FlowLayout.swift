import SwiftUI

/// 폭이 차면 다음 줄로 넘기는 배치. 오늘 화면 브랜드 칩에 쓴다.
///
/// 칩 9개(브랜드 8 + 직접 입력)를 가로 스크롤에 두면 "직접 입력"이 화면 밖으로 밀려
/// 스크롤해야만 보인다. 프로토타입도 줄바꿈이다(`design/prototype.html:250`, `flex-wrap:wrap`).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var cursorX: CGFloat = 0
        var cursorY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursorX > 0, cursorX + size.width > maxWidth {
                cursorY += lineHeight + lineSpacing
                cursorX = 0
                lineHeight = 0
            }
            widest = max(widest, cursorX + size.width)
            cursorX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: widest, height: cursorY + lineHeight)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        var cursorX = bounds.minX
        var cursorY = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursorX > bounds.minX, cursorX + size.width > bounds.maxX {
                cursorY += lineHeight + lineSpacing
                cursorX = bounds.minX
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: cursorX, y: cursorY), proposal: ProposedViewSize(size))
            cursorX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
