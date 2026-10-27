import SwiftUI

/// 상자에서 나온 것을 보여 주는 조명 무대(SPEC §4.9, 대표님 레퍼런스 2026-10-11 "팝업 대신 이런 연출").
/// 화면이 어두워지고 → 가운데 조명이 "딱" 켜지며 물건이 드러나고 → 손그림 반짝이와 “ 이름 ” 캡션이 붙는다.
/// 조명 두 개가 화면을 훑다 모이던 연출은 뺐다(빌드 264 대표님 "빛 와리가리하는 연출 빼자").
/// 아무 데나 누르면 닫힌다(드러나기 전에 누르면 드러난 장면으로 건너뛴다).
/// 전부 `t`(시작 뒤 초)의 순수 함수다. 에어브러시 없음(CLAUDE.md 모션 규칙): 조명은 가장자리가 또렷한 단색 면.
enum GiftRevealTimeline {
    static let dimLength = 0.3
    /// 조명이 물건에 켜지는 때(어두워진 직후).
    static let land = 0.55
    static let captionIn = land + 0.3
    static let dim = 0.62
    /// 최종 조명 반지름(화면 폭 대비, 레퍼런스 300/923).
    static let spotRatio = 0.33
    /// 물건 자리(화면 비율, 레퍼런스 컵 가운데).
    static let centerY = 0.595

    /// 어둠의 진하기(0~1).
    static func darkness(_ t: Double, calm: Bool) -> Double {
        calm ? Motion.seg(t, 0, 0.3) : Motion.seg(t, 0, dimLength, Ease.power2Out)
    }

    /// 드러난 정도. 켜질 때 한 번 깜빡인다(서서히 밝아지지 않는다).
    static func lit(_ t: Double, calm: Bool) -> Double {
        if calm { return Motion.seg(t, 0, 0.3) }
        if t < land { return 0 }
        if t >= land + 0.06, t < land + 0.12 { return 0.25 }
        return 1
    }

    /// 물건 밝기(0 = 어둠과 같은 진하기, 1 = 제 색).
    static func itemLight(_ t: Double, calm: Bool) -> Double {
        lit(t, calm: calm)
    }

    /// 물건이 켜질 때 한 번 톡.
    static func itemScale(_ t: Double, calm: Bool) -> Double {
        calm ? 1 : 1 + 0.1 * RigMotion.bump(t, land + 0.02, 0.32)
    }

    /// 캡션: 불투명도, 아래에서 올라오는 거리(pt).
    static func caption(_ t: Double, calm: Bool) -> (opacity: Double, dy: Double) {
        if calm { return (Motion.seg(t, 0, 0.3), 0) }
        let k: Double = Motion.seg(t, captionIn, captionIn + 0.35, Ease.power3Out)
        return (k, 10 * (1 - k))
    }

    /// 반짝이(조명 반지름 단위 자리, 크기 pt). 안팎에 흩어 둔다.
    private static let sparkles: [(x: Double, y: Double, size: Double)] = [
        (0.62, -0.88, 24), (-0.82, -0.62, 14), (1.02, -0.35, 12),
        (-1.05, 0.22, 20), (0.98, 0.42, 16), (-0.2, -0.42, 18),
        (0.62, 0.86, 13), (-0.72, 0.9, 11), (1.18, 0.62, 15),
    ]

