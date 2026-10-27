import SpriteKit
import SwiftUI

/// 추이 월 달력(2026-10-27 이식, 프로토 `design/proto/trends-month-dump.html`). 캐릭터 없는 한 달.
/// 달마다 바뀌는 배경 사진(블러 2) 위 정중앙에 머리("10월 먹은 당") · 요일 · 정사각 격자 · 합계 두 줄. 아래 ◀ ▶로 달을 옮긴다.
/// 칸 = 그날 먹은 양 사진 5단계, 무작위 순서로 하나씩 찍힌다. 칸을 누르면 그날이 든 월~일 주 보기로 간다(대표님 B).
/// 그 위로 면 주인의 보관함(물건·병뚜껑·마음)이 굴러다닌다(`MonthShakerScene`). 격자가 벽이다.
struct MonthTrendsView: View {
    let entries: [Entry]
    let boundaryHour: Int
    let limits: DailyLimits
    let today: DayKey
    let side: CupSide
    let trackedSides: [CupSide]
    /// 보는 달의 1일.
    @Binding var shown: DayKey
    /// 기록이 시작된 달의 1일. 그 앞으로는 못 간다.
    let earliest: DayKey
    let onPickDay: (DayKey) -> Void
    let onPickSide: (CupSide) -> Void
    /// 셰이커에 넣을 보관함(보는 달 기준).
    let inventory: MonthInventory

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 칸 번호 → 찍히는 차례. `filledFor`가 지금 달이 아니면 아직 안 찍었다.
    @State private var rank: [Int: Int] = [:]
    @State private var revealed = 0
    @State private var filledFor: String?
    @State private var shaker: MonthShakerScene?
    /// 격자 자리(`shakerSpace` 좌표). 셰이커 벽으로 넘긴다.
    @State private var gridFrame: CGRect = .zero
    private static let shakerSpace = "monthShaker"

    /// 프로토 `.mast --F: 64px`, h1 = F × 1.02.
    private static let titleSize: CGFloat = 64 * 1.02
    private static let kainBrown = Color(red: 0x3B / 255, green: 0x23 / 255, blue: 0x14 / 255)

    private var isSugar: Bool { side == .sugar }
    /// 글자색. 당 면은 흰 배경이라 먹색, 카페인 면은 흰색.
    private var textColor: Color { isSugar ? Color.ink : .white }
    private var lineColor: Color { isSugar ? Color.ink.opacity(0.32) : Color.white.opacity(0.85) }
    private var monthKey: String { "\(side.rawValue)-\(shown.rawValue)" }

    var body: some View {
        let page = MonthPage.make(
            entries: entries, boundaryHour: boundaryHour, year: shown.year, month: shown.month, today: today, side: side
        )
        let change = MonthStats.change(
            entries: entries, boundaryHour: boundaryHour, year: shown.year, month: shown.month, today: today, side: side
        )
        ZStack(alignment: .bottom) {
            block(page: page, change: change)
                .padding(.horizontal, 30)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay { shakerLayer }
                .background { photo }
                .coordinateSpace(.named(Self.shakerSpace))
                .ignoresSafeArea()
            steps
        }
        .contentShape(Rectangle())
        .simultaneousGesture(sideSwipe)
        .task(id: monthKey) { await fill(page) }
        .onAppear {
            if shaker == nil { shaker = MonthShakerScene() }
            feedShaker()
            shaker?.startMotion()
        }
        .onDisappear { shaker?.stopMotion() }
        .onChange(of: inventory) { feedShaker() }
        .onChange(of: side) { feedShaker() }
        .onChange(of: gridFrame) { shaker?.setGrid(gridFrame) }
    }

    // MARK: - 셰이커

