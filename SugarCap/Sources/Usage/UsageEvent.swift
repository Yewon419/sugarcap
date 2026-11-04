import Foundation

/// 기기 안 대기열에 쌓는 이벤트 한 건(SPEC §9.10). 보낼 때 `IngestSignal`로 바뀐다.
struct UsageEvent: Codable, Equatable, Sendable {
    /// 퍼널 이벤트는 설치 ID(해시)와 실행 단위 세션으로 잇는다. 음료 통계는 아무것도 붙이지 않는다.
    enum Scope: String, Codable, Sendable {
        case install
        case anonymous
    }

    let id: UUID
    let type: String
    let scope: Scope
    let parameters: [String: String]
    let createdAt: Date
    /// `install`만 값이 있다.
    let sessionID: UUID?
}

enum UsageError: Error, CustomStringConvertible {
    case keychain(operation: String, status: OSStatus)
    case queueFile(operation: String, path: String, underlying: String)
    case ingest(url: String, signalCount: Int, status: Int, body: String)
    case transport(url: String, signalCount: Int, underlying: String)

    var description: String {
        switch self {
        case .keychain(let operation, let status):
            "keychain \(operation) failed: OSStatus \(status)"
        case .queueFile(let operation, let path, let underlying):
            "usage queue \(operation) failed at \(path): \(underlying)"
        case .ingest(let url, let signalCount, let status, let body):
            "ingest POST \(url) (\(signalCount) signals) returned \(status): \(body)"
        case .transport(let url, let signalCount, let underlying):
            "ingest POST \(url) (\(signalCount) signals) failed: \(underlying)"
        }
    }
}
