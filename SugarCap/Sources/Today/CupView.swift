import SwiftUI

/// 컵 장면. 식탁 배경(`cup-table`) 위에 오려 낸 컵(`cup-<세트>-<단계>`)을 같은 자리로 얹는다.
/// 둘 다 원본 사진과 같은 937×1666 캔버스라, 가만히 있을 땐 원래 사진 한 장과 똑같이 보인다(SPEC §9-10).
///
/// - 같은 면에서 단계가 바뀌면(기록·삭제) 컵만 크로스페이드한다.
/// - 당 ↔ 카페인을 넘기면 식탁은 그대로 두고 컵이 식탁 위를 밀려 나가고 다른 컵이 밀려 들어온다
///   (2026-09-27 대표님 베타 피드백: "페이드 말고 식탁 위에서 음료를 미는 것처럼").
///
/// 크기(2026-09-26 대표님 지시): 장면 높이를 화면의 84%로 줄여 바닥에 붙이고, 위 빈 곳은 벽 색(#F3F5F8)으로 채운다.
/// 장면 윗부분 14%는 벽 색으로 녹아들게 가린다. 폭은 화면 폭 그대로 채우기라 양옆 경계선이 생기지 않는다.
struct CupView: View {
    let step: Int
    let setID: String
    /// 면이 바뀔 때 컵이 움직이는 방향. `.leading`이면 새 컵이 오른쪽에서 들어와 왼쪽으로 민다.
    var pushTowards: Edge = .leading

    init(step: Int, setID: String = CupLevel.defaultSetID, pushTowards: Edge = .leading) {
        self.step = step
        self.setID = setID
        self.pushTowards = pushTowards
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let heightRatio: CGFloat = 0.84
    static let wallColor = Color(red: 0xF3 / 255, green: 0xF5 / 255, blue: 0xF8 / 255)
    static let tableAsset = "cup-table"

    private var assetName: String {
        CupLevel.assetName(setID: setID, step: step)
    }

    var body: some View {
        GeometryReader { proxy in
            Self.wallColor
                // 아래 정렬로 자른다. 장면 위쪽 약 28%는 빈 흰 여백이고 잔은 아래쪽에 있어서,
                // 가운데 정렬로 자르면 잔 바닥이 잘린다.
                .overlay(alignment: .bottom) {
                    Color.clear
                        .frame(height: proxy.size.height * Self.heightRatio)
                        .overlay(alignment: .bottom) {
                            ZStack(alignment: .bottom) {
                                Image(Self.tableAsset)
                                    .resizable()
                                    .scaledToFill()
                                glass(width: proxy.size.width)
                            }
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
        // 기록처럼 애니메이션 없이 바뀐 단계도 부드럽게. 넘기기처럼 호출한 쪽이 애니메이션을 주면 그걸 따른다.
        .transaction { transaction in
            if transaction.animation == nil { transaction.animation = .easeInOut(duration: 0.35) }
        }
        .accessibilityHidden(true)
    }

    /// 면(세트)마다 한 덩어리. 세트가 바뀌면 덩어리째 밀려 나가고, 안에서는 단계 이미지가 크로스페이드한다.
    private func glass(width: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            Image(assetName)
                .resizable()
                .scaledToFill()
                // .id로 뷰를 교체해야 transition이 걸린다. 같은 Image에 이름만 바꾸면 페이드 없이 즉시 갈린다.
                .id(assetName)
                .transition(.opacity)
        }
        .id(setID)
        .transition(reduceMotion ? .opacity : .push(towards: pushTowards, distance: width))
    }
}

private struct GlassPush: ViewModifier {
    let offset: CGFloat
    let tilt: Double

    func body(content: Content) -> some View {
        content
            // 바닥을 밀면 윗부분이 살짝 뒤처진다. 잔 바닥을 축으로 기울인다.
            .rotationEffect(.degrees(tilt), anchor: UnitPoint(x: 0.5, y: 0.9))
            .offset(x: offset)
    }
}

private extension AnyTransition {
    /// 식탁 위에서 잔을 미는 전환. 들어오는 잔은 반대편에서, 나가는 잔은 미는 방향으로.
    static func push(towards edge: Edge, distance: CGFloat) -> AnyTransition {
        let sign: CGFloat = edge == .leading ? -1 : 1
        return .asymmetric(
            insertion: .modifier(
                active: GlassPush(offset: -sign * distance, tilt: -Double(sign) * 4),
                identity: GlassPush(offset: 0, tilt: 0)
            ),
            removal: .modifier(
                active: GlassPush(offset: sign * distance, tilt: -Double(sign) * 4),
                identity: GlassPush(offset: 0, tilt: 0)
            )
        )
    }
}

/// 오려 낸 컵에서 잔만 잘라 주어진 틀에 맞춘다(추이 선반·영향 미리보기). 캔버스 대부분이 빈 곳이라
/// 두 세트의 잔 영역 합집합(`design/assets/cups/make_cutouts.py` 출력)으로 자른다. 바닥 정렬.
struct CupCrop: View {
    let asset: String

    private static let canvas = CGSize(width: 937, height: 1666)
    /// 잔 영역(x 194~741, y 410~1491) + 가장자리 여유.
    private static let glass = CGRect(x: 186, y: 400, width: 564, height: 1100)

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / Self.glass.width, proxy.size.height / Self.glass.height)
            let x = (proxy.size.width - Self.glass.width * scale) / 2 - Self.glass.minX * scale
            let y = proxy.size.height - Self.glass.maxY * scale
            Image(asset)
                .resizable()
                .frame(width: Self.canvas.width * scale, height: Self.canvas.height * scale)
                .offset(x: x, y: y)
        }
        .clipped()
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
