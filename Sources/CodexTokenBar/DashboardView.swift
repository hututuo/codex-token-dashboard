import AppKit
import SwiftUI

struct DashboardView: View {
    @StateObject private var store = CodexUsageStore()
    @StateObject private var quotaStore = AccountQuotaStore()
    @StateObject private var providerSyncStore = ProviderSyncStore()
    @StateObject private var floatingPanel = FloatingTokenPanelController()
    @StateObject private var statusBarPanel = StatusBarTokenController()
    @State private var liveMonitor = LiveRateMonitor()
    @AppStorage("tokenDisplayMode") private var tokenDisplayModeRaw = TokenDisplayMode.floating.rawValue
    @AppStorage("tokenDisplayModeDefaultedToFloatingV021") private var tokenDisplayModeDefaultedToFloating = false
    @AppStorage("tokenDisplayModeDefaultedToFloatingQuotaV01") private var tokenDisplayModeDefaultedToFloatingQuota = false
    @AppStorage("tokenDisplayModeDefaultedToFloatingQuotaV02") private var tokenDisplayModeDefaultedToFloatingQuotaV02 = false
    @AppStorage("tokenDisplayModeInitialDefaultAppliedV03") private var tokenDisplayModeInitialDefaultApplied = false
    @AppStorage("tokenDisplayModeUserSelected") private var tokenDisplayModeUserSelected = false
    @AppStorage("tokenDisplayModePanelCloseRepairV01") private var tokenDisplayModePanelCloseRepairApplied = false
    @AppStorage("preciseTokenCountingEnabled") private var preciseTokenCountingEnabled = false
    @AppStorage("floatingPanelOpacity") private var floatingPanelOpacity = 0.88
    @AppStorage("floatingPanelScale") private var floatingPanelScale = FloatingTokenPanelMetrics.defaultScale
    @State private var showingProviderSync = false

    init() {
        Self.applyStartupDisplayModeRepairIfNeeded()
    }

    private var tokenDisplayMode: Binding<TokenDisplayMode> {
        Binding {
            TokenDisplayMode(rawValue: tokenDisplayModeRaw) ?? .floating
        } set: { mode in
            tokenDisplayModeUserSelected = true
            tokenDisplayModeRaw = mode.rawValue
        }
    }

    var body: some View {
        ZStack {
            AppTheme.pageBackground
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 18) {
                    HeaderView(
                        snapshot: store.snapshot,
                        quotaSnapshot: quotaStore.snapshot,
                        status: store.status,
                        dataSourceLabel: store.dataSourceLabel,
                        dataSourceOrigin: store.dataSourceOrigin,
                        isRefreshing: store.isRefreshing,
                        onRefresh: refreshAllData,
                        onChangeDirectory: store.chooseDataSourceDirectory,
                        onOpenProviderSync: {
                            showingProviderSync = true
                            providerSyncStore.scan(dataSource: store.currentDataSource)
                        }
                    )

                    StatStrip(stats: store.snapshot.stats)

                    LiveRateView(
                        monitor: liveMonitor,
                        tokenDisplayMode: tokenDisplayMode,
                        preciseTokenCountingEnabled: $preciseTokenCountingEnabled,
                        floatingPanelOpacity: $floatingPanelOpacity,
                        floatingPanelScale: $floatingPanelScale
                    )

                    ActivitySection(
                        dailyUsage: store.snapshot.dailyUsage,
                        cacheDaily: store.snapshot.cacheUsage.daily,
                        selectedMode: $store.selectedMode
                    )

                    RecentUsageChart(
                        bins: store.snapshot.recentBins,
                        cacheRecentBins: store.snapshot.cacheUsage.recentBins
                    )

                    CacheHitRankingSection(cacheUsage: store.snapshot.cacheUsage)
                }
                .padding(.horizontal, 54)
                .padding(.vertical, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if store.isInitialLoading {
                InitialLoadingOverlay(status: store.status)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: store.isInitialLoading)
        .onAppear {
            applyFloatingModeDefaultIfNeeded()
            liveMonitor.setPreciseTokenCountingEnabled(preciseTokenCountingEnabled)
            quotaStore.start()
            updateTokenDisplaySurface()
            updateUsageRefreshCadence()
        }
        .onChange(of: tokenDisplayModeRaw) {
            updateTokenDisplaySurface()
            updateUsageRefreshCadence()
        }
        .onChange(of: floatingPanelScale) {
            updateTokenDisplaySurface()
        }
        .onChange(of: preciseTokenCountingEnabled) {
            liveMonitor.setPreciseTokenCountingEnabled(preciseTokenCountingEnabled)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didHideNotification)) { _ in
            updateUsageRefreshCadence()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didUnhideNotification)) { _ in
            updateUsageRefreshCadence()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            updateUsageRefreshCadence()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didMiniaturizeNotification)) { _ in
            updateUsageRefreshCadence()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didDeminiaturizeNotification)) { _ in
            updateUsageRefreshCadence()
        }
        .sheet(isPresented: $showingProviderSync) {
            ProviderSyncPage(
                store: providerSyncStore,
                dataSource: store.currentDataSource
            )
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    refreshAllData()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(store.isRefreshing)

                Button {
                    Exporter.exportCSV(snapshot: store.snapshot)
                } label: {
                    Label("Export CSV", systemImage: "tablecells")
                }

                Button {
                    Exporter.exportPNG(snapshot: store.snapshot)
                } label: {
                    Label("Export PNG", systemImage: "photo")
                }
            }
        }
    }

    private func refreshAllData() {
        store.refresh()
        quotaStore.refresh()
        if showingProviderSync {
            providerSyncStore.scan(dataSource: store.currentDataSource)
        }
    }

    private func applyFloatingModeDefaultIfNeeded() {
        tokenDisplayModeDefaultedToFloating = true
        tokenDisplayModeDefaultedToFloatingQuota = true
        tokenDisplayModeDefaultedToFloatingQuotaV02 = true

        let currentMode = TokenDisplayMode(rawValue: tokenDisplayModeRaw)
        if !tokenDisplayModeInitialDefaultApplied && !tokenDisplayModeUserSelected,
           currentMode == nil || currentMode == .off {
            tokenDisplayModeRaw = TokenDisplayMode.floating.rawValue
        }
        tokenDisplayModeInitialDefaultApplied = true

        if !tokenDisplayModePanelCloseRepairApplied,
           currentMode == nil || currentMode == .off {
            tokenDisplayModeRaw = TokenDisplayMode.floating.rawValue
            tokenDisplayModeUserSelected = false
        }
        tokenDisplayModePanelCloseRepairApplied = true
    }

    private static func applyStartupDisplayModeRepairIfNeeded() {
        let defaults = UserDefaults.standard
        let defaultAppliedKey = "tokenDisplayModeInitialDefaultAppliedV03"
        let userSelectedKey = "tokenDisplayModeUserSelected"
        let panelCloseRepairKey = "tokenDisplayModePanelCloseRepairV01"

        let rawMode = defaults.string(forKey: "tokenDisplayMode")
        let mode = rawMode.flatMap(TokenDisplayMode.init(rawValue:))

        if !defaults.bool(forKey: defaultAppliedKey), !defaults.bool(forKey: userSelectedKey) {
            if mode == nil || mode == .off {
                defaults.set(TokenDisplayMode.floating.rawValue, forKey: "tokenDisplayMode")
            }
            defaults.set(true, forKey: defaultAppliedKey)
            return
        }

        if !defaults.bool(forKey: panelCloseRepairKey), mode == nil || mode == .off {
            defaults.set(TokenDisplayMode.floating.rawValue, forKey: "tokenDisplayMode")
            defaults.set(false, forKey: userSelectedKey)
        }
        defaults.set(true, forKey: panelCloseRepairKey)
    }

    private func updateTokenDisplaySurface() {
        switch TokenDisplayMode(rawValue: tokenDisplayModeRaw) ?? .floating {
        case .off:
            floatingPanel.close()
            statusBarPanel.close()
        case .floating:
            statusBarPanel.close()
            floatingPanel.show(store: store, monitor: liveMonitor, quota: quotaStore, scale: floatingPanelScale) {
                tokenDisplayModeUserSelected = true
                tokenDisplayModeRaw = TokenDisplayMode.off.rawValue
            }
        case .statusBar:
            floatingPanel.close()
            statusBarPanel.show(store: store, monitor: liveMonitor, quota: quotaStore) {
                tokenDisplayModeUserSelected = true
                tokenDisplayModeRaw = TokenDisplayMode.off.rawValue
            }
        }
    }

    private func updateUsageRefreshCadence() {
        let displayMode = TokenDisplayMode(rawValue: tokenDisplayModeRaw) ?? .floating
        let onlyCompactSurfaceVisible = displayMode != .off && !hasVisibleDashboardWindow()
        store.setRefreshInterval(onlyCompactSurfaceVisible ? 180 : 300)
    }

    private func hasVisibleDashboardWindow() -> Bool {
        guard !NSApp.isHidden else { return false }
        return NSApp.windows.contains { window in
            window.isVisible
                && !window.isMiniaturized
                && window.occlusionState.contains(.visible)
                && !(window is NSPanel)
                && window.contentViewController != nil
        }
    }
}

