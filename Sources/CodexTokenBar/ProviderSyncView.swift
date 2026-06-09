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
                        Text("把历史会话 JSONL、SQLite 索引和 session_index 同步到当前 Codex provider。")
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
        .frame(width: 1080, height: 470)
        .onAppear {
            store.scan(dataSource: dataSource)
        }
    }
}

struct ProviderSyncView: View {
    @ObservedObject var store: ProviderSyncStore
    let dataSource: CodexDataSource?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("会话消失修复")
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
                ProviderSyncMetric(value: "\(store.snapshot.sessionFilesFound)", label: "session JSONL")
                ProviderSyncMetric(value: "\(store.snapshot.invalidSessionFiles)", label: "异常首行")
                ProviderSyncMetric(value: store.snapshot.sqliteIntegrity, label: "SQLite integrity")
                ProviderSyncMetric(
                    value: store.snapshot.sessionIndexCurrentThreadPresent ? "present" : "missing",
                    label: "current index"
                )
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    ProviderDistributionRow(title: "JSONL", values: store.snapshot.sessionProviders.map { "\($0.provider) \($0.count)" })
                    ProviderDistributionRow(
                        title: "SQLite",
                        values: store.snapshot.sqliteProviders.map { "\($0.provider) archived=\($0.archived) \($0.count)" }
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 8) {
                    HStack(spacing: 8) {
                        Toggle("归档", isOn: $store.includeArchivedSessions)
                            .toggleStyle(.checkbox)
                        Toggle("Dry run", isOn: $store.dryRunOnly)
                            .toggleStyle(.checkbox)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                    TextField("手动 provider，可留空", text: $store.manualProvider)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(AppTheme.raisedBackground)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(AppTheme.border, lineWidth: 1)
                        )
                        .frame(maxWidth: .infinity)

                    HStack(spacing: 7) {
                        Button {
                            store.scan(dataSource: dataSource)
                        } label: {
                            Label("Scan", systemImage: "magnifyingglass")
                        }

                        Button {
                            store.verify(dataSource: dataSource)
                        } label: {
                            Label("Verify", systemImage: "checkmark.seal")
                        }

                        Button {
                            store.backup(dataSource: dataSource)
                        } label: {
                            Label("Backup", systemImage: "externaldrive.badge.timemachine")
                        }

                        Button {
                            store.sync(dataSource: dataSource)
                        } label: {
                            Label(store.dryRunOnly ? "Dry run" : "一键同步", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .keyboardShortcut("s", modifiers: [.command, .shift])

                        Button(role: .destructive) {
                            store.rollbackLatest(dataSource: dataSource)
                        } label: {
                            Label("Rollback", systemImage: "clock.arrow.circlepath")
                        }
                    }
                    .buttonStyle(.bordered)
                    .font(.system(size: 12, weight: .medium))
                    .disabled(store.snapshot.isWorking || dataSource == nil)

                    if let backupPath = store.snapshot.lastBackupPath {
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: backupPath)])
                        } label: {
                            Text(backupPath.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 540, alignment: .trailing)
            }
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
