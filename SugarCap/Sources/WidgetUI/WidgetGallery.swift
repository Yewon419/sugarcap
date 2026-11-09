#if DEBUG
import SwiftUI

/// CI 스크린샷용 위젯 모음(Debug `-screenshotWidget small|medium|large|large-more`). 홈 화면 위젯은 시뮬레이터에서 찍을 수 없어
/// 위젯과 같은 그림(`WidgetSmallFace`·`WidgetMediumFace`)을 6.1인치 위젯 크기로 늘어놓는다.
/// 잔은 지금 고른 잔(`-cupSet.sugar mango` 등), 값은 시안 v7과 같다.
struct WidgetGallery: View {
    let mode: String

    private static let smallSize = CGSize(width: 158, height: 158)
    private static let mediumSize = CGSize(width: 338, height: 158)
    private static let largeSize = CGSize(width: 338, height: 354)
    private static let values: [CupSide: [Int: Double]] = [
        .sugar: [0: 0, 30: 12, 50: 20, 80: 38, 100: 50],
        .caffeine: [0: 0, 30: 80, 50: 200, 80: 310, 100: 400],
    ]

    var body: some View {
        VStack(spacing: 16) {
            if mode == "large" {
                // 두 잔 단계 차이가 가장 큰 조합 + 시안 기본 선반, 카탈로그에서 이름이 가장 긴 축(줄바꿈 확인).
                large([.sugar: 100, .caffeine: 30], shelf: Self.shelf)
                large([.sugar: 80, .caffeine: 80], shelf: Self.longNames)
            } else if mode == "large-more" {
                // 기록 없음(빈 선반), 한 면만 켠 사용자.
                large([.sugar: 50, .caffeine: 50], shelf: [])
                large([.sugar: 30], shelf: Array(Self.shelf.prefix(3)))
            } else if mode == "medium" {
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

    private func large(_ steps: [CupSide: Int], shelf: [ShelfDrink]) -> some View {
        let cups = CupSide.allCases.compactMap { side in steps[side].map { cup(side, step: $0) } }
        return WidgetLargeFace(cups: cups, shelf: shelf)
            .frame(width: Self.largeSize.width, height: Self.largeSize.height)
            .background(WidgetLargeFace.floor)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private static func drink(_ name: String, _ hex: String) -> ShelfDrink {
        ShelfDrink(
            key: name, servingID: name, variantLabel: nil, name: name, brandName: "", sizeLabel: "",
            sugarG: nil, caffeineMg: nil, estimated: false, liquidHex: hex
        )
    }

    /// 시안 A와 같은 스타벅스 음료.
    private static let shelf = [
        drink("아이스 카페 아메리카노", "#4A2C1D"), drink("자몽 허니 블랙 티", "#F06B5B"),
        drink("바닐라 크림 콜드 브루", "#4A2C1D"), drink("아이스 바닐라 라떼", "#C49A6C"),
    ]

    private static let longNames = [
        drink("빅포즈 디카페인 제로슈가 제로칼로리 아이스티", "#DCE8EE"), drink("나 혼자만 드랍 UP! 은랑 큐브 레몬에이드", "#F3D34A"),
        drink("레몬차", "#F3D34A"), drink("ARIH 포스트바이오틱에너지 드링크 트로피칼웨이브", "#E3C93C"),
    ]

    private func medium(_ steps: [CupSide: Int]) -> some View {
        let cups = CupSide.allCases.compactMap { side in steps[side].map { cup(side, step: $0) } }
        return WidgetMediumFace(cups: cups)
            .frame(width: Self.mediumSize.width, height: Self.mediumSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
#endif
