import SwiftUI

/// 속이 빈 외곽선 글자. 글자를 둘레로 여러 번 찍은 뒤 가운데를 글자 모양으로 파낸다.
struct OutlineText: View {
    let text: String
    let font: Font
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        let half = lineWidth / 2
        ZStack {
            ForEach(0..<16, id: \.self) { index in
                let angle = Double(index) / 16 * 2 * Double.pi
                Text(text)
                    .font(font)
                    .foregroundStyle(color)
                    .offset(x: half * cos(angle), y: half * sin(angle))
            }
            Text(text)
                .font(font)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
        .fixedSize()
    }
}
