import Foundation
import Security

/// 설치마다 무작위로 만든 값(SPEC §9.10 퍼널 흐름). 키체인에 두어 앱을 지웠다 다시 깔아도 같은 값이 남는다.
/// 이 기기에만 저장하고(`ThisDeviceOnly`) iCloud 키체인으로 넘기지 않는다. 보낼 때는 해시만 보낸다.
enum InstallID {
    private static let service = "com.sugarcap.app.usage"
    private static let account = "installID"

    static func current() throws -> UUID {
        if let existing = try read() {
            return existing
        }
        let created = UUID()
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(created.uuidString.utf8),
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw UsageError.keychain(operation: "add", status: status)
        }
        return created
    }

    private static func read() throws -> UUID? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw UsageError.keychain(operation: "read", status: status)
        }
        guard let data = item as? Data, let text = String(data: data, encoding: .utf8), let id = UUID(uuidString: text) else {
            throw UsageError.keychain(operation: "decode", status: status)
        }
        return id
    }
}
