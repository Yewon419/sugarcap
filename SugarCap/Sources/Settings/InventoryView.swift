import SwiftData
import SwiftUI

/// 보관함(대표님 2026-10-24 "설정에 인벤토리, 뭐 모았는지 볼 수 있게"). 설정 맨 위 줄에서 연다.
/// 병뚜껑은 잔액(열어 본 병뚜껑 − 거래에 쓴 것, §4.10), 물건은 열어 본 선물만. 마음은 넣지 않는다(같은 날 대표님 "마음은 빼").
/// 물건 칸은 등록된 물건 수 + 물음표 칸 3개(아직 없는 물건 자리, 대표님 "몇 개 미리 물음표 깔아 한 세 개쯤").
/// "컵 스킨" 칸(§4.10, 2026-11-28 대표님 "잔" → "컵 스킨"): 면마다 기본 잔 + 거래로 산 잔. 누르면 그 면의 잔으로 바꾼다.
/// 2026-11-28 개선(대표님 "1~5 다"): 컵 스킨을 캐릭터별 줄로 나누고 쓰는 잔에 「사용 중」, 아직 없는 거래 상품은 실루엣 + 다음 가격,
/// 물음표 칸은 글자 없이, 머리 병뚜껑은 선물 무대와 같은 두 색 기호.
struct InventoryView: View {
    @Query private var gifts: [GiftEvent]
    @Query private var trades: [TradeOffer]
    /// 잔 선택은 기기 설정이라 바뀐 걸 다시 그리게 한다.
    @State private var cupChoice = 0

