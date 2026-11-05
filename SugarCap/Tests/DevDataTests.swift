import Foundation
import SwiftData
import XCTest

@testable import SugarCap

/// 개발자 모드 "지난 2달 데이터 채우기"(대표님 2026-11-05). 실제 마감 길로 채워 보상이 규칙대로 쌓이는지 본다.
final class DevDataTests: XCTestCase {
    private var savedDefaults: [String: Any] = [:]
    private let touchedKeys = [StampProgress.seenKey, StampProgress.seedKey]

    override func setUp() {
        super.setUp()
        // 같은 시뮬레이터의 UI 테스트가 이 값을 읽는다. 끝나면 되돌린다.
        for key in touchedKeys {
            if let value = UserDefaults.standard.object(forKey: key) { savedDefaults[key] = value }
        }
    }

    override func tearDown() {
        for key in touchedKeys {
            if let value = savedDefaults[key] {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        super.tearDown()
    }

    @MainActor
    func testFillClosesEveryPastDayAndLeavesNothingPending() throws {
        let container = try ModelContainer(
            for: SharedStore.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let catalog = try CatalogStore.loadBundled(.kr, from: Bundle(for: Self.self))
        let now = Date()

        let filled = try DevData.fill(
            days: 60, catalog: catalog, sides: CupSide.allCases, limits: .default, boundaryHour: 4, isPro: false,
            now: now, in: context
        )
        XCTAssertEqual(filled, 60)

        let rows = try context.fetch(FetchDescriptor<DaySettlement>())
        XCTAssertEqual(rows.filter { $0.isClosed && $0.finalizedAt != nil }.count, 60, "매일 마감·적립돼야 한다")
        let today = DayKey(at: now, boundaryHour: 4)
        XCTAssertFalse(rows.contains { $0.day == today.rawValue }, "오늘은 건드리지 않는다")

        let entries = try context.fetch(FetchDescriptor<Entry>())
        XCTAssertTrue((60 ... 180).contains(entries.count), "하루 1~3잔: \(entries.count)")

        let gifts = try GiftStore.all(in: context)
        XCTAssertTrue(gifts.allSatisfy(\.isOpened), "쌓인 상자·무대는 연 것으로 둔다")
        XCTAssertEqual(StampMath.stamped(cellNumbers: gifts.filter { $0.giftKind == .stamp }.compactMap(\.level)), 14)
        XCTAssertEqual(UserDefaults.standard.integer(forKey: StampProgress.seenKey), 14, "스탬프판은 본 것으로")
        XCTAssertTrue(gifts.contains { $0.giftKind == .trendsUnlock }, "첫 적립 선물")
        XCTAssertEqual(gifts.filter { $0.giftKind == .starterCap }.count, 2, "튜토리얼 병뚜껑 2개")
        XCTAssertTrue(try SettlementStore.affinity(for: .sugar, in: context).points > 0)

        XCTAssertEqual(
            try DevData.fill(
                days: 60, catalog: catalog, sides: CupSide.allCases, limits: .default, boundaryHour: 4, isPro: false,
                now: now, in: context
            ),
            0,
            "이미 마감한 날은 다시 채우지 않는다"
        )
    }
}
