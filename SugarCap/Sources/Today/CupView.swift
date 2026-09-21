import SwiftUI

/// 컵 장면 한 장. 배경·컵·액체가 다 들어간 완성 이미지라 레이어를 합성하지 않는다(SPEC §9-10).
/// 단계가 바뀌면 크로스페이드한다.
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

    var body: some View {
        Color.clear
            // 아래 정렬로 자른다. 장면 위쪽 약 28%는 빈 흰 여백이고 잔은 아래쪽에 있어서,
            // 가운데 정렬로 자르면 잔 바닥이 잘린다.
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
