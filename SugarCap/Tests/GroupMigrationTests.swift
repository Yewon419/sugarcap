import SwiftData
import XCTest

@testable import SugarCap

/// App Group 없이 나간 빌드의 앱 전용 저장소를 공용 저장소로 옮기기(`GroupMigration`, 2026-11-14).
final class GroupMigrationTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "GroupMigrationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    private func entry(_ name: String) -> Entry {
        Entry(
            servingID: "starbucks:\(name):iced:tall", quantity: 1, loggedAt: Date(timeIntervalSinceReferenceDate: 0),
            sugarG: 10, caffeineMg: 150, drinkName: name, brandName: "스타벅스", sizeLabel: "Tall"
        )
    }

    private func names(at url: URL) throws -> [String] {
        let container = try ModelContainer(for: SharedStore.schema, configurations: ModelConfiguration(schema: SharedStore.schema, url: url))
        return try container.mainContext.fetch(FetchDescriptor<Entry>()).map(\.drinkName).sorted()
    }

    func testStoreMovesWithRecordsAndOnlyOnce() throws {
        let source = root.appending(path: "local/default.store")
        let destination = root.appending(path: "group/Library/Application Support/default.store")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            let container = try ModelContainer(
                for: SharedStore.schema, configurations: ModelConfiguration(schema: SharedStore.schema, url: source)
            )
            container.mainContext.insert(entry("latte"))
            container.mainContext.insert(entry("americano"))
            try container.mainContext.save()
        }
        // 위젯이 먼저 만든 빈 공용 저장소는 덮인다.
        XCTAssertEqual(try names(at: destination), [])

        XCTAssertTrue(try GroupMigration.moveStore(from: source, to: destination))

        XCTAssertEqual(try names(at: destination), ["americano", "latte"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path(percentEncoded: false)), "옛 본 파일은 치운다")
        let backup = URL(filePath: source.path(percentEncoded: false) + GroupMigration.backupSuffix)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path(percentEncoded: false)), "옛 파일은 백업으로 남긴다")
        XCTAssertFalse(try GroupMigration.moveStore(from: source, to: destination), "한 번 옮기면 다시 옮기지 않는다")
        XCTAssertEqual(try names(at: destination), ["americano", "latte"])
    }

    func testNoLocalStoreMovesNothing() throws {
        let destination = root.appending(path: "group/default.store")
        XCTAssertFalse(try GroupMigration.moveStore(from: root.appending(path: "none/default.store"), to: destination))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)))
    }

    func testDefaultsMoveWithoutOverwritingSharedValues() throws {
        let suite = "GroupMigrationTests"
        let store = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { store.removePersistentDomain(forName: suite) }
        store.set("glass-soda", forKey: "cupSet.caffeine")

        let plist = root.appending(path: "group.com.sugarcap.app.plist")
        let legacy: [String: Any] = ["cupSet.sugar": "choco-frappe", "cupSet.caffeine": "iced-americano", "isPro": true]
        try PropertyListSerialization.data(fromPropertyList: legacy, format: .binary, options: 0).write(to: plist)

        XCTAssertEqual(try GroupMigration.moveDefaults(fromPlist: plist, to: store), ["cupSet.sugar", "isPro"])

        XCTAssertEqual(store.string(forKey: "cupSet.sugar"), "choco-frappe")
        XCTAssertEqual(store.string(forKey: "cupSet.caffeine"), "glass-soda", "공용 쪽 값이 이긴다")
        XCTAssertTrue(store.bool(forKey: "isPro"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: plist.path(percentEncoded: false)))
        XCTAssertEqual(try GroupMigration.moveDefaults(fromPlist: plist, to: store), [], "한 번 옮기면 다시 옮기지 않는다")
    }
}