    @ViewBuilder
    private var shakerLayer: some View {
        if let shaker {
            SpriteView(scene: shaker, options: [.allowsTransparency])
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func feedShaker() {
        guard let shaker else { return }
        shaker.setGrid(gridFrame)
        shaker.show(ShakerGift.list(inventory), side: side, reduceMotion: reduceMotion)
    }

    // MARK: - 배경

    private var photo: some View {
        Image(String(format: "month-bg-%@-%02d", side.rawValue, shown.month))
            .resizable()
            .scaledToFill()
            .blur(radius: 2, opaque: true)
            .overlay { if !isSugar { Color.white.opacity(0.08) } }
            .clipped()
            .accessibilityHidden(true)
    }

    // MARK: - 덩어리

    private func block(page: MonthPage, change: Int?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            masthead
                .padding(.bottom, 6)
            weekdayRow
                .padding(.bottom, 5)
            grid(page)
            totals(page: page, change: change)
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
        }
        .foregroundStyle(textColor)
    }

    /// 큰 Anton 숫자 + "월" + "먹은 당"(면 이름만 굵게, 캐릭터 대표색 + 윤곽). 지난해면 해를 붙인다.
    private var masthead: some View {
        let size = Self.titleSize
        let number = Text(verbatim: "\(shown.month)").font(.custom(CupHero.fontName, fixedSize: size * 1.3))
        return HStack(alignment: .lastTextBaseline, spacing: size * 0.27 * 0.35) {
            Text("\(number)월")
                .font(AppFont.pretendardFixed(size * 0.58, .black))
            subtitle(size: size * 0.27)
        }
        .lineLimit(1)
        .offset(x: -8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(shown.month)월 먹은 \(side.label)"))
        .accessibilityAddTraits(.isHeader)
    }

    /// 프로토 `-webkit-text-stroke: 3px; paint-order: stroke fill` = 글자 바깥 1.5 pt 윤곽. 같은 줄을 8방향으로 밀어 깐다.
    private func subtitle(size: CGFloat) -> some View {
        let labelColor = isSugar ? Color.white : Self.kainBrown
        let strokeColor = isSugar ? Color.ink : Color.white
        let year = shown.year == today.year ? Text(verbatim: "") : Text(verbatim: " · \(shown.year)")
        let face = Text("먹은 \(Text(side.label).font(AppFont.pretendardFixed(size, .extraBold)).foregroundColor(labelColor))") + year
        let edge = Text("먹은 \(Text(side.label).font(AppFont.pretendardFixed(size, .extraBold)).foregroundColor(strokeColor))") + year
        return ZStack(alignment: .leading) {
            ForEach(0..<8, id: \.self) { index in
                let angle: Double = Double(index) * Double.pi / 4
                edge
                    .foregroundStyle(Color.clear)
                    .offset(x: 1.5 * cos(angle), y: 1.5 * sin(angle))
            }
            face
        }
        .font(AppFont.pretendardFixed(size, .medium))
        .tracking(-0.01 * size)
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"], id: \.self) { name in
                Text(verbatim: name)
                    .frame(maxWidth: .infinity)
            }
        }
        .font(AppFont.pretendardFixed(12, .thin))
        .opacity(0.85)
        .shadow(color: isSugar ? .clear : .black.opacity(0.28), radius: 1.5, y: 1)
        .accessibilityHidden(true)
    }

    // MARK: - 격자

