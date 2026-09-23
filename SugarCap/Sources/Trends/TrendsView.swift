import Charts
import SwiftData
import SwiftUI

/// 추이 탭(SPEC §4.3). 당·카페인은 단위가 달라 **차트를 둘로 나눈다**(이중 축 금지).
/// 계열이 하나씩이라 범례를 두지 않고, 색은 앱 액센트 한 색만 쓴다(§5).
///
/// 월 보기와 "지난주 대비"는 Pro 기능이다(§6). 잠금은 Phase 3에서 StoreKit과 함께 건다.
struct TrendsView: View {
    @Query private var settingsRows: [AppSettings]
    @Query(sort: \Entry.loggedAt, order: .reverse) private var entries: [Entry]

    @State private var range: TrendRange = .week
    @State private var paywall: ProFeature?

    @Environment(ProStore.self) private var pro

    private var limits: DailyLimits { settingsRows.first?.limits ?? .default }
    private var boundaryHour: Int { settingsRows.first?.dayBoundaryHour ?? 4 }

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { timeline in
                let today = DayKey(at: timeline.date, boundaryHour: boundaryHour)
                content(today: today)
            }
            .navigationTitle("추이")
            .sheet(item: $paywall) { feature in
                PaywallView(feature: feature)
            }
        }
    }

    @ViewBuilder
    private func content(today: DayKey) -> some View {
        let points = range.points(entries: entries, boundaryHour: boundaryHour, today: today)
        let hasRecords = points.contains { $0.sugarG > 0 || $0.caffeineMg > 0 }

        ScrollView {
            VStack(spacing: 28) {
                Picker("기간", selection: $range) {
                    ForEach(TrendRange.allCases) { range in
                        Text(range.label).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("trend-range")
                // 월 보기는 Pro다(§6). 무료가 고르면 주 보기로 되돌리고 페이월을 연다.
                .onChange(of: range) { _, newValue in
                    guard newValue == .month, !pro.isPro else { return }
                    range = .week
                    paywall = .monthlyTrends
                }

                if hasRecords {
                    ForEach(CupSide.allCases) { side in
                        chartSection(side, points: points, today: today)
                    }
                } else {
                    ContentUnavailableView(
                        "아직 볼 추이가 없어요",
                        systemImage: "chart.bar",
                        description: Text("기록이 쌓이면 여기에 하루치가 쌓여요.")
                    )
                    .padding(.top, 48)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    private func chartSection(_ side: CupSide, points: [TrendPoint], today: DayKey) -> some View {
        let change = TrendMath.changeVersusPreviousWeek(
            entries: entries, boundaryHour: boundaryHour, today: today, side: side
        )

        return VStack(alignment: .leading, spacing: 8) {
            Text(range == .week ? "\(side.label) 하루 합계" : "\(side.label) 하루 평균")
                .font(.headline)

            if let change {
                if pro.isPro {
                    Text(changeText(change))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else {
                    Button {
                        paywall = .weekOverWeek
                    } label: {
                        Label("지난주 대비 보기", systemImage: "lock")
                            .font(.subheadline)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }

            Chart {
                // 하루 기준선. 막대와 경쟁하지 않게 회색 점선으로 뒤로 뺀다.
                // `.secondary`는 차트 안에서 액센트로 풀려 막대와 같은 색이 된다.
                RuleMark(y: .value("하루 기준", side.limit(limits)))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Color.gray.opacity(0.6))
                    .annotation(position: .top, alignment: .leading, spacing: 2) {
                        Text("하루 기준 \(Amount.number(side.limit(limits))) \(side.unit)")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                ForEach(points) { point in
                    BarMark(
                        x: .value("날짜", point.day.rawValue),
                        y: .value(side.label, point.value(side))
                    )
                    .cornerRadius(4)
                    .foregroundStyle(.tint)
                    .accessibilityLabel(range.axisLabel(point.day))
                    .accessibilityValue("\(Amount.number(point.value(side))) \(side.unit)")
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let raw = value.as(String.self), let day = DayKey(rawValue: raw) {
                            Text(range.axisLabel(day))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.2))
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(Amount.number(number))
                                .monospacedDigit()
                        }
                    }
                }
            }
            .frame(height: 180)
            .accessibilityIdentifier("trend-chart-\(side.rawValue)")
        }
    }

    /// 줄어든 쪽이 좋은 신호다. 증감 부호를 그대로 쓰고 죄책감 문구는 붙이지 않는다(§4.3).
    private func changeText(_ change: Double) -> String {
        let rounded = abs(change).formatted(.number.precision(.fractionLength(0)))
        if change < 0 {
            return "지난주 대비 −\(rounded)%"
        }
        if change > 0 {
            return "지난주 대비 +\(rounded)%"
        }
        return "지난주와 같아요"
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

    func points(entries: [Entry], boundaryHour: Int, today: DayKey) -> [TrendPoint] {
        switch self {
        case .week:
            return TrendMath.daily(entries: entries, boundaryHour: boundaryHour, today: today, days: 7)
        case .month:
            return TrendMath.weekly(entries: entries, boundaryHour: boundaryHour, today: today, weeks: 5)
        }
    }

    /// 주 보기는 요일, 월 보기는 그 주 첫날의 월/일.
    func axisLabel(_ day: DayKey) -> String {
        let components = DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)
        guard let date = Calendar.current.date(from: components) else { return day.rawValue }
        switch self {
        case .week:
            return date.formatted(.dateTime.weekday(.narrow))
        case .month:
            return date.formatted(.dateTime.month(.defaultDigits).day())
        }
    }
}
