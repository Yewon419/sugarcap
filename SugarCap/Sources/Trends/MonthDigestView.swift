import SwiftUI

/// 월 달력 아래 통계(프로토 `design/proto/trends-month-stats.html`). 글자는 제목·숫자만(대표님 2026-10-28 "쓸데없는 말 다 빼").
/// 바탕은 면 색: 당 = 흰 바탕 먹색, 카페인 = 진한 커피색 바탕 흰 글자. 강조는 당 먹색, 카페인 라떼색.
/// 섹션마다 핵심 숫자 하나와 강조 막대에 접시 사진을 씌운다(`PhotoFill`). 요일은 막대 대신 기준 컵(대표님 2026-10-28).
struct MonthDigestView: View {
    let digest: MonthDigest
    let side: CupSide
    let limit: Double
    /// 보는 달의 1일.
    let shown: DayKey

    static func background(_ side: CupSide) -> Color {
        switch side {
        case .sugar: return .white
        case .caffeine: return Color(red: 0x17 / 255, green: 0x11 / 255, blue: 0x0C / 255)
        }
    }

    private static let latte = Color(red: 0xE3 / 255, green: 0xC2 / 255, blue: 0x9F / 255)
    private static let appCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "ko")
        return calendar
    }()

    private var isSugar: Bool { side == .sugar }
    private var fg: Color { isSugar ? Color.ink : .white }
    private var dim: Color { fg.opacity(isSugar ? 0.55 : 0.6) }
    private var faint: Color { fg.opacity(0.12) }
    private var rule: Color { fg.opacity(isSugar ? 0.18 : 0.2) }
    private var hi: Color { isSugar ? Color.ink : Self.latte }
    private var lo: Color { fg.opacity(isSugar ? 0.16 : 0.18) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if digest.total == 0 && digest.closedDays == 0 {
                section("많이 먹은 음료") { empty }
            } else {
                section("많이 먹은 음료") { topDrinks }
                section("시간대") { slots }
                section("요일별 하루 평균") { weekdays }
                section("기준 안에서 끝낸 날") { kept }
                section("최근 6개월 하루 평균") { recent }
            }
        }
        .foregroundStyle(fg)
        .padding(.horizontal, 24)
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(AppFont.pretendardFixed(13, .bold))
                .foregroundStyle(dim)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 26)
        .padding(.bottom, 28)
        .overlay(alignment: .top) { rule.frame(height: 1) }
    }

    private var empty: some View {
        Text("기록 없음")
            .font(AppFont.pretendardFixed(14, .medium))
            .foregroundStyle(dim)
            .padding(.top, 10)
    }

    private func figure(_ number: String, unit: String, size: CGFloat) -> Text {
        Text(verbatim: number).font(.custom(CupHero.fontName, fixedSize: size))
            + Text(verbatim: unit).font(AppFont.pretendardFixed(size * 0.5, .bold))
    }

    private func percent(_ part: Double, of whole: Double) -> Int {
        whole > 0 ? Int((part / whole * 100).rounded()) : 0
    }

    /// 사진을 씌운 Anton 숫자. 글자 모양으로 사진을 오려 낸다.
    private func photoNumber(_ number: String, size: CGFloat) -> some View {
        let text = Text(verbatim: number).font(.custom(CupHero.fontName, fixedSize: size))
        return text
            .hidden()
            .overlay { PhotoFill(side: side).mask { text } }
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: number))
    }

    /// 섹션의 큰 강조 숫자 한 줄: 사진 숫자 + 단위, 오른쪽에 붙는 이름(있으면).
    private func hero(
        _ number: String, unit: String, of total: String? = nil, title: String? = nil, detail: Text? = nil
    ) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 6) {
            photoNumber(number, size: number.count > 3 ? 84 : 112)
            if let total {
                Text(verbatim: total)
                    .font(.custom(CupHero.fontName, fixedSize: 30))
                    .foregroundStyle(dim)
            }
            Text(verbatim: unit)
                .font(AppFont.pretendardFixed(18, .extraBold))
            Spacer(minLength: 8)
            if title != nil || detail != nil {
                VStack(alignment: .trailing, spacing: 2) {
                    if let title {
                        Text(verbatim: title)
                            .font(AppFont.pretendardFixed(16, .extraBold))
                            .lineLimit(1)
                    }
                    if let detail {
                        detail
                            .font(AppFont.pretendardFixed(12, .regular))
                            .foregroundStyle(dim)
                            .lineLimit(1)
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .padding(.top, 10)
        .accessibilityElement(children: .combine)
    }

    // MARK: - 많이 먹은 음료

    @ViewBuilder
    private var topDrinks: some View {
        if let first = digest.top.first {
            let meta = first.brand.isEmpty
                ? Text("\(first.cups)잔")
                : Text("\(first.brand) · \(first.cups)잔")
            VStack(spacing: 0) {
                hero(
                    Amount.number(first.amount.rounded()), unit: side.unit, title: first.name,
                    detail: meta + Text(verbatim: " · \(percent(first.amount, of: digest.total))%")
                )
                ForEach(Array(digest.top.enumerated().dropFirst()), id: \.offset) { index, drink in
                    drinkRow(rank: index + 1, drink: drink)
                        .overlay(alignment: .top) { if index > 1 { faint.frame(height: 1) } }
                }
            }
            .padding(.top, 6)
        } else {
            empty
        }
    }

    private func drinkRow(rank: Int, drink: MonthDigest.Drink) -> some View {
        let share = digest.total > 0 ? drink.amount / digest.total : 0
        let meta = drink.brand.isEmpty ? Text("\(drink.cups)잔") : Text("\(drink.brand) · \(drink.cups)잔")
        return VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Text(verbatim: "\(rank)")
                    .font(.custom(CupHero.fontName, fixedSize: 26))
                    .foregroundStyle(dim)
                    .frame(width: 30, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: drink.name)
                        .font(AppFont.pretendardFixed(16, .bold))
                        .lineLimit(1)
                    meta
                        .font(AppFont.pretendardFixed(12, .regular))
                        .foregroundStyle(dim)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 0) {
                    figure(Amount.number(drink.amount.rounded()), unit: side.unit, size: 22)
                    Text(verbatim: "\(percent(drink.amount, of: digest.total))%")
                        .font(AppFont.pretendardFixed(12, .regular))
                        .foregroundStyle(dim)
                }
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    faint
                    hi.frame(width: proxy.size.width * share)
                }
            }
            .frame(height: 3)
            .padding(.leading, 40)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    // MARK: - 시간대

    private func slotName(_ slot: MonthDigest.Slot) -> Text {
        switch slot {
        case .morning: return Text("아침")
        case .lunch: return Text("점심")
        case .afternoon: return Text("오후")
        case .evening: return Text("저녁")
        }
    }

    @ViewBuilder
    private var slots: some View {
        if digest.total == 0 {
            empty
        } else {
            let top = digest.slots.indices.max { digest.slots[$0] < digest.slots[$1] } ?? 0
            let topShare = max(digest.slots[top] / digest.total, 0.0001)
            VStack(alignment: .leading, spacing: 0) {
                if side == .caffeine {
                    hero("\(percent(digest.late, of: digest.total))", unit: "%", title: String(localized: "오후 2시 이후"))
                }
                // 네 칸 같은 폭. 칸마다 숫자(바닥 맞춤) · 자기 막대 · 이름이 같은 세로줄에 선다.
                HStack(alignment: .top, spacing: 10) {
                    ForEach(MonthDigest.Slot.allCases, id: \.rawValue) { slot in
                        let on = slot.rawValue == top
                        let share = digest.slots[slot.rawValue] / digest.total
                        let label = "\(percent(digest.slots[slot.rawValue], of: digest.total))%"
                        VStack(alignment: .leading, spacing: 0) {
                            Group {
                                if on {
                                    photoNumber(label, size: 36)
                                } else {
                                    Text(verbatim: label).font(.custom(CupHero.fontName, fixedSize: 20))
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 40, alignment: .bottomLeading)
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    faint
                                    Group {
                                        if on { PhotoFill(side: side) } else { lo }
                                    }
                                    .frame(width: proxy.size.width * share / topShare)
                                }
                            }
                            .frame(height: 8)
                            .padding(.top, 8)
                            .padding(.bottom, 6)
                            slotName(slot)
                                .font(AppFont.pretendardFixed(12, on ? .bold : .regular))
                                .foregroundStyle(on ? fg : dim)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.top, 14)
            }
        }
    }

    // MARK: - 막대(요일·6개월)

    private func bars(values: [Double?], labels: [String], highlight: Int?) -> some View {
        let peak = max(limit * 1.15, values.compactMap { $0 }.max() ?? 0)
        let scale: CGFloat = 0.82
        let height: CGFloat = 150
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                DashedRule().stroke(fg.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .frame(width: 16, height: 1.5)
                Text("하루 기준 \(Amount.number(limit))\(side.unit)")
                    .font(AppFont.pretendardFixed(11, .semibold))
                    .foregroundStyle(dim)
            }
            .padding(.top, 16)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(values.indices, id: \.self) { index in
                    let on = index == highlight
                    VStack(spacing: 4) {
                        Spacer(minLength: 0)
                        if let value = values[index] {
                            Text(verbatim: Amount.number(value.rounded()))
                                .font(AppFont.pretendardFixed(11, .bold))
                                .foregroundStyle(on ? fg : dim)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Group {
                                if on { PhotoFill(side: side) } else { lo }
                            }
                            .frame(height: peak > 0 ? height * scale * value / peak : 0)
                        } else {
                            Text(verbatim: "–")
                                .font(AppFont.pretendardFixed(11, .bold))
                                .foregroundStyle(dim)
                            DashedRule().stroke(lo, style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                                .frame(height: 2)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        values[index].map { Text("\(labels[index]), \(Amount.number($0.rounded())) \(side.unit)") }
                            ?? Text("\(labels[index]), 기록 없음")
                    )
                }
            }
            .frame(height: height)
            .overlay(alignment: .bottom) {
                if peak > 0 {
                    DashedRule().stroke(fg.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .frame(height: 1.5)
                        .padding(.bottom, height * scale * limit / peak)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .padding(.top, 10)
            HStack(spacing: 8) {
                ForEach(labels.indices, id: \.self) { index in
                    Text(verbatim: labels[index])
                        .font(AppFont.pretendardFixed(12, index == highlight ? .bold : .regular))
                        .foregroundStyle(index == highlight ? fg : dim)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 6)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var weekdays: some View {
        let values = digest.weekdays
        if values.allSatisfy({ $0 == nil }) {
            empty
        } else {
            let top = values.indices.max { (values[$0] ?? -1) < (values[$1] ?? -1) }
            cups(values: values, labels: Self.appCalendar.veryShortStandaloneWeekdaySymbols, highlight: top)
        }
    }

    /// 요일 컵: 컵 하나 = 하루 기준, 평균만큼 찬다(넘치면 가득). 모양은 기준 설정 컵(`SetupCupOutline`·`SetupCupInner`).
    /// 안쪽은 컵 높이의 4%~96% 구간이라 그만큼만 채운다.
    private func cups(values: [Double?], labels: [String], highlight: Int?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                SetupCupOutline()
                    .stroke(dim, style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
                    .frame(width: 10, height: 13)
                Text("하루 기준 \(Amount.number(limit))\(side.unit)")
                    .font(AppFont.pretendardFixed(11, .semibold))
                    .foregroundStyle(dim)
            }
            .padding(.top, 16)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(values.indices, id: \.self) { index in
                    let on = index == highlight
                    let value = values[index]
                    VStack(spacing: 0) {
                        Text(verbatim: value.map { Amount.number($0.rounded()) } ?? "–")
                            .font(AppFont.pretendardFixed(11, .bold))
                            .foregroundStyle(on || (value ?? 0) > limit ? fg : dim)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .padding(.bottom, 4)
                        cup(value: value, on: on)
                            .aspectRatio(3 / 4, contentMode: .fit)
                        Text(verbatim: labels[index])
                            .font(AppFont.pretendardFixed(12, on ? .bold : .regular))
                            .foregroundStyle(on ? fg : dim)
                            .padding(.top, 6)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        value.map { Text("\(labels[index]), \(Amount.number($0.rounded())) \(side.unit)") }
                            ?? Text("\(labels[index]), 기록 없음")
                    )
                }
            }
            .padding(.top, 16)
        }
    }

    private func cup(value: Double?, on: Bool) -> some View {
        GeometryReader { proxy in
            let ratio: Double = limit > 0 ? min((value ?? 0) / limit, 1) : 0
            let level: CGFloat = value == nil ? 0 : proxy.size.height * (0.04 + 0.92 * ratio)
            let line: CGFloat = proxy.size.width * 14 / 300
            let dash: [CGFloat] = value == nil ? [line * 1.6, line * 1.3] : []
            let opacity: Double = value == nil ? 0.25 : (on ? 0.9 : 0.35)
            let liquid: Color = on ? hi : lo
            ZStack(alignment: .bottom) {
                liquid
                    .frame(height: level)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .clipShape(SetupCupInner())
                SetupCupOutline()
                    .stroke(fg.opacity(opacity), style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round, dash: dash))
            }
        }
    }

    // MARK: - 기준 안

    @ViewBuilder
    private var kept: some View {
        if digest.closedDays == 0 {
            empty
        } else {
            VStack(alignment: .leading, spacing: 0) {
                hero("\(digest.keptDays)", unit: String(localized: "일"), of: "/ \(digest.closedDays)")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("기록한 \(digest.closedDays)일 중 \(digest.keptDays)일"))
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        lo
                        PhotoFill(side: side)
                            .frame(width: proxy.size.width * CGFloat(digest.keptDays) / CGFloat(digest.closedDays))
                    }
                }
                .frame(height: 6)
                .padding(.top, 16)
                .accessibilityHidden(true)
                Text("하루 기준 \(Amount.number(limit))\(side.unit)")
                    .font(AppFont.pretendardFixed(12, .regular))
                    .foregroundStyle(dim)
                    .padding(.top, 10)
            }
        }
    }

    // MARK: - 6개월

    private var recent: some View {
        let labels = digest.recent.map { Self.monthLabel($0.month.month) }
        return bars(values: digest.recent.map(\.average), labels: labels, highlight: digest.recent.count - 1)
    }

    private static func monthLabel(_ month: Int) -> String {
        let names = appCalendar.shortStandaloneMonthSymbols
        return names.indices.contains(month - 1) ? names[month - 1] : "\(month)"
    }
}

/// 강조 숫자·막대에 씌우는 접시 사진(각설탕·원두). 프로토 `.pf`/`.pfill`과 같은 처리:
/// 당은 회색에 곱해 결 있는 진회색, 카페인은 갈색 위에 screen으로 얹어 라떼색 원두결. 사진은 260pt로 가운데만 쓴다.
private struct PhotoFill: View {
    let side: CupSide

    var body: some View {
        let isSugar = side == .sugar
        let tint = isSugar
            ? Color(red: 0x6C / 255, green: 0x6C / 255, blue: 0x76 / 255)
            : Color(red: 0x8A / 255, green: 0x5E / 255, blue: 0x36 / 255)
        tint
            .overlay {
                Image(isSugar ? "month-cell-sugar-100" : "month-cell-caffeine-100")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 260, height: 260)
                    .blendMode(isSugar ? .multiply : .screen)
            }
            .clipped()
            .compositingGroup()
            .contrast(isSugar ? 1.35 : 1.15)
            .saturation(isSugar ? 1 : 1.2)
            .accessibilityHidden(true)
    }
}

/// 가로 점선 한 줄(기준선).
private struct DashedRule: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
