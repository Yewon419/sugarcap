import OSLog
import SwiftData
import SwiftUI
import WidgetKit

/// 추이(SPEC §4.3). 2026-10-06 HTML 프로토타입 "식탁 위 일주일"(`design/proto/screens-trends-table.js`) 이식.
/// 대표님 "버튼과 글자가 너무 많다, 척 보고 알아야 한다" → 화면 글자는 기간·제목·큰 숫자·잔 숫자·요일뿐이다.
///  - 지면: 기간 메뉴 + 날짜 → "남긴 당" → 큰 숫자(기록한 날과 오늘 남긴 양의 합) → 지난주 대비(Pro) · 하루 기준.
///  - 장면: 오늘 탭과 같은 벽·식탁. 잔 = 하루(주) 또는 그 주 하루 평균(월, Pro). 캐릭터는 지금 잔 뒤에서 엿본다.
///  - 당↔카페인은 옆으로 밀기 + 점 두 개.
struct TrendsView: View {
    /// 하루 기록 시트의 줄 썸네일 색에만 쓴다.
    let catalog: CatalogIndex

    @Query private var settingsRows: [AppSettings]
    @Query(sort: \Entry.loggedAt, order: .reverse) private var entries: [Entry]
    @Query private var goals: [ReductionGoal]
    @Environment(\.modelContext) private var context
    @Environment(ProStore.self) private var pro
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var side: CupSide = .sugar
    @State private var range: TrendRange = .week
    @State private var paywall: ProFeature?
    @State private var pendingMonth = false
    @State private var dayLog: DayKey?
    @State private var failureMessage: String?
    /// 하루 기준 화면으로 넘어간 쪽(2026-10-05 설정에서 옮겨 옴).
    @State private var limitSide: CupSide?
    /// 당↔카페인 넘기기. 잔 층과 캐릭터 층은 쪽 번호(당 0, 카페인 1)를 따로 움직인다.
    @State private var dragX: CGFloat = 0
    @State private var cupPage: CGFloat = 0
    @State private var castPage: CGFloat = 0
    /// 넘길 때마다 캐릭터 젖힘을 한 번 돌린다. 방향은 화면에서 움직인 쪽(왼쪽 -1, 오른쪽 +1).
    @State private var leanTrigger = 0
    @State private var leanDirection: Double = 1

    private static let logger = Logger(subsystem: "com.sugarcap.app", category: "trends")
    private static let weekdays = ["일", "월", "화", "수", "목", "금", "토"]

