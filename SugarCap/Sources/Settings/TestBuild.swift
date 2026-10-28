import OSLog
import StoreKit

/// 설정의 테스트 카드를 보일지. Debug 빌드와 TestFlight(샌드박스 앱 영수증)에서만 참이다.
/// App Store 빌드에서는 거짓이라 카드가 아예 그려지지 않는다.
enum TestBuild {
    private static let logger = Logger(subsystem: "com.sugarcap.app", category: "settings")

    static func isActive() async -> Bool {
        #if DEBUG
        return true
        #else
        do {
            switch try await AppTransaction.shared {
            case .verified(let transaction):
                return transaction.environment == .sandbox
            case .unverified(_, let error):
                logger.error("앱 영수증 검증 실패: \(String(describing: error), privacy: .public)")
                return false
            }
        } catch {
            logger.error("앱 영수증 읽기 실패: \(String(describing: error), privacy: .public)")
            return false
        }
        #endif
    }
}

/// 테스트 카드에서 고른 일. 설정 시트가 닫힌 뒤 오늘 화면이 실행한다(시트 위에 전체 화면을 겹쳐 띄우지 않는다).
enum SettingsTestAction {
    /// 오늘 마감 먹이기를 저장 없이 연다.
    case feeding
    /// 첫 마감 한 묶음을 저장 없이: 로슈·카인 소개 → 튜토리얼 먹이기 → 두 면 "처음 만난 사이" 무대(2026-10-28 대표님).
    case companionIntro
    /// 어젯밤 정산 화면을 저장 없이 연다.
    case yesterdayGate
    /// 기준 지킨 주 축하 화면을 이번 주로 열고, 끝나면 캐릭터가 실제 선물 상자를 들고 있다(주 칸은 비워 진짜 주 선물과 안 겹친다).
    case weekKept
    /// 앱 소개·로슈 카인 소개를 처음부터. 기록은 그대로 둔다.
    case firstRun
}
