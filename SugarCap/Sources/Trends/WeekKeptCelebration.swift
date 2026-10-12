import SwiftData
import SwiftUI

/// 기준 지킨 주 축하(SPEC §4.9 2026-10-12). 그 주를 마감한 먹이기 화면을 닫으면 오늘 화면 대신 이 화면이 뜬다.
/// 추이 화면처럼 생긴 별도 화면: 머리줄 → "남긴 당" → 큰 숫자 → 식탁 위 그 주 잔 7개와 캐릭터.
/// "남긴 당" 글자가 한 글자씩 다른 글자로 빠르게 바뀌다가 "주 목표 달성!"에 멈추고(스크램블), 멈추는 순간 팡파레와 함께 캐릭터가 바닥에서 방방 뛴다.
/// 두 면을 지켰으면 조금 빠르게 당 → 카페인으로 넘기며 한 번 더. 끝나면 선물을 든 캐릭터 쪽 오늘 화면으로 돌아간다.
/// 아무 데나 누르면 시계가 부드럽게 빨라진다(뚝 건너뛰지 않는다). 뒤로 가기는 없다(전체 화면).
struct WeekKeptCelebration: Identifiable, Equatable {
    let id = UUID()
    /// 마감한 그 주 일요일.
    let closed: DayKey
    /// 축하할 면(기록하는 면, 당 → 카페인 순).
    let sides: [CupSide]
    /// 선물을 들고 오는 캐릭터의 면. 끝나면 이쪽 오늘 화면을 띄운다.
    let carrier: CupSide
}

/// 축하 시간표. `t` = 시작 뒤 초(가속된 시계). 전부 `t`의 순수 함수다.
enum WeekKeptTimeline {
    /// 첫 면은 화면이 올라온 뒤 잠깐 그대로 보여 주고, 다음 면은 넘어오자마자 시작한다.
    static let firstLead = 0.7
    static let nextLead = 0.25
    static let scrambleLength = 0.5
    static let stagger = 0.07
    /// 글자가 멈춘 뒤 점프·팡파레가 다 끝날 때까지.
    static let hold = 1.8
    static let slide = 0.6
    /// 두 면이면 시계를 이만큼 빨리 돌린다(대표님 "조금 빠른 모션").
    static func baseRate(sides: Int) -> Double { sides > 1 ? 1.25 : 1 }

    /// 글자가 다 멈추는 시각(면 시작 기준).
    static func lockAt(lead: Double, letters: Int) -> Double {
        lead + scrambleLength + stagger * Double(max(letters - 1, 0))
    }

    /// 면마다 시작 시각과 멈춤 시각(전체 시계 기준), 그리고 끝 시각.
    static func plan(sides: Int, letters: Int) -> (starts: [Double], locks: [Double], end: Double) {
        var starts: [Double] = []
        var locks: [Double] = []
        var cursor = 0.0
        for index in 0 ..< max(sides, 1) {
            let lead = index == 0 ? firstLead : nextLead
            starts.append(cursor)
            let lock = cursor + lockAt(lead: lead, letters: letters)
            locks.append(lock)
            cursor = lock + hold + (index < sides - 1 ? slide : 0)
        }
        return (starts, locks, cursor)
    }

    /// 넘긴 쪽 수(소수). 멈춘 뒤 `hold`가 지나면 다음 쪽으로 미끄러진다.
    static func page(_ t: Double, locks: [Double]) -> Double {
        var page = 0.0
        for lock in locks.dropLast() {
            page += Motion.seg(t, lock + hold, lock + hold + slide, Ease.power3InOut)
        }
        return page
    }

    /// 한 글자가 바뀌기 시작하는 시각과 멈추는 시각(면 시작 기준).
    static func letterWindow(_ index: Int, lead: Double) -> (start: Double, lock: Double) {
        let start: Double = lead + stagger * Double(index)
        return (start, start + scrambleLength)
    }

