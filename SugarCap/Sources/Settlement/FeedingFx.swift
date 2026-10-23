import SwiftUI

/// 먹이기 전환(2026-10-23 대표님 "조잡하고 유치하고 긺"으로 다시 만듦). 밤하늘 단색 면이 빠르게 덮었다가 걷히는 짧은 페이드 하나로
/// 통일했다. 달·별·제목 카드·카인 팝업·링·별 폭발은 뺐다. 덮을 때보다 걷힐 때를 길게 둬서 새 화면이 부드럽게 드러난다.
enum FeedFx: Equatable {
    /// 마감 진입: 오늘 화면 → 밤 장면.
    case dusk
    /// 로슈 → 카인.
    case turn
    /// 마무리: 카페인 → 요약.
    case night

    var duration: Double {
        switch self {
        case .dusk: return 0.38
        case .turn: return 0.34
        case .night: return 0.4
        }
    }

    /// 화면이 다 덮여 밑 화면을 바꿔도 되는 시각.
    var swapAt: Double {
        switch self {
        case .dusk: return 0.14
        case .turn: return 0.12
        case .night: return 0.14
        }
    }

    /// 바꾼 화면이 한 번 그려질 틈을 두고 걷기 시작한다.
    static let hold: Double = 0.04
}

struct FeedFxOverlay: View {
    let fx: FeedFx
    let t: Double

    var body: some View {
        let cover: Double = Motion.seg(t, 0, fx.swapAt, Ease.power2Out)
        let reveal: Double = Motion.seg(t, fx.swapAt + FeedFx.hold, fx.duration, Ease.power3Out)
        Color.nightSky
            .opacity(cover * (1 - reveal))
            .ignoresSafeArea()
            .allowsHitTesting(true)
            .accessibilityHidden(true)
    }
}
