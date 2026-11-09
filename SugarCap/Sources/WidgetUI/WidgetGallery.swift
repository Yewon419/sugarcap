#if DEBUG
import SwiftUI

/// CI 스크린샷용 위젯 모음(Debug `-screenshotWidget small|medium`). 홈 화면 위젯은 시뮬레이터에서 찍을 수 없어
/// 위젯과 같은 그림(`WidgetSmallFace`·`WidgetMediumFace`)을 6.1인치 위젯 크기로 늘어놓는다.
/// 잔은 지금 고른 잔(`-cupSet.sugar mango` 등), 값은 시안 v7과 같다.
struct WidgetGallery: View {
    let mode: String

    private static let smallSize = CGSize(width: 158, height: 158)
    private static let mediumSize = CGSize(width: 338, height: 158)
    private static let values: [CupSide: [Int: Double]] = [
        .sugar: [0: 0, 30: 12, 50: 20, 80: 38, 100: 50],
        .caffeine: [0: 0, 30: 80, 50: 200, 80: 310, 100: 400],
    ]

    var body: some View {
        VStack(spacing: 16) {
            if mode == "medium" {
                // 두 잔 단계 차이가 가장 큰 조합: 입구 높이·숫자 외곽선 확인(2026-11-09).
                medium([.sugar: 100, .caffeine: 30])
                medium([.sugar: 0, .caffeine: 30])
                medium([.sugar: 80])
                HStack(spacing: 16) {
                    small(.sugar, step: 0)
                    small(.caffeine, step: 0)
                }
            } else {
                ForEach([30, 50, 80, 100], id: \.self) { step in
                    HStack(spacing: 16) {
                        small(.sugar, step: step)
                        small(.caffeine, step: step)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0xE9 / 255, green: 0xE9 / 255, blue: 0xEC / 255))
    }

    private func cup(_ side: CupSide, step: Int) -> WidgetCupModel {
        let limit = side.limit(.default)
        return WidgetCupModel(side: side, setID: side.cupSetID, remaining: Self.values[side]?[step] ?? limit, limit: limit)
    }

    private func small(_ side: CupSide, step: Int) -> some View {
        WidgetSmallFace(cup: cup(side, step: step))
            .frame(width: Self.smallSize.width, height: Self.smallSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func medium(_ steps: [CupSide: Int]) -> some View {
        let cups = CupSide.allCases.compactMap { side in steps[side].map { cup(side, step: $0) } }
        return WidgetMediumFace(cups: cups)
            .frame(width: Self.mediumSize.width, height: Self.mediumSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
#endif
