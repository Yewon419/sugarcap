import SwiftUI
import UIKit

/// 대기 영상(`CupIdleOverlay`)이 없는 잔의 대기 모션: 잔 겉에 물방울이 서서히 맺힌다(대표님 2026-11-03 "망고스무디·초코프라페는
/// 안 움직이니 겉에 물방울 맺히는 걸로", "물방울 없는 사진에 있는 사진을 얹어놓고 서서히 보이게", 12초).
/// 물방울 층(`condense-<세트>-<단계>`)은 단계 사진에 물방울만 더한 편집본을 원본에 맞춘 것이다(`design/assets/cups/make_condense.py`).
/// 층이 없는 단계는 아무것도 그리지 않는다. 한 번 맺히면 그대로 두고, 화면이 다시 뜰 때 처음부터 맺힌다.
struct CupCondensation: View {
    let setID: String
    let step: Int
    /// 넘기는 중·화면 밖이면 맺히기 시작하지 않는다. 처음 보이는 면이 됐을 때 시작한다.
    let isActive: Bool

    static let fadeDuration: Double = 12
    static let fadeDelay: Double = 0.8

    @State private var shown = false

    private var assetName: String {
        "condense-\(setID)-\(step)"
    }

    var body: some View {
        if UIImage(named: assetName) != nil {
            Image(assetName)
                .resizable()
                .opacity(shown || Self.isScreenshot ? 1 : 0)
                .allowsHitTesting(false)
                .onChange(of: isActive, initial: true) { _, active in
                    guard active, !shown else { return }
                    withAnimation(.easeInOut(duration: Self.fadeDuration).delay(Self.fadeDelay)) { shown = true }
                }
        }
    }

    /// CI 스크린샷(Debug `-idleAt`)은 다 맺힌 상태로 찍는다.
    private static var isScreenshot: Bool {
        #if DEBUG
        return UserDefaults.standard.object(forKey: "idleAt") != nil
        #else
        return false
        #endif
    }
}
