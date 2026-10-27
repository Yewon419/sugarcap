import SwiftData
import SwiftUI

/// 보관함(대표님 2026-10-24 "설정에 인벤토리, 뭐 모았는지 볼 수 있게"). 설정 맨 위 줄에서 연다.
/// 병뚜껑은 잔액(열어 본 병뚜껑 − 거래에 쓴 것, §4.10), 물건은 열어 본 선물만. 마음은 넣지 않는다(같은 날 대표님 "마음은 빼").
/// 물건 칸은 등록된 물건 수 + 물음표 칸 3개(아직 없는 물건 자리, 대표님 "몇 개 미리 물음표 깔아 한 세 개쯤").
/// "잔" 칸(§4.10): 면마다 기본 잔 + 거래로 산 잔. 누르면 그 면의 잔으로 바꾼다.
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
                sectionTitle("잔")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(cupTiles, id: \.setID) { tile in
                        cupTile(tile)
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
            Image(systemName: "seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.ink.opacity(0.75))
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
                .frame(maxWidth: 64, maxHeight: 64)
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
        .frame(maxWidth: .infinity, minHeight: 128)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("inventory-item")
    }

    private var hiddenTile: some View {
        VStack(spacing: 10) {
            Circle()
                .fill(Color(.tertiarySystemFill))
                .frame(width: 52, height: 52)
                .overlay {
                    Text(verbatim: "?")
                        .font(AppFont.pretendardFixed(22, .bold))
                        .foregroundStyle(.tertiary)
                }
            Text("아직 몰라요")
                .font(AppFont.pretendard(13, .semibold, relativeTo: .footnote))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 128)
        .background(Color(.quaternarySystemFill), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
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

    /// 면마다 기본 잔, 그 뒤에 산 잔(상품 목록 순서).
    private var cupTiles: [CupTile] {
        let owned = ownedSets
        return CupSide.allCases.flatMap { side in
            [CupTile(setID: side.defaultCupSetID, name: side.defaultCupSetName, side: side)]
                + TradeCatalog.items
                .filter { $0.side == side && owned.contains($0.id) }
                .map { CupTile(setID: $0.id, name: $0.name, side: side) }
        }
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
                    .frame(maxWidth: 64, maxHeight: 72)
                Text(tile.name)
                    .font(AppFont.pretendard(13, .semibold, relativeTo: .footnote))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.ink)
                HStack(spacing: 6) {
                    Circle()
                        .fill(CupHero.color(tile.side))
                        .frame(width: 6, height: 6)
                    Text(tile.side.characterName)
                        .font(AppFont.pretendard(11, .regular, relativeTo: .caption2))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 148)
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

    /// 병뚜껑 잔액(§4.10). Debug `-screenshotCaps <n>`이면 그 값(추이 탭과 같은 인자).
    private var caps: Int {
        CapBalance.current(gifts: gifts, trades: trades)
    }

    /// 산 잔. Debug에서 `-cupSet.<면>`으로 켠 잔도 가진 것으로 본다(스크린샷용).
    private var ownedSets: Set<String> {
        var owned = TradeMath.ownedSets(trades: trades.map(\.record))
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
        case "sugar-cube": return (String(localized: "각설탕"), "gift-item-sugar-cube")
        default: return nil
        }
    }
}