private struct InitialLoadingOverlay: View {
    let status: String

    var body: some View {
        ZStack {
            MacVisualEffect(material: .windowBackground, blendingMode: .withinWindow)
                .opacity(0.72)
                .ignoresSafeArea()

            Color.black
                .opacity(0.10)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                    .progressViewStyle(.circular)

                VStack(spacing: 4) {
                    Text("正在加载本地统计")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(status)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 320)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppTheme.panelBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 1)
            )
            .shadow(color: AppTheme.shadow, radius: 24, y: 14)
        }
    }
}

private struct MacVisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
    }
}

struct HeaderView: View {
    let snapshot: DashboardSnapshot
    let quotaSnapshot: AccountQuotaSnapshot
    let status: String
    let dataSourceLabel: String
    let dataSourceOrigin: String
    let isRefreshing: Bool
    let onRefresh: () -> Void
    let onChangeDirectory: () -> Void
    let onOpenProviderSync: () -> Void

    @AppStorage("customAccountDisplayName") private var customAccountDisplayName = ""
    @State private var isEditingDisplayName = false
    @State private var displayNameDraft = ""
    @FocusState private var displayNameFieldFocused: Bool

    private var accountDisplayName: String {
        let trimmed = customAccountDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? quotaSnapshot.accountDisplayName : trimmed
    }

    private var planDisplayName: String {
        "Codex Token Bar"
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 72, height: 72)
                Text("CX")
                    .font(.system(size: 27, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 9) {
                if isEditingDisplayName {
                    TextField("昵称", text: $displayNameDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 24, weight: .regular))
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .frame(width: 300)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(AppTheme.raisedBackground, in: Capsule())
                        .overlay(Capsule().stroke(AppTheme.border, lineWidth: 1))
                        .focused($displayNameFieldFocused)
                        .onSubmit(saveDisplayNameDraft)
                        .onChange(of: displayNameFieldFocused) { _, isFocused in
                            if !isFocused {
                                saveDisplayNameDraft()
                            }
                        }
                        .onAppear {
                            displayNameDraft = accountDisplayName
                            displayNameFieldFocused = true
                        }
                } else {
                    Button {
                        displayNameDraft = accountDisplayName
                        isEditingDisplayName = true
                    } label: {
                        HStack(spacing: 6) {
                            Text(accountDisplayName)
                                .font(.system(size: 24, weight: .regular))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                            Image(systemName: "pencil")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary.opacity(0.75))
                        }
                        .frame(maxWidth: 360)
                    }
                    .buttonStyle(.plain)
                    .help("点击修改顶部昵称；留空会恢复本地账户名")
                }

