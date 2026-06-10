import AppKit
import Foundation
import ServiceManagement

@MainActor
final class LoginItemStore: ObservableObject {
    @Published private(set) var status: SMAppService.Status = SMAppService.mainApp.status
    @Published private(set) var errorMessage: String?

    private let defaults = UserDefaults.standard
    private let defaultAppliedKey = "launchAtLoginDefaultAppliedV01"

    var isOn: Bool {
        status == .enabled || status == .requiresApproval
    }

    var menuTitle: String {
        switch status {
        case .enabled:
            return "开机自启"
        case .requiresApproval:
            return "开机自启（待系统允许）"
        case .notFound:
            return "开机自启（应用未找到）"
        case .notRegistered:
            return "开机自启"
        @unknown default:
            return "开机自启"
        }
    }

    var needsSystemApproval: Bool {
        status == .requiresApproval
    }

    func start() {
        refresh()
        guard !defaults.bool(forKey: defaultAppliedKey) else { return }
        setEnabled(true, markDefaultApplied: true)
    }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func setEnabled(_ enabled: Bool) {
        setEnabled(enabled, markDefaultApplied: false)
    }

    func openLoginItemsSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    private func setEnabled(_ enabled: Bool, markDefaultApplied: Bool) {
        do {
            if enabled {
                if status != .enabled && status != .requiresApproval {
                    try SMAppService.mainApp.register()
                }
            } else {
                if status != .notRegistered {
                    try SMAppService.mainApp.unregister()
                }
            }
            errorMessage = nil
            if markDefaultApplied {
                defaults.set(true, forKey: defaultAppliedKey)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }
}