    static let hiddenSlots = 3

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                capHeader
                    .padding(.horizontal, 32)
                    .padding(.top, 8)
                sectionTitle("컵 스킨")
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(CupSide.allCases, id: \.self) { side in
                        VStack(alignment: .leading, spacing: 10) {
                            sideLabel(side)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                                ForEach(cupTiles(side), id: \.setID) { tile in
                                    cupTile(tile)
                                }
                                ForEach(lockedCups(side), id: \.id) { item in
                                    lockedCupTile(item)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .sensoryFeedback(.selection, trigger: cupChoice)
                sectionTitle("물건")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(GiftContent.items, id: \.id) { item in
                        if owned.contains(item.id), let info = Self.info(item.id) {
                            ownedTile(name: info.name, asset: info.asset, owner: item.owner)
                        } else {
                            hiddenTile
                        }
                    }
                    ForEach(0 ..< Self.hiddenSlots, id: \.self) { _ in hiddenTile }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 32)
        }
        // 설정 목록과 같은 벽 색.
        .background(Color.wall.ignoresSafeArea())
        .navigationTitle("보관함")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var capHeader: some View {
        HStack(alignment: .bottom, spacing: 12) {
            // 선물·거래 꼬리표와 같은 병뚜껑 기호. 두 캐릭터가 모아 주니 로슈 것 위에 카인 것을 겹친다.
            ZStack(alignment: .bottomTrailing) {
                capGlyph(.sugar, size: 40)
                    .padding(.trailing, 22)
                    .padding(.bottom, 14)
                capGlyph(.caffeine, size: 40)
            }
            .padding(.bottom, 8)
            Text("\(caps)")
                .font(.custom(CupHero.fontName, fixedSize: 84))
                .monospacedDigit()
            VStack(alignment: .leading, spacing: 2) {
                Text("병뚜껑")
                    .font(AppFont.pretendard(17, .bold, relativeTo: .headline))
                Text("지금 가진 것")
                    .font(AppFont.pretendard(13, .regular, relativeTo: .footnote))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 12)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("병뚜껑 \(caps)개"))
        .accessibilityIdentifier("inventory-caps")
    }

    private func ownedTile(name: String, asset: String, owner: CupSide) -> some View {
        VStack(spacing: 8) {
            Image(asset)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 80, maxHeight: 80)
            Text(name)
                .font(AppFont.pretendard(13, .semibold, relativeTo: .footnote))
            HStack(spacing: 6) {
                Circle()
                    .fill(CupHero.color(owner))
                    .frame(width: 6, height: 6)
                Text(owner.characterName)
                    .font(AppFont.pretendard(11, .regular, relativeTo: .caption2))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: Self.tileHeight)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("inventory-item")
    }

    /// 아직 없는 물건 자리. 글자 없이 물음표만(대표님 2026-11-28 보관함 개선).
    private var hiddenTile: some View {
        Circle()
            .fill(Color(.tertiarySystemFill))
            .frame(width: 52, height: 52)
            .overlay {
                Text(verbatim: "?")
                    .font(AppFont.pretendardFixed(22, .bold))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, minHeight: Self.tileHeight)
            .background(Color(.quaternarySystemFill), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("아직 몰라요"))
    }

    /// 컵 스킨 줄 머리: 캐릭터 색 점 + 이름.
    private func sideLabel(_ side: CupSide) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(CupHero.color(side))
                .overlay { Circle().strokeBorder(Color.ink.opacity(0.25), lineWidth: 0.5) }
                .frame(width: 8, height: 8)
            Text(side.characterName)
                .font(AppFont.pretendard(15, .semibold, relativeTo: .subheadline))
                .foregroundStyle(Color.ink)
        }
        .padding(.leading, 16)
        .accessibilityAddTraits(.isHeader)
    }

    /// 선물 무대·도장 카드와 같은 병뚜껑 기호. 로슈(흰색)는 바깥에 옅은 먹색을 한 겹 두른다.
    private func capGlyph(_ side: CupSide, size: CGFloat) -> some View {
        ZStack {
            Image(systemName: "seal.fill")
                .font(.system(size: size + 3))
                .foregroundStyle(side == .sugar ? Color(white: 0.33) : Color.white)
            Image(systemName: "seal.fill")
                .font(.system(size: size))
                .foregroundStyle(side == .sugar ? Color.roshuWhite : Color.caffeineAmber)
        }
        .accessibilityHidden(true)
    }

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(AppFont.pretendard(13, .regular, relativeTo: .footnote))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 32)
            .padding(.top, 28)
            .padding(.bottom, 8)
            .accessibilityAddTraits(.isHeader)
    }

    private struct CupTile {
        let setID: String
        let name: String
        let side: CupSide
    }

    /// 그 면의 기본 잔, 그 뒤에 산 잔(상품 목록 순서), 얼리버드로 받은 유리 공예 잔.
    private func cupTiles(_ side: CupSide) -> [CupTile] {
        let owned = ownedSets
        return [CupTile(setID: side.defaultCupSetID, name: side.defaultCupSetName, side: side)]
            + (TradeCatalog.items + TradeCatalog.perks)
            .filter { $0.side == side && owned.contains($0.id) }
            .map { CupTile(setID: $0.id, name: $0.name, side: side) }
    }

    /// 아직 없는 거래 상품(대표님 2026-11-28 "교환할 수 있는 게 보이게"). 특전 잔은 거래로 안 오니 넣지 않는다.
    private func lockedCups(_ side: CupSide) -> [TradeItem] {
        let owned = ownedSets
        return TradeCatalog.items.filter { $0.side == side && !owned.contains($0.id) }
    }

    /// 다음 거래 가격(§4.10). 첫 거래 전이면 2, 그 뒤 5.
    private var nextPrice: Int {
        TradeMath.price(trades: trades.map(\.record))
    }

    private func cupTile(_ tile: CupTile) -> some View {
        let selected = tile.side.cupSetID == tile.setID
        return Button {
            CupSetChoice.select(tile.setID, for: tile.side)
            cupChoice += 1
        } label: {
            VStack(spacing: 8) {
                Image(CupLevel.cutoutName(setID: tile.setID, step: 80))
                    .resizable()
                    .scaledToFit()
                    .frame(height: Self.cupHeight)
                Text(tile.name)
                    .font(AppFont.pretendard(13, .semibold, relativeTo: .footnote))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .foregroundStyle(Color.ink)
                    .frame(minHeight: 34, alignment: .top)
                // 쓰는 잔 표시(대표님 2026-11-28). 안 쓰는 칸도 같은 높이를 비워 둬 사진 줄이 맞는다.
                Text("사용 중")
                    .font(AppFont.pretendard(11, .bold, relativeTo: .caption2))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .opacity(selected ? 1 : 0)
                    .accessibilityHidden(!selected)
            }
            .padding(.top, 16)
            .padding(.bottom, 12)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: Self.tileHeight)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("inventory-cup-\(tile.setID)")
    }

    /// 아직 없는 컵 스킨: 누끼 실루엣 + 다음 거래 가격. 누르는 동작은 없다(거래는 캐릭터가 들고 온다).
    private func lockedCupTile(_ item: TradeItem) -> some View {
        VStack(spacing: 8) {
            Image(CupLevel.cutoutName(setID: item.id, step: 80))
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .foregroundStyle(Color(.tertiaryLabel))
                .frame(height: Self.cupHeight)
            HStack(spacing: 4) {
                Image(systemName: "seal.fill")
                    .font(.system(size: 11))
                Text("병뚜껑 \(nextPrice)개")
                    .font(AppFont.pretendard(13, .semibold, relativeTo: .footnote))
            }
            .foregroundStyle(.secondary)
            .frame(minHeight: 34, alignment: .top)
        }
        .padding(.top, 16)
        .padding(.bottom, 12)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, minHeight: Self.tileHeight, alignment: .top)
        .background(Color(.quaternarySystemFill), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: item.name))
        .accessibilityValue(Text("병뚜껑 \(nextPrice)개"))
        .accessibilityIdentifier("inventory-locked-\(item.id)")
    }

    static let cupHeight: CGFloat = 96
    static let tileHeight: CGFloat = 176

    /// 병뚜껑 잔액(§4.10). Debug `-screenshotCaps <n>`이면 그 값(추이 탭과 같은 인자).
    private var caps: Int {
        CapBalance.current(gifts: gifts, trades: trades)
    }

    /// 산 잔. Debug에서 `-cupSet.<면>`으로 켠 잔도 가진 것으로 본다(스크린샷용).
    private var ownedSets: Set<String> {
        var owned = TradeMath.ownedSets(trades: trades.map(\.record)).union(GiftContent.wonSets(in: gifts))
        #if DEBUG
        for side in CupSide.allCases where side.cupSetID != side.defaultCupSetID {
            owned.insert(side.cupSetID)
        }
        #endif
        return owned
    }

    /// 열어 본 물건 id. Debug `-screenshotInventoryItems strawberry`(쉼표로 여럿)면 그 값.
    private var owned: Set<String> {
        #if DEBUG
        if let list = UserDefaults.standard.string(forKey: "screenshotInventoryItems") {
            return Set(list.split(separator: ",").map(String.init))
        }
        #endif
        return GiftContent.takenItems(in: gifts.filter(\.isOpened))
    }

    /// 물건 이름·그림. 물건이 늘면 `GiftRevealItem`과 같이 여기에도 넣는다.
    private static func info(_ id: String) -> (name: String, asset: String)? {
        switch id {
        case "strawberry": return (String(localized: "딸기"), "gift-item-strawberry")
        case "coffee-bean": return (String(localized: "커피콩"), "gift-item-coffee-bean")
        case "cinnamon-stick": return (String(localized: "시나몬 스틱"), "gift-item-cinnamon-stick")
        case "sugar-cube": return (String(localized: "각설탕"), "gift-item-sugar-cube")
        default: return nil
        }
    }
}