    /// 오늘 탭 사진에서 잰 벽·식탁 색(프로토 `trends-table.css`).
    private static let tableTop = Color(red: 0xEC / 255, green: 0xEF / 255, blue: 0xF2 / 255)
    private static let tableEdge = Color(red: 0xE1 / 255, green: 0xE5 / 255, blue: 0xE9 / 255)
    private static let hairline = Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255).opacity(0.18)
    private static let dotOff = Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255).opacity(0.22)
    private static let noRecord = Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255).opacity(0.3)
    /// 잔이 식탁 모서리 위로 올라오는 높이와 그 위 벽 높이.
    private static let wallHeight: CGFloat = 150
    private static let cupRise: CGFloat = 52
    /// `CupCrop` 잔 영역의 세로/가로.
    private static let glassAspect: CGFloat = 1100.0 / 564.0

    private var limits: DailyLimits { settingsRows.first?.limits ?? .default }
    private var boundaryHour: Int { settingsRows.first?.dayBoundaryHour ?? 4 }
    private var limit: Double { side.limit(limits) }
    /// 월 보기는 Pro다(§6). Pro가 끝나면 주로 돌아간다.
    private var isMonth: Bool { range == .month && pro.isPro }

    /// 기준을 넘긴 숫자에만 쓰는 색. 당 = 딸기, 카페인 = 라떼 갈색.
    private static func overColor(_ side: CupSide) -> Color {
        switch side {
        case .sugar: return Color(red: 0xD2 / 255, green: 0x3B / 255, blue: 0x55 / 255)
        case .caffeine: return Color(red: 0x9A / 255, green: 0x5B / 255, blue: 0x2A / 255)
        }
    }

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            let today = DayKey(at: timeline.date, boundaryHour: boundaryHour)
            let tables: [CupSide: TrendTable] = Dictionary(
                uniqueKeysWithValues: CupSide.allCases.map { ($0, makeTable(today: today, side: $0)) }
            )
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        if let table = tables[side] {
                            page(table: table, today: today)
                        }
                        Spacer(minLength: 32)
                        scene(tables: tables, width: proxy.size.width)
                    }
                    .frame(minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
                .simultaneousGesture(sideDrag(width: proxy.size.width))
                // 식탁 색이 홈 인디케이터 밑까지 이어지게 한다.
                .background {
                    VStack(spacing: 0) {
                        CupView.wallColor
                        Self.tableTop.frame(height: proxy.safeAreaInsets.bottom + 1)
                    }
                    .ignoresSafeArea()
                }
            }
            .onAppear(perform: applyScreenshotArguments)
        }
        .sheet(item: $paywall, onDismiss: {
            // 구매하고 닫히면 누르려던 월 보기로 바로 넘어간다(§6 "구매 후 그 화면으로").
            if pro.isPro, pendingMonth { range = .month }
            pendingMonth = false
        }) { feature in
            PaywallView(feature: feature)
        }
        .sheet(item: $dayLog) { day in
            let today = DayKey(at: Date(), boundaryHour: boundaryHour)
            DayLogSheet(
                day: day,
                isToday: day == today,
                entries: entries.filter { $0.dayKey(boundaryHour: boundaryHour) == day },
                limits: limits,
                catalog: catalog,
                onDelete: delete
            )
        }
        .navigationDestination(item: $limitSide) { side in
            LimitDetailView(side: side)
        }
        .alert(failureMessage ?? "", isPresented: Binding(get: { failureMessage != nil }, set: { if !$0 { failureMessage = nil } })) {
            Button("확인", role: .cancel) {}
        }
    }

    private func makeTable(today: DayKey, side: CupSide) -> TrendTable {
        let limit = side.limit(limits)
        if isMonth {
            return TrendTable.month(entries: entries, boundaryHour: boundaryHour, today: today, side: side, limit: limit)
        }
        return TrendTable.week(entries: entries, boundaryHour: boundaryHour, today: today, side: side, limit: limit)
    }

    // MARK: - 지면

    /// 매거진 지면처럼: 머리(기간·날짜) + 검은 가는 선 → 제목 → 바로 아래 큰 숫자 → 가는 선 + 한 줄.
    /// 2026-10-06 대표님 "남긴 당 아래 붙게": 남는 공간은 지면과 장면 사이로 간다.
    private func page(table: TrendTable, today: DayKey) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            masthead(table: table, today: today)
            Text("남긴 \(side.label)")
                .font(AppFont.pretendard(34, .extraBold, relativeTo: .largeTitle))
                .tracking(AppFont.displayTracking(for: 34))
                .foregroundStyle(Color.ink)
                .padding(.top, 18)
                .accessibilityAddTraits(.isHeader)
            figure(total: table.total)
                .padding(.top, 4)
            deck(today: today)
                .padding(.top, 22)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    private func masthead(table: TrendTable, today: DayKey) -> some View {
        HStack(spacing: 8) {
            periodMenu(today: today)
            Spacer(minLength: 8)
            Text("\(table.first.month).\(table.first.day) – \(table.last.month).\(table.last.day)")
                .font(AppFont.pretendard(13, .medium, relativeTo: .footnote))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.ink).frame(height: 1)
        }
    }

    /// 주↔월. 무료가 월을 고르면 주에 머물고 페이월을 연다.
    private func periodMenu(today: DayKey) -> some View {
        let selection = Binding<TrendRange>(
            get: { isMonth ? .month : .week },
            set: { newValue in
                if newValue == .month, !pro.isPro {
                    pendingMonth = true
                    paywall = .monthlyTrends
                } else {
                    range = newValue
                }
            }
        )
        let monthLabel = "\(today.month)월"
        return Menu {
            Picker("기간", selection: selection) {
                Text("이번 주").tag(TrendRange.week)
                Text(pro.isPro ? monthLabel : "\(monthLabel) · Pro").tag(TrendRange.month)
            }
        } label: {
            HStack(spacing: 6) {
                Text(isMonth ? monthLabel : "이번 주")
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .font(AppFont.pretendard(15, .bold, relativeTo: .subheadline))
            .foregroundStyle(Color.ink)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("기간")
        .accessibilityValue(isMonth ? monthLabel : "이번 주")
        .accessibilityIdentifier("trend-range")
    }

    /// 단위는 숫자 어깨 위. 자리 수가 늘면 글자를 줄여 한 줄에 둔다.
    private func figure(total: Double) -> some View {
        let text = Amount.number(total.rounded())
        let size = Self.figureSize(digits: text.count)
        return HStack(alignment: .top, spacing: 6) {
            Text(text)
                .font(AppFont.pretendardFixed(size, .extraBold))
                .tracking(-0.045 * size)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                // 음수 자간은 마지막 글자 뒤에도 붙어 끝자리가 단위에 덮인다. 줄인 만큼 돌려준다.
                .padding(.trailing, 0.045 * size)
                // 글꼴 위아래 여백(숫자 높이의 약 1/4씩)을 프로토 줄 높이 0.9만큼 걷어 낸다. CI 스크린샷 실측(2026-10-06).
                .padding(.top, -0.18 * size)
                .padding(.bottom, -0.15 * size)
                .contentTransition(.numericText())
            Text(side.unit)
                .font(AppFont.pretendard(22, .bold, relativeTo: .title2))
                .padding(.top, size * 0.03)
        }
        .foregroundStyle(Color.ink)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("남긴 \(side.label) \(text) \(side.unit)")
        .accessibilityIdentifier("trend-total")
    }

    private static func figureSize(digits: Int) -> CGFloat {
        switch digits {
        case ...2: return 150
        case 3: return 124
        case 4...5: return 100
        default: return 80
        }
    }

    /// 지면 끝줄: 왼쪽 지난주 비교(Pro), 오른쪽 하루 기준. 비교가 없으면 기준만 오른쪽에 남는다.
    private func deck(today: DayKey) -> some View {
        HStack(spacing: 12) {
            if let note = compareNote(today: today) {
                note
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("trend-compare")
            } else {
                Spacer(minLength: 0)
            }
            limitLink
        }
        .font(AppFont.pretendard(15, .regular, relativeTo: .subheadline))
        .foregroundStyle(.secondary)
        .frame(minHeight: 44)
        .overlay(alignment: .top) {
            Rectangle().fill(Self.hairline).frame(height: 1)
        }
    }

    /// 큰 숫자가 "남긴 양"이라 비교도 남긴 양으로 한다.
    private func compareNote(today: DayKey) -> Text? {
        guard pro.isPro, !isMonth,
              let diff = TrendTable.weekChange(entries: entries, boundaryHour: boundaryHour, today: today, side: side, limit: limit)
        else { return nil }
        let rounded = diff.rounded()
        guard rounded != 0 else { return Text("지난주만큼 남겼어요") }
        let amount = Text("\(Amount.number(abs(rounded)))\(side.unit) \(rounded > 0 ? "더" : "덜")")
            .font(AppFont.pretendard(15, .bold, relativeTo: .subheadline))
            .foregroundStyle(Color.ink)
        return Text("지난주보다 \(amount) 남겼어요")
    }

    /// 하루 기준(2026-10-05 설정에서 옮겨 옴). 큰 숫자가 이 기준에서 남긴 양이라 바로 아래 끝줄에 둔다.
    private var limitLink: some View {
        let isReducing = goals.contains { $0.side == side.rawValue }
        return Button {
            limitSide = side
        } label: {
            HStack(spacing: 6) {
                Text(isReducing ? "줄이는 중" : "하루 기준")
                Text("\(Amount.number(limit)) \(side.unit)")
                    .font(AppFont.pretendard(15, .bold, relativeTo: .subheadline))
                    .monospacedDigit()
                    .foregroundStyle(Color.ink)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .lineLimit(1)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(side.label) 하루 기준 \(Amount.number(limit)) \(side.unit)\(isReducing ? ", 줄이는 중" : "")")
        .accessibilityIdentifier("trend-limit")
    }

    // MARK: - 장면

    /// 벽(캐릭터) 위로 잔 끝이 올라오고, 잔 몸통부터 식탁이다. 점은 식탁 위.
    /// 당↔카페인을 넘길 때 글자는 제자리에서 바뀌고 그림만 옆으로 밀린다(2026-10-06 대표님 "페이드 말고 슬라이드").
    /// 캐릭터 층은 잔 층보다 빨리, 더 탱탱한 스프링으로 움직여 앞서 달려 나가고 멈출 때 통 튄다.
    private func scene(tables: [CupSide: TrendTable], width: CGFloat) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: Self.wallHeight - Self.cupRise)
            pager(width: width, page: cupPage, drag: dragX) { pageSide in
                cupRow(table: tables[pageSide], side: pageSide)
            }
            sideDots
                .padding(.top, 10)
                .padding(.bottom, 20)
        }
        .background(alignment: .top) {
            VStack(spacing: 0) {
                pager(width: width, page: castPage, drag: dragX * castLead) { pageSide in
                    characterWall(table: tables[pageSide], side: pageSide, width: width)
                }
                .frame(height: Self.wallHeight)
                .clipped()
                Self.tableTop
                    .overlay(alignment: .top) { Self.tableEdge.frame(height: 1) }
            }
        }
    }

    /// 캐릭터가 손가락보다 앞서 가는 비율. 동작 줄이기면 잔과 같이 움직인다.
    private var castLead: CGFloat { reduceMotion ? 1 : 1.3 }

    /// 두 쪽을 옆으로 나란히 놓고 지금 쪽만 화면에 둔다. 안 보이는 쪽은 보이스오버에서 뺀다.
    private func pager<Content: View>(
        width: CGFloat, page: CGFloat, drag: CGFloat, @ViewBuilder content: @escaping (CupSide) -> Content
    ) -> some View {
        HStack(spacing: 0) {
            ForEach(CupSide.allCases) { pageSide in
                content(pageSide)
                    .frame(width: width)
                    .accessibilityHidden(pageSide != side)
            }
        }
        .frame(width: width, alignment: .leading)
        .offset(x: -page * width + drag)
    }

    @ViewBuilder
    private func cupRow(table: TrendTable?, side pageSide: CupSide) -> some View {
        if let table {
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(Array(table.cups.enumerated()), id: \.element.id) { index, cup in
                    cupColumn(cup, index: index, side: pageSide)
                }
            }
            .padding(.horizontal, 8)
        }
    }

    /// 캐릭터는 지금 잔 뒤에 선다. 몸 가장자리를 그 잔 가운데에 맞추고, 왼쪽 절반이면 반대쪽으로 비켜 선다.
    /// 식탁 모서리 아래는 잘린다(식탁 뒤에 서 있다).
    @ViewBuilder
    private func characterWall(table: TrendTable?, side pageSide: CupSide, width: CGFloat) -> some View {
        if let table {
            let count = CGFloat(max(table.cups.count, 1))
            let at = CGFloat(table.nowIndex)
            let cupX: CGFloat = 8 + (width - 16) * (at + 0.5) / count
            let height: CGFloat = pageSide == .sugar ? 190 : 168
            let sink: CGFloat = pageSide == .sugar ? 64 : 40
            let fromLeft = at < count / 2
            let boxWidth: CGFloat = fromLeft ? max(0, width - cupX + 4) : cupX + 4
            CastMember(
                asset: pageSide.characterAsset, height: height, dragLean: dragLean(width: width),
                direction: leanDirection, trigger: leanTrigger, animates: !reduceMotion
            )
            .frame(width: boxWidth, alignment: fromLeft ? .leading : .trailing)
            .frame(maxWidth: .infinity, alignment: fromLeft ? .trailing : .leading)
            .frame(height: Self.wallHeight, alignment: .top)
            .offset(y: Self.wallHeight - height + sink)
            .accessibilityHidden(true)
        }
    }

    /// 끄는 동안 캐릭터는 끌려가듯 뒤로 젖혀진다(도). 왼쪽으로 끌면 머리가 오른쪽에 남는다.
    private func dragLean(width: CGFloat) -> Double {
        guard !reduceMotion, width > 0 else { return 0 }
        return min(8, max(-8, Double(-dragX / width) * 14))
    }

    @ViewBuilder
    private func cupColumn(_ cup: TableCup, index: Int, side pageSide: CupSide) -> some View {
        if isMonth {
            cupFace(cup, label: "\(index + 1)주", width: 58, dimmed: !cup.recorded || cup.isFuture, side: pageSide)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(index + 1)주차 \(cupDescription(cup, average: true, side: pageSide))")
        } else {
            let weekday = Self.weekdays[cup.day.weekday() - 1]
            Button {
                dayLog = cup.day
            } label: {
                cupFace(cup, label: cup.isNow ? "오늘" : weekday, width: 50, dimmed: !cup.recorded, side: pageSide)
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(weekday)요일 \(cupDescription(cup, average: false, side: pageSide))")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("shelf-\(cup.day.rawValue)")
        }
    }

    private func cupDescription(_ cup: TableCup, average: Bool, side pageSide: CupSide) -> String {
        guard cup.recorded else { return "기록 없음" }
        let limit = pageSide.limit(limits)
        let over = cup.used - limit
        if over > 0 { return "기준보다 \(Amount.number(over.rounded())) \(pageSide.unit) 더 마심" }
        return "\(average ? "하루 평균 " : "")남은 \(pageSide.label) \(Amount.number(max(0, limit - cup.used).rounded())) \(pageSide.unit)"
    }

    private func cupFace(_ cup: TableCup, label: String, width: CGFloat, dimmed: Bool, side pageSide: CupSide) -> some View {
        let limit = pageSide.limit(limits)
        let left = max(0, limit - cup.used)
        let step = cup.recorded ? CupLevel.step(remaining: left, limit: limit) : 0
        return VStack(spacing: 2) {
            CupCrop(asset: CupLevel.cutoutName(setID: pageSide.cupSetID, step: step))
                .frame(width: width, height: width * Self.glassAspect)
                .opacity(dimmed ? 0.4 : 1)
            amountText(cup, left: left, over: cup.used - limit, side: pageSide)
                .padding(.top, 8)
            Text(label)
                .font(AppFont.pretendard(12, cup.isNow ? .semibold : .regular, relativeTo: .caption))
                .foregroundStyle(cup.isNow ? Color.ink : Color.secondary)
                .lineLimit(1)
                .frame(minHeight: 18)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    /// 잔 아래 숫자: 남긴 양, 넘겼으면 +넘긴 양(색), 기록 없으면 -. 단위는 큰 숫자에만 붙인다.
    private func amountText(_ cup: TableCup, left: Double, over: Double, side pageSide: CupSide) -> some View {
        Group {
            if !cup.recorded {
                Text("-")
                    .font(AppFont.pretendard(17, .medium, relativeTo: .body))
                    .foregroundStyle(Self.noRecord)
            } else if over > 0 {
                Text("+\(Amount.number(over.rounded()))")
                    .font(AppFont.pretendard(17, .bold, relativeTo: .body))
                    .foregroundStyle(Self.overColor(pageSide))
            } else {
                Text(Amount.number(left.rounded()))
                    .font(AppFont.pretendard(17, .bold, relativeTo: .body))
                    .foregroundStyle(Color.ink)
            }
        }
        .monospacedDigit()
        .tracking(-0.3)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    // MARK: - 당↔카페인

    private var sideDots: some View {
        HStack(spacing: 0) {
            ForEach(CupSide.allCases) { cupSide in
                Button {
                    settle(on: cupSide)
                } label: {
                    Circle()
                        .fill(cupSide == side ? Color.ink : Self.dotOff)
                        .frame(width: 7, height: 7)
                        .frame(width: 30, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(cupSide.label)
                .accessibilityAddTraits(cupSide == side ? .isSelected : [])
                .accessibilityIdentifier("trend-side-\(cupSide.rawValue)")
            }
        }
    }

    /// 오늘 탭처럼 손가락을 따라 밀린다. 왼쪽으로 밀면 카페인, 오른쪽으로 밀면 당. 끝에서는 고무줄처럼 덜 밀린다.
    private func sideDrag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let pullingPastEdge = (side == .sugar && value.translation.width > 0)
                    || (side == .caffeine && value.translation.width < 0)
                dragX = pullingPastEdge ? value.translation.width * 0.25 : value.translation.width
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else {
                    settle(on: side)
                    return
                }
                let travel = value.predictedEndTranslation.width
                settle(on: travel < -width / 3 ? .caffeine : (travel > width / 3 ? .sugar : side))
            }
    }

    /// 잔 층은 오늘 탭과 같은 스프링, 캐릭터 층은 더 빠르고 덜 감쇠된 스프링이라 먼저 도착해 살짝 지나쳤다 선다.
    private func settle(on next: CupSide) {
        let target: CGFloat = next == .sugar ? 0 : 1
        if next != side {
            leanDirection = next == .caffeine ? -1 : 1
            leanTrigger += 1
        }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.25) : .spring(response: 0.45, dampingFraction: 0.86)) {
            side = next
            cupPage = target
            dragX = 0
        }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.25) : .spring(response: 0.36, dampingFraction: 0.7)) {
            castPage = target
        }
    }

    // MARK: - 동작

    private func delete(_ targets: [Entry]) {
        for entry in targets { context.delete(entry) }
        do {
            try context.save()
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            Self.logger.error("기록 삭제 실패: \(String(describing: error), privacy: .public)")
            context.rollback()
            failureMessage = "기록 삭제에 실패했어요. 다시 시도해 주세요."
        }
    }

    /// CI 스크린샷 전용(Debug). `-trendSide caffeine`, `-trendRange month`, `-trendLimit sugar`(하루 기준 화면을 바로 연다).
    private func applyScreenshotArguments() {
        #if DEBUG
        let defaults = UserDefaults.standard
        if defaults.string(forKey: "trendSide") == "caffeine" {
            side = .caffeine
            cupPage = 1
            castPage = 1
        }
        if defaults.string(forKey: "trendRange") == "month" { range = .month }
        if let raw = defaults.string(forKey: "trendLimit"), let limitSide = CupSide(rawValue: raw) { self.limitSide = limitSide }
        #endif
    }
}

