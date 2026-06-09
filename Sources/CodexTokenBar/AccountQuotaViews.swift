import SwiftUI

struct AccountQuotaStrip: View {
    let snapshot: AccountQuotaSnapshot

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Label(
                    snapshot.displayName,
                    systemImage: snapshot.isAvailable ? "gauge.with.dots.needle.33percent" : "gauge.with.dots.needle.0percent"
                )
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(snapshot.isAvailable ? .primary : .secondary)
                .lineLimit(1)

                Text(snapshot.isAvailable ? "本地账户额度" : snapshot.status)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 104, alignment: .leading)

            HStack(spacing: 8) {
                if let fiveHour = snapshot.fiveHour {
                    AccountQuotaSegment(window: fiveHour, accent: AppTheme.accentCyan)
                }
                if let sevenDay = snapshot.sevenDay {
                    AccountQuotaSegment(window: sevenDay, accent: AppTheme.accentBlue)
                }
                if !snapshot.isAvailable {
                    Text(snapshot.status)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            AccountQuotaPaceInsight(snapshot: snapshot)
                .padding(.leading, 10)
        }
        .padding(.leading, 12)
        .padding(.trailing, 0)
        .padding(.vertical, 7)
        .frame(maxWidth: 980, minHeight: 54)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.insetBackground)
        )
        .help(helpText)
    }

    private var helpText: String {
        guard snapshot.isAvailable else { return snapshot.status }
        return [snapshot.fiveHour, snapshot.sevenDay].compactMap { window -> String? in
            guard let window else { return nil }
            return "\(window.label)：已用 \(window.usedPercent)%，剩余 \(window.remainingPercent)%，\(window.accessibleResetText) 重置"
        }.joined(separator: "；")
    }
}

struct AccountQuotaSegment: View {
    let window: AccountQuotaWindow
    let accent: Color

    private var remainingFraction: CGFloat {
        CGFloat(Double(window.remainingPercent) / 100.0)
    }

    var body: some View {
        HStack(spacing: 7) {
            VStack(alignment: .leading, spacing: 1) {
                Text(window.displayLabel)
                    .font(.system(size: 10, weight: .bold))
                    .lineLimit(1)
                Text("重置 \(window.detailedResetText)")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .frame(width: 72, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppTheme.raisedBackground)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [accent.opacity(0.92), accent.opacity(0.55)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(4, proxy.size.width * remainingFraction))
                    HStack(spacing: 4) {
                        Text("剩 \(window.remainingPercent)%")
                            .fontWeight(.semibold)
                        Text("已用 \(window.usedPercent)%")
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 8)
                }
            }
            .frame(height: 20)
        }
        .frame(maxWidth: .infinity)
    }
}

struct AccountQuotaPaceInsight: View {
    let snapshot: AccountQuotaSnapshot

    private var insight: (icon: String, title: String, detail: String, accent: Color)? {
        guard let sevenDay = snapshot.sevenDay,
              sevenDay.resetsAt != nil else {
            return nil
        }

        let expectedRemaining = sevenDay.expectedRemainingPercentByEvenPace ?? sevenDay.remainingPercent
        let delta = sevenDay.remainingPercent - expectedRemaining
        let detail = "剩 \(sevenDay.remainingPercent)% · 均速应剩 \(expectedRemaining)%"

        if delta < -6 {
            return ("figure.outdoor.cycle", "7天用快了，加油蹬", detail, AppTheme.accentCyan)
        }
        if delta < 0 {
            return ("speedometer", "略快于均速", detail, Color.orange)
        }
        return ("checkmark.seal", "7天余量充足", detail, AppTheme.accentBlue)
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: insight?.icon ?? "clock.badge.questionmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(insight?.accent ?? .secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(insight?.title ?? "等待额度")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(insight == nil ? .secondary : .primary)
                    .lineLimit(1)
                Text(insight?.detail ?? "读取后计算均速")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(width: 245, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.raisedBackground)
        )
    }
}
