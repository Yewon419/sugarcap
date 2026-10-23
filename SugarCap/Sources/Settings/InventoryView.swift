import SwiftData
import SwiftUI

/// 보관함(대표님 2026-10-24 "설정에 인벤토리, 뭐 모았는지 볼 수 있게"). 설정 맨 위 줄에서 연다.
/// 열어 본 선물만 센다: 병뚜껑 개수, 모은 물건. 마음은 넣지 않는다(같은 날 대표님 "마음은 빼").
/// 물건 칸은 등록된 물건 수 + 물음표 칸 3개(아직 없는 물건 자리, 대표님 "몇 개 미리 물음표 깔아 한 세 개쯤").
struct InventoryView: View {
    @Query private var gifts: [GiftEvent]

    static let hiddenSlots = 3

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                capHeader
                    .padding(.horizontal, 32)
                    .padding(.top, 8)
                Text("물건")
                    .font(AppFont.pretendard(13, .regular, relativeTo: .footnote))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 32)
                    .padding(.top, 28)
                    .padding(.bottom, 8)
                    .accessibilityAddTraits(.isHeader)
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
                Text("선물 상자에서 모은 것")
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

    /// 열어 본 병뚜껑 수. Debug `-screenshotCaps <n>`이면 그 값(추이 탭과 같은 인자).
    private var caps: Int {
        #if DEBUG
        if UserDefaults.standard.object(forKey: "screenshotCaps") != nil {
            return UserDefaults.standard.integer(forKey: "screenshotCaps")
        }
        #endif
        return gifts.filter { $0.isCap && $0.isOpened }.count
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
        default: return nil
        }
    }
}
