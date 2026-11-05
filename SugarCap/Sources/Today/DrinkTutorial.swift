import SwiftUI

/// 첫 기록 안내(대표님 2026-11-05, SPEC §4.1). 온보딩을 마친 첫 오늘 화면에서 한 번, 설정 사용설명서 「음료 기록법」에서 다시.
/// 컵 넘겨 보이기 → 컵 누르기 → 브랜드 → 맨 위 음료 → 추가 → 줄어든 컵 → 큰 숫자 → 편집 → 지우기 → 닫기.
/// 연습 음료는 저장하지 않는다(통계·이용 기록·위젯에 안 들어간다). 브랜드도 연습용 하나뿐이라 실제 카페가 나오지 않는다.
enum DrinkTutorial {
    enum Step: Equatable {
        /// 당 → 카페인 → 당으로 저절로 넘겨 컵이 둘인 걸 보여 준다. 카페인을 끈 사용자는 건너뛴다.
        case slide
        case cup
        /// 기록 시트(브랜드) → 브랜드 메뉴(맨 위 음료) → 패널(추가). 어느 화면이 떠 있는지로 구멍 자리가 갈린다.
        case record
        /// 추가한 만큼 줄어든 컵을 잠깐 보여 준다.
        case drop
        case number
        /// 하루 기록 시트: 편집 → 지우기.
        case log
        case close
    }

    /// 온보딩을 마치면 켠다. 안내를 끝까지 보면 끈다(중간에 앱을 닫으면 다음에 처음부터 다시).
    /// 설정 "앱 소개 다시 보기"는 온보딩만 다시 보여 주고 이 값을 건드리지 않는다.
    static let pendingKey = "drinkTutorialPending"

    static let brandID = "sugarcap-tutorial"

    /// 연습용 카탈로그: 브랜드 하나, 음료 하나(당 20 g, 카페인 0 mg).
    static var catalog: CatalogIndex {
        let brand = Brand(
            id: brandID, name: String(localized: "슈가캡 카페"), servingNote: String(localized: "연습용 메뉴"), hasSizeChoice: false
        )
        let serving = Serving(
            id: "\(brandID):strawberry-latte:iced:regular", sizeLabel: "기본", volumeMl: nil, sugarG: 20, caffeineMg: 0,
            caffeineVariants: [], caffeineRange: nil, estimated: nil
        )
        let drink = Drink(
            id: "\(brandID):strawberry-latte:iced", brandId: brandID, name: String(localized: "딸기 라떼"), nameEn: nil,
            category: String(localized: "라떼"), temperature: .iced, liquidColor: "#F2A9BB", servings: [serving]
        )
        return CatalogIndex(catalog: Catalog(schemaVersion: CatalogStore.supportedSchemaVersion, builtAt: "", brands: [brand], drinks: [drink]))
    }
}

extension EnvironmentValues {
    /// 진행 중인 첫 기록 안내 단계. 기록 시트·브랜드 메뉴·패널·하루 기록 시트가 제 화면 위에 덮개를 띄운다.
    @Entry var drinkTutorial: DrinkTutorial.Step?
}

/// 안내 한 단계의 덮개. `hole`(화면 좌표)만 밝게 두고 나머지는 어둡게 막는다. 구멍을 누르면 `onTap`.
/// 구멍 위가 아니라 덮개가 누르기를 받는다(아래 버튼에 맡기면 캐릭터·끌기가 먼저 가로챈다). `onTap`이 없으면 보여 주기만 한다.
struct CoachMark: View {
    let hole: CGRect
    var radius: CGFloat = 18
    let text: String
    let onTap: (() -> Void)?

    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            let local = hole.offsetBy(dx: -origin.x, dy: -origin.y)
            // 구멍이 위쪽이면 글은 아래, 아래쪽이면 위.
            let textBelow = local.midY < proxy.size.height * 0.5
            ZStack(alignment: .topLeading) {
                CoachDim(holes: hole == .zero ? [] : [CoachDim.Hole(rect: local, radius: radius)])
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {}
                    .accessibilityHidden(true)
                if hole != .zero {
                    if let onTap {
                        Button(action: onTap) {
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .fill(Color.white.opacity(0.001))
                        }
                        .buttonStyle(.plain)
                        .frame(width: local.width, height: local.height)
                        .position(x: local.midX, y: local.midY)
                        .accessibilityLabel(text)
                        .accessibilityIdentifier("coach-target")
                    }
                    Text(text)
                        .font(AppFont.pretendard(18, .semibold, relativeTo: .headline))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: max(proxy.size.width - 48, 0))
                        .position(x: proxy.size.width / 2, y: textBelow ? local.maxY + 40 : local.minY - 40)
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("coach-text")
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .transition(.opacity)
    }
}