    /// 켜진 뒤 하나씩 톡 붙고, 천천히 반짝인다. 네 갈래 별을 흰 면으로 칠한다(번짐 없음).
    /// 처음엔 손그림 `+`(일부는 동그라미)였는데 과녁처럼 보여 바꿨다(빌드 227 대표님 "반짝이도 좀 구림").
    static func drawSparkles(in context: GraphicsContext, size: CGSize, t: Double, calm: Bool, centerY: Double = centerY) {
        let cx: Double = Double(size.width) / 2
        let cy: Double = Double(size.height) * centerY
        let radius: Double = Double(size.width) * spotRatio
        for (index, sparkle) in sparkles.enumerated() {
            let start: Double = land + 0.05 + Double(index) * 0.05
            let pop: Double = calm ? Motion.seg(t, 0, 0.3) : Motion.seg(t, start, start + 0.3) { Ease.backOut($0, overshoot: 2.4) }
            guard pop > 0 else { continue }
            let twinkle: Double = calm ? 1 : 0.82 + 0.18 * sin(2 * Double.pi * (t / 1.6 + Double(index) * 0.37))
            let scale: Double = pop * twinkle
            var mark = context
            mark.translateBy(x: cx + sparkle.x * radius, y: cy + sparkle.y * radius)
            mark.scaleBy(x: scale, y: scale)
            let half: Double = sparkle.size / 2
            let pinch: Double = half * 0.12
            var star = Path()
            star.move(to: CGPoint(x: 0, y: -half))
            star.addQuadCurve(to: CGPoint(x: half, y: 0), control: CGPoint(x: pinch, y: -pinch))
            star.addQuadCurve(to: CGPoint(x: 0, y: half), control: CGPoint(x: pinch, y: pinch))
            star.addQuadCurve(to: CGPoint(x: -half, y: 0), control: CGPoint(x: -pinch, y: pinch))
            star.addQuadCurve(to: CGPoint(x: 0, y: -half), control: CGPoint(x: -pinch, y: -pinch))
            star.closeSubpath()
            mark.fill(star, with: .color(.white))
        }
    }

    /// CI 스크린샷(Debug `-giftRevealAt <초>`)이면 그 시각에 멈춘다.
    static var frozenTime: Double? {
        #if DEBUG
        if UserDefaults.standard.object(forKey: "giftRevealAt") != nil {
            return UserDefaults.standard.double(forKey: "giftRevealAt")
        }
        #endif
        return nil
    }
}

/// 무대에 올리는 물건 그림과 이름. 마음·병뚜껑은 기호 + 하얀 윤곽으로 확정(대표님 2026-10-12, 따로 그리지 않는다).
struct GiftRevealItem {
    let name: String
    let asset: String?
    let symbol: String
    let tint: Color

    init?(gift: GiftEvent) {
        guard let side = gift.cupSide, let payload = gift.payload else { return nil }
        let tint: Color = side == .sugar ? .sugarPink : .caffeineAmber
        if gift.isHeart {
            self.init(name: String(localized: "\(side.characterName)의 마음"), asset: nil, symbol: "heart.fill", tint: tint)
        } else if gift.isCap {
            self.init(name: String(localized: "병뚜껑"), asset: nil, symbol: "seal.fill", tint: tint)
        } else if payload == GiftContent.item("strawberry") {
            self.init(name: String(localized: "딸기"), asset: "gift-item-strawberry", symbol: "", tint: tint)
        } else if payload == GiftContent.item("coffee-bean") {
            self.init(name: String(localized: "커피콩"), asset: "gift-item-coffee-bean", symbol: "", tint: tint)
        } else {
            return nil
        }
    }

    private init(name: String, asset: String?, symbol: String, tint: Color) {
        self.name = name
        self.asset = asset
        self.symbol = symbol
        self.tint = tint
    }
}

/// 진행 중인 선물 무대(오늘 화면이 들고 있는다).
struct GiftReveal: Identifiable {
    let id = UUID()
    let gift: GiftEvent
    let startedAt: Date
}

/// 어둠 + 조명 + 물건 + 반짝이 + 캡션. 화면 전체를 덮고, 아무 데나 누르면 닫힌다.
struct GiftRevealOverlay: View {
    let reveal: GiftReveal
    /// 두 번째 마음부터(무료) 결제 줄을 붙인다(`GiftMath.offersPro`).
    let offersPro: Bool
    let onClose: () -> Void
    let onPro: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 드러나기 전에 누르면 드러난 장면으로 건너뛴 만큼(초).
    @State private var skipped = 0.0
    @State private var didLand = false

    private var item: GiftRevealItem? { GiftRevealItem(gift: reveal.gift) }

