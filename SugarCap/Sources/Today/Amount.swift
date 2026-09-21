import Foundation

/// 당·카페인 수치 표기. 소수 첫째 자리까지, `.0`은 붙이지 않는다(`design/prototype.html:182`).
enum Amount {
    /// nil은 "브랜드 미공개"다. 0으로 적지 않는다(SPEC §9.2).
    static func text(_ value: Double?, unit: String) -> String {
        guard let value else { return "미공개" }
        return "\(number(value)) \(unit)"
    }

    static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}
