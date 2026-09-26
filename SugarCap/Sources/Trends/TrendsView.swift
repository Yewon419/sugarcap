import OSLog
import SwiftData
import SwiftUI
import WidgetKit

/// 추이 탭(2026-09-26 HTML 프로토타입 확정 = 캐주얼, 대표님 "그래픽으로 캐주얼하고 멋지게"). SPEC §4.3.
/// 기존 그림 자산(컵 사진·방울·캐릭터)만 쓴다. 당·카페인은 단위가 달라 따로 본다.
///  - 주: 영웅 카드(기준 안에서 마신 날 N/7) → 이번 주 컵 선반(누르면 그날 기록) → 준 양 · 지난주 대비(Pro)
///  - 월(Pro): 영웅 카드(이번 달 준 양) → 방울 달력(남긴 만큼 방울이 커진다)
struct TrendsView: View {
    @Query private var settingsRows: [AppSettings]
    @Query(sort: \Entry.loggedAt, order: .reverse) private var entries: [Entry]
    @Environment(\.modelContext) private var context
    @Environment(ProStore.self) private var pro
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var side: CupSide = .sugar
    @State private var range: TrendRange = .week
    @State private var paywall: ProFeature?
    @State private var pendingMonth = false
    @State private var dayLog: DayKey?
    @State private var failureMessage: String?

    private static let logger = Logger(subsystem: "com.sugarcap.app", category: "trends")
    private static let weekdays = ["일", "월", "화", "수", "목", "금", "토"]

