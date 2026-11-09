import AppIntents
import Foundation
import SwiftData
import WidgetKit

/// Large 위젯 선반 칸을 누르면 그 음료 1잔을 기록한다(시안 widget-large.html A). 위젯 확장 프로세스에서 돈다.
/// 시리·단축어에는 내놓지 않는다.
struct RecordShelfDrinkIntent: AppIntent {
    static var title: LocalizedStringResource { "음료 기록" }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "음료")
    var key: String

    init() {}

    init(key: String) {
        self.key = key
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try WidgetRecorder.record(key: key, now: AppClock.now)
        return .result()
    }
}

/// 방금 위젯으로 기록한 1잔을 지운다(기록 뒤 약 10초 그 칸이 되돌리기 버튼).
struct UndoShelfDrinkIntent: AppIntent {
    static var title: LocalizedStringResource { "기록 되돌리기" }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "기록")
    var entryID: String

    init() {}

    init(entryID: UUID) {
        self.entryID = entryID.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try WidgetRecorder.undo(entryID: entryID)
        return .result()
    }
}

enum WidgetRecordError: Error, CustomStringConvertible {
    case noAppGroup
    case drinkNotOnShelf(key: String)
    case badEntryID(String)

    var description: String {
        switch self {
        case .noAppGroup: "App Group \(SharedStore.appGroupID) 없음"
        case .drinkNotOnShelf(let key): "선반에 없는 음료: \(key)"
        case .badEntryID(let id): "기록 id 형식 오류: \(id)"
        }
    }
}

/// 위젯에서 기록·되돌리기. 저장은 앱과 같은 App Group SwiftData(`SharedStore`)에 한다.
/// 정산·먹이기는 앱을 열 때 저장된 기록 전체로 하니 위젯 기록도 그대로 들어간다.
enum WidgetRecorder {
    @MainActor
    static func record(key: String, now: Date) throws {
        guard let store = SharedDefaults.store else { throw WidgetRecordError.noAppGroup }
        guard let drink = try WidgetShelf.load(from: store).first(where: { $0.key == key }) else {
            throw WidgetRecordError.drinkNotOnShelf(key: key)
        }
        let container = try SharedStore.makeContainer()
        let context = ModelContext(container)
        let entry = drink.makeEntry(at: now)
        context.insert(entry)
        try context.save()
        try WidgetShelf.saveRecord(WidgetRecord(entryID: entry.id, key: key, at: now), to: store)
        try WidgetShelf.appendEvent(WidgetEntryEvent(brandID: drink.brandID, at: now), to: store)
        WidgetCenter.shared.reloadAllTimelines()
    }

    @MainActor
    static func undo(entryID: String) throws {
        guard let store = SharedDefaults.store else { throw WidgetRecordError.noAppGroup }
        guard let id = UUID(uuidString: entryID) else { throw WidgetRecordError.badEntryID(entryID) }
        let container = try SharedStore.makeContainer()
        let context = ModelContext(container)
        let targets = try context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.id == id }))
        for entry in targets { context.delete(entry) }
        try context.save()
        if try WidgetShelf.loadRecord(from: store)?.entryID == id {
            try WidgetShelf.saveRecord(nil, to: store)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