enum TrendRange: String, CaseIterable, Identifiable {
    case week
    case month

    var id: String { rawValue }
}

extension DayKey: Identifiable {
    var id: String { rawValue }
}

/// 넘길 때의 캐릭터. 출발하면 끌려가듯 뒤로 젖혀지고 몸이 늘어나며, 도착하면 앞으로 쏠리고 납작해졌다 통 튀며 선다.
/// 그림 한 장을 바닥 기준으로 기울이고 늘리기만 한다(에어브러시·잔상 없음).
private struct CastMember: View {
    let asset: String
    let height: CGFloat
    /// 손가락으로 끄는 동안의 젖힘(도).
    let dragLean: Double
    /// 화면에서 움직인 방향. 왼쪽 -1, 오른쪽 +1.
    let direction: Double
    let trigger: Int
    let animates: Bool

    var body: some View {
        Image(asset)
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .keyframeAnimator(initialValue: CastPose(), trigger: trigger) { view, pose in
                view
                    .scaleEffect(x: animates ? pose.stretch : 1, y: animates ? 1 / pose.stretch : 1, anchor: .bottom)
                    .rotationEffect(.degrees(dragLean + (animates ? pose.lean * direction : 0)), anchor: .bottom)
            } keyframes: { _ in
                // lean은 움직이는 쪽 기준: 음수 = 뒤로 젖힘, 양수 = 앞으로 쏠림.
                KeyframeTrack(\.lean) {
                    CubicKeyframe(-9, duration: 0.12)
                    CubicKeyframe(7, duration: 0.2)
                    SpringKeyframe(0, duration: 0.45, spring: .bouncy)
                }
                KeyframeTrack(\.stretch) {
                    CubicKeyframe(1.07, duration: 0.12)
                    CubicKeyframe(0.94, duration: 0.2)
                    SpringKeyframe(1, duration: 0.45, spring: .bouncy)
                }
            }
    }
}

private struct CastPose {
    var lean: Double = 0
    var stretch: Double = 1
}
