import OSLog
import SwiftUI

/// 정산 화면의 "음료 추가"(2026-10-02 대표님: 다음 날 먹일 때 깜빡한 음료를 넣을 수 있게).
/// 오늘 화면의 기록 시트를 그대로 쓰고, 브랜드 메뉴는 이 시트 안에서 넘어간다.
/// 지난 날 정산이면 그날 23:59로 기록해 그날 몫에 들어가게 한다(하루 경계는 0~23시라 23:59는 늘 그날 안이다).
struct FeedingRecordSheet: View {
    let catalog: CatalogIndex
    let request: FeedingRequest
    /// 정산 화면인지 하루 기록 목록인지(이용 기록 §9.10).
    let place: EntryPlace
    let onRecord: (Entry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var path: [BrandRoute] = []
    @State private var isManualEntryPresented = false
    /// 직접 입력 시트가 닫힌 뒤에 넘긴다. 닫히는 중에 이 시트까지 닫으면 두 시트가 엉킨다.
    @State private var pendingManual: Entry?

    private static let logger = Logger(subsystem: "com.sugarcap.app", category: "feeding")

    var body: some View {
        NavigationStack(path: $path) {
            RecordSheet(
                catalog: catalog,
                todayTotals: request.totals,
                limits: request.limits,
                onBrand: { route in path = [route] },
                onManualEntry: { isManualEntryPresented = true },
                onAdd: { selection, brand in
                    UsageReporter.shared?.logEntry(path: .search, place: place, brandID: brand.id, now: Date())
                    save(selection.makeEntry(brandName: brand.name, at: loggedAt()))
                },
                onQuickAdd: { drink, entryPath in
                    UsageReporter.shared?.logEntry(path: entryPath, place: place, brandID: drink.brand.id, now: Date())
                    save(drink.selection.makeEntry(brandName: drink.brand.name, at: loggedAt()))
                },
                todayCount: 0,
                onTodayLog: {}
            )
            .toolbar(.hidden, for: .navigationBar)
            .navigationTitle("기록")
            .navigationDestination(for: BrandRoute.self) { route in
                if let brand = catalog.brand(id: route.brandID) {
                    BrandMenuView(
                        brand: brand,
                        catalog: catalog,
                        todayTotals: request.totals,
                        limits: request.limits,
                        menuQuery: route.menuQuery,
                        onAdd: { selection in
                            UsageReporter.shared?.logEntry(path: .brandMenu, place: place, brandID: brand.id, now: Date())
                            save(selection.makeEntry(brandName: brand.name, at: loggedAt()))
                        },
                        onManualEntry: { isManualEntryPresented = true }
                    )
                }
            }
        }
        .sheet(isPresented: $isManualEntryPresented, onDismiss: savePendingManual) {
            ManualEntrySheet { entry in pendingManual = entry }
        }
    }

    private func save(_ entry: Entry) {
        onRecord(entry)
        dismiss()
    }

    private func savePendingManual() {
        guard let entry = pendingManual else { return }
        pendingManual = nil
        entry.loggedAt = loggedAt()
        UsageReporter.shared?.logEntry(path: .manual, place: place, brandID: nil, now: Date())
        save(entry)
    }

    private func loggedAt() -> Date {
        switch request.kind {
        case .closeToday:
            return AppClock.now
        case .pastDay(let day):
            let parts = DateComponents(year: day.year, month: day.month, day: day.day, hour: 23, minute: 59)
            guard let date = Calendar.current.date(from: parts) else {
                // 유효한 DayKey라 일어나지 않는다. 일어나면 오늘 몫으로 들어가니 기록을 남긴다.
                Self.logger.fault("지난 날 기록 시각을 못 만듦(\(day.rawValue, privacy: .public)), 지금 시각으로 기록")
                return AppClock.now
            }
            return date
        }
    }
}
