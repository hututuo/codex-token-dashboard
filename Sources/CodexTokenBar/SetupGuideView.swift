import SwiftUI

struct SetupGuideView: View {
    let dataSource: CodexDataSource?
    let dataSourceLabel: String
    let dataSourceOrigin: String
    @ObservedObject var loginItemStore: LoginItemStore
    @ObservedObject var updateSettingsStore: AppUpdateSettingsStore
    let onChooseDirectory: () -> Void
    let onFinish: () -> Void

    private var hasCodexDirectory: Bool {
        dataSource != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("完成初始设置")
                    .font(.system(size: 24, weight: .semibold))
                Text("确认本地 Codex 数据、开机自启和更新检查。")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                SetupGuideRow(
                    number: "1",
                    title: "Codex 目录",
                    status: hasCodexDirectory ? "已找到" : "需要选择",
                    systemImage: hasCodexDirectory ? "checkmark.circle.fill" : "folder.badge.questionmark",
                    tint: hasCodexDirectory ? .green : AppTheme.accentOrange
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            HStack(spacing: 7) {
                                Text(hasCodexDirectory ? dataSourceOrigin : "未自动发现")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Text(dataSourceLabel)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            SetupGuideCompactButton(
                                title: hasCodexDirectory ? "更改" : "选择目录",
                                systemImage: hasCodexDirectory ? "folder.badge.gearshape" : "folder",
                                action: onChooseDirectory
                            )
                        }
                    }
                }

                SetupGuideRow(
                    number: "2",
                    title: "开机自启",
                    status: loginItemStore.isOn ? "已开启" : "建议开启",
                    systemImage: loginItemStore.isOn ? "checkmark.circle.fill" : "power.circle",
                    tint: loginItemStore.isOn ? .green : AppTheme.accentBlue
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        SetupGuideCompactToggle(
                            title: loginItemStore.menuTitle,
                            isOn: loginItemStore.isOn,
                            tint: AppTheme.accentBlue
                        ) { isOn in
                            loginItemStore.setEnabled(isOn)
                        }

                        Text("这次不开也没关系，之后可以在左上角 App 菜单里开启。开机自启会保留悬浮窗或状态栏读数，不需要先打开主界面。")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if loginItemStore.needsSystemApproval {
                            SetupGuideCompactButton(title: "打开登录项设置", systemImage: "gearshape") {
                                loginItemStore.openLoginItemsSettings()
                            }
                        }

                        if let message = loginItemStore.errorMessage {
                            Text("自启设置失败：\(message)")
                                .font(.system(size: 11))
                                .foregroundStyle(AppTheme.accentOrange)
                        }
                    }
                }

                SetupGuideRow(
                    number: "3",
                    title: "更新检查",
                    status: updateSettingsStore.statusText,
                    systemImage: updateSettingsStore.automaticChecksEnabled ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath.circle",
                    tint: updateSettingsStore.automaticChecksEnabled ? .green : AppTheme.accentBlue
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        SetupGuideCompactToggle(
                            title: "自动检查更新",
                            isOn: updateSettingsStore.automaticChecksEnabled,
                            tint: AppTheme.accentBlue
                        ) { isOn in
                            updateSettingsStore.setAutomaticChecksEnabled(isOn)
                        }

                        Text("开启后会自动检查 GitHub appcast，有新版本时再由你确认安装；也可以在左上角 App 菜单手动检查。")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            HStack {
                Spacer()
                Button("稍后再说") {
                    onFinish()
                }
                .buttonStyle(SetupGuideFooterButtonStyle())
                .keyboardShortcut(.cancelAction)
                Button("开始使用") {
                    onFinish()
                }
                .buttonStyle(SetupGuideFooterButtonStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 560)
        .background(AppTheme.pageBackground)
    }
}

private struct SetupGuideCompactToggle: View {
    let title: String
    let isOn: Bool
    let tint: Color
    let onChange: (Bool) -> Void

    var body: some View {
        Button {
            onChange(!isOn)
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule(style: .continuous)
                        .fill(isOn ? tint.opacity(0.95) : AppTheme.panelBackgroundAlt)
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(isOn ? Color.clear : AppTheme.borderStrong, lineWidth: 1)
                        )
                    Circle()
                        .fill(Color.white)
                        .frame(width: 12, height: 12)
                        .shadow(color: .black.opacity(isOn ? 0.16 : 0.08), radius: 1.5, x: 0, y: 0.5)
                        .padding(2)
                }
                .frame(width: 28, height: 16)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "已开启" : "已关闭")
        .animation(.easeInOut(duration: 0.14), value: isOn)
    }
}

private struct SetupGuideCompactButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(AppTheme.panelBackgroundAlt)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(AppTheme.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }
}

private struct SetupGuideFooterButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(prominent ? AppTheme.accentBlue : AppTheme.panelBackgroundAlt)
                    .opacity(configuration.isPressed ? 0.82 : 1)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(prominent ? Color.clear : AppTheme.border, lineWidth: 1)
            )
    }
}

private struct SetupGuideRow<Content: View>: View {
    let number: String
    let title: String
    let status: String
    let systemImage: String
    let tint: Color
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.14))
                Text(number)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Label(status, systemImage: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tint)
                        .labelStyle(.titleAndIcon)
                }

                content
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.panelBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
    }
}