                HStack(spacing: 9) {
                    Text(planDisplayName)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: 132, alignment: .leading)
                    Text("Local")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .stroke(AppTheme.borderStrong, lineWidth: 1)
                        )
                    DataSourceBadge(path: dataSourceLabel, origin: dataSourceOrigin)
                    Text(status)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 8)

                    Button(action: onRefresh) {
                        Label(isRefreshing ? "刷新中" : "立即刷新", systemImage: "arrow.clockwise")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRefreshing)

                    Button(action: onChangeDirectory) {
                        Label("更改目录", systemImage: "folder")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.bordered)

                    Button(action: onOpenProviderSync) {
                        Label("会话消失修复", systemImage: "wrench.and.screwdriver")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                }
                .font(.system(size: 14))
                .padding(.leading, 12)
                .frame(maxWidth: 980)

                AccountQuotaStrip(snapshot: quotaSnapshot)
            }
        }
    }

    private func saveDisplayNameDraft() {
        customAccountDisplayName = displayNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        isEditingDisplayName = false
    }
}

struct DataSourceBadge: View {
    let path: String
    let origin: String

    var body: some View {
        Label {
            HStack(spacing: 5) {
                Text(origin)
                    .foregroundStyle(.secondary)
                Text(path)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        } icon: {
            Image(systemName: "externaldrive")
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(AppTheme.raisedBackground)
        )
        .overlay(
            Capsule()
                .stroke(AppTheme.border, lineWidth: 1)
        )
        .frame(maxWidth: 260)
        .help(path)
    }
}

struct StatStrip: View {
    let stats: DashboardStats

    var body: some View {
        HStack(spacing: 0) {
            StatCell(value: stats.totalTokens.abbreviatedTokens, label: "累计 Token 数")
            Divider().frame(height: 40)
            StatCell(value: stats.peakDayTokens.abbreviatedTokens, label: "峰值 Token 数")
            Divider().frame(height: 40)
            StatCell(value: stats.peakThreadTokens.abbreviatedTokens, label: "单会话最大 Token")
            Divider().frame(height: 40)
            StatCell(value: "\(stats.currentStreakDays) 天", label: "当前连续天数")
            Divider().frame(height: 40)
            StatCell(value: "\(stats.longestStreakDays) 天", label: "最长连续天数")
        }
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.panelBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
        .shadow(color: AppTheme.shadow, radius: 18, y: 10)
        .frame(maxWidth: 980)
    }

}

struct StatCell: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.72)
                .lineLimit(1)

            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ActivitySection: View {
    let dailyUsage: [DayUsage]
    let cacheDaily: [TokenCacheBucket]
    @Binding var selectedMode: ActivityMode

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Token 活动")
                    .font(.system(size: 19, weight: .semibold))
                Spacer()
                ActivityModeSelector(selectedMode: $selectedMode)
            }

            TokenHeatmap(dailyUsage: dailyUsage, cacheDaily: cacheDaily, mode: selectedMode)
        }
        .frame(maxWidth: 980)
    }
}

struct ActivityModeSelector: View {
    @Binding var selectedMode: ActivityMode

