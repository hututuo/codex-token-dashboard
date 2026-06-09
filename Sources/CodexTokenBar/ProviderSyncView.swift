import SwiftUI

struct ProviderSyncPage: View {
    @ObservedObject var store: ProviderSyncStore
    let dataSource: CodexDataSource?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AppTheme.pageBackground
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("会话消失修复")
                            .font(.system(size: 24, weight: .semibold))
                        Text("按 1-2-3-4 扫描、备份、修复、验证，把消失的历史会话找回来。")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.borderless)
                    .background(
                        Circle()
                            .fill(AppTheme.raisedBackground)
                    )
                }

                ProviderSyncView(store: store, dataSource: dataSource)

                Text("建议退出 Codex Desktop 后执行同步；运行中的 Codex 可能会重新写回历史索引。所有同步都会先创建完整备份，可在本页回滚最近一次备份。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(24)
            .frame(width: 1040)
        }
        .frame(width: 1080, height: 570)
        .onAppear {
            store.scan(dataSource: dataSource)
        }
    }
}

struct ProviderSyncView: View {
    @ObservedObject var store: ProviderSyncStore
    let dataSource: CodexDataSource?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("修复向导")
                        .font(.system(size: 17, weight: .semibold))
                    Text(store.snapshot.status)
                        .font(.system(size: 12))
                        .foregroundStyle(store.snapshot.codexRunning ? AppTheme.accentOrange : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 12)