    /// 바닥에서 시작해 세 번 방방(점점 낮게). `u` = 글자가 멈춘 뒤 초. 반환: 뜬 정도(키 대비), 눌림(+ 납작, - 길쭉).
    /// 첫 도약 직전에 살짝 웅크렸다가 멈추는 순간 발이 떨어진다. 회전 없음(카인 360도 금지 규칙).
    static func jump(_ u: Double) -> (lift: Double, squash: Double) {
        let hops: [(at: Double, length: Double, height: Double)] = [(0, 0.42, 0.3), (0.52, 0.34, 0.18), (0.96, 0.28, 0.1)]
        var lift = 0.0
        var squash = 0.0
        for hop in hops {
            let p: Double = (u - hop.at) / hop.length
            if p > 0, p < 1 {
                lift += 4 * p * (1 - p) * hop.height
                squash -= 0.5 * (1 - abs(2 * p - 1))
            }
            // 뛰기 직전 웅크림, 착지 눌림.
            squash += bump(u, hop.at - 0.08, 0.08) * hop.height / 0.3
            squash += bump(u, hop.at + hop.length, 0.1) * hop.height / 0.3
        }
        return (lift, squash)
    }

    private static func bump(_ t: Double, _ a: Double, _ length: Double) -> Double {
        let k = Motion.seg(t, a, a + length)
        return k > 0 && k < 1 ? sin(Double.pi * k) : 0
    }

    /// 지금 보일 글자. 아직 차례가 안 온 자리는 원래 글자, 바뀌는 중이면 섞인 글자, 멈췄으면 목표 글자.
    /// 띄어쓰기는 처음부터 제자리라 줄이 흔들리지 않는다.
    static func scramble(from source: String, to target: String, t: Double, lead: Double) -> String {
        let from = Array(source)
        let to = Array(target)
        var out = ""
        for index in 0 ..< max(from.count, to.count) {
            let window = letterWindow(index, lead: lead)
            let goal: Character? = index < to.count ? to[index] : nil
            if t < window.start {
                if index < from.count { out.append(from[index]) }
            } else if t >= window.lock {
                if let goal { out.append(goal) }
            } else if let goal, goal == " " {
                out.append(goal)
            } else {
                // 1/20초마다 바뀐다. 자리마다 다른 순서라 같이 깜빡이지 않는다.
                let tick = Int(t * 20)
                out.append(randomLetter(like: goal ?? from[min(index, from.count - 1)], seed: tick &* 31 &+ index &* 17))
            }
        }
        return out
    }

    private static let hangul = Array("가날담롱뭉별솔앙잔콩탕퐁훅달목표주성당남긴")
    private static let latin = Array("ABCDEFGHJKLMNPRSTUVWXYZ")
    private static let han = Array("週目標達成糖咖啡留杯日好")

    /// 목표 글자와 같은 문자 체계에서 하나(글자 폭이 덜 흔들린다).
    private static func randomLetter(like goal: Character, seed: Int) -> Character {
        let pool: [Character]
        if let scalar = goal.unicodeScalars.first, (0xAC00 ... 0xD7A3).contains(scalar.value) {
            pool = hangul
        } else if goal.isLetter, goal.isASCII {
            pool = latin
        } else if goal.isLetter {
            pool = han
        } else {
            pool = hangul
        }
        let mixed = (seed &* 2_654_435_761) >> 7
        return pool[abs(mixed) % pool.count]
    }
}

/// 누를 때마다 빨라지는 시계. 빨라질 때도 0.35초에 걸쳐 속도가 올라가 장면이 뚝 건너뛰지 않는다.
struct CelebrationClock: Equatable {
    var since: Date
    var start: Double
    var fromRate: Double
    var toRate: Double

    static let ramp = 0.35
    static let maxRate = 4.0

    init(at date: Date, rate: Double) {
        since = date
        start = 0
        fromRate = rate
        toRate = rate
    }

    func time(at date: Date) -> Double {
        let u = max(0, date.timeIntervalSince(since))
        let extra = toRate - fromRate
        if u < Self.ramp { return start + fromRate * u + extra * u * u / (2 * Self.ramp) }
        return start + fromRate * u + extra * (u - Self.ramp / 2)
    }

    private func rate(at date: Date) -> Double {
        let u = max(0, date.timeIntervalSince(since))
        return fromRate + (toRate - fromRate) * min(1, u / Self.ramp)
    }

    /// 누를 때마다 두 배(최대 4배). 지금 시각·속도에서 이어 간다.
    func tapped(at date: Date) -> CelebrationClock {
        var next = self
        next.start = time(at: date)
        next.fromRate = rate(at: date)
        next.toRate = min(Self.maxRate, max(next.fromRate, toRate) * 2)
        next.since = date
        return next
    }
}

