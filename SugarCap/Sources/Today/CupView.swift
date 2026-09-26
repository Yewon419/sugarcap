import SwiftUI

/// 컵 장면 한 장. 배경·컵·액체가 다 들어간 완성 이미지라 레이어를 합성하지 않는다(SPEC §9-10).
/// 단계가 바뀌면 크로스페이드한다.
///
/// 크기(2026-09-26 대표님 지시, HTML 프로토타입에서 확정): 사진 높이를 화면의 84%로 줄여 바닥에 붙이고,
/// 위에 생긴 빈 곳은 사진 가장자리 벽 색(#F3F5F8)으로 채운다. 사진 윗부분 14%는 벽 색으로 녹아들게 가린다.
/// 폭은 화면 폭 그대로 채우기라 양옆 경계선이 생기지 않는다(scale로 줄이면 폭까지 줄어 경계가 보였다).
struct CupView: View {
    let step: Int
    let setID: String

    init(step: Int, setID: String = CupLevel.defaultSetID) {
        self.step = step
        self.setID = setID
    }

    private var assetName: String {
        CupLevel.assetName(setID: setID, step: step)
    }

    static let heightRatio: CGFloat = 0.84
    static let wallColor = Color(red: 0xF3 / 255, green: 0xF5 / 255, blue: 0xF8 / 255)

    var body: some View {
        GeometryReader { proxy in
            Self.wallColor
                // 아래 정렬로 자른다. 장면 위쪽 약 28%는 빈 흰 여백이고 잔은 아래쪽에 있어서,
                // 가운데 정렬로 자르면 잔 바닥이 잘린다.
                .overlay(alignment: .bottom) {
                    Color.clear
                        .frame(height: proxy.size.height * Self.heightRatio)
                        .overlay(alignment: .bottom) {
                            Image(assetName)
                                .resizable()
                                .scaledToFill()
                                // .id로 뷰를 교체해야 transition이 걸린다. 같은 Image에 이름만 바꾸면
                                // 페이드 없이 즉시 갈린다.
                                .id(assetName)
                                .transition(.opacity)
                        }
                        .clipped()
                        .mask {
                            LinearGradient(
                                stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.14)],
                                startPoint: .top, endPoint: .bottom
                            )
                        }
                }
        }
        .animation(.easeInOut(duration: 0.35), value: assetName)
        .accessibilityHidden(true)
    }
}

#Preview("단계") {
    VStack(spacing: 0) {
        CupView(step: 100)
        CupView(step: 50)
        CupView(step: 0)
    }
}