    private func grid(_ page: MonthPage) -> some View {
        let total = Int((Double(page.leadingBlanks + page.cells.count) / 7).rounded(.up)) * 7
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        return LazyVGrid(columns: columns, spacing: 0) {
            ForEach(0..<total, id: \.self) { slot in
                let index = slot - page.leadingBlanks
                if index >= 0, index < page.cells.count {
                    dayCell(page.cells[index], index: index)
                } else {
                    gridSquare
                }
            }
        }
        .overlay(alignment: .top) { lineColor.frame(height: 1) }
        .overlay(alignment: .leading) { lineColor.frame(width: 1) }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.shakerSpace)) } action: { gridFrame = $0 }
        .id(monthKey)
    }

    /// 칸 하나의 틀: 정사각 + 오른쪽·아래 선.
    private var gridSquare: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay(alignment: .trailing) { lineColor.frame(width: 1) }
            .overlay(alignment: .bottom) { lineColor.frame(height: 1) }
    }

    private func dayCell(_ cell: MonthPage.Cell, index: Int) -> some View {
        let step = cell.used.map { MonthPage.step(used: $0, limit: side.limit(limits)) }
        let visible = step != nil && isRevealed(index)
        let numberColor: Color = isSugar || step != nil ? Color.ink : .white
        return Button {
            onPickDay(cell.day)
        } label: {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let step, visible {
                        Image("month-cell-\(side.rawValue)-\(step)")
                            .resizable()
                            .scaledToFill()
                    }
                }
                .clipped()
                .overlay(alignment: .topLeading) {
                    Text(verbatim: "\(cell.day.day)")
                        .font(AppFont.pretendardFixed(12, .thin))
                        .foregroundStyle(numberColor)
                        .opacity(cell.isFuture ? 0.45 : 1)
                        .padding(.top, 2)
                        .padding(.leading, 4)
                }
                .overlay {
                    if cell.isToday { Rectangle().strokeBorder(Color.white, lineWidth: 2) }
                }
                .overlay(alignment: .trailing) { lineColor.frame(width: 1) }
                .overlay(alignment: .bottom) { lineColor.frame(height: 1) }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(cell.isFuture)
        .accessibilityLabel(cellLabel(cell))
        .accessibilityIdentifier("month-day-\(cell.day.rawValue)")
    }

    private func cellLabel(_ cell: MonthPage.Cell) -> Text {
        guard let used = cell.used else {
            return cell.isFuture ? Text("\(cell.day.day)일") : Text("\(cell.day.day)일, 기록 없음")
        }
        return Text("\(cell.day.day)일, \(Amount.number(used.rounded())) \(side.unit)")
    }

    private func isRevealed(_ index: Int) -> Bool {
        if reduceMotion { return true }
        guard filledFor == monthKey else { return false }
        // 찍는 도중 새로 기록한 칸은 바로 보인다.
        return rank[index].map { $0 < revealed } ?? true
    }

    /// 칸은 무작위 순서로 하나씩 툭툭 찍힌다(페이드 없음, 프로토 `fill`).
    private func fill(_ page: MonthPage) async {
        let filled = page.cells.indices.filter { page.cells[$0].used != nil }
        rank = Dictionary(uniqueKeysWithValues: filled.shuffled().enumerated().map { ($0.element, $0.offset) })
        revealed = 0
        filledFor = monthKey
        guard !reduceMotion, !filled.isEmpty else {
            revealed = filled.count
            return
        }
        try? await Task.sleep(for: .milliseconds(200))
        for count in 1...filled.count {
            guard !Task.isCancelled else { return }
            revealed = count
            try? await Task.sleep(for: .milliseconds(45))
        }
    }

    // MARK: - 합계

    /// 왼쪽 실물 환산(각설탕 · 에스프레소), 오른쪽 지난달 하루 평균 대비(이번 달은 지난달 이맘때까지).
    private func totals(page: MonthPage, change: Int?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 22) {
            thingsLine(page: page)
            if let change { compareLine(change) }
        }
        .font(AppFont.pretendardFixed(11, .semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .shadow(color: isSugar ? .clear : .black.opacity(0.28), radius: 1.5, y: 1)
    }

    private func figure(_ number: String, unit: String) -> Text {
        Text(verbatim: number).font(.custom(CupHero.fontName, fixedSize: 22)).foregroundColor(textColor)
            + Text(verbatim: unit).font(AppFont.pretendardFixed(11, .bold)).foregroundColor(textColor)
    }

    private func thingsLine(page: MonthPage) -> Text {
        let count = Amount.number(Double(MonthStats.things(eaten: page.eaten, side: side)))
        switch side {
        case .sugar:
            return Text("각설탕 \(figure(count, unit: String(localized: "개")))").foregroundColor(textColor.opacity(0.8))
        case .caffeine:
            return Text("에스프레소 \(figure(count, unit: String(localized: "샷")))").foregroundColor(textColor.opacity(0.8))
        }
    }

    /// 이번 달은 아직 진행 중이라 "~먹는 중", 지난 달은 끝났으니 "~먹음".
    private func compareLine(_ change: Int) -> Text {
        let live = shown.year == today.year && shown.month == today.month
        let percent = figure("\(abs(change))", unit: "%")
        let line: Text
        switch (change.signum(), live) {
        case (-1, true): line = Text("지난달보다 \(percent) 덜 먹는 중")
        case (-1, false): line = Text("지난달보다 \(percent) 덜 먹음")
        case (1, true): line = Text("지난달보다 \(percent) 더 먹는 중")
        case (1, false): line = Text("지난달보다 \(percent) 더 먹음")
        case (_, true): line = Text("지난달과 똑같이 먹는 중")
        default: line = Text("지난달과 똑같이 먹음")
        }
        return line.foregroundColor(textColor.opacity(0.8))
    }

    // MARK: - 아래 줄

    /// ◀ 이전 달 · 면 점 · 다음 달 ▶. 첫 기록 달 앞, 이번 달 뒤로는 못 간다.
    private var steps: some View {
        let canGoBack = shown > earliest
        let canGoForward = shown < DayKey(year: today.year, month: today.month, day: 1)
        return HStack(spacing: 0) {
            stepButton(pointsLeft: true, enabled: canGoBack, label: "이전 달", id: "month-prev") { shown = Self.shift(shown, by: -1) }
            Spacer(minLength: 0)
            sideDots
            Spacer(minLength: 0)
            stepButton(pointsLeft: false, enabled: canGoForward, label: "다음 달", id: "month-next") { shown = Self.shift(shown, by: 1) }
        }
        .padding(.horizontal, 14)
        .foregroundStyle(textColor)
    }

    private func stepButton(
        pointsLeft: Bool, enabled: Bool, label: LocalizedStringKey, id: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            StepTriangle(pointsLeft: pointsLeft)
                .frame(width: 14, height: 16)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    private var sideDots: some View {
        HStack(spacing: 0) {
            ForEach(trackedSides.count > 1 ? trackedSides : []) { cupSide in
                Button {
                    onPickSide(cupSide)
                } label: {
                    Circle()
                        .fill(textColor.opacity(cupSide == side ? 1 : 0.35))
                        .frame(width: 7, height: 7)
                        .frame(width: 30, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(cupSide.label)
                .accessibilityAddTraits(cupSide == side ? .isSelected : [])
                .accessibilityIdentifier("month-side-\(cupSide.rawValue)")
            }
        }
    }

    /// 주 보기처럼 옆으로 밀면 다른 면. 왼쪽으로 밀면 카페인, 오른쪽으로 밀면 당.
    private var sideSwipe: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                let width = value.translation.width
                guard abs(width) > abs(value.translation.height), abs(width) > 60,
                      let index = trackedSides.firstIndex(of: side) else { return }
                let next = min(max(index + (width < 0 ? 1 : -1), 0), trackedSides.count - 1)
                if trackedSides[next] != side { onPickSide(trackedSides[next]) }
            }
    }

    static func shift(_ month: DayKey, by months: Int) -> DayKey {
        let index = month.year * 12 + (month.month - 1) + months
        return DayKey(year: index / 12, month: index % 12 + 1, day: 1)
    }
}

/// 프로토 ◀ ▶ 세모(14×16). 월 달력과 주 보기 머리 줄이 같이 쓴다.
struct StepTriangle: Shape {
    let pointsLeft: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tip = pointsLeft ? rect.minX : rect.maxX
        let back = pointsLeft ? rect.maxX : rect.minX
        path.move(to: CGPoint(x: tip, y: rect.midY))
        path.addLine(to: CGPoint(x: back, y: rect.minY))
        path.addLine(to: CGPoint(x: back, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
