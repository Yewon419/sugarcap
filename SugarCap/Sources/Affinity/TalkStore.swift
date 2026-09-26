import Foundation
import OSLog
import SwiftData

/// 말걸기 저장(§4.8). 캐릭터마다 하루 한 번, +2점(`TalkMath.points`).
@MainActor
enum TalkStore {
    private static let logger = Logger(subsystem: "com.sugarcap.app", category: "talk")

    struct Outcome: Equatable {
        let reaction: TalkReaction
        let leveledUp: Bool
    }

    enum TalkError: Error, Equatable {
        /// 오늘 이미 말을 걸었다. 화면이 막지만 두 번 눌러도 점수가 두 번 오르지 않게 저장소에서도 막는다.
        case alreadyTalkedToday
    }

    static func log(for side: CupSide, day: DayKey, in logs: [TalkLog]) -> TalkLog? {
        logs.first { $0.character == side.characterID && $0.day == day.rawValue }
    }

    static func talk(side: CupSide, choiceID: String, day: DayKey, logs: [TalkLog], in context: ModelContext) throws -> Outcome {
        guard log(for: side, day: day, in: logs) == nil else { throw TalkError.alreadyTalkedToday }
        let affinity = try SettlementStore.affinity(for: side, in: context)
        let before = affinity.level
        let reaction = TalkMath.reaction(side: side, choiceID: choiceID, level: before, day: day)
        affinity.points += TalkMath.points
        context.insert(TalkLog(character: side.characterID, day: day.rawValue, choiceID: choiceID, reaction: reaction.rawValue))
        do {
            try context.save()
        } catch {
            logger.error("말걸기 저장 실패(\(side.characterID, privacy: .public), \(day.rawValue, privacy: .public)): \(String(describing: error), privacy: .public)")
            context.rollback()
            throw error
        }
        return Outcome(reaction: reaction, leveledUp: affinity.level > before)
    }
}
