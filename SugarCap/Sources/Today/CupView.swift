import SwiftUI

/// 컵 장면 한 장. 배경·컵·액체가 다 들어간 원본 사진이다(SPEC §9-10). 단계가 바뀌면 크로스페이드한다.
/// 2026-09-27 대표님: 오늘 탭은 누끼 없이 원본 사진으로. 오린 컵(`cutout-*`)은 추이 선반·영향 미리보기와
/// 영향 미리보기로만 쓴다. 큰 숫자(`CupHero`)는 유리 선(`rimline-*`)으로 끊는다.
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
    /// 선물을 들고 온 캐릭터(SPEC §4.9). 있는 동안 대기 자세 대신 이게 캐릭터다.
    let gift: GiftCarrierLayer?
    /// 단계 상승 무대에 선 캐릭터(SPEC §4.9 결정 4). 있는 동안 대기 자세 대신 이게 캐릭터다.
    let stage: LevelUpStageLayer?
    /// 잔 뒤에 걸친 큰 숫자(2026-10-13). 사진 위·캐릭터 아래.
    let hero: CupHero?
    /// 오늘 화면 넘기기 띠에서만 준다. 사진을 원본처럼 좌우로 넓혀(`cupwide-*`) 옆 장과 겹치게 하고, 왼쪽 날개는 이 값(0 = 왼쪽
    /// 장을 보는 중, 1 = 이 장을 보는 중)만큼 드러낸다. nil이면 사진을 칸 폭으로 자른다(대표님 베타 피드백 2026-10-23
    /// "냅킨 겹치는 게 거슬려서 원본처럼 좌우를 넓게, 그 사이는 투명도로 자연스럽게").
    let seam: Double?

    init(
        step: Int, setID: String = CupLevel.defaultSetID, idle: IdleCharacterLayer? = nil, gift: GiftCarrierLayer? = nil,
        stage: LevelUpStageLayer? = nil, hero: CupHero? = nil, seam: Double? = nil
    ) {
        self.step = step
        self.setID = setID
        self.idle = idle
        self.gift = gift
        self.stage = stage
        self.hero = hero
        self.seam = seam
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let heightRatio: CGFloat = 0.84
    static let liftRatio: CGFloat = 0.04
    static let wallColor = Color(red: 0xF3 / 255, green: 0xF5 / 255, blue: 0xF8 / 255)
    /// 넓힌 사진(`design/assets/cups/make_wide.py`)의 한쪽 날개 폭(원래 사진 937px 대비). 넘길 때 옆 장과 겹치는 폭이자
    /// 투명도가 바뀌는 폭이다.
    static let wingRatio: CGFloat = 300 / 937

    private var assetName: String {
        CupLevel.assetName(setID: setID, step: step)
    }

    var body: some View {
        GeometryReader { proxy in
            let slot = CGSize(width: proxy.size.width, height: proxy.size.height * Self.heightRatio)
            let photo = IdlePhoto(slot: slot)
            let wing: CGFloat = seam == nil ? 0 : Self.wingRatio * photo.width
            ZStack(alignment: .bottom) {
                Self.wallColor
                    // 아래 정렬로 자른다. 장면 위쪽 약 28%는 빈 흰 여백이고 잔은 아래쪽에 있어서,
                    // 가운데 정렬로 자르면 잔 바닥이 잘린다.
                    .overlay(alignment: .bottom) {
                        photoLayer(photo: photo, wing: wing)
                            .frame(width: slot.width + 2 * wing, height: slot.height, alignment: .bottom)
                            .clipped()
                            // 위아래 녹임은 사진에만 건다. 숫자(사진 칸 위 14% 안까지 올라온다)·캐릭터는 녹이지 않는다(2026-10-13).
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
                    // 마스크는 넓힌 폭에서 건다. 음수 패딩 뒤에 걸면 마스크 칸이 이 칸 폭이라 날개가 통째로 가려진다
                    // (빌드 267 CI slide-*: 두 장 사이 흰 띠). 마지막 frame이 칸 폭을 알리고 날개는 양옆으로 넘친다.
                    .frame(width: slot.width + 2 * wing)
                    .mask(alignment: .leading) {
                        if let seam {
                            // 왼쪽 날개 폭만큼 투명 → 불투명. 0이면 이 칸 왼쪽 끝부터, 1이면 왼쪽 날개 끝부터 드러난다.
                            HStack(spacing: 0) {
                                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                                    .frame(width: wing)
                                Color.black
                            }
                            .offset(x: wing * (1 - seam))
                        } else {
                            Color.black
                        }
                    }
                    .frame(width: slot.width)
                Color.clear
                    .frame(height: slot.height)
                    .overlay { hero }
                    // 사진 칸 안에 두어 사진과 한 묶음으로 움직인다. 단계가 바뀔 때 자세가 다시 시작되지 않게 `.id` 밖에 둔다.
                    .overlay { idle }
                    .overlay { gift }
                    .overlay { stage }
                    .clipped()
                    .padding(.bottom, proxy.size.height * Self.liftRatio)
            }
        }
        // 기록처럼 애니메이션 없이 바뀐 단계도 부드럽게. 넘기기처럼 호출한 쪽이 애니메이션을 주면 그걸 따른다.
        // 손가락을 따라 끄는 중(`disablesAnimations`)이면 날개 투명도가 늦게 따라오지 않게 그대로 둔다.
        .transaction { transaction in
            if transaction.animation == nil, !transaction.disablesAnimations {
                transaction.animation = .easeInOut(duration: 0.35)
            }
        }
        .accessibilityHidden(true)
    }

    /// 사진 칸(위아래 녹임 전). 날개가 있으면 넓힌 사진을 밑에 깔고, 원래 사진 좌우 끝 3%를 녹여 이음매를 감춘다.
    private func photoLayer(photo: IdlePhoto, wing: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            if wing > 0 {
                let wideName = CupLevel.wideName(setID: setID, step: step)
                Image(wideName)
                    .resizable()
                    .frame(width: photo.width + 2 * wing, height: photo.height)
                    .id(wideName)
                    .transition(.opacity)
            }
            Image(assetName)
                .resizable()
                .frame(width: photo.width, height: photo.height)
                .overlay {
                    // 대기 루프(얼음, SPEC §9-10). 동작 줄이기면 정지 사진만.
                    if !reduceMotion { CupIdleOverlay(assetName: assetName) }
                }
                .mask {
                    if wing > 0 {
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0), .init(color: .black, location: 0.03),
                                .init(color: .black, location: 0.97), .init(color: .clear, location: 1),
                            ],
                            startPoint: .leading, endPoint: .trailing
                        )
                    } else {
                        Color.black
                    }
                }
                // .id로 뷰를 교체해야 transition이 걸린다. 같은 Image에 이름만 바꾸면 페이드 없이 즉시 갈린다.
                .id(assetName)
                .transition(.opacity)
        }
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
