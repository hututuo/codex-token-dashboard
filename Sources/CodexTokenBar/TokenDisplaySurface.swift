import AppKit
import SwiftUI

private enum TokenDisplayLayout {
    static let metricOutset: CGFloat = 9
}

enum TokenDisplayMode: String, CaseIterable, Identifiable {
    case off
    case floating
    case statusBar

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off:
            return "关闭"
        case .floating:
            return "悬浮窗"
        case .statusBar:
            return "状态栏"
        }
    }

    var controlLabel: String {
        switch self {
        case .statusBar:
            return "状态栏（待开发）"
        default:
            return label
        }
    }

    var systemImage: String {
        switch self {
        case .off:
            return "slash.circle"
        case .floating:
            return "rectangle.on.rectangle"
        case .statusBar:
            return "menubar.rectangle"
        }
    }
}

struct TokenDisplaySnapshot {
    let title: String
    let status: String
    let rate: Double
    let consumedTokens: Int
    let todayTokens: Int
    let todayRequests: Int
    let quota: AccountQuotaSnapshot
    let updatedAt: Date

    @MainActor
    static func make(store: CodexUsageStore, monitor: LiveRateMonitor, quota: AccountQuotaStore) -> TokenDisplaySnapshot {
        let calendar = Calendar.current
        let today = Date()
        let todayUsage = store.snapshot.dailyUsage.first { calendar.isDate($0.date, inSameDayAs: today) }

        return TokenDisplaySnapshot(
            title: "全会话实时",
            status: monitor.totalSnapshot.status,
            rate: monitor.totalSnapshot.rollingTokensPerSecond,
            consumedTokens: store.snapshot.stats.totalTokens,
            todayTokens: todayUsage?.tokens ?? 0,
            todayRequests: todayUsage?.calls ?? 0,
            quota: quota.snapshot,
            updatedAt: max(store.snapshot.generatedAt, max(monitor.totalSnapshot.updatedAt, quota.snapshot.updatedAt ?? .distantPast))
        )
    }

    var statusBarTitle: String {
        if rate >= 100 {
            return "\(Int(rate.rounded()))/s"
        }
        if rate < 10 {
            return String(format: "%.1f/s", rate)
        }
        return "\(Int(rate.rounded()))/s"
    }

    var compactUsageStatus: String {
        guard quota.isAvailable else {
            if quota.status.contains("失败") {
                return "读取失败"
            }
            return "读取中"
        }

        let remaining = [quota.fiveHour, quota.sevenDay]
            .compactMap { $0?.remainingPercent }
            .min() ?? 100

        let label: String
        switch remaining {
        case 50...:
            label = "用量充足"
        case 25..<50:
            label = "节奏正常"
        case 10..<25:
            label = "额度偏紧"
        default:
            label = "快见底"
        }

        if let expectedRemaining = quota.sevenDay?.expectedRemainingPercentByEvenPace
            ?? quota.fiveHour?.expectedRemainingPercentByEvenPace {
            return "\(label)(均\(expectedRemaining)%)"
        }
        return label
    }
}

struct TokenDisplayCard: View {
    let snapshot: TokenDisplaySnapshot
    let onClose: (() -> Void)?

    var body: some View {
        VStack(alignment: .center, spacing: 3) {
            HStack(alignment: .center, spacing: 8) {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(String(format: "%.1f", snapshot.rate))
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: 56, alignment: .leading)
                    Text("tok/s")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                TokenDisplayRateBar(rate: snapshot.rate, usageStatus: snapshot.compactUsageStatus, onClose: onClose)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 6) {
                TokenDisplayMetric(label: "总", value: snapshot.consumedTokens.abbreviatedTokens)
                    .offset(x: -TokenDisplayLayout.metricOutset)
                TokenDisplayMetric(label: "今", value: snapshot.todayTokens.abbreviatedTokens)
                TokenDisplayMetric(label: "次", value: "\(snapshot.todayRequests)")
                    .offset(x: TokenDisplayLayout.metricOutset)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            TokenQuotaMiniStrip(snapshot: snapshot.quota)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

struct TokenQuotaMiniStrip: View {
    let snapshot: AccountQuotaSnapshot

    var body: some View {
        GeometryReader { proxy in
            let windows = [snapshot.fiveHour, snapshot.sevenDay].compactMap { $0 }
            let spacing: CGFloat = 4
            let segmentWidth = max(44, (proxy.size.width - spacing * CGFloat(max(windows.count - 1, 0))) / CGFloat(max(windows.count, 1)))

            HStack(spacing: spacing) {
                ForEach(windows, id: \.label) { window in
                    TokenQuotaMiniSegment(window: window)
                        .frame(width: segmentWidth, height: 13)
                }
                if !snapshot.isAvailable {
                    Text("额度 --")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .frame(width: proxy.size.width, height: 13, alignment: .center)
        }
        .frame(height: 13)
        .help(quotaHelpText)
    }

    private var quotaHelpText: String {
        guard snapshot.isAvailable else { return snapshot.status }
        let chunks = [snapshot.fiveHour, snapshot.sevenDay].compactMap { window -> String? in
            guard let window else { return nil }
            return "\(window.label) 剩余 \(window.remainingPercent)%，\(window.accessibleResetText) 重置"
        }
        return chunks.joined(separator: "；")
    }
}

struct TokenQuotaMiniSegment: View {
    let window: AccountQuotaWindow

    private var fillFraction: CGFloat {
        CGFloat(Double(window.remainingPercent) / 100.0)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.10))
                Capsule()
                    .fill(AppTheme.accentBlue.opacity(0.72))
                    .frame(width: max(2, proxy.size.width * fillFraction))
                Text("\(window.compactDisplayLabel) \(window.remainingPercent)% \(window.compactResetText)")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.primary.opacity(0.82))
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 3)
            }
        }
        .frame(height: 13)
    }
}

struct TokenDisplayRateBar: View {
    let rate: Double
    let usageStatus: String
    let onClose: (() -> Void)?
    private let fullScale = 250.0

    private var fillFraction: CGFloat {
        CGFloat(min(max(rate, 0), fullScale) / fullScale)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 1) {
                Text(usageStatus)
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(.secondary.opacity(0.86))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: 3)

                Text("总速")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 6, weight: .bold))
                            .foregroundStyle(.secondary.opacity(0.72))
                            .frame(width: 9, height: 9)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            GeometryReader { proxy in
                let width = max(3, proxy.size.width * fillFraction)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.cyan.opacity(0.98), Color.blue.opacity(0.92)],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: width)
                }
            }
            .frame(height: 4)
        }
        .frame(height: 18)
    }
}

struct TokenDisplayMetric: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 7, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 7, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

struct TokenGlassBackground: View {
    var opacity = 0.88

    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(AppTheme.panelBackground.opacity(opacity))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.06),
                                AppTheme.accentCyan.opacity(0.10),
                                AppTheme.accentBlue.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.16), Color.white.opacity(0.045)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
}
