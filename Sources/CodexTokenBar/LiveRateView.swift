import SwiftUI

struct LiveRateView: View {
    @ObservedObject var monitor: LiveRateMonitor
    @Binding var tokenDisplayMode: TokenDisplayMode
    @Binding var preciseTokenCountingEnabled: Bool
    @Binding var floatingPanelOpacity: Double
    @Binding var floatingPanelScale: Double

    private var primarySnapshot: LiveRateSnapshot {
        monitor.totalSnapshot
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LiveRateHeader(
                snapshot: primarySnapshot,
                onReset: monitor.reset
            )

            HStack(alignment: .top, spacing: 10) {
                LiveRateGauge(value: primarySnapshot.rollingTokensPerSecond)
                    .frame(width: 132, height: 82)

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            LiveMetricCell(
                                value: String(format: "%.1f", primarySnapshot.rollingTokensPerSecond),
                                label: "全会话 tok/s"
                            )
                            LiveMetricCell(
                                value: "\(primarySnapshot.breakdown.modelGenerated)",
                                label: "模型生成"
                            )
                            LiveMetricCell(
                                value: "\(primarySnapshot.outputTokens)",
                                label: "综合 token"
                            )
                        }

                        HStack(spacing: 5) {
                            LivePill(systemImage: "sum", text: primarySnapshot.scopeLabel)
                            LivePill(systemImage: "point.3.connected.trianglepath.dotted", text: primarySnapshot.interfaceLabel)
                            LivePill(systemImage: tokenDisplayMode.systemImage, text: tokenDisplayMode.label)
                            Spacer(minLength: 0)
                        }

                        LiveBreakdownRow(breakdown: primarySnapshot.breakdown)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    LiveRateControls(
                        tokenDisplayMode: $tokenDisplayMode,
                        preciseTokenCountingEnabled: $preciseTokenCountingEnabled,
                        floatingPanelOpacity: $floatingPanelOpacity,
                        floatingPanelScale: $floatingPanelScale
                    )
                }
            }

            LiveSelectedThreadRow(monitor: monitor)
                .frame(maxWidth: .infinity)
        }
        .padding(12)
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
    }
}

struct LiveRateHeader: View {
    let snapshot: LiveRateSnapshot
    let onReset: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("全会话实时速度")
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(1)

            Text("\(snapshot.status) · \(snapshot.sourceLabel)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 6)

            Button(action: onReset) {
                Label("重置整体速率", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("重置全会话实时速率窗口")
        }
    }
}

struct LiveRateControls: View {
    @Binding var tokenDisplayMode: TokenDisplayMode
    @Binding var preciseTokenCountingEnabled: Bool
    @Binding var floatingPanelOpacity: Double
    @Binding var floatingPanelScale: Double

    private let contentWidth: CGFloat = 286
    private let controlWidth: CGFloat = 139

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(TokenDisplayMode.allCases) { mode in
                        Button {
                            tokenDisplayMode = mode
                        } label: {
                            if mode == tokenDisplayMode {
                                Label(mode.controlLabel, systemImage: "checkmark")
                            } else {
                                Label(mode.controlLabel, systemImage: mode.systemImage)
                            }
                        }
                    }
                } label: {
                    Label("显示：\(tokenDisplayMode.controlLabel)", systemImage: tokenDisplayMode.systemImage)
                }
                .buttonStyle(.bordered)
                .frame(width: controlWidth)
                .help("显示模式")

                Toggle(isOn: $preciseTokenCountingEnabled) {
                    Label("精准 token 统计", systemImage: "number")
                }
                .toggleStyle(.button)
                .buttonStyle(.bordered)
                .frame(width: controlWidth)
                .help("开启后使用 o200k_base 精确统计流式输出 token；关闭后使用轻量估算。")
            }
            .frame(width: contentWidth, alignment: .leading)

            FloatingOpacityControl(opacity: $floatingPanelOpacity)
                .frame(width: contentWidth, alignment: .leading)

            FloatingSizeControl(scale: $floatingPanelScale)
                .frame(width: contentWidth, alignment: .leading)
        }
        .controlSize(.small)
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: 306, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(AppTheme.insetBackground)
        )
    }
}