struct WeekKeptCelebrationView: View {
    let celebration: WeekKeptCelebration
    let onFinish: () -> Void

    @Query private var settingsRows: [AppSettings]
    @Query(sort: \Entry.loggedAt, order: .reverse) private var entries: [Entry]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var clock: CelebrationClock?
    /// 글자가 멈춘 면 수. 멈출 때마다 성공 햅틱 한 번.
    @State private var locked = 0

    private static let tableTop = Color(red: 0xEC / 255, green: 0xEF / 255, blue: 0xF2 / 255)
    private static let tableEdge = Color(red: 0xE1 / 255, green: 0xE5 / 255, blue: 0xE9 / 255)
    private static let dotOff = Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255).opacity(0.22)
    private static let wallHeight: CGFloat = 150
    private static let cupRise: CGFloat = 52
    private static let glassAspect: CGFloat = 1100.0 / 564.0
    private static let appCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "ko")
        return calendar
    }()
    private static let weekdays = appCalendar.veryShortStandaloneWeekdaySymbols

    private var limits: DailyLimits { settingsRows.first?.limits ?? .default }
    private var boundaryHour: Int { settingsRows.first?.dayBoundaryHour ?? 4 }
    private var sides: [CupSide] { celebration.sides.isEmpty ? [celebration.carrier] : celebration.sides }
    private var target: String { String(localized: "주 목표 달성!") }
    private var plan: (starts: [Double], locks: [Double], end: Double) {
        WeekKeptTimeline.plan(sides: sides.count, letters: target.count)
    }

    /// Debug 스크린샷에서 멈출 시각(`-weekKeptAt 2`, 가속 시계 기준).
    private var frozenAt: Double? {
        #if DEBUG
        if UserDefaults.standard.object(forKey: "weekKeptAt") != nil {
            return UserDefaults.standard.double(forKey: "weekKeptAt")
        }
        #endif
        return nil
    }

    var body: some View {
        let tables: [CupSide: TrendTable] = Dictionary(uniqueKeysWithValues: sides.map { side in
            (side, TrendTable.week(
                entries: entries, boundaryHour: boundaryHour, today: celebration.closed, side: side, limit: side.limit(limits)
            ))
        })
        TimelineView(.animation(minimumInterval: nil, paused: frozenAt != nil || clock == nil)) { timeline in
            let t: Double = frozenAt ?? clock?.time(at: timeline.date) ?? 0
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    header(t: t, tables: tables)
                    Spacer(minLength: 32)
                    scene(t: t, tables: tables, width: proxy.size.width)
                }
                .background {
                    VStack(spacing: 0) {
                        CupView.wallColor
                        Self.tableTop.frame(height: proxy.safeAreaInsets.bottom + 1)
                    }
                    .ignoresSafeArea()
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let clock { self.clock = clock.tapped(at: Date()) }
        }
        .accessibilityAction(named: Text("건너뛰기")) { onFinish() }
        .accessibilityIdentifier("week-kept")
        .sensoryFeedback(.success, trigger: locked) { old, new in new > old }
        .task {
            guard frozenAt == nil else { return }
            clock = CelebrationClock(at: Date(), rate: WeekKeptTimeline.baseRate(sides: sides.count))
            await run()
        }
    }

    /// 시계를 보며 멈춤마다 햅틱을 울리고, 끝나면 닫는다.
    private func run() async {
        let plan = self.plan
        while !Task.isCancelled {
            guard let clock else { return }
            let t = clock.time(at: Date())
            let reached = plan.locks.filter { t >= $0 }.count
            if reached > locked { locked = reached }
            if t >= plan.end {
                onFinish()
                return
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// 지금 보이는 면 번호. 넘기는 중간을 지나면 다음 면 글자로 바뀐다(글자는 제자리, 그림만 밀린다).
    private func sideIndex(_ t: Double) -> Int {
        min(sides.count - 1, Int((WeekKeptTimeline.page(t, locks: plan.locks) + 0.5).rounded(.down)))
    }

    // MARK: - 지면

    private func header(t: Double, tables: [CupSide: TrendTable]) -> some View {
        let index = sideIndex(t)
        let side = sides[index]
        let local: Double = t - plan.starts[index]
        let lead: Double = index == 0 ? WeekKeptTimeline.firstLead : WeekKeptTimeline.nextLead
        let source = String(localized: "남긴 \(side.label)")
        let title: String
        if reduceMotion {
            title = local >= WeekKeptTimeline.lockAt(lead: lead, letters: target.count) ? target : source
        } else {
            title = WeekKeptTimeline.scramble(from: source, to: target, t: local, lead: lead)
        }
        let table = tables[side]
        let digits = tables.values.map { Amount.number($0.total.rounded()).count }.max() ?? 1
        return VStack(alignment: .leading, spacing: 0) {
            masthead(table: table)
            Text(verbatim: title)
                .font(AppFont.pretendard(34, .extraBold, relativeTo: .largeTitle))
                .tracking(AppFont.displayTracking(for: 34))
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, 18)
                .accessibilityLabel(target)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("week-kept-title")
            figure(total: table?.total ?? 0, digits: digits, side: side)
                .padding(.top, 4)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    private func masthead(table: TrendTable?) -> some View {
        let thisWeek = GiftMath.weekStart(of: DayKey(at: Date(), boundaryHour: boundaryHour))
            == GiftMath.weekStart(of: celebration.closed)
        return HStack(spacing: 8) {
            Text(thisWeek ? String(localized: "이번 주") : String(localized: "지난주"))
                .font(AppFont.pretendard(15, .bold, relativeTo: .subheadline))
                .foregroundStyle(Color.ink)
                .frame(minHeight: 44)
            Spacer(minLength: 8)
            if let table {
                Text("\(table.first.month).\(table.first.day) – \(table.last.month).\(table.last.day)")
                    .font(AppFont.pretendard(13, .medium, relativeTo: .footnote))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.ink).frame(height: 1)
        }
    }

    /// 추이 화면의 큰 숫자와 같은 모양(`TrendsView.figureSize`).
    private func figure(total: Double, digits: Int, side: CupSide) -> some View {
        let text = Amount.number(total.rounded())
        let size = TrendsView.figureSize(digits: max(digits, text.count))
        return HStack(alignment: .top, spacing: 6) {
            Text(text)
                .font(AppFont.pretendardFixed(size, .extraBold))
                .tracking(-0.045 * size)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.trailing, 0.045 * size)
                .padding(.top, -0.18 * size)
                .padding(.bottom, -0.15 * size)
            Text(side.unit)
                .font(AppFont.pretendard(22, .bold, relativeTo: .title2))
                .padding(.top, size * 0.03)
        }
        .foregroundStyle(Color.ink)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("남긴 \(side.label) \(text) \(side.unit)")
    }

    // MARK: - 장면

    /// 추이 화면과 같은 벽·식탁. 캐릭터는 일요일 잔 뒤에 서고, 식탁이 아랫몸을 가린다.
    private func scene(t: Double, tables: [CupSide: TrendTable], width: CGFloat) -> some View {
        let page = pageOffset(t)
        return VStack(spacing: 0) {
            Color.clear.frame(height: Self.wallHeight - Self.cupRise)
            pager(width: width, page: page.value) { side in
                cupRow(table: tables[side], side: side)
            }
            dots(t)
                .padding(.top, 10)
                .padding(.bottom, 20)
        }
        .opacity(page.opacity)
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                pager(width: width, page: page.value) { side in
                    character(t: t, table: tables[side], side: side, width: width)
                }
                .frame(height: Self.wallHeight, alignment: .top)
                VStack(spacing: 0) {
                    Color.clear.frame(height: Self.wallHeight)
                    Self.tableTop
                        .overlay(alignment: .top) { Self.tableEdge.frame(height: 1) }
                }
            }
            .opacity(page.opacity)
        }
    }

    /// 동작 줄이기면 미끄러지지 않고 흐려졌다 다음 면으로 바뀐다.
    private func pageOffset(_ t: Double) -> (value: CGFloat, opacity: Double) {
        let page = WeekKeptTimeline.page(t, locks: plan.locks)
        guard reduceMotion else { return (CGFloat(page), 1) }
        let fraction = page - page.rounded(.down)
        return (CGFloat(page.rounded()), 1 - sin(Double.pi * fraction))
    }

    private func pager<Content: View>(
        width: CGFloat, page: CGFloat, @ViewBuilder content: @escaping (CupSide) -> Content
    ) -> some View {
        HStack(spacing: 0) {
            ForEach(sides) { side in
                content(side).frame(width: width)
            }
        }
        .frame(width: width, alignment: .leading)
        .offset(x: -page * width)
    }

    @ViewBuilder
    private func cupRow(table: TrendTable?, side: CupSide) -> some View {
        if let table {
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(table.cups) { cup in
                    cupFace(cup, side: side)
                }
            }
            .padding(.horizontal, 8)
            .accessibilityElement(children: .ignore)
            .accessibilityHidden(true)
        }
    }

    private func cupFace(_ cup: TableCup, side: CupSide) -> some View {
        let limit = side.limit(limits)
        let left = max(0, limit - cup.used)
        let step = cup.recorded ? CupLevel.step(remaining: left, limit: limit) : 0
        return VStack(spacing: 2) {
            CupCrop(asset: CupLevel.cutoutName(setID: side.cupSetID, step: step))
                .frame(width: 50, height: 50 * Self.glassAspect)
            Text(cup.recorded ? Amount.number(left.rounded()) : "-")
                .font(AppFont.pretendard(17, .bold, relativeTo: .body))
                .monospacedDigit()
                .tracking(-0.3)
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, 8)
            Text(Self.weekdays[cup.day.weekday() - 1])
                .font(AppFont.pretendard(12, .regular, relativeTo: .caption))
                .foregroundStyle(Color.secondary)
                .lineLimit(1)
                .frame(minHeight: 18)
        }
        .frame(maxWidth: .infinity)
    }

    /// 일요일 잔 뒤 캐릭터. 글자가 멈추는 순간 바닥에서 방방 뛰고, 발밑 양옆에서 팡파레가 터진다.
    @ViewBuilder
    private func character(t: Double, table: TrendTable?, side: CupSide, width: CGFloat) -> some View {
        if let table {
            let count = CGFloat(max(table.cups.count, 1))
            let at = CGFloat(table.nowIndex)
            let cupX: CGFloat = 8 + (width - 16) * (at + 0.5) / count
            let height: CGFloat = side == .sugar ? 190 : 168
            let sink: CGFloat = side == .sugar ? 64 : 40
            let fromLeft = at < count / 2
            let boxWidth: CGFloat = fromLeft ? max(0, width - cupX + 4) : cupX + 4
            let index = sides.firstIndex(of: side) ?? 0
            let since: Double = t - plan.locks[index]
            let pose = reduceMotion ? (lift: 0.0, squash: 0.0) : WeekKeptTimeline.jump(since)
            let lift: CGFloat = CGFloat(pose.lift) * height
            Image(side.characterAsset)
                .resizable()
                .scaledToFit()
                .frame(height: height)
                .scaleEffect(x: 1 + 0.06 * pose.squash, y: 1 - 0.1 * pose.squash, anchor: .bottom)
                .offset(y: -lift)
                .overlay(alignment: .bottom) {
                    if !reduceMotion, since > 0, since < 1.6 {
                        Canvas { context, size in
                            let foot = CGPoint(x: size.width / 2, y: size.height - sink)
                            LevelUpTimeline.drawFanfare(
                                in: context, foot: foot, height: Double(height),
                                t: since + LevelUpTimeline.burst, colors: LevelUpTimeline.fanfareColors(side)
                            )
                        }
                        .frame(width: 640, height: 900)
                        .allowsHitTesting(false)
                    }
                }
                .frame(width: boxWidth, alignment: fromLeft ? .leading : .trailing)
                .frame(maxWidth: .infinity, alignment: fromLeft ? .trailing : .leading)
                .frame(height: Self.wallHeight, alignment: .top)
                .offset(y: Self.wallHeight - height + sink)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func dots(_ t: Double) -> some View {
        let current = sideIndex(t)
        HStack(spacing: 0) {
            ForEach(Array((sides.count > 1 ? sides : []).enumerated()), id: \.element) { offset, _ in
                Circle()
                    .fill(offset == current ? Color.ink : Self.dotOff)
                    .frame(width: 7, height: 7)
                    .frame(width: 30, height: 44)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}
