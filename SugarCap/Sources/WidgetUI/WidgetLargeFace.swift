import SwiftUI
import UIKit

/// Large 위젯(SPEC §4.6, 시안 `design/proto/widget-large.html` A 대표님 2026-11-09 확정).
/// 위 262pt = 잔 전체(Medium처럼 두 잔 입구 높이가 같다), 아래 = 기록한 음료 선반 4칸.
/// 기준 칸 338×354pt(6.1인치)를 폭에 맞춰 늘린다. 위젯 확장과 앱(Debug 위젯 스크린샷)이 함께 컴파일한다.
struct WidgetLargeFace: View {
    let cups: [WidgetCupModel]
    let shelf: [ShelfDrink]

    static let referenceWidth = 338.0
    /// 잔 사진 아래 끝을 바닥색으로 녹이는 높이.
    private static let fadeHeight = 28.0
    private static let columns = 4
    private static let sideInset = 10.0
    private static let bottomInset = 12.0
    private static let badgeSize = 50.0
    private static let badgeGap = 7.0
    private static let emptyHeight = 80.0
    private static let ink = Color(red: 0x1D / 255, green: 0x1D / 255, blue: 0x1F / 255)
    /// 위젯 바닥색. 잔 사진이 이 색으로 녹아 선반이 그 위에 놓인다.
    static let floor = Color(red: 0xEE / 255, green: 0xF0 / 255, blue: 0xF3 / 255)

    var body: some View {
        GeometryReader { proxy in
            let scale: Double = proxy.size.width / Self.referenceWidth
            ZStack(alignment: .top) {
                cupArea(scale: scale, width: proxy.size.width)
                if shelf.isEmpty {
                    Text("기록한 음료가 여기 떠요")
                        .font(.custom("Pretendard-SemiBold", fixedSize: 12 * scale))
                        .foregroundStyle(Self.ink.opacity(0.5))
                        .frame(width: proxy.size.width, height: Self.emptyHeight * scale)
                        .offset(y: WidgetCupFamily.large.referenceSize.height * scale)
                } else {
                    shelfRow(scale: scale)
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .clipped()
    }

    private func cupArea(scale: Double, width: Double) -> some View {
        let height: Double = WidgetCupFamily.large.referenceSize.height * scale
        let fade: Double = Self.fadeHeight * scale
        return Group {
            if cups.count >= 2 {
                WidgetCupPair(family: .large, left: cups[0], right: cups[1], scale: scale, width: width)
            } else if let cup = cups.first {
                WidgetCupArt(family: .largeSolo, cup: cup, scale: scale)
            }
        }
        .frame(width: width, height: height, alignment: .leading)
        .mask {
            VStack(spacing: 0) {
                Color.black.frame(height: height - fade)
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: fade)
            }
        }
    }

    private func shelfRow(scale: Double) -> some View {
        let column: Double = (Self.referenceWidth - 2 * Self.sideInset) / Double(Self.columns) * scale
        return HStack(spacing: 0) {
            ForEach(shelf.prefix(Self.columns)) { drink in
                ShelfItem(drink: drink, scale: scale)
                    .frame(width: column)
            }
        }
        .padding(.horizontal, Self.sideInset * scale)
        .padding(.bottom, Self.bottomInset * scale)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private struct ShelfItem: View {
        let drink: ShelfDrink
        let scale: Double

        var body: some View {
            let lines = ShelfName.lines(drink.name, width: ShelfName.width, measure: ShelfName.measure)
            VStack(spacing: WidgetLargeFace.badgeGap * scale) {
                LiquidBadge(
                    color: drink.liquidHex.flatMap(Color.init(liquidHex:)) ?? LiquidBadge.fallback,
                    size: WidgetLargeFace.badgeSize * scale
                )
                VStack(spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.custom("Pretendard-SemiBold", fixedSize: ShelfName.fontSize * scale))
                            .foregroundStyle(WidgetLargeFace.ink)
                            .lineLimit(1)
                            .fixedSize()
                            .frame(height: ShelfName.lineHeight * scale)
                    }
                }
                .frame(height: 2 * ShelfName.lineHeight * scale, alignment: .top)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(drink.name))
        }
    }
}

/// 선반 이름 줄바꿈(대표님 2026-11-09 "줄바꿈만 좀 신경써줘", 시안 `wrapName`과 같은 규칙). 기준 칸 pt로 잰다.
/// 1) 한 줄에 들어가면 한 줄. 2) 아니면 띄어쓰기 자리 중 두 줄 중 긴 쪽이 가장 짧은 곳에서 끊는다(외톨이 단어 방지).
/// 3) 둘째 줄이 넘치면 끝을 "…"로 줄인다. 4) 칸보다 긴 첫 단어는 글자 단위로 끊는다.
enum ShelfName {
    static let width = 74.0
    static let fontSize = 11.0
    static let lineHeight = 11.0 * 1.25

    static func measure(_ text: String) -> Double {
        let font = UIFont(name: "Pretendard-SemiBold", size: fontSize) ?? .systemFont(ofSize: fontSize, weight: .semibold)
        return (text as NSString).size(withAttributes: [.font: font]).width
    }

    static func lines(_ name: String, width: Double, measure: (String) -> Double) -> [String] {
        guard measure(name) > width else { return [name] }
        let words = name.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        var best: (cost: Double, first: String, second: String)?
        for index in 1..<max(words.count, 1) {
            let first = words[..<index].joined(separator: " ")
            let second = words[index...].joined(separator: " ")
            let firstWidth = measure(first)
            if firstWidth > width { break }
            let secondWidth = measure(second)
            // 둘째 줄이 넘치는 자리는 줄일 글자가 적은 쪽(첫 줄이 긴 쪽)이 낫다.
            let cost: Double = secondWidth <= width ? max(firstWidth, secondWidth) : 1000 + secondWidth - firstWidth
            if best == nil || cost < (best?.cost ?? .infinity) {
                best = (cost, first, second)
            }
        }
        if let best {
            return [best.first, ellipsize(best.second, width: width, measure: measure)]
        }
        var count = name.count
        while count > 1, measure(String(name.prefix(count))) > width {
            count -= 1
        }
        let rest = String(name.dropFirst(count)).trimmingCharacters(in: .whitespaces)
        return [String(name.prefix(count)), ellipsize(rest, width: width, measure: measure)]
    }

    static func ellipsize(_ text: String, width: Double, measure: (String) -> Double) -> String {
        guard measure(text) > width else { return text }
        var kept = text
        while kept.count > 1, measure(kept + "…") > width {
            kept.removeLast()
        }
        return kept.trimmingCharacters(in: .whitespaces) + "…"
    }
}
