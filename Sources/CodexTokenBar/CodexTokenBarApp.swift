import Sparkle
import SwiftUI

@main
struct CodexTokenBarApp: App {
    @StateObject private var loginItemStore = LoginItemStore()
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .frame(minWidth: 1080, minHeight: 760)
                .task {
                    loginItemStore.start()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 1000)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesMenuItem(updater: updaterController.updater)

                Divider()

                Toggle(
                    loginItemStore.menuTitle,
                    isOn: Binding(
                        get: { loginItemStore.isOn },
                        set: { loginItemStore.setEnabled($0) }
                    )
                )

                if loginItemStore.needsSystemApproval {
                    Button("打开登录项设置") {
                        loginItemStore.openLoginItemsSettings()
                    }
                }

                if let message = loginItemStore.errorMessage {
                    Text("自启设置失败：\(message)")
                }

                Divider()
            }
        }
    }
}
