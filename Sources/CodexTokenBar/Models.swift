import Foundation

struct TokenEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let sessionID: String
    let tokens: Int
    let inputTokens: Int
    let cachedInputTokens: Int
    let outputTokens: Int
    let reasoningOutputTokens: Int
}

struct DayUsage: Identifiable {
    let id = UUID()
    let date: Date
    let tokens: Int
    let calls: Int
}

struct BinUsage: Identifiable {
    let id = UUID()
    let start: Date
    let tokens: Int
    let calls: Int
}

struct PluginUsage: Identifiable {
    let id = UUID()
    let name: String
    let runs: Int
}

struct DashboardStats {
    let totalTokens: Int
    let peakDayTokens: Int
    let longestTaskSeconds: Int
    let currentStreakDays: Int
    let longestStreakDays: Int
    let totalCalls: Int
    let totalThreads: Int
    let fastModePercent: Int
    let mostUsedReasoning: String
    let skillsExplored: Int
    let totalSkillsUsed: Int
}

struct DashboardSnapshot {
    let stats: DashboardStats
    let dailyUsage: [DayUsage]
    let recentBins: [BinUsage]
    let pluginUsage: [PluginUsage]
    let generatedAt: Date
}

extension Int {
    var abbreviatedTokens: String {
        let value = Double(self)
        if value >= 100_000_000 {
            return String(format: "%.1f亿", value / 100_000_000)
        }
        if value >= 10_000 {
            return String(format: "%.1f万", value / 10_000)
        }
        return "\(self)"
    }

    var millions: String {
        String(format: "%.1fM", Double(self) / 1_000_000)
    }
}
