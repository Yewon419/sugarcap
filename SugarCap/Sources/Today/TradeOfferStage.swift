import SwiftUI

/// 진행 중인 거래 무대(오늘 화면이 들고 있는다).
struct TradeStage: Identifiable {
    let id = UUID()
    let offer: TradeOffer
    let startedAt: Date
}

/// 거래 제안 무대(SPEC §4.10). 선물 조명 무대(`GiftRevealOverlay`)와 같은 어둠·조명·반짝이에 상품(그 세트 100% 누끼)과
/// 이름 꼬리표를 올리고, 아래에 "병뚜껑 N개랑 바꿀래?"와 버튼 둘("바꾸기" 강조색, "다음에" 유리 알약)을 둔다.
/// 배경을 눌러도 닫히지 않는다(드러나기 전에 누르면 드러난 장면으로 건너뛴다). 동작 줄이기면 어둠과 카드만 켰다 끈다.
/// 첫 거래(튜토리얼 라떼)는 "다음에" 없이 "바꾸기"만 둔다(대표님 2026-10-31).
struct TradeOfferOverlay: View {
    let stage: TradeStage
    let canRefuse: Bool
    let onAccept: () -> Void
    let onRefuse: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var skipped = 0.0

    /// 조명 자리(화면 비율). 선물 무대보다 올려 아래에 버튼 자리를 둔다.
    static let centerY = 0.46

    private var item: TradeItem? { TradeCatalog.item(stage.offer.itemID) }

    var body: some View {
        let frozen = GiftRevealTimeline.frozenTime
        TimelineView(.animation(minimumInterval: nil, paused: frozen != nil)) { timeline in
            let t: Double = frozen ?? timeline.date.timeIntervalSince(stage.startedAt) + skipped
            GeometryReader { proxy in
                let size = proxy.size
                let itemY: CGFloat = size.height * CGFloat(Self.centerY)
                let spot: CGFloat = size.width * CGFloat(GiftRevealTimeline.spotRatio)
                ZStack {
                    Canvas { context, canvasSize in
                        GiftRevealTimeline.drawLights(
                            in: context, size: canvasSize, t: t, calm: reduceMotion, centerY: Self.centerY
                        )
                    }
                    itemView(height: Double(spot) * 1.7, t: t)
                        .position(x: size.width / 2, y: itemY)
                    Canvas { context, canvasSize in
                        GiftRevealTimeline.drawSparkles(
                            in: context, size: canvasSize, t: t, calm: reduceMotion, centerY: Self.centerY
                        )
                    }
                    nameView(t: t)
                        .frame(width: size.width - 48)
                        .position(x: size.width / 2, y: itemY - spot - 40)
                    choiceView(t: t)
                        .frame(width: size.width - 48)
                        .position(x: size.width / 2, y: itemY + spot + 92)
                }
                .contentShape(Rectangle())
                .onTapGesture { skip(at: t) }
            }
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trade-card")
    }

    private func skip(at t: Double) {
        guard !reduceMotion, t < GiftRevealTimeline.land else { return }
        skipped += GiftRevealTimeline.land - t
    }

    private func itemView(height: Double, t: Double) -> some View {
        let light: Double = GiftRevealTimeline.itemLight(t, calm: reduceMotion)
        let dark: Double = GiftRevealTimeline.dim * GiftRevealTimeline.darkness(t, calm: reduceMotion) * (1 - light)
        return TradeItemArt(setID: stage.offer.itemID)
            .frame(width: height * TradeItemArt.aspect, height: height)
            .colorMultiply(Color(white: 1 - dark))
            .scaleEffect(GiftRevealTimeline.itemScale(t, calm: reduceMotion))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// 선물 무대와 같은 꼬리표(흰 바탕 + 굵은 글씨 + 끈 구멍). 누르는 동작은 없다.
    private func nameView(t: Double) -> some View {
        let caption = GiftRevealTimeline.caption(t, calm: reduceMotion)
        return HStack(spacing: 10) {
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
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .opacity(caption.opacity)
        .offset(y: caption.dy)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("trade-item")
    }

    private func choiceView(t: Double) -> some View {
        let caption = GiftRevealTimeline.caption(t, calm: reduceMotion)
        return VStack(spacing: 16) {
            Text("병뚜껑 \(stage.offer.price)개랑 바꿀래?")
                .font(AppFont.pretendard(17, .semibold, relativeTo: .headline))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("trade-question")
            HStack(spacing: 12) {
                if canRefuse {
                    Button(action: onRefuse) {
                        Text("다음에")
                            .font(AppFont.pretendard(17, .semibold, relativeTo: .headline))
                            .foregroundStyle(Color.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .glassPill()
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityIdentifier("trade-refuse")
                }
                Button(action: onAccept) {
                    Text("바꾸기")
                        .font(AppFont.pretendard(17, .semibold, relativeTo: .headline))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(Color.accentColor, in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.45), lineWidth: 1))
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityIdentifier("trade-accept")
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .opacity(caption.opacity)
        .offset(y: caption.dy)
        .allowsHitTesting(caption.opacity > 0.5)
    }
}

/// 잔 세트 100% 누끼에서 잔만 잘라 보인다. 프라페는 크림이 입구 위로 솟아 `CupCrop`(잔 영역)보다 위를 더 잡는다.
struct TradeItemArt: View {
    let setID: String

    private static let canvas = CGSize(width: 937, height: 1666)
    /// 세트들의 100% 누끼 알파 영역 합집합(프라페 y 215~1363, 라떼·아메리카노 y 433~1438) + 여유.
    private static let glass = CGRect(x: 186, y: 200, width: 564, height: 1250)
    static let aspect: Double = Double(glass.width / glass.height)

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / Self.glass.width, proxy.size.height / Self.glass.height)
            let x = (proxy.size.width - Self.glass.width * scale) / 2 - Self.glass.minX * scale
            let y = proxy.size.height - Self.glass.maxY * scale
            Image(CupLevel.cutoutName(setID: setID, step: 100))
                .resizable()
                .frame(width: Self.canvas.width * scale, height: Self.canvas.height * scale)
                .offset(x: x, y: y)
        }
        .clipped()
        .accessibilityHidden(true)
    }
}