    private var limits: DailyLimits { settingsRows.first?.limits ?? .default }
    private var boundaryHour: Int { settingsRows.first?.dayBoundaryHour ?? 4 }
    private var limit: Double { side.limit(limits) }

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            let today = DayKey(at: timeline.date, boundaryHour: boundaryHour)
            ScrollView {
                VStack(spacing: 0) {
                    header
                    if range == .month, pro.isPro {
                        monthContent(today: today)
                    } else {
                        weekContent(today: today)
                    }
                    Color.clear.frame(height: 110)
                }
            }
            .background(background)
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
                onDelete: delete
            )
        }
        .alert(failureMessage ?? "", isPresented: Binding(get: { failureMessage != nil }, set: { if !$0 { failureMessage = nil } })) {
            Button("확인", role: .cancel) {}
        }
    }

    /// 벽 색 단색. 프로토타입의 옅은 물빛 번짐은 에어브러시 계열이라 뺐다(대표님 교정 2026-09-26).
    private var background: some View {
        Color.wall.ignoresSafeArea()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("추이")
                .dateLabel()
                .padding(.top, 8)
            HStack(spacing: 10) {
                Picker("당·카페인", selection: $side) {
                    ForEach(CupSide.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("기간", selection: $range) {
                    ForEach(TrendRange.allCases) { Text(range == $0 || pro.isPro || $0 == .week ? $0.label : "\($0.label) · Pro").tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("trend-range")
                // 월 보기는 Pro다(§6). 무료가 고르면 주 보기로 되돌리고 페이월을 연다.
                .onChange(of: range) { _, newValue in
                    guard newValue == .month, !pro.isPro else { return }
                    range = .week
                    pendingMonth = true
                    paywall = .monthlyTrends
                }
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - 주

    @ViewBuilder
    private func weekContent(today: DayKey) -> some View {
        let week = WeekSummary.make(entries: entries, boundaryHour: boundaryHour, today: today, side: side, limit: limit)
        heroCard(
            kicker: "이번 주 기준 안에서 마신 날",
            number: "\(week.withinDays)", unit: "일", suffix: "/7일",
            caption: week.isGoodWeek
                ? "\(side.characterNameWithGwa) 사이가 쑥쑥 가까워지는 중"
                : "하루 평균 \(Amount.number(week.dailyAverage)) \(side.unit) 마셨어요",
            cheer: week.isGoodWeek
        )
        shelf(week: week, today: today)
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { statCards(week: week, today: today) }
            VStack(spacing: 12) { statCards(week: week, today: today) }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private func heroCard(kicker: String, number: String, unit: String, suffix: String?, caption: String, cheer: Bool) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(kicker).kicker()
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(number)
                        .font(AppFont.pretendardFixed(84, .bold))
                        .tracking(-4.5)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(unit)
                        .heroUnit()
                        .padding(.leading, 2)
                    if let suffix {
                        Text(suffix)
                            .font(AppFont.pretendard(13, .regular, relativeTo: .footnote))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 10)
                    }
                }
                Text(caption)
                    .font(AppFont.pretendard(13, .regular, relativeTo: .footnote))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("trend-hero")

            if !typeSize.isAccessibilitySize {
                CheerCharacter(side: side, isCheering: cheer && !reduceMotion)
                    .padding(.bottom, -28)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 20)
        .frame(minHeight: 196, alignment: .bottom)
        .card(radius: 28)
        .padding(.horizontal, 16)
        .padding(.top, 22)
    }

    private func shelf(week: WeekSummary, today: DayKey) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("이번 주 컵").kicker()
                Spacer()
                Text("컵을 누르면 그날 기록")
                    .font(AppFont.pretendard(11, .regular, relativeTo: .caption2))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(week.days) { point in
                    shelfCup(point, today: today)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .card(radius: 28)
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    private func shelfCup(_ point: TrendPoint, today: DayKey) -> some View {
        let used = point.value(side)
        let left = max(0, limit - used)
        let over = used - limit
        let isToday = point.day == today
        let hasRecord = used > 0 || entries.contains { $0.dayKey(boundaryHour: boundaryHour) == point.day }
        let recorded = hasRecord || isToday
        let weekday = Self.weekdays[point.day.weekday() - 1]

        return Button {
            dayLog = point.day
        } label: {
            VStack(spacing: 8) {
                ZStack(alignment: .top) {
                    ShelfGlass(asset: CupLevel.assetName(setID: side.cupSetID, step: recorded ? CupLevel.step(remaining: left, limit: limit) : 0))
                        .opacity(recorded ? 1 : 0.35)
                        .offset(y: isToday ? -4 : 0)
                        .padding(.top, 16)
                    if over > 0 {
                        Text("+\(Amount.number(over))")
                            .font(AppFont.pretendard(10, .bold, relativeTo: .caption2))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(white: 0.11), in: Capsule())
                    }
                }
                Text(weekday)
                    .font(AppFont.pretendard(12, isToday ? .bold : .regular, relativeTo: .caption))
                    .foregroundStyle(isToday ? Color.white : Color.secondary)
                    .padding(.horizontal, isToday ? 8 : 0)
                    .padding(.vertical, 1)
                    .background(isToday ? Color.accentColor : Color.clear, in: Capsule())
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel("\(weekday)요일 남은 \(side.label) \(Amount.number(left)) \(side.unit)")
        .accessibilityIdentifier("shelf-\(point.day.rawValue)")
    }

    @ViewBuilder
    private func statCards(week: WeekSummary, today: DayKey) -> some View {
        HStack(spacing: 12) {
            Image(side.dropAsset)
                .resizable()
                .scaledToFit()
                .frame(width: 52, height: 52)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                statNumber(Amount.number(week.given), unit: side.unit)
                Text("이번 주 \(side.characterName)에게 준 \(side.label)")
                    .statLabel()
            }
            Spacer(minLength: 0)
        }
        .statCard()
        .accessibilityElement(children: .combine)

        deltaCard(today: today)
    }

    @ViewBuilder
    private func deltaCard(today: DayKey) -> some View {
        if !pro.isPro {
            Button {
                paywall = .weekOverWeek
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 13))
                    Text("지난주와\n비교하기")
                        .statLabel()
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .statCard()
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityIdentifier("trend-delta-locked")
        } else {
            let current = WeekSummary.make(entries: entries, boundaryHour: boundaryHour, today: today, side: side, limit: limit)
            let previous = WeekSummary.make(entries: entries, boundaryHour: boundaryHour, today: today, side: side, limit: limit, weeksAgo: 1)
            if previous.dailyAverage == 0 {
                Text("지난주 기록이\n없어요")
                    .statLabel()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .statCard()
            } else {
                let diff = current.dailyAverage - previous.dailyAverage
                HStack(spacing: 12) {
                    Image(systemName: diff <= 0 ? "arrow.down" : "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(diff <= 0 ? Color.accentColor : Color(white: 0.56), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        statNumber(Amount.number(abs(diff)), unit: side.unit)
                        Text("지난주보다 하루 \(diff <= 0 ? "덜" : "더")")
                            .statLabel()
                    }
                    Spacer(minLength: 0)
                }
                .statCard()
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func statNumber(_ value: String, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(value)
                .font(AppFont.pretendard(28, .bold, relativeTo: .title))
                .tracking(-1)
                .monospacedDigit()
            Text(unit)
                .font(AppFont.pretendard(13, .medium, relativeTo: .footnote))
        }
    }

    // MARK: - 월(Pro)

    @ViewBuilder
    private func monthContent(today: DayKey) -> some View {
        let month = DropCalendar.make(entries: entries, boundaryHour: boundaryHour, today: today, side: side, limit: limit)
        heroCard(
            kicker: "\(today.month)월 \(side.characterName)에게 준 \(side.label)",
            number: Amount.number(month.given), unit: side.unit, suffix: nil,
            caption: "기준 안에서 마신 날 \(month.withinDays)일 / \(month.elapsedDays)일",
            cheer: false
        )
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("방울 달력").kicker()
                Spacer()
                Text("남긴 만큼 방울이 커요")
                    .font(AppFont.pretendard(11, .regular, relativeTo: .caption2))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(Self.weekdays, id: \.self) { day in
                    Text(day)
                        .font(AppFont.pretendard(11, .regular, relativeTo: .caption2))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 4)
                }
                ForEach(0..<month.leadingBlanks, id: \.self) { _ in Color.clear.frame(height: 1) }
                ForEach(month.cells) { cell in
                    dropCell(cell, month: month, today: today)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .card(radius: 28)
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    @ViewBuilder
    private func dropCell(_ cell: DropCalendar.Cell, month: DropCalendar, today: DayKey) -> some View {
        if let left = month.left(cell) {
            let size = DropCalendar.dropSize(left: left, limit: limit)
            Button {
                dayLog = cell.day
            } label: {
                VStack(spacing: 2) {
                    ZStack {
                        if size > 0 {
                            Image(side.dropAsset)
                                .resizable()
                                .scaledToFit()
                                .frame(width: size, height: size)
                        } else {
                            Circle().fill(Color.secondary.opacity(0.35)).frame(width: 6, height: 6)
                        }
                    }
                    .frame(height: 40)
                    Text("\(cell.day.day)")
                        .font(AppFont.pretendard(11, cell.day == today ? .bold : .regular, relativeTo: .caption2))
                        .monospacedDigit()
                        .foregroundStyle(cell.day == today ? Color.primary : Color.secondary)
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .background(
                    cell.day == today ? Color.accentColor.opacity(0.12) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel("\(cell.day.day)일 남은 \(Amount.number(left)) \(side.unit)")
        } else {
            Text("\(cell.day.day)")
                .font(AppFont.pretendard(11, .regular, relativeTo: .caption2))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .opacity(0.35)
                .frame(maxWidth: .infinity, minHeight: 62, alignment: .bottom)
                .padding(.bottom, 4)
                .accessibilityHidden(true)
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

    /// CI 스크린샷 전용(Debug). `-trendSide caffeine`, `-trendRange month`.
    private func applyScreenshotArguments() {
        #if DEBUG
        let defaults = UserDefaults.standard
        if defaults.string(forKey: "trendSide") == "caffeine" { side = .caffeine }
        if defaults.string(forKey: "trendRange") == "month" { range = .month }
        #endif
    }
}

enum TrendRange: String, CaseIterable, Identifiable {
    case week
    case month

    var id: String { rawValue }

    var label: String {
        switch self {
        case .week: return "주"
        case .month: return "월"
        }
    }
}

extension DayKey: Identifiable {
    var id: String { rawValue }
}

/// 선반 위 컵 한 잔. 오늘 화면과 같은 사진을 크게 확대해 잔만 잘라 쓴다(프로토타입 background-size 260%, 위치 50% 92%).
private struct ShelfGlass: View {
    let asset: String
    private static let width: CGFloat = 44
    private static let height: CGFloat = 82

    var body: some View {
        let imageWidth = Self.width * 2.6
        let imageHeight = imageWidth * 1666 / 937
        Image(asset)
            .resizable()
            .scaledToFill()
            .frame(width: imageWidth, height: imageHeight)
            .offset(y: -(imageHeight - Self.height) * 0.92)
            .frame(width: Self.width, height: Self.height, alignment: .top)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 8, bottomTrailingRadius: 8, topTrailingRadius: 12, style: .continuous))
            .mask {
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12)], startPoint: .top, endPoint: .bottom)
            }
            .accessibilityHidden(true)
    }
}

/// 영웅 카드 캐릭터. 좋은 주에는 가끔 폴짝 뛰며 응원한다(1.8초마다 한 번).
private struct CheerCharacter: View {
    let side: CupSide
    let isCheering: Bool

    var body: some View {
        Image(side.characterAsset)
            .resizable()
            .scaledToFit()
            .frame(height: side == .sugar ? 150 : 128)
            .keyframeAnimator(initialValue: CheerPose(), repeating: isCheering) { view, pose in
                view
                    .rotationEffect(.degrees(pose.rotation), anchor: .bottom)
                    .offset(y: pose.y)
            } keyframes: { _ in
                KeyframeTrack(\.y) {
                    LinearKeyframe(0, duration: 1.08)
                    CubicKeyframe(-14, duration: 0.18)
                    CubicKeyframe(0, duration: 0.18)
                    CubicKeyframe(-6, duration: 0.144)
                    CubicKeyframe(0, duration: 0.216)
                }
                KeyframeTrack(\.rotation) {
                    LinearKeyframe(0, duration: 1.08)
                    CubicKeyframe(-4, duration: 0.18)
                    CubicKeyframe(0, duration: 0.18)
                    CubicKeyframe(3, duration: 0.144)
                    CubicKeyframe(0, duration: 0.216)
                }
            }
            .accessibilityHidden(true)
    }
}

private struct CheerPose {
    var y: Double = 0
    var rotation: Double = 0
}

private extension View {
    /// 흰 유리 카드(추이·설정 공통 문법).
    func card(radius: CGFloat) -> some View {
        background {
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            shape.fill(.white.opacity(0.78))
                .overlay(shape.strokeBorder(.white))
                .shadow(color: Color(red: 20 / 255, green: 30 / 255, blue: 50 / 255).opacity(0.06), radius: 15, y: 10)
        }
    }

    /// 두 카드가 한 줄을 나눠 쓴다(한쪽이 다른 쪽을 밀어 세로 한 줄로 찌그러졌던 일, 2026-09-27).
    func statCard() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .card(radius: 24)
    }

    func statLabel() -> some View {
        font(AppFont.pretendard(12, .regular, relativeTo: .caption))
            .foregroundStyle(.secondary)
            .lineSpacing(2)
    }
}
