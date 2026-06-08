import SwiftUI

@main
struct CodexTokenBarApp: App {
    var body: some Scene {
        WindowGroup {
            DashboardView()
                .frame(minWidth: 1080, minHeight: 760)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 1000)
    }
}
