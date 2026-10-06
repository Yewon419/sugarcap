import OSLog
import SwiftData
import SwiftUI

// 기록 시트·브랜드 메뉴·하루 기록 시트가 같이 쓰는 조각(2026-09-26 HTML 프로토타입 확정 모양).
// 글자 위계: 이름 16 semibold → 12 보조 메타 / 오른쪽에 당 22 bold 숫자 + 카페인 12. 액센트는 주 동작 하나.

extension EnvironmentValues {
    /// 기록을 연 컵. 기록 시트·브랜드 메뉴·메뉴 패널이 어느 면을 크게 보일지 고른다(`CupSide.shown`).
    @Entry var recordCup: CupSide?
    /// 설정 "기록할 것"에서 켠 면(`AppSettings.trackedSides`). 루트가 넣는다.
    @Entry var trackedSides: [CupSide] = CupSide.allCases
}

extension CupSide {
    /// 기록 화면에서 크게 보일 면. 한 면만 켰으면 늘 그 면.
    /// 카페인 컵에서 열면 늘 카페인(대표님 2026-10-06, 빌드 105 베타 피드백).
    /// 당 컵이나 컵 밖(하루 기록)에서는 음료의 대표 면이라 카페인 음료는 그대로 카페인이 크다.
    static func shown(in cup: CupSide?, primary: CupSide, tracked: [CupSide]) -> CupSide {
        if tracked.count == 1, let only = tracked.first { return only }
        return cup == .caffeine ? .caffeine : primary
    }
}

/// 음료 한 줄. 왼쪽 장식(별표·지우기) → 이름·메타 → 수치 → 오른쪽 장식(+).
struct DrinkLine<Leading: View, Trailing: View>: View {
    let title: String
    let meta: String
    /// 오른쪽 수치. 즐겨찾기 줄처럼 수치를 메타에 넣는 곳은 nil.
    let figure: DrinkFigure?
    /// 왼쪽 동그란 액체 썸네일(SPEC §9.7). 직접 입력 기록처럼 카탈로그 음료가 아니면 기본색.
    var liquid: Color?
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: 12) {
            leading
            if let liquid {
                LiquidBadge(color: liquid, size: typeSize.isAccessibilitySize ? 56 : 44)
            }
            // 큰 글자에서는 수치를 이름 옆에 두면 둘 다 부서진다. 이름 아래로 내린다.
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
            layout {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(AppFont.pretendard(16, .semibold, relativeTo: .callout))
                        .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                    Text(meta)
                        .font(AppFont.pretendard(12, .regular, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let figure {
                    figure.aligned(typeSize.isAccessibilitySize ? .leading : .trailing)
                }
            }
            trailing
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Divider().padding(.leading, 24) }
    }
}

extension DrinkLine where Leading == EmptyView, Trailing == EmptyView {
    init(title: String, meta: String, figure: DrinkFigure?, liquid: Color? = nil) {
        self.init(title: title, meta: meta, figure: figure, liquid: liquid, leading: { EmptyView() }, trailing: { EmptyView() })
    }
}

/// 음료의 대표 면(`CupSide.primary`)은 크게, 다른 면은 작게. 카페라떼는 카페인이, 딸기라떼는 당이 크다.
/// 카페인 컵에서 연 기록이거나 한 면만 켰으면 그 면이 크다(`CupSide.shown`). nil은 "미공개"(0으로 적지 않는다, SPEC §9.2).
struct DrinkFigure: View {
    let name: String
    let sugarG: Double?
    let caffeineMg: Double?
    var alignment: HorizontalAlignment = .trailing

    @Environment(\.recordCup) private var recordCup
    @Environment(\.trackedSides) private var trackedSides

    func aligned(_ value: HorizontalAlignment) -> DrinkFigure {
        DrinkFigure(name: name, sugarG: sugarG, caffeineMg: caffeineMg, alignment: value)
    }

    private func amount(_ side: CupSide) -> Double? {
        switch side {
        case .sugar: return sugarG
        case .caffeine: return caffeineMg
        }
    }

    var body: some View {
        let primary = CupSide.shown(
            in: recordCup, primary: CupSide.primary(name: name, sugarG: sugarG, caffeineMg: caffeineMg), tracked: trackedSides
        )
        VStack(alignment: alignment, spacing: 2) {
            if let value = amount(primary) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(Amount.number(value))
                        .font(AppFont.pretendard(22, .bold, relativeTo: .title2))
                        .tracking(-0.6)
                    Text(primary.unit)
                        .font(AppFont.pretendard(13, .medium, relativeTo: .footnote))
                }
                .monospacedDigit()
            } else {
                Text("미공개")
                    .font(AppFont.pretendard(13, .regular, relativeTo: .footnote))
                    .foregroundStyle(.secondary)
            }
            // 끈 면(설정 "기록할 것")은 작은 줄도 숨긴다.
            if trackedSides.contains(primary.other) {
                Text("\(primary.other.label) \(Amount.text(amount(primary.other), unit: primary.other.unit))")
                    .font(AppFont.pretendard(12, .regular, relativeTo: .caption))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize()
    }
}

/// 즐겨찾기 별표. 켜지면 액센트.
struct StarButton: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isOn ? "star.fill" : "star")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.secondary.opacity(0.6)))
                .tapTarget()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOn ? "즐겨찾기 해제" : "즐겨찾기")
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: isOn)
    }
}

/// 시트 머리글: 왼쪽 소제목, 오른쪽 글자 버튼들(편집·닫기).
struct SheetHeader<Actions: View>: View {
    let title: String
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack {
            Text(title)
                .kicker()
                .padding(.leading, 4)
            Spacer()
            HStack(spacing: 14) { actions }
                .font(AppFont.pretendard(15, .regular, relativeTo: .subheadline))
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 4)
    }
}

/// 소제목 줄(섹션 사이 간격 포함).
struct SectionKicker: View {
    let title: String
    var topPadding: CGFloat = 30

    var body: some View {
        Text(title)
            .kicker()
            .padding(.horizontal, 24)
            .padding(.top, topPadding)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 안내 캡션(빈 상태·주의). 13pt 보조색.
struct CaptionNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(AppFont.pretendard(13, .regular, relativeTo: .footnote))
            .lineSpacing(3)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 즐겨찾기 저장. 실패하면 되돌리고 알린다(조용히 삼키지 않는다).
enum Favorites {
    private static let logger = Logger(subsystem: "com.sugarcap.app", category: "favorites")

    static func toggle(_ selection: ServingSelection, favorites: [FavoriteDrink], in context: ModelContext) throws {
        let key = selection.drinkKey
        if let existing = favorites.first(where: { $0.key == key }) {
            context.delete(existing)
        } else {
            context.insert(FavoriteDrink(servingID: selection.serving.id, variantLabel: selection.variant?.label, addedAt: Date()))
        }
        do {
            try context.save()
        } catch {
            logger.error("즐겨찾기 저장 실패(\(key, privacy: .public)): \(String(describing: error), privacy: .public)")
            context.rollback()
            throw error
        }
    }
}
