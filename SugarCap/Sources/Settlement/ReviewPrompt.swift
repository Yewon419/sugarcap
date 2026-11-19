import StoreKit
import SwiftUI

/// 별점 요청(대표님 2026-11-19). 하루 마감 7칸(얼리버드 잔을 받는 칸)까지 찍은 뒤 스탬프판을 닫을 때 한 번만 묻는다.
/// 창을 실제로 띄울지는 시스템이 정한다(1년 3회 제한). Debug(CI)는 시스템 창이 스크린샷을 덮어서 부르지 않는다.
enum ReviewPrompt {
    /// 한 번 물었는지(UserDefaults Bool).
    static let askedKey = "reviewPromptAsked"

    static func isDue(stampedCells: Int, asked: Bool) -> Bool {
        !asked && stampedCells >= StampMath.earlyBirdCell
    }
}

extension View {
    /// `trigger`가 true가 되면 스탬프판이 닫히는 전환(0.25초)이 끝난 뒤 별점 창을 부른다.
    /// StoreKit을 이 파일에만 둔다. `TodayView`가 쓰는 SwiftUI `Transaction`과 이름이 겹친다.
    func requestsReview(when trigger: Bool) -> some View {
        modifier(ReviewRequester(trigger: trigger))
    }
}

private struct ReviewRequester: ViewModifier {
    let trigger: Bool
    @Environment(\.requestReview) private var requestReview

    func body(content: Content) -> some View {
        content.task(id: trigger) {
            guard trigger else { return }
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }
            requestReview()
        }
    }
}
