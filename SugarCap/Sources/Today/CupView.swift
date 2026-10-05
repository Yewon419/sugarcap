import SwiftUI

/// 컵 장면 한 장. 배경·컵·액체가 다 들어간 원본 사진이다(SPEC §9-10). 단계가 바뀌면 크로스페이드한다.
/// 2026-09-27 대표님: 오늘 탭은 누끼 없이 원본 사진으로. 오린 컵(`cutout-*`)은 추이 선반·영향 미리보기만 쓴다.
///
/// 크기(2026-09-26 대표님 지시): 사진 높이를 화면의 84%로 줄여 바닥에 붙이고, 위 빈 곳은 벽 색(#F3F5F8)으로 채운다.
/// 사진 윗부분 14%는 벽 색으로 녹아들게 가린다. 폭은 화면 폭 그대로 채우기라 양옆 경계선이 생기지 않는다.
/// 2026-09-28 대표님: 잔 바닥이 페이지 점·탭 바에 가려서 사진을 화면 높이의 8%만큼 올렸다. 아래 빈 곳은
/// 벽 색이고(식탁 색과 거의 같다, RGB 239~247), 사진 아래 끝 4%를 녹여 경계가 안 보이게 한다.
/// 2026-10-05 대표님 베타 피드백 "하단바 없어졌으니 컵 더 아래로": 탭 바를 없앤 만큼 8% → 4%로 내렸다.
struct CupView: View {
    let step: Int
    let setID: String
    /// 캐릭터 대기 자세. 오늘 탭 컵에만 붙인다.
    let idle: IdleCharacterLayer?

    init(step: Int, setID: String = CupLevel.defaultSetID, idle: IdleCharacterLayer? = nil) {
        self.step = step
        self.setID = setID
        self.idle = idle
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let heightRatio: CGFloat = 0.84
    static let liftRatio: CGFloat = 0.04
    static let wallColor = Color(red: 0xF3 / 255, green: 0xF5 / 255, blue: 0xF8 / 255)

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
                            Image(assetName)
                                .resizable()
                                .scaledToFill()
                                .overlay {
                                    // 대기 루프(얼음, SPEC §9-10). 동작 줄이기면 정지 사진만.
                                    if !reduceMotion { CupIdleOverlay(assetName: assetName) }
                                }
                                // .id로 뷰를 교체해야 transition이 걸린다. 같은 Image에 이름만 바꾸면 페이드 없이 즉시 갈린다.
                                .id(assetName)
                                .transition(.opacity)
                        }
                        // 사진 칸 안에 두어 사진과 한 묶음으로 움직인다. 단계가 바뀔 때 자세가 다시 시작되지 않게 `.id` 밖에 둔다.
                        .overlay { idle }
                        .clipped()
                        .mask {
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0), .init(color: .black, location: 0.14),
                                    .init(color: .black, location: 0.96), .init(color: .clear, location: 1),
                                ],
                                startPoint: .top, endPoint: .bottom
                            )
                        }
                        .padding(.bottom, proxy.size.height * Self.liftRatio)
                }
        }
        // 기록처럼 애니메이션 없이 바뀐 단계도 부드럽게. 넘기기처럼 호출한 쪽이 애니메이션을 주면 그걸 따른다.
        .transaction { transaction in
            if transaction.animation == nil { transaction.animation = .easeInOut(duration: 0.35) }
        }
        .accessibilityHidden(true)
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