    var body: some View {
        HStack(spacing: 4) {
            Text("Mode")
                .font(.system(size: 13))
                .foregroundStyle(.primary)

            HStack(spacing: 2) {
                ForEach(ActivityMode.allCases) { mode in
                    Button {
                        selectedMode = mode
                    } label: {
                        Text(mode.rawValue)
                            .font(.system(size: 13, weight: selectedMode == mode ? .semibold : .medium))
                            .foregroundStyle(labelColor(for: mode))
                            .frame(width: mode.isSpecial ? 58 : 42, height: 25)
                            .background(background(for: mode))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(mode.isSpecial ? AppTheme.accentBlue.opacity(selectedMode == mode ? 0.95 : 0.55) : Color.clear, lineWidth: 1.2)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(AppTheme.raisedBackground)
            )
        }
    }

    private func labelColor(for mode: ActivityMode) -> Color {
        return .primary
    }

    @ViewBuilder
    private func background(for mode: ActivityMode) -> some View {
        if selectedMode == mode {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(AppTheme.accentBlue.opacity(mode.isSpecial ? 0.13 : 0.18))
                .shadow(color: AppTheme.shadow, radius: 3, y: 1)
        } else {
            Color.clear
        }
    }
}

private struct HeatmapMonthMarker: Identifiable {
    let label: String
    let column: Int
    let nextColumn: Int

    var id: String {
        "\(label)-\(column)"
    }
}

private struct HeatmapPreparedData {
    let summaries: [HeatmapUsageSummary]
    let maxTokens: Int
    let columns: [[Int]]
    let monthMarkers: [HeatmapMonthMarker]

    static let empty = HeatmapPreparedData(summaries: [], maxTokens: 1, columns: [], monthMarkers: [])
}

struct TokenHeatmap: View {
    let dailyUsage: [DayUsage]
    let cacheDaily: [TokenCacheBucket]
    let mode: ActivityMode
    @State private var hoveredIndex: Int?
    @State private var preparedData: HeatmapPreparedData

    private let rows = 7
    private let gap: CGFloat = 4
    private let trailingInset: CGFloat = 9

    init(dailyUsage: [DayUsage], cacheDaily: [TokenCacheBucket], mode: ActivityMode) {
        self.dailyUsage = dailyUsage
        self.cacheDaily = cacheDaily
        self.mode = mode
        _preparedData = State(initialValue: .empty)
    }

    var body: some View {
        GeometryReader { proxy in
            let summaries = preparedData.summaries
            let columns = preparedData.columns
            let selectedIndex = hoveredIndex ?? summaries.indices.last
            let cellSize = adaptiveCellSize(containerWidth: proxy.size.width, columnCount: columns.count)
            let gridWidth = gridWidth(columnCount: columns.count, cellSize: cellSize)
            let gridHeight = gridHeight(cellSize: cellSize)

            VStack(spacing: 8) {
                ZStack(alignment: .topLeading) {
                    HStack(alignment: .top, spacing: gap) {
                        ForEach(columns.indices, id: \.self) { columnIndex in
                            VStack(spacing: gap) {
                                ForEach(0..<rows, id: \.self) { rowIndex in
                                    if let dayIndex = columns[columnIndex][safe: rowIndex],
                                       let summary = summaries[safe: dayIndex] {
                                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .fill(color(for: summary, maxTokens: preparedData.maxTokens))
                                            .frame(width: cellSize, height: cellSize)
                                    } else {
                                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .fill(Color.clear)
                                            .frame(width: cellSize, height: cellSize)
                                    }
                                }
                            }
                        }
                    }

                    if let selectedIndex,
                       summaries.indices.contains(selectedIndex) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(AppTheme.accentBlue, lineWidth: 1.4)
                            .frame(width: cellSize, height: cellSize)
                            .offset(
                                x: CGFloat(selectedIndex / rows) * (cellSize + gap),
                                y: CGFloat(selectedIndex % rows) * (cellSize + gap)
                            )
                            .allowsHitTesting(false)
                    }

                    HoverTrackingArea(
                        onMove: { location in
                            let nextIndex = nearestDayIndex(
                                at: location,
                                columnCount: columns.count,
                                dayCount: summaries.count,
                                cellSize: cellSize
                            )
                            if hoveredIndex != nextIndex {
                                hoveredIndex = nextIndex
                            }
                        },
                        onExit: {
                            if hoveredIndex != nil {
                                hoveredIndex = nil
                            }
                        }
                    )
                    .frame(width: gridWidth, height: gridHeight)
                }
                .frame(width: gridWidth, height: gridHeight, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .leading)

                MonthLabels(markers: preparedData.monthMarkers, cellSize: cellSize, gap: gap)
                HeatmapHoverInfo(summary: hoveredIndex.flatMap { summaries[safe: $0] } ?? summaries.last)
            }
        }
        .frame(height: 180)
        .onAppear(perform: refreshPreparedData)
        .onChange(of: dailyUsage) { _, _ in
            refreshPreparedData()
        }
        .onChange(of: cacheDaily) { _, _ in
            refreshPreparedData()
        }
        .onChange(of: mode) { _, _ in
            hoveredIndex = nil
            refreshPreparedData()
        }
    }

    private func adaptiveCellSize(containerWidth: CGFloat, columnCount: Int) -> CGFloat {
        guard columnCount > 0 else { return 12 }
        let targetWidth = max(0, containerWidth - trailingInset)
        let availableForCells = targetWidth - CGFloat(columnCount - 1) * gap
        return max(10, availableForCells / CGFloat(columnCount))
    }

    private func gridHeight(cellSize: CGFloat) -> CGFloat {
        CGFloat(rows) * cellSize + CGFloat(rows - 1) * gap
    }

    private func gridWidth(columnCount: Int, cellSize: CGFloat) -> CGFloat {
        guard columnCount > 0 else { return 0 }
        return CGFloat(columnCount) * cellSize + CGFloat(columnCount - 1) * gap
    }

    private func nearestDayIndex(at location: CGPoint, columnCount: Int, dayCount: Int, cellSize: CGFloat) -> Int? {
        guard dayCount > 0, columnCount > 0 else { return nil }
        let pitch = cellSize + gap
        let rawColumn = Int(((location.x - cellSize / 2) / pitch).rounded())
        let rawRow = Int(((location.y - cellSize / 2) / pitch).rounded())
        let column = min(max(rawColumn, 0), columnCount - 1)
        let row = min(max(rawRow, 0), rows - 1)
        let center = CGPoint(
            x: CGFloat(column) * pitch + cellSize / 2,
            y: CGFloat(row) * pitch + cellSize / 2
        )
        let distance = hypot(location.x - center.x, location.y - center.y)
        guard distance <= cellSize else { return nil }

        let dayIndex = column * rows + row
        guard dayIndex < dayCount else { return nil }
        return dayIndex
    }

    private func color(for summary: HeatmapUsageSummary, maxTokens: Int) -> Color {
        if summary.isCacheRate {
            guard summary.calls > 0, let cacheBreakdown = summary.cacheBreakdown else {
                return AppTheme.emptyCell
            }
            return AppTheme.cacheHitColor(rate: cacheBreakdown.cacheHitRate)
        }

        let value = summary.tokens
        guard value > 0 else { return AppTheme.emptyCell }
        let ratio = min(1.0, Double(value) / Double(max(maxTokens, 1)))
        return AppTheme.heatmapColor(ratio: ratio)
    }

    private func refreshPreparedData() {
        preparedData = Self.prepare(dailyUsage: dailyUsage, cacheDaily: cacheDaily, mode: mode)
    }

    private static func prepare(dailyUsage: [DayUsage], cacheDaily: [TokenCacheBucket], mode: ActivityMode) -> HeatmapPreparedData {
        let summaries = makeSummaries(dailyUsage: dailyUsage, cacheDaily: cacheDaily, mode: mode)
        let columns = makeColumnIndices(dayCount: summaries.count)
        return HeatmapPreparedData(
            summaries: summaries,
            maxTokens: max(summaries.map(\.tokens).max() ?? 1, 1),
            columns: columns,
            monthMarkers: monthMarkers(dailyUsage: dailyUsage, endColumn: max(columns.count, 1))
        )
    }

    private static func makeColumnIndices(dayCount: Int) -> [[Int]] {
        stride(from: 0, to: dayCount, by: 7).map { start in
            Array(start..<min(start + 7, dayCount))
        }
    }

    private static func makeSummaries(dailyUsage: [DayUsage], cacheDaily: [TokenCacheBucket], mode: ActivityMode) -> [HeatmapUsageSummary] {
        switch mode {
        case .daily:
            return dailyUsage.map { day in
                HeatmapUsageSummary(
                    title: DateFormatter.fullDay.string(from: day.date),
                    tokens: day.tokens,
                    calls: day.calls,
                    iconName: "calendar"
                )
            }
        case .weekly:
            return weeklySummaries(dailyUsage: dailyUsage)
        case .cumulative:
            var runningTokens = 0
            var runningCalls = 0
            return dailyUsage.map { day in
                runningTokens += day.tokens
                runningCalls += day.calls
                return HeatmapUsageSummary(
                    title: "截至 \(DateFormatter.fullDay.string(from: day.date))",
                    tokens: runningTokens,
                    calls: runningCalls,
                    iconName: "sum"
                )
            }
        case .cacheHitRate:
            return cacheHitRateSummaries(dailyUsage: dailyUsage, cacheDaily: cacheDaily)
        }
    }

    private static func cacheHitRateSummaries(dailyUsage: [DayUsage], cacheDaily: [TokenCacheBucket]) -> [HeatmapUsageSummary] {
        let calendar = Calendar.current
        let cacheByDay = Dictionary(uniqueKeysWithValues: cacheDaily.map { bucket in
            (calendar.startOfDay(for: bucket.start), bucket.breakdown)
        })

        return dailyUsage.map { day in
            let date = calendar.startOfDay(for: day.date)
            let breakdown = cacheByDay[date]
            return HeatmapUsageSummary(
                title: DateFormatter.fullDay.string(from: day.date),
                tokens: breakdown?.totalTokens ?? 0,
                calls: breakdown?.calls ?? 0,
                iconName: "bolt.horizontal.circle",
                cacheBreakdown: breakdown,
                isCacheRate: true
            )
        }
    }

    private static func weeklySummaries(dailyUsage: [DayUsage]) -> [HeatmapUsageSummary] {
        let calendar = Calendar.current
        var weekTotals: [String: (tokens: Int, calls: Int, first: Date, last: Date)] = [:]

        for day in dailyUsage {
            let key = "\(calendar.component(.yearForWeekOfYear, from: day.date))-\(calendar.component(.weekOfYear, from: day.date))"
            if let current = weekTotals[key] {
                weekTotals[key] = (
                    current.tokens + day.tokens,
                    current.calls + day.calls,
                    min(current.first, day.date),
                    max(current.last, day.date)
                )
            } else {
                weekTotals[key] = (day.tokens, day.calls, day.date, day.date)
            }
        }

        return dailyUsage.map { day in
            let key = "\(calendar.component(.yearForWeekOfYear, from: day.date))-\(calendar.component(.weekOfYear, from: day.date))"
            let total = weekTotals[key] ?? (day.tokens, day.calls, day.date, day.date)
            return HeatmapUsageSummary(
                title: "\(DateFormatter.monthDay.string(from: total.first)) - \(DateFormatter.monthDay.string(from: total.last))",
                tokens: total.tokens,
                calls: total.calls,
                iconName: "calendar.badge.clock"
            )
        }
    }

    private static func monthMarkers(dailyUsage: [DayUsage], endColumn: Int) -> [HeatmapMonthMarker] {
        guard !dailyUsage.isEmpty else { return [] }

        var markers: [HeatmapMonthMarker] = []
        var previousMonth = -1
        let calendar = Calendar.current

        for (index, day) in dailyUsage.enumerated() {
            let month = calendar.component(.month, from: day.date)
            guard month != previousMonth else { continue }

            previousMonth = month
            let column = index / 7
            let nextColumn = nextMonthColumn(after: index, dailyUsage: dailyUsage) ?? endColumn
            markers.append(HeatmapMonthMarker(label: "\(month)月", column: column, nextColumn: nextColumn))
        }

        return markers
    }

    private static func nextMonthColumn(after index: Int, dailyUsage: [DayUsage]) -> Int? {
        guard index < dailyUsage.count else { return nil }
        let calendar = Calendar.current
        let month = calendar.component(.month, from: dailyUsage[index].date)
        for next in (index + 1)..<dailyUsage.count {
            let nextMonth = calendar.component(.month, from: dailyUsage[next].date)
            if nextMonth != month {
                return next / 7
            }
        }
        return nil
    }

}

struct HeatmapUsageSummary {
    let title: String
    let tokens: Int
    let calls: Int
    let iconName: String
    let cacheBreakdown: TokenCacheBreakdown?
    let isCacheRate: Bool