    var body: some View {
        let frozen = GiftRevealTimeline.frozenTime
        TimelineView(.animation(minimumInterval: nil, paused: frozen != nil)) { timeline in
            let t: Double = frozen ?? timeline.date.timeIntervalSince(reveal.startedAt) + skipped
            GeometryReader { proxy in
                let size = proxy.size
                let itemY: CGFloat = size.height * CGFloat(GiftRevealTimeline.centerY)
                let spot: CGFloat = size.width * CGFloat(GiftRevealTimeline.spotRatio)
                let captionY: CGFloat = itemY + spot + 60
                ZStack {
                    Canvas { context, canvasSize in
                        drawLights(in: context, size: canvasSize, t: t)
                    }
                    itemView(width: Double(size.width) * 0.27, t: t, size: size)
                        .position(x: size.width / 2, y: itemY)
                    Canvas { context, canvasSize in
                        GiftRevealTimeline.drawSparkles(in: context, size: canvasSize, t: t, calm: reduceMotion)
                    }
                    // 이름은 그림 위(빌드 264 대표님 "이름 그림 위쪽에 쓰고 폰트 두꺼운 걸로").
                    nameView(t: t)
                        .frame(width: size.width - 48)
                        .position(x: size.width / 2, y: itemY - spot - 52)
                    captionView(t: t)
                        .frame(width: size.width - 48)
                        .position(x: size.width / 2, y: captionY)
                }
                .contentShape(Rectangle())
                .onTapGesture { tap(at: t) }
            }
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gift-card")
        .sensoryFeedback(.success, trigger: didLand) { _, new in new }
        .task {
            guard frozen == nil, !reduceMotion else { return }
            let wait: Double = GiftRevealTimeline.land - Date().timeIntervalSince(reveal.startedAt)
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            if !Task.isCancelled { didLand = true }
        }
    }

    private func tap(at t: Double) {
        if !reduceMotion, t < GiftRevealTimeline.land {
            skipped += GiftRevealTimeline.land - t
            didLand = true
        } else {
            onClose()
        }
    }

    @ViewBuilder
    private func itemView(width: Double, t: Double, size: CGSize) -> some View {
        let light: Double = GiftRevealTimeline.itemLight(t, calm: reduceMotion)
        let dark: Double = GiftRevealTimeline.dim * GiftRevealTimeline.darkness(t, calm: reduceMotion) * (1 - light)
        Group {
            if let item, let asset = item.asset {
                Image(asset)
                    .resizable()
                    .scaledToFit()
            } else if let item {
                symbolView(item, width: width)
            }
        }
        .frame(width: width, height: width)
        .colorMultiply(Color(white: 1 - dark))
        .scaleEffect(GiftRevealTimeline.itemScale(t, calm: reduceMotion))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 마음·병뚜껑: 기호 + 하얀 윤곽(대표님 2026-10-12 "하얀 윤곽 붙여서 그냥 쓰자").
    /// 윤곽은 흰 기호를 둘레 16방향으로 조금씩 밀어 겹친 것이다. 흐림 없이 가장자리가 또렷하다(에어브러시 금지 규칙).
    private func symbolView(_ item: GiftRevealItem, width: Double) -> some View {
        let outline: Double = width * 0.035
        let symbol = Image(systemName: item.symbol).resizable().scaledToFit()
        return ZStack {
            ForEach(0 ..< 16, id: \.self) { step in
                let angle: Double = Double(step) / 16 * 2 * Double.pi
                symbol
                    .foregroundStyle(.white)
                    .offset(x: outline * cos(angle), y: outline * sin(angle))
            }
            symbol.foregroundStyle(item.tint)
        }
        .padding(width * 0.1)
    }

    private func nameView(t: Double) -> some View {
        let caption = GiftRevealTimeline.caption(t, calm: reduceMotion)
        // 선물 꼬리표: 흰 바탕 + 검정 굵은 글씨 + 왼쪽 끈 구멍(빌드 264 대표님 시안 1). 따옴표는 뺐다.
        return Button(action: onClose) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color.ink.opacity(0.7))
                    .frame(width: 8, height: 8)
                Text(item?.name ?? "")
                    .font(AppFont.pretendard(20, .extraBold, relativeTo: .title3))
                    .foregroundStyle(Color.ink)
            }
            .padding(.leading, 12)
            .padding(.trailing, 18)
            .padding(.vertical, 10)
            .background(.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item?.name ?? "")
        .accessibilityHint("눌러서 닫기")
        .accessibilityIdentifier("gift-confirm")
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .opacity(caption.opacity)
        .offset(y: caption.dy)
        .allowsHitTesting(caption.opacity > 0.5)
    }

