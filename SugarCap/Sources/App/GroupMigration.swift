import Foundation
import OSLog
import SwiftData

/// 빌드 453까지 TestFlight·App Store 빌드에는 App Group entitlement가 빠져 있었다
/// (아카이브를 무서명으로 만들어 cloud signing이 기본 키만 넣었다, 2026-11-14 CI에서 확인).
/// 그동안 앱은 앱 전용 저장소에 기록했고 위젯은 빈 저장소를 봤다.
/// App Group이 붙은 첫 실행에 앱 전용 SwiftData 파일과 공용 설정(`group.com.sugarcap.app` suite)을 공용 저장소로 옮긴다.
/// 옮긴 옛 파일은 지우지 않고 `.pre-group`을 붙여 둔다. 옛 파일이 없으면 다시 옮기지 않는다
/// (완료 표시를 설정 키로 두면 설정의 앱 초기화가 지워 옛 기록이 되살아난다).
enum GroupMigration {
    static let backupSuffix = ".pre-group"
    private static let logger = Logger(subsystem: "com.sugarcap.app", category: "store")
    /// SQLite 본 파일과 WAL·공유 메모리 파일.
    private static let storeSuffixes = ["", "-wal", "-shm"]

    /// 앱이 열 저장소. App Group이 없으면(CI 시뮬레이터 무서명) 앱 전용 저장소.
    /// 옮기다 실패하면 이번 실행은 앱 전용 저장소를 그대로 쓰고 다음 실행에 다시 옮긴다.
    static func appConfiguration() -> ModelConfiguration {
        let local = ModelConfiguration(schema: SharedStore.schema)
        guard SharedStore.groupContainerURL != nil, let shared = SharedDefaults.store else { return local }
        let group = ModelConfiguration(schema: SharedStore.schema, groupContainer: .identifier(SharedStore.appGroupID))
        do {
            let keys = try moveDefaults(fromPlist: legacySuitePlist(), to: shared)
            let moved = try moveStore(from: local.url, to: group.url)
            if moved || !keys.isEmpty {
                logger.info("공용 저장소로 옮김: SwiftData \(moved ? "있음" : "없음", privacy: .public), 설정 \(keys.joined(separator: ","), privacy: .public)")
            }
            return group
        } catch {
            logger.fault("공용 저장소로 옮기지 못해 앱 전용 저장소를 씀: \(String(describing: error), privacy: .public)")
            return local
        }
    }

    /// entitlement 없이 연 suite가 쌓인 곳(앱 컨테이너 `Library/Preferences`).
    private static func legacySuitePlist() -> URL {
        URL.libraryDirectory.appending(path: "Preferences/\(SharedStore.appGroupID).plist")
    }

    /// 앱 전용 저장소 파일을 공용 위치에 복사하고 옛 파일에 `.pre-group`을 붙인다.
    /// 공용 위치에 있던 파일(위젯이 먼저 만든 빈 저장소)은 덮는다. 복사가 끝나기 전에 실패하면 옛 파일은 그대로다.
    /// - Returns: 옮길 저장소가 있었는지. 새로 설치했거나 이미 옮긴 기기는 없다.
    @discardableResult
    static func moveStore(from source: URL, to destination: URL, fileManager: FileManager = .default) throws -> Bool {
        guard fileManager.fileExists(atPath: source.path(percentEncoded: false)) else { return false }
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        for suffix in storeSuffixes {
            let from = sibling(source, suffix)
            let to = sibling(destination, suffix)
            if fileManager.fileExists(atPath: to.path(percentEncoded: false)) {
                try fileManager.removeItem(at: to)
            }
            if fileManager.fileExists(atPath: from.path(percentEncoded: false)) {
                try fileManager.copyItem(at: from, to: to)
            }
        }
        // 본 파일을 먼저 치운다. 본 파일이 남은 채 실패하면 다음 실행에 처음부터 다시 옮긴다.
        for suffix in storeSuffixes {
            try backUp(sibling(source, suffix), fileManager: fileManager)
        }
        return true
    }

    /// 옛 suite plist의 값을 공용 설정에 넣고 plist에 `.pre-group`을 붙인다. 공용 쪽에 이미 있는 키는 그대로 둔다.
    /// - Returns: 넣은 키.
    @discardableResult
    static func moveDefaults(fromPlist plist: URL, to store: UserDefaults, fileManager: FileManager = .default) throws -> [String] {
        guard fileManager.fileExists(atPath: plist.path(percentEncoded: false)) else { return [] }
        let data = try Data(contentsOf: plist)
        guard let values = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw GroupMigrationError.unreadablePlist(plist.lastPathComponent)
        }
        var copied: [String] = []
        for (key, value) in values.sorted(by: { $0.key < $1.key }) where store.object(forKey: key) == nil {
            store.set(value, forKey: key)
            copied.append(key)
        }
        try backUp(plist, fileManager: fileManager)
        return copied
    }

    private static func sibling(_ url: URL, _ suffix: String) -> URL {
        URL(filePath: url.path(percentEncoded: false) + suffix)
    }

    private static func backUp(_ url: URL, fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        let backup = sibling(url, backupSuffix)
        if fileManager.fileExists(atPath: backup.path(percentEncoded: false)) {
            try fileManager.removeItem(at: backup)
        }
        try fileManager.moveItem(at: url, to: backup)
    }
}

enum GroupMigrationError: Error {
    case unreadablePlist(String)
}