                ProviderTargetPill(snapshot: store.snapshot)
            }

            HStack(alignment: .top, spacing: 12) {
                ProviderSyncMetric(value: "\(store.snapshot.sessionFilesFound)", label: "会话文件")
                ProviderSyncMetric(value: "\(store.snapshot.visibilitySummary.sqliteThreads)", label: "SQLite 线程")
                ProviderSyncMetric(value: "\(store.snapshot.visibilitySummary.desktopUserThreads)", label: "桌面会话")
                ProviderSyncMetric(value: "\(store.snapshot.visibilitySummary.currentWorkspaceDesktopThreads)", label: "当前项目")
                ProviderSyncMetric(value: store.snapshot.sqliteIntegrity, label: "数据库检查")
                ProviderSyncMetric(value: "\(store.snapshot.sqliteRowsToRepair)", label: "Provider 行")
                ProviderSyncMetric(value: "\(store.snapshot.sessionIndexDuplicateIDs)", label: "重复索引")
            }

            HStack(alignment: .top, spacing: 10) {
                ProviderSyncStepCard(
                    number: 1,
                    title: "扫描现状",
                    subtitle: scanSummary,
                    status: scanStatus,
                    accent: AppTheme.accentCyan,
                    buttonTitle: "重新扫描",
                    systemImage: "magnifyingglass",
                    disabled: store.snapshot.isWorking || dataSource == nil
                ) {
                    store.scan(dataSource: dataSource)
                }

                ProviderSyncStepCard(
                    number: 2,
                    title: "创建备份",
                    subtitle: "先备份 config、SQLite、索引和会话 JSONL，后面不满意可以回滚。",
                    status: store.snapshot.lastBackupPath == nil ? "建议先做" : "已有备份",
                    accent: AppTheme.accentBlue,
                    buttonTitle: "只创建备份",
                    systemImage: "externaldrive.badge.timemachine",
                    disabled: store.snapshot.isWorking || dataSource == nil
                ) {
                    store.backup(dataSource: dataSource)
                }

                ProviderSyncStepCard(
                    number: 3,
                    title: "一键修复",
                    subtitle: "同步 provider，处理异常时间戳，并补齐索引和前端工作区状态。",
                    status: repairStatus,
                    accent: AppTheme.accentOrange,
                    buttonTitle: store.dryRunOnly ? "演练修复" : "修复历史",
                    systemImage: "arrow.triangle.2.circlepath",
                    isProminent: true,
                    disabled: store.snapshot.isWorking || dataSource == nil
                ) {
                    store.sync(dataSource: dataSource)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                ProviderSyncStepCard(
                    number: 4,
                    title: "验证结果",
                    subtitle: "修复后检查 provider、数据库、索引和工作区状态是否都正常。",
                    status: store.snapshot.sqliteIntegrity == "ok" ? "可验证" : "先扫描",
                    accent: AppTheme.accentCyan,
                    buttonTitle: "验证结果",
                    systemImage: "checkmark.seal",
                    secondaryTitle: "回滚备份",
                    secondarySystemImage: "clock.arrow.circlepath",
                    secondaryRole: .destructive,
                    disabled: store.snapshot.isWorking || dataSource == nil
                ) {
                    store.verify(dataSource: dataSource)
                } secondaryAction: {
                    store.rollbackLatest(dataSource: dataSource)
                }
            }

            ProviderSyncAdvancedPanel(store: store, backupPath: store.snapshot.lastBackupPath)

            ProviderSyncResultPanel(snapshot: store.snapshot)
        }
        .padding(16)
        .frame(maxWidth: 980)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.panelBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
        .shadow(color: AppTheme.shadow, radius: 18, y: 10)
        .onAppear {
            if store.snapshot.providerSource == "等待扫描" {
                store.scan(dataSource: dataSource)
            }
        }
    }

    private var repairStatus: String {
        if store.snapshot.hasMixedProviders ||
            store.snapshot.sqliteRowsToRepair > 0 ||
            store.snapshot.sessionIndexDuplicateIDs > 0 ||
            store.snapshot.workspaceOrderMissing > 0 {
            return "待修复"
        }
        if store.snapshot.providerSource == "等待扫描" {
            return "待扫描"
        }
        return "看起来正常"
    }

    private var scanStatus: String {
        if store.snapshot.providerSource == "等待扫描" {
            return "未扫描"
        }
        let total = scanIssueCount
        return total == 0 ? "未发现不一致" : "发现 \(total) 处"
    }

    private var scanSummary: String {
        if store.snapshot.providerSource == "等待扫描" {
            return "读取会话文件、SQLite 和索引，先确认到底哪里不一致。"
        }

        let total = scanIssueCount
        guard total > 0 else {
            return "扫描完成：未发现需修复项。\(visibilitySummaryText)"
        }

        var parts: [String] = []
        if jsonlMismatchCount > 0 {
            parts.append("JSONL \(jsonlMismatchCount) 条")
        }
        if store.snapshot.sqliteRowsToRepair > 0 {
            parts.append("SQLite provider \(store.snapshot.sqliteRowsToRepair) 行")
        }
        if store.snapshot.invalidSessionFiles > 0 {
            parts.append("异常首行 \(store.snapshot.invalidSessionFiles) 条")
        }
        if store.snapshot.sessionIndexDuplicateIDs > 0 {
            parts.append("重复索引 \(store.snapshot.sessionIndexDuplicateIDs) 个")
        }
        if store.snapshot.workspaceOrderMissing > 0 {
            parts.append("工作区缺序 \(store.snapshot.workspaceOrderMissing) 个")
        }
        return "扫描完成：发现 \(total) 处需要处理，" + parts.joined(separator: "，") + "。\(visibilitySummaryText)"
    }

    private var scanIssueCount: Int {
        jsonlMismatchCount
            + store.snapshot.sqliteRowsToRepair
            + store.snapshot.invalidSessionFiles
            + store.snapshot.sessionIndexDuplicateIDs
            + store.snapshot.workspaceOrderMissing
    }

    private var jsonlMismatchCount: Int {
        store.snapshot.sessionProviders
            .filter { $0.provider != store.snapshot.detectedProvider }
            .reduce(0) { $0 + $1.count }
    }

    private var visibilitySummaryText: String {
        let summary = store.snapshot.visibilitySummary
        guard summary.sqliteThreads > 0 else { return "历史数量还未读取。" }
        var parts = [
            "SQLite \(summary.sqliteThreads)",
            "桌面 \(summary.desktopUserThreads)",
            "当前项目 \(summary.currentWorkspaceDesktopThreads)"
        ]
        if summary.cliExecUserThreads > 0 {
            parts.append("CLI/exec \(summary.cliExecUserThreads)")
        }
        if summary.subagentThreads > 0 {
            parts.append("子会话 \(summary.subagentThreads)")
        }
        if summary.archivedThreads > 0 {
            parts.append("归档 \(summary.archivedThreads)")
        }
        return "数量口径：" + parts.joined(separator: "，") + "。项目卡片可能只预览 3 条，完整列表以项目行的接口数为准。"
    }
}

