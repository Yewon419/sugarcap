import Observation
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

/// 설정 테스트 카드를 여는 개발자 모드. TestFlight·Debug에서 버전 줄을 연달아 누르면 켜고 끈다.
enum DeveloperMode {
    static let key = "developerMode"
    static let tapCount = 7
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
    /// 보고 있는 면의 다음 호감도 단계 레벨업 무대를 저장 없이 연다.
    case levelUp
    /// 거래 제안을 저장 없이 보낸다. 캐릭터가 상자를 들고 오고, 바꾸면 잔만 바뀐다(병뚜껑·제안 기록은 그대로).
    case trade
    /// 테스트 카드가 아니라 사용설명서 「음료 기록법」(모든 빌드). 첫 기록 안내를 연습 음료로 다시 보여 준다(`DrinkTutorial`).
    case drinkGuide
    /// 사용설명서 「하루 마감법」(모든 빌드, 첫 마감 뒤에만 보인다). 로슈·카인 소개와 안내 먹이기를 저장 없이 다시 보여 준다.
    case closeGuide
    /// 기록·마감·선물·설정을 전부 지우고 온보딩부터(`DevData.reset`). 개발자 모드는 켜 둔다.
    case resetAll
    /// 지난 두 달 기록과 매일 밤 마감을 실제 규칙대로 채운다(`DevData.fill`).
    case fillData
    /// 앱 달력을 하루 앞당긴다(`AppClock`). 오늘 기록이 어제 것이 되어 어젯밤 정산이 뜬다. 앱 초기화로 0이 된다.
    case advanceDay
    /// 스탬프판 보상 연출을 저장 없이 연다(대표님 2026-11-05).
    case stampReward(StampRehearsal)
}

/// 테스트 카드에서 여는 스탬프판 보상. 판 행은 저장소에 넣지 않는다.
enum StampRehearsal: CaseIterable {
    /// 4칸째 도장이 찍힌다.
    case stamp
    /// 7칸 도장 뒤 얼리버드 무대.
    case earlyBird
    /// 14칸 잔 룰렛(안 가진 잔 중 하나에서 멈춤).
    case roulette
    /// 14칸 병뚜껑 3개(잔을 다 가졌을 때).
    case caps

    var title: String {
        switch self {
        case .stamp: return String(localized: "도장 한 칸")
        case .earlyBird: return String(localized: "얼리버드 선물")
        case .roulette: return String(localized: "14일 룰렛")
        case .caps: return String(localized: "14일 선물")
        }
    }

    /// 찍힌 칸 수.
    var count: Int {
        switch self {
        case .stamp: return 4
        case .earlyBird: return StampMath.earlyBirdCell
        case .roulette, .caps: return StampMath.cells
        }
    }
}

/// 테스트 카드에서 고른 대기 자세(TestFlight·Debug). 캐릭터 id("roshu", "kain") → 자세 이름.
/// 해금·컵 단계와 상관없이 그 자세로 세운다(지금 잔에서 안 보이는 자세는 빼고). 저장하지 않아 앱을 다시 켜면 자동으로 돌아간다.
@MainActor
@Observable
final class IdleTestPose {
    static let shared = IdleTestPose()

    private var poses: [String: String] = [:]

    func pose(for character: String) -> String? {
        poses[character]
    }

    func set(_ pose: String?, for character: String) {
        poses[character] = pose
    }
}