    init(
        title: String,
        tokens: Int,
        calls: Int,
        iconName: String,
        cacheBreakdown: TokenCacheBreakdown? = nil,
        isCacheRate: Bool = false
    ) {
        self.title = title
        self.tokens = tokens
        self.calls = calls
        self.iconName = iconName
        self.cacheBreakdown = cacheBreakdown
        self.isCacheRate = isCacheRate
    }

    var average: Int {
        calls > 0 ? tokens / calls : 0
    }
}

struct HeatmapHoverInfo: View {
    let summary: HeatmapUsageSummary?

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: summary == nil ? "cursorarrow.rays" : summary?.iconName ?? "calendar")
                .foregroundStyle(summary == nil ? Color.secondary : AppTheme.accentBlue)
            if let summary {
                Text(summary.title)
                    .font(.system(size: 13, weight: .medium))
                if summary.isCacheRate, let breakdown = summary.cacheBreakdown {
                    Text(breakdown.cacheHitRate.percentString)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.accentBlue)
                    Text("命中 \(breakdown.cachedInputTokens.abbreviatedTokens)")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text("未命中 \(breakdown.uncachedInputTokens.abbreviatedTokens)")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text("\(breakdown.calls) calls")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(summary.tokens.abbreviatedTokens) tokens")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.accentBlue)
                    Text("\(summary.calls) calls")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text("avg \(summary.average.abbreviatedTokens)")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Hover a day to inspect token usage")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.insetBackground)
        )
    }
}

private struct MonthLabels: View {
    let markers: [HeatmapMonthMarker]
    let cellSize: CGFloat
    let gap: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            ForEach(markers) { marker in
                Text(marker.label)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: width(for: marker), alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func width(for marker: HeatmapMonthMarker) -> CGFloat {
        CGFloat(max(2, marker.nextColumn - marker.column)) * (cellSize + gap)
    }
}

private enum CacheRankingScope: String, CaseIterable, Identifiable {
    case sessions = "会话"
    case turns = "单轮"

    var id: String { rawValue }
}

private struct CacheRankingItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let context: String?
    let breakdown: TokenCacheBreakdown
}

struct CacheHitRankingSection: View {
    let cacheUsage: TokenCacheUsage
    @State private var scope: CacheRankingScope = .sessions
    @State private var excludesSingleTurnSessions = true
    @State private var excludesFirstTurns = true

    private let minimumInputTokens = 1_000

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("缓存命中排行")
                        .font(.system(size: 19, weight: .semibold))
                    Text(rankingSubtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    CacheRankingCheckmark(
                        isOn: scope == .sessions ? $excludesSingleTurnSessions : $excludesFirstTurns,
                        title: scope == .sessions ? "排除单轮会话" : "排除首轮"
                    )

                    Picker("", selection: $scope) {
                        ForEach(CacheRankingScope.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 132)
                }
            }