    @ViewBuilder
    private func captionView(t: Double) -> some View {
        let caption = GiftRevealTimeline.caption(t, calm: reduceMotion)
        VStack(spacing: 14) {
            // 결제 줄: 밑줄 글자 대신 잠긴 선물(딸기·병뚜껑·앞으로 올 것) + 글자 ›(빌드 264 대표님, 시안 B).
            if offersPro, reveal.gift.isHeart {
                Button(action: onPro) {
                    VStack(spacing: 14) {
                        HStack(spacing: 14) {
                            lockedGift { Color.white.mask(Image("gift-item-strawberry").resizable().scaledToFit()) }
                            lockedGift { Image(systemName: "seal.fill").resizable().scaledToFit().foregroundStyle(.white) }
                            lockedGift {
                                Image(systemName: "questionmark").resizable().scaledToFit().fontWeight(.bold)
                                    .foregroundStyle(.white).padding(3)
                            }
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("이제 마음 말고 슬슬 다른 것도 받고 싶으시다고요?")
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .opacity(0.75)
                        }
                        .font(AppFont.pretendard(14, .semibold, relativeTo: .subheadline))
                        .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("이제 마음 말고 슬슬 다른 것도 받고 싶으시다고요?")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("gift-pro")
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .opacity(caption.opacity)
        .offset(y: caption.dy)
        .allowsHitTesting(caption.opacity > 0.5)
    }

    /// Pro에서 받을 수 있는 선물 하나. 흐린 흰 실루엣 + 오른쪽 아래 자물쇠.
    private func lockedGift<Art: View>(@ViewBuilder _ art: () -> Art) -> some View {
        art()
            .opacity(0.55)
            .frame(width: 24, height: 24)
            .frame(width: 52, height: 52)
            .background(Color.white.opacity(0.12), in: Circle())
            .overlay(Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.ink)
                    .frame(width: 20, height: 20)
                    .background(.white, in: Circle())
                    .offset(x: 2, y: 2)
            }
    }

    private func drawLights(in context: GraphicsContext, size: CGSize, t: Double) {
        GiftRevealTimeline.drawLights(in: context, size: size, t: t, calm: reduceMotion)
    }
}

extension GiftRevealTimeline {
    /// 어둠은 한 장을 깔고 조명 자리를 도려낸다. 조명 원은 흰빛을 얹어 레퍼런스처럼 하얗게 바랜다.
    /// 거래 무대(`TradeOfferOverlay`)는 아래 버튼 자리 때문에 조명을 조금 올려 쓴다(`centerY`).
    static func drawLights(in context: GraphicsContext, size: CGSize, t: Double, calm: Bool, centerY: Double = centerY) {
        let dark: Double = GiftRevealTimeline.darkness(t, calm: calm)
        guard dark > 0 else { return }
        let lit: Double = GiftRevealTimeline.lit(t, calm: calm)
        let center = CGPoint(x: Double(size.width) / 2, y: Double(size.height) * centerY)
        let finalRadius: Double = Double(size.width) * GiftRevealTimeline.spotRatio
        let finalSpot = Path(ellipseIn: CGRect(
            x: Double(center.x) - finalRadius, y: Double(center.y) - finalRadius,
            width: finalRadius * 2, height: finalRadius * 2
        ))
        context.drawLayer { layer in
            layer.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(GiftRevealTimeline.dim * dark)))
            guard lit > 0 else { return }
            layer.blendMode = .destinationOut
            layer.fill(finalSpot, with: .color(.black.opacity(lit)))
        }
        guard lit > 0 else { return }
        context.fill(finalSpot, with: .color(.white.opacity(0.62 * lit)))
    }
}
