import Foundation

/// 아직 안 보낸 이벤트 파일(JSON 배열). 동의 전에는 여기에만 쌓이고, 거절·철회하면 파일째 지운다.
struct UsageQueue {
    /// 넘치면 오래된 것부터 버린다. 하루 5건 남짓이라 몇 달 치다.
    static let capacity = 1000

    let fileURL: URL

    static func defaultURL() throws -> URL {
        do {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            return support.appendingPathComponent("Usage", isDirectory: true).appendingPathComponent("queue.json")
        } catch {
            throw UsageError.queueFile(operation: "locate", path: "Application Support", underlying: String(describing: error))
        }
    }

    func load() throws -> [UsageEvent] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([UsageEvent].self, from: data)
        } catch {
            throw UsageError.queueFile(operation: "load", path: fileURL.path, underlying: String(describing: error))
        }
    }

    func save(_ events: [UsageEvent]) throws {
        let kept = Array(events.suffix(Self.capacity))
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(kept).write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            throw UsageError.queueFile(operation: "save", path: fileURL.path, underlying: String(describing: error))
        }
    }

    func delete() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            throw UsageError.queueFile(operation: "delete", path: fileURL.path, underlying: String(describing: error))
        }
    }
}
