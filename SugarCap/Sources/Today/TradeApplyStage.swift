import SwiftUI

/// 바꾼 잔을 적용하는 중(오늘 화면이 들고 있는다).
struct TradeApply: Identifiable {
    let id = UUID()
    let item: TradeItem
    let startedAt: Date
}

/// 교환 적용 연출(대표님 2026-11-06 "교환으로 적용되는 특별한 애니메이션"). 거래 무대가 닫히면 그 잔의 방울이 위에서
/// 잔 속으로 떨어지고, 닿는 순간 또렷한 동심원 두 겹이 퍼지며 잔이 새 세트로 바뀌고 폭죽이 터진다.
/// 에어브러시 없이 단색 면·선만. 동작 줄이기면 연출 없이 잔만 바꾼다(`TodayView.acceptTrade`).
enum TradeApplyTimeline {
    /// 거래 무대가 사라지는 동안 기다린다.
    static let fallStart = 0.3
    /// 방울이 수면에 닿는 시각. 이때 잔이 바뀐다.
    static let contact = 0.85
    static let ringLength = 0.55
    static let ringGap = 0.12
    static let duration = 2.4
    /// 떨어지는 자리(사진 비율). 잔 가운데, 수면쯤.
    static let landX = 0.5
    static let landY = 0.45
    static let dropSide: CGFloat = 72

    /// CI 스크린샷 전용(Debug `-tradeApplyAt 초`). 그 시각에 멈춘다.
    static var frozenTime: Double? {
        #if DEBUG
        if UserDefaults.standard.object(forKey: "tradeApplyAt") != nil {
            return UserDefaults.standard.double(forKey: "tradeApplyAt")
        }
        #endif
        return nil
    }

    /// 오늘 화면 사진 칸과 같은 셈(`CupView`: 높이 84%, 바닥에서 4% 올림)으로 잡은 착지점(화면 좌표).
    static func landing(in size: CGSize) -> CGPoint {
        let slot = CGSize(width: size.width, height: size.height * CupView.heightRatio)
        let photo = IdlePhoto(slot: slot)
        let top: Double = Double(size.height) * (1 - Double(CupView.liftRatio)) - Double(slot.height) + photo.top
        return CGPoint(x: photo.left + landX * photo.width, y: top + landY * photo.height)
    }

    /// 떨어지는 진행(0~1). 가속하며 떨어진다.
    static func fall(_ t: Double) -> Double {
        let p: Double = min(max((t - fallStart) / (contact - fallStart), 0), 1)
        return p * p
    }

    /// 동심원 한 겹의 진행(0~1). 시작 전·끝난 뒤는 nil.
    static func ring(_ t: Double, index: Int) -> Double? {
        let start: Double = contact + Double(index) * ringGap
        let p: Double = (t - start) / ringLength
        return p >= 0 && p <= 1 ? p : nil
    }
}

struct TradeApplyOverlay: View {
    let apply: TradeApply

    var body: some View {
        let frozen = TradeApplyTimeline.frozenTime
        TimelineView(.animation(minimumInterval: nil, paused: frozen != nil)) { timeline in
            let t: Double = frozen ?? timeline.date.timeIntervalSince(apply.startedAt)
            GeometryReader { proxy in
                let land = TradeApplyTimeline.landing(in: proxy.size)
                ZStack {
                    ForEach(0 ..< 2, id: \.self) { index in
                        if let p = TradeApplyTimeline.ring(t, index: index) {
                            ringView(p: p, width: Double(proxy.size.width))
                                .position(land)
                        }
                    }
                    if t < TradeApplyTimeline.contact {
                        dropView(t: t, land: land)
                    }
                    if t >= TradeApplyTimeline.contact {
                        ConfettiBurst(size: .big)
                            .position(land)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func dropView(t: Double, land: CGPoint) -> some View {
        let side = TradeApplyTimeline.dropSide
        let startY: Double = -Double(side)
        let fall: Double = TradeApplyTimeline.fall(t)
        let y: Double = startY + (Double(land.y) - startY) * fall
        // 빨라질수록 세로로 조금 늘어난다.
        let stretch: Double = 1 + 0.18 * fall
        return Image(apply.item.dropAsset)
            .resizable()
            .scaledToFit()
            .frame(width: side, height: side)
            .scaleEffect(x: 1 / stretch, y: stretch, anchor: .bottom)
            .position(x: land.x, y: y - Double(side) / 2)
    }

    /// 수면에 퍼지는 원. 잔 입구처럼 납작한 타원으로, 퍼질수록 선이 가늘어지고 끝에서 사라진다.
    private func ringView(p: Double, width: Double) -> some View {
        let eased: Double = 1 - (1 - p) * (1 - p)
        let w: Double = 16 + (width * 0.5 - 16) * eased
        let line: Double = 5 - 3.5 * p
        let fade: Double = p < 0.6 ? 1 : 1 - (p - 0.6) / 0.4
        return Ellipse()
            .stroke(Color.accentColor, lineWidth: line)
            .frame(width: w, height: w * 0.3)
            .opacity(fade)
    }
}
