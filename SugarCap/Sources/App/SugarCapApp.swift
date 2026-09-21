import SwiftData
import SwiftUI

@main
struct SugarCapApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [Entry.self, AppSettings.self])
    }
}