struct FloatingOpacityControl: View {
    @Binding var opacity: Double

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "circle.lefthalf.filled")
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: 12, height: 18, alignment: .center)
                Text("悬浮窗透明度")
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(.secondary)
            .frame(width: 82, height: 18, alignment: .leading)

            Slider(value: $opacity, in: 0.45...0.98, step: 0.01)
                .frame(width: 138)
            Text("\(Int((opacity * 100).rounded()))%")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(AppTheme.raisedBackground.opacity(0.72))
        )
        .help("悬浮窗透明度")
    }
}

struct FloatingSizeControl: View {
    @Binding var scale: Double

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: 12, height: 18, alignment: .center)
                Text("悬浮窗大小")
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(.secondary)
            .frame(width: 82, height: 18, alignment: .leading)

            Slider(value: $scale, in: FloatingTokenPanelMetrics.scaleRange, step: 0.01)
                .frame(width: 138)
            Text("\(Int((scale * 100).rounded()))%")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(AppTheme.raisedBackground.opacity(0.72))
        )
        .help("等比调整悬浮窗大小")
    }
}

struct LiveSelectedThreadRow: View {
    @ObservedObject var monitor: LiveRateMonitor

    private var snapshot: LiveRateSnapshot {
        monitor.snapshot
    }

    var body: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(monitor.threadOptions) { option in
                    Button {
                        monitor.selectThread(option.id)
                    } label: {
                        if option.id == monitor.selectedThreadID {
                            Label(option.displayTitle, systemImage: "checkmark")
                        } else {
                            Text(option.displayTitle)
                        }
                    }
                }
            } label: {
                Label("选中会话", systemImage: "sidebar.leading")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .frame(width: 96, alignment: .leading)
            .help("选择要查看的单会话")

            HStack(spacing: 4) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(snapshot.threadTitle)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(AppTheme.raisedBackground)
            )
            .help(snapshot.threadTitle)

            Text(String(format: "%.1f tok/s", snapshot.rollingTokensPerSecond))
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .frame(width: 64, alignment: .trailing)

            Text("\(snapshot.outputTokens) 综合")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .frame(width: 54, alignment: .trailing)

            Text("\(snapshot.breakdown.modelGenerated) 模型")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .frame(width: 48, alignment: .trailing)

            Text(snapshot.status)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.insetBackground)
        )
    }
}

struct LiveBreakdownRow: View {
    let breakdown: LiveTokenBreakdown

    var body: some View {
        HStack(spacing: 5) {
            LiveBreakdownChip(label: "可见", value: breakdown.visibleText)
            LiveBreakdownChip(label: "工具参数", value: breakdown.toolArguments)
            LiveBreakdownChip(label: "编辑输入", value: breakdown.patchInput)
            LiveBreakdownChip(label: "实际改动", value: breakdown.patchApplied)
            LiveBreakdownChip(label: "工具输出", value: breakdown.toolOutput)
            LiveBreakdownChip(label: "reasoning", value: breakdown.reasoning)
            if breakdown.exactModelOutput > 0 {
                LiveBreakdownChip(label: "精确输出", value: breakdown.exactModelOutput)
            }
        }
    }
}

struct LiveBreakdownChip: View {
    let label: String
    let value: Int

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .font(.system(size: 9))
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(AppTheme.raisedBackground)
        )
    }
}

struct LiveRateGauge: View {
    let value: Double
    private let fullScale = 250.0

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.insetBackground)

            GeometryReader { proxy in
                let capped = min(max(value, 0), fullScale)
                let width = max(5, proxy.size.width * capped / fullScale)
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.accentCyan, AppTheme.accentBlue],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: width)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "%.1f", value))
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("tokens / second")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(8)
        }
    }
}

struct LiveMetricCell: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.raisedBackground)
        )
    }
}

struct LivePill: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(AppTheme.raisedBackground)
            )
            .lineLimit(1)
    }
}