            if rankingItems.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "tray")
                    Text("暂无可排行的缓存命中数据")
                }
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 72)
                .background(AppTheme.insetBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                VStack(spacing: 5) {
                    ForEach(Array(rankingItems.enumerated()), id: \.element.id) { index, item in
                        CacheRankingRow(rank: index + 1, item: item)
                    }
                }
            }
        }
        .frame(maxWidth: 980)
    }

    private var rankingItems: [CacheRankingItem] {
        let source: [CacheRankingItem]
        switch scope {
        case .sessions:
            source = cacheUsage.sessions
                .filter { !excludesSingleTurnSessions || $0.breakdown.calls > 1 }
                .map { session in
                CacheRankingItem(
                    id: session.id,
                    title: session.title,
                    subtitle: sessionSubtitle(session),
                    context: nil,
                    breakdown: session.breakdown
                )
            }
        case .turns:
            source = cacheUsage.turns
                .filter { !excludesFirstTurns || $0.turnIndexInSession > 1 }
                .map { turn in
                let time = DateFormatter.monthDayHourMinute.string(from: turn.timestamp)
                return CacheRankingItem(
                    id: turn.id,
                    title: "问：\(turn.userPrompt.isEmpty ? "暂无可见问题" : turn.userPrompt)",
                    subtitle: "答：\(turn.assistantResponse.isEmpty ? "暂无可见回答" : turn.assistantResponse)",
                    context: "\(turn.sessionTitle) · 第 \(turn.turnIndexInSession) 轮 · \(time)",
                    breakdown: turn.breakdown
                )
            }
        }

        return source
            .filter { $0.breakdown.inputTokens >= minimumInputTokens && $0.breakdown.calls > 0 }
            .sorted { lhs, rhs in
                let leftRate = lhs.breakdown.cacheHitRate
                let rightRate = rhs.breakdown.cacheHitRate
                if abs(leftRate - rightRate) > 0.0001 {
                    return leftRate < rightRate
                }
                return lhs.breakdown.uncachedInputTokens > rhs.breakdown.uncachedInputTokens
            }
            .prefix(10)
            .map { $0 }
    }

    private var rankingSubtitle: String {
        switch scope {
        case .sessions:
            return excludesSingleTurnSessions ? "低命中优先 · 已排除只有一轮的会话" : "低命中优先 · 包含单轮会话"
        case .turns:
            return excludesFirstTurns ? "低命中优先 · 已排除每个会话首轮" : "低命中优先 · 包含首轮"
        }
    }

    private func sessionSubtitle(_ session: SessionCacheUsage) -> String {
        let time = session.lastUpdated.map { DateFormatter.monthDayHourMinute.string(from: $0) } ?? "未知时间"
        return "\(session.breakdown.calls) 轮 · \(time)"
    }
}