private struct ProviderSyncStepCard: View {
    let number: Int
    let title: String
    let subtitle: String
    let status: String
    let accent: Color
    let buttonTitle: String
    let systemImage: String
    var secondaryTitle: String?
    var secondarySystemImage: String?
    var secondaryRole: ButtonRole?
    var isProminent = false
    var disabled = false
    let action: () -> Void
    var secondaryAction: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text("\(number)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(accent)
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(status)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                }
            }

            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 54, alignment: .topLeading)

            Spacer(minLength: 0)

            VStack(spacing: 6) {
                primaryButton

                if let secondaryTitle, let secondaryAction {
                    Button(role: secondaryRole) {
                        secondaryAction()
                    } label: {
                        Label(secondaryTitle, systemImage: secondarySystemImage ?? "arrow.uturn.backward")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .font(.system(size: 12, weight: .medium))
            .disabled(disabled)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 176, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.raisedBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(AppTheme.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var primaryButton: some View {
        if isProminent {
            Button {
                action()
            } label: {
                Label(buttonTitle, systemImage: systemImage)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button {
                action()
            } label: {
                Label(buttonTitle, systemImage: systemImage)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }
}

private struct ProviderSyncAdvancedPanel: View {
    @ObservedObject var store: ProviderSyncStore
    let backupPath: String?

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("高级选项")
                    .font(.system(size: 12, weight: .semibold))
                Text("一般保持默认。需要测试时打开演练模式；切换过自定义 provider 时再手动填写。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 270, alignment: .leading)

            Toggle("包含归档会话", isOn: $store.includeArchivedSessions)
                .toggleStyle(.checkbox)
            Toggle("演练模式", isOn: $store.dryRunOnly)
                .toggleStyle(.checkbox)

            TextField("手动 provider，可留空", text: $store.manualProvider)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppTheme.panelBackgroundAlt)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AppTheme.border, lineWidth: 1)
                )
                .frame(maxWidth: .infinity)

            if let backupPath {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: backupPath)])
                } label: {
                    Label("打开备份", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .font(.system(size: 12, weight: .medium))
            }
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.insetBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
    }
}

private struct ProviderSyncResultPanel: View {
    let snapshot: ProviderSyncSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 14) {
                ProviderDistributionRow(title: "JSONL", values: snapshot.sessionProviders.map { "\($0.provider) \($0.count)" })
                    .frame(maxWidth: .infinity, alignment: .leading)
                ProviderDistributionRow(
                    title: "SQLite",
                    values: snapshot.sqliteProviders.map { "\($0.provider) archived=\($0.archived) \($0.count)" }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            ProviderDistributionRow(
                title: "前端",
                values: frontendStateValues
            )

            ProviderDistributionRow(
                title: "数量",
                values: visibilityValues
            )

            ProviderDistributionRow(
                title: "项目",
                values: workspaceValues
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.panelBackgroundAlt)
        )
    }

    private var frontendStateValues: [String] {
        var values: [String] = []
        values.append("索引 \(snapshot.sessionIndexRows)")
        values.append(snapshot.sessionIndexCurrentThreadPresent ? "当前会话 present" : "当前会话 missing")
        if snapshot.sessionIndexDuplicateIDs > 0 {
            values.append("重复索引 \(snapshot.sessionIndexDuplicateIDs)")
        }
        if snapshot.workspaceIssues.isEmpty {
            values.append("工作区顺序正常")
        } else {
            values.append(contentsOf: snapshot.workspaceIssues.prefix(3).map { "\($0.label) 缺序 \($0.threadCount) 条" })
        }
        return values
    }

    private var visibilityValues: [String] {
        let summary = snapshot.visibilitySummary
        guard summary.sqliteThreads > 0 else { return ["暂无"] }
        return [
            "SQLite \(summary.sqliteThreads)",
            "未归档 \(summary.activeThreads)",
            "桌面 \(summary.desktopUserThreads)",
            "用户全来源 \(summary.userThreads)",
            "当前项目 \(summary.currentWorkspaceDesktopThreads)",
            "CLI/exec \(summary.cliExecUserThreads)",
            "子会话 \(summary.subagentThreads)",
            "归档 \(summary.archivedThreads)"
        ]
    }

    private var workspaceValues: [String] {
        let workspaces = snapshot.visibilitySummary.workspaces
        guard !workspaces.isEmpty else { return ["暂无"] }
        return workspaces.prefix(5).map { workspace in
            let marker = workspace.isActive ? "当前 " : ""
            return "\(marker)\(workspace.label) 桌面 \(workspace.threadCount) / 接口 \(workspace.interactiveThreadCount)"
        }
    }
}

private struct ProviderTargetPill: View {
    let snapshot: ProviderSyncSnapshot

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: snapshot.hasMixedProviders ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(snapshot.hasMixedProviders ? AppTheme.accentOrange : AppTheme.accentCyan)
            VStack(alignment: .leading, spacing: 1) {
                Text(snapshot.detectedProvider)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(snapshot.providerSource)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(AppTheme.raisedBackground)
        )
        .overlay(
            Capsule()
                .stroke(AppTheme.border, lineWidth: 1)
        )
    }
}

private struct ProviderSyncMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.raisedBackground)
        )
    }
}

private struct ProviderDistributionRow: View {
    let title: String
    let values: [String]

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .leading)
            if values.isEmpty {
                Text("暂无")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                Text(values.prefix(4).joined(separator: "  ·  "))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}
