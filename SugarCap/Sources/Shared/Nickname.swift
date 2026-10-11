import Foundation

/// 받침에 맞춘 조사(SPEC §4.9 2026-10-11 회의 4). 별명 끝 글자로 고른다.
/// 한글은 끝 음절 받침, 홀로 쓴 자음(ㅋ)은 받침 있음, 숫자는 읽는 소리(0 영, 1 일, 3 삼, 6 육, 7 칠, 8 팔)로 본다. 그 밖(영문 등)은 받침 없음.
enum Josa {
    static func hasBatchim(_ word: String) -> Bool {
        guard let last = word.unicodeScalars.last else { return false }
        let v = last.value
        if (0xAC00 ... 0xD7A3).contains(v) { return (v - 0xAC00) % 28 != 0 }
        if (0x3131 ... 0x314E).contains(v) { return true }
        return "013678".unicodeScalars.contains(last)
    }

    /// 와/과.
    static func withGwa(_ word: String) -> String { word + (hasBatchim(word) ? "과" : "와") }
    /// 가/이.
    static func withIga(_ word: String) -> String { word + (hasBatchim(word) ? "이" : "가") }
}

/// 로슈·카인 별명(호감도 Lv8부터, SPEC §4.9 2026-10-11 회의 4). 기기 설정(UserDefaults)에 둔다.
/// 정해 두면 화면의 캐릭터 이름(`CupSide.characterName` 등)이 별명으로 바뀐다. 소개 연출의 "로슈!"·"카인!"은 원래 이름 그대로다.
enum Nickname {
    static let unlockLevel = 8
    static let maxLength = 8

    static func key(_ characterID: String) -> String { "nickname.\(characterID)" }

    /// 저장된 별명. 없거나 빈칸이면 nil.
    static func stored(_ characterID: String, in defaults: UserDefaults = .standard) -> String? {
        guard let raw = defaults.string(forKey: key(characterID)) else { return nil }
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    /// 앞뒤 빈칸을 자르고 `maxLength`자까지 저장한다. 비우면 원래 이름으로 돌아간다.
    static func save(_ text: String, for characterID: String, in defaults: UserDefaults = .standard) {
        let name = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxLength))
        if name.isEmpty {
            defaults.removeObject(forKey: key(characterID))
        } else {
            defaults.set(name, forKey: key(characterID))
        }
    }

    /// 조사를 붙여 쓰는 화면 언어인지(한국어). 영어·중국어 화면은 별명만 쓴다.
    static var usesJosa: Bool { Bundle.main.preferredLocalizations.first == "ko" }
}