private struct CacheRankingCheckmark: View {
    @Binding var isOn: Bool
    let title: String

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isOn ? AppTheme.accentBlue : .secondary)
            .padding(.horizontal, 8)
            .frame(height: 25)
            .background(AppTheme.raisedBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isOn ? AppTheme.accentBlue.opacity(0.25) : AppTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct CacheRankingRow: View {
    let rank: Int
    let item: CacheRankingItem

    var body: some View {
        HStack(spacing: 10) {
            Text("\(rank)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.accentBlue)
                .frame(width: 21, height: 21)
                .background(AppTheme.accentBlue.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let context = item.context {
                    Text(context)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            CacheHitMeter(breakdown: item.breakdown)
                .frame(width: 154)

            VStack(alignment: .trailing, spacing: 2) {
                Text(item.breakdown.cacheHitRate.percentString)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.cacheHitColor(rate: item.breakdown.cacheHitRate))
                Text("未命中 \(item.breakdown.uncachedInputTokens.abbreviatedTokens)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 88, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(AppTheme.panelBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
    }
}

private struct CacheHitMeter: View {
    let breakdown: TokenCacheBreakdown

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppTheme.insetBackground)
                    Capsule()
                        .fill(AppTheme.cacheHitColor(rate: breakdown.cacheHitRate))
                        .frame(width: proxy.size.width * CGFloat(max(0, min(1, breakdown.cacheHitRate))))
                    Capsule()
                        .stroke(AppTheme.border, lineWidth: 1)
                }
            }
            .frame(height: 7)

            HStack(spacing: 6) {
                Text("命中 \(breakdown.cachedInputTokens.abbreviatedTokens)")
                Text("输入 \(breakdown.inputTokens.abbreviatedTokens)")
            }
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
        }
    }
}

private struct RecentChartPreparedData {
    let maxTokens: Int
    let maxCalls: Int
    let tokenTotal: Int
    let callTotal: Int
    let recentCacheBreakdown: TokenCacheBreakdown
    let cacheBreakdowns: [TokenCacheBreakdown]
    let carriedCacheHitRates: [Double]
    let hasCacheCalls: Bool
    let markerIndices: [Int]

    static let empty = RecentChartPreparedData(
        maxTokens: 1,
        maxCalls: 1,
        tokenTotal: 0,
        callTotal: 0,
        recentCacheBreakdown: .empty,
        cacheBreakdowns: [],
        carriedCacheHitRates: [],
        hasCacheCalls: false,
        markerIndices: []
    )
}

private struct RecentChartPlotData {
    let tokenPoints: [CGPoint]
    let callPoints: [CGPoint]
    let cachePoints: [CGPoint]

    init(bins: [BinUsage], prepared: RecentChartPreparedData, plot: CGRect, step: CGFloat) {
        tokenPoints = bins.indices.map { index in
            let x = plot.minX + CGFloat(index) * step
            let y = plot.maxY - CGFloat(bins[index].tokens) / CGFloat(prepared.maxTokens) * plot.height
            return CGPoint(x: x, y: y)
        }
        callPoints = bins.indices.map { index in
            let x = plot.minX + CGFloat(index) * step
            let y = plot.maxY - CGFloat(bins[index].calls) / CGFloat(prepared.maxCalls) * plot.height
            return CGPoint(x: x, y: y)
        }
        cachePoints = bins.indices.map { index in
            let x = plot.minX + CGFloat(index) * step
            let rate = prepared.carriedCacheHitRates[safe: index] ?? 0
            let y = plot.maxY - CGFloat(rate) * plot.height
            return CGPoint(x: x, y: y)
        }
    }
}

struct RecentUsageChart: View {
    let bins: [BinUsage]
    let cacheRecentBins: [TokenCacheBucket]
    @State private var hoveredIndex: Int?
    @State private var preparedData: RecentChartPreparedData

    init(bins: [BinUsage], cacheRecentBins: [TokenCacheBucket]) {
        self.bins = bins
        self.cacheRecentBins = cacheRecentBins
        _preparedData = State(initialValue: .empty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("最近 24 小时")
                        .font(.system(size: 19, weight: .semibold))
                    Text("5 分钟粒度 · 5 分钟自动刷新")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 14) {
                    ChartLegend(color: .blue, label: "Token", value: preparedData.tokenTotal.abbreviatedTokens)
                    ChartLegend(color: .orange, label: "调用", value: "\(preparedData.callTotal)")
                    ChartLegend(color: AppTheme.accentCyan, label: "命中率", value: preparedData.recentCacheBreakdown.cacheHitRate.percentString)
                }
            }

            GeometryReader { proxy in
                let plot = CGRect(x: 0, y: 18, width: proxy.size.width, height: proxy.size.height - 42)
                let step = plot.width / CGFloat(max(bins.count - 1, 1))
                let activeIndex = hoveredIndex.flatMap { bins.indices.contains($0) ? $0 : nil } ?? bins.indices.last
                let plotData = RecentChartPlotData(bins: bins, prepared: preparedData, plot: plot, step: step)

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.accentBlue.opacity(0.10), Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: plot.width, height: plot.height)
                        .offset(x: plot.minX, y: plot.minY)

                    ForEach(0..<4, id: \.self) { line in
                        let y = plot.minY + CGFloat(line) * plot.height / 3
                        Path { path in
                            path.move(to: CGPoint(x: plot.minX, y: y))
                            path.addLine(to: CGPoint(x: plot.maxX, y: y))
                        }
                        .stroke(AppTheme.grid, style: StrokeStyle(lineWidth: 1, dash: [4, 8]))
                    }

                    tokenAreaPath(points: plotData.tokenPoints, plot: plot)
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.accentBlue.opacity(0.22), AppTheme.accentBlue.opacity(0.055), Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    linePath(points: plotData.tokenPoints)
                        .stroke(AppTheme.accentBlue, style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round))
                        .shadow(color: AppTheme.accentBlue.opacity(0.18), radius: 5, y: 4)

                    linePath(points: plotData.callPoints)
                        .stroke(AppTheme.accentOrange, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))

                    if preparedData.hasCacheCalls {
                        linePath(points: plotData.cachePoints)
                            .stroke(AppTheme.accentCyan, style: StrokeStyle(lineWidth: 2.1, lineCap: .round, lineJoin: .round, dash: [5, 5]))
                            .shadow(color: AppTheme.accentCyan.opacity(0.16), radius: 4, y: 3)
                    }

                    if let activeIndex {
                        let tokenPoint = plotData.tokenPoints[safe: activeIndex] ?? .zero
                        let callPoint = plotData.callPoints[safe: activeIndex] ?? .zero
                        let cachePoint = plotData.cachePoints[safe: activeIndex] ?? .zero

                        Path { path in
                            path.move(to: CGPoint(x: tokenPoint.x, y: plot.minY))
                            path.addLine(to: CGPoint(x: tokenPoint.x, y: plot.maxY))
                        }
                        .stroke(AppTheme.accentBlue.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))

                        Circle()
                            .fill(AppTheme.pageBackground)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(AppTheme.accentBlue, lineWidth: 3))
                            .position(tokenPoint)

                        Circle()
                            .fill(AppTheme.pageBackground)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(AppTheme.accentOrange, lineWidth: 2.4))
                            .position(callPoint)

                        if preparedData.cacheBreakdowns[safe: activeIndex]?.calls ?? 0 > 0 {
                            Circle()
                                .fill(AppTheme.pageBackground)
                                .frame(width: 9, height: 9)
                                .overlay(Circle().stroke(AppTheme.accentCyan, lineWidth: 2.2))
                                .position(cachePoint)
                        }

                        ChartHoverBubble(
                            bin: bins[activeIndex],
                            cacheBreakdown: preparedData.cacheBreakdowns[safe: activeIndex],
                            isHovering: hoveredIndex != nil
                        )
                            .position(
                                x: min(max(tokenPoint.x + 88, 94), plot.maxX - 94),
                                y: max(plot.minY + 38, tokenPoint.y - 34)
                            )
                    }

                    HoverTrackingArea(
                        onMove: { location in
                            let plotLocation = CGPoint(
                                x: location.x + plot.minX,
                                y: location.y + plot.minY
                            )
                            hoveredIndex = hoverIndex(at: plotLocation, in: plot, step: step)
                        },
                        onExit: {
                            hoveredIndex = nil
                        }
                    )
                    .frame(width: plot.width, height: plot.height)
                    .position(x: plot.midX, y: plot.midY)

                    ChartTimeMarkers(bins: bins, markerIndices: preparedData.markerIndices, plot: plot)
                }
            }
            .frame(height: 185)
        }
        .frame(maxWidth: 980)
        .onAppear(perform: refreshPreparedData)
        .onChange(of: bins) { _, _ in
            refreshPreparedData()
        }
        .onChange(of: cacheRecentBins) { _, _ in
            refreshPreparedData()
        }
    }

    private func linePath(points: [CGPoint]) -> Path {
        Path { path in
            appendSmoothPolyline(points, to: &path)
        }
    }

    private func tokenAreaPath(points: [CGPoint], plot: CGRect) -> Path {
        var path = Path()
        guard let first = points.first, let last = points.last else { return path }
        path.move(to: CGPoint(x: first.x, y: plot.maxY))
        path.addLine(to: first)
        appendSmoothPolyline(points, to: &path, moveToStart: false)
        path.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
        path.addLine(to: CGPoint(x: last.x, y: plot.maxY))
        path.closeSubpath()
        return path
    }

    private func appendSmoothPolyline(_ points: [CGPoint], to path: inout Path, moveToStart: Bool = true) {
        guard let first = points.first else { return }
        if moveToStart {
            path.move(to: first)
        }

        guard points.count > 2 else {
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            return
        }

        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let midpoint = CGPoint(
                x: (previous.x + current.x) / 2,
                y: (previous.y + current.y) / 2
            )
            path.addQuadCurve(to: midpoint, control: previous)
        }

        if let last = points.last {
            path.addLine(to: last)
        }
    }

    private func hoverIndex(at location: CGPoint, in plot: CGRect, step: CGFloat) -> Int? {
        guard plot.contains(location), !bins.isEmpty else { return nil }
        let rawIndex = Int(round((location.x - plot.minX) / max(step, 1)))
        return min(max(rawIndex, bins.startIndex), bins.index(before: bins.endIndex))
    }

    private func refreshPreparedData() {
        preparedData = Self.prepare(bins: bins, cacheRecentBins: cacheRecentBins)
    }

    private static func prepare(bins: [BinUsage], cacheRecentBins: [TokenCacheBucket]) -> RecentChartPreparedData {
        let cacheByStart = Dictionary(uniqueKeysWithValues: cacheRecentBins.map { bucket in
            (bucket.start, bucket.breakdown)
        })
        let cacheBreakdowns = bins.map { bin in
            cacheByStart[bin.start] ?? .empty
        }
        let carriedRates = carriedCacheHitRates(cacheBreakdowns: cacheBreakdowns)
        let last = bins.count - 1
        let markerIndices: [Int] = bins.count > 1
            ? [0, last / 4, last / 2, (last * 3) / 4, last].reduce(into: [Int]()) { result, index in
                if !result.contains(index) {
                    result.append(index)
                }
            }
            : []

        return RecentChartPreparedData(
            maxTokens: max(bins.map(\.tokens).max() ?? 1, 1),
            maxCalls: max(bins.map(\.calls).max() ?? 1, 1),
            tokenTotal: bins.reduce(0) { $0 + $1.tokens },
            callTotal: bins.reduce(0) { $0 + $1.calls },
            recentCacheBreakdown: cacheBreakdowns.combined,
            cacheBreakdowns: cacheBreakdowns,
            carriedCacheHitRates: carriedRates,
            hasCacheCalls: cacheBreakdowns.contains { $0.calls > 0 },
            markerIndices: markerIndices
        )
    }

    private static func carriedCacheHitRates(cacheBreakdowns: [TokenCacheBreakdown]) -> [Double] {
        var carriedRate = cacheBreakdowns.first(where: { $0.calls > 0 })?.cacheHitRate ?? 0
        return cacheBreakdowns.map { breakdown in
            if breakdown.calls > 0 {
                carriedRate = breakdown.cacheHitRate
                return breakdown.cacheHitRate
            }
            return carriedRate
        }
    }
}

struct ChartLegend: View {
    let color: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .foregroundStyle(label == "命中率" ? .primary : .secondary)
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        }
        .font(.system(size: 12))
    }
}

struct ChartHoverBubble: View {
    let bin: BinUsage
    let cacheBreakdown: TokenCacheBreakdown?
    let isHovering: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(isHovering ? "当前点" : "最新点")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isHovering ? AppTheme.accentBlue : .secondary)
                Text(timeRange)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text(bin.tokens.abbreviatedTokens)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.accentBlue)
            Text("请求 \(bin.calls) 次 · avg \(average.abbreviatedTokens)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if let cacheBreakdown, cacheBreakdown.calls > 0 {
                Text("缓存命中 \(cacheBreakdown.cacheHitRate.percentString) · 命中 \(cacheBreakdown.cachedInputTokens.abbreviatedTokens)")
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.accentCyan)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(AppTheme.hoverBubble, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.borderStrong, lineWidth: 1)
        )
        .shadow(color: AppTheme.shadow, radius: 12, y: 7)
    }

    private var average: Int {
        bin.calls > 0 ? bin.tokens / bin.calls : 0
    }

    private var timeRange: String {
        let end = bin.start.addingTimeInterval(5 * 60)
        return "\(DateFormatter.hourMinute.string(from: bin.start)) - \(DateFormatter.hourMinute.string(from: end))"
    }
}

struct ChartTimeMarkers: View {
    let bins: [BinUsage]
    let markerIndices: [Int]
    let plot: CGRect

    var body: some View {
        ForEach(markerIndices, id: \.self) { index in
            if let bin = bins[safe: index] {
                Text(DateFormatter.hourMinute.string(from: bin.start))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .position(x: xPosition(for: index), y: plot.maxY + 20)
            }
        }
    }

    private func xPosition(for index: Int) -> CGFloat {
        plot.minX + CGFloat(index) * plot.width / CGFloat(max(bins.count - 1, 1))
    }
}

struct HoverTrackingArea: NSViewRepresentable {
    let onMove: (CGPoint) -> Void
    let onExit: () -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onMove = onMove
        view.onExit = onExit
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onMove = onMove
        nsView.onExit = onExit
    }

    final class TrackingView: NSView {
        var onMove: ((CGPoint) -> Void)?
        var onExit: (() -> Void)?
        private var currentTrackingArea: NSTrackingArea?

        override var isFlipped: Bool {
            true
        }

        override var acceptsFirstResponder: Bool {
            true
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            bounds.contains(point) ? self : nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.acceptsMouseMovedEvents = true
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            guard currentTrackingArea == nil else { return }
            let area = NSTrackingArea(
                rect: .zero,
                options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
                owner: self,
                userInfo: nil
            )
            currentTrackingArea = area
            addTrackingArea(area)
        }

        override func mouseMoved(with event: NSEvent) {
            onMove?(convert(event.locationInWindow, from: nil))
        }

        override func mouseEntered(with event: NSEvent) {
            onMove?(convert(event.locationInWindow, from: nil))
        }

        override func mouseExited(with event: NSEvent) {
            onExit?()
        }
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension DateFormatter {
    static let monthDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        return formatter
    }()

    static let fullDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月d日"
        return formatter
    }()

    static let hourMinute: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static let monthDayHourMinute: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()
}

extension NumberFormatter {
    static let integer: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()
}
