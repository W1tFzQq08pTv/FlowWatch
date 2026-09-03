import AppKit
import Combine
import SwiftUI

// MARK: - Date Range

enum PerAppDateRange: String, CaseIterable, Sendable {
    case today
    case last7Days
    case last30Days
    case allTime
}

// MARK: - Data Model

struct PerAppTrafficItem: Identifiable {
    let id: String
    let displayName: String
    let icon: NSImage?
    let isApp: Bool
    let downloadBps: Double
    let uploadBps: Double
    let totalDownloaded: UInt64
    let totalUploaded: UInt64

    var totalBytes: UInt64 { totalDownloaded &+ totalUploaded }
}

private struct PerAppTrafficAggregate: Sendable {
    let bundleID: String
    let displayName: String
    let isApp: Bool?
    let downloadBytes: UInt64
    let uploadBytes: UInt64

    nonisolated var totalBytes: UInt64 { downloadBytes &+ uploadBytes }
}

// MARK: - ViewModel

@MainActor
final class PerAppTrafficViewModel: ObservableObject {
    @Published private(set) var items: [PerAppTrafficItem] = []
    @Published private(set) var historicalItems: [PerAppTrafficItem] = []
    @Published private(set) var historicalCharts = PerAppTrafficHistoricalCharts.empty
    @Published private(set) var isLoadingHistorical = false

    private var cancellable: AnyCancellable?
    private var historicalLoadGeneration = 0
    private var iconCache: [String: NSImage] = [:]
    private var missingIconIDs: Set<String> = []

    func bind(to monitor: ProcessNetworkMonitor) {
        cancellable = monitor.$appTrafficRates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rates in
                guard let self else { return }
                self.items = rates.map { rate in
                    if let icon = rate.icon {
                        self.iconCache[rate.id] = icon
                        self.missingIconIDs.remove(rate.id)
                    }
                    let resolvedIcon = rate.icon ?? self.iconCache[rate.id]
                    return PerAppTrafficItem(
                        id: rate.id,
                        displayName: rate.displayName,
                        icon: resolvedIcon,
                        isApp: rate.isApp,
                        downloadBps: rate.downloadBps,
                        uploadBps: rate.uploadBps,
                        totalDownloaded: rate.totalDownloaded,
                        totalUploaded: rate.totalUploaded
                    )
                }
            }
    }

    func loadHistoricalData(range: PerAppDateRange) {
        historicalLoadGeneration += 1
        let generation = historicalLoadGeneration

        guard range != .today else {
            historicalItems = []
            historicalCharts = .empty
            isLoadingHistorical = false
            return
        }

        isLoadingHistorical = true
        historicalItems = []
        historicalCharts = .empty

        let bounds = Self.dateBounds(for: range)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let storage = ProcessTrafficStorage.shared
            let records: [AppDailyTrafficRecord]
            if let startDate = bounds.start, let endDate = bounds.end {
                records = storage.getRecords(from: startDate, to: endDate)
            } else {
                records = storage.getAllRecords()
            }
            let aggregated = Self.aggregate(records: records)
            let charts = PerAppTrafficSummaryBuilder.makeHistoricalCharts(
                records: records,
                range: range
            )

            DispatchQueue.main.async {
                guard let self, self.historicalLoadGeneration == generation else { return }
                var remainingChartIconCount = PerAppTrafficSummaryConstants.topLimit
                self.historicalItems = aggregated.map { record in
                    let isApp = record.isApp ?? Self.isApplicationIdentifier(record.bundleID)
                    let icon: NSImage?
                    if isApp && remainingChartIconCount > 0 {
                        icon = self.cachedIcon(bundleID: record.bundleID)
                        remainingChartIconCount -= 1
                    } else {
                        icon = nil
                    }
                    return PerAppTrafficItem(
                        id: record.bundleID,
                        displayName: record.displayName,
                        icon: icon,
                        isApp: isApp,
                        downloadBps: 0,
                        uploadBps: 0,
                        totalDownloaded: record.downloadBytes,
                        totalUploaded: record.uploadBytes
                    )
                }
                self.historicalCharts = charts
                self.isLoadingHistorical = false
            }
        }
    }

    nonisolated private static func aggregate(
        records: [AppDailyTrafficRecord]
    ) -> [PerAppTrafficAggregate] {
        var aggregated: [String: (
            displayName: String,
            isApp: Bool?,
            download: UInt64,
            upload: UInt64
        )] = [:]

        for record in records {
            if var current = aggregated[record.bundleID] {
                current.displayName = record.displayName
                current.isApp = record.isApp ?? current.isApp
                current.download &+= record.downloadBytes
                current.upload &+= record.uploadBytes
                aggregated[record.bundleID] = current
            } else {
                aggregated[record.bundleID] = (
                    record.displayName,
                    record.isApp,
                    record.downloadBytes,
                    record.uploadBytes
                )
            }
        }

        return aggregated.map { bundleID, value in
            PerAppTrafficAggregate(
                bundleID: bundleID,
                displayName: value.displayName,
                isApp: value.isApp,
                downloadBytes: value.download,
                uploadBytes: value.upload
            )
        }
        .sorted { lhs, rhs in
            if lhs.totalBytes == rhs.totalBytes {
                return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
            return lhs.totalBytes > rhs.totalBytes
        }
    }

    nonisolated private static func dateBounds(
        for range: PerAppDateRange
    ) -> (start: Date?, end: Date?) {
        let calendar = Calendar.current
        let endDate = calendar.startOfDay(for: Date())
        switch range {
        case .today:
            return (endDate, endDate)
        case .last7Days:
            return (calendar.date(byAdding: .day, value: -6, to: endDate), endDate)
        case .last30Days:
            return (calendar.date(byAdding: .day, value: -29, to: endDate), endDate)
        case .allTime:
            return (nil, nil)
        }
    }

    nonisolated private static func isApplicationIdentifier(_ identifier: String) -> Bool {
        if identifier.hasPrefix("/") {
            return identifier.hasSuffix(".app")
        }
        return identifier.contains(".")
    }

    private func cachedIcon(bundleID: String) -> NSImage? {
        if let cached = iconCache[bundleID] {
            return cached
        }
        guard !missingIconIDs.contains(bundleID) else { return nil }

        guard let icon = resolveIcon(bundleID: bundleID) else {
            missingIconIDs.insert(bundleID)
            return nil
        }
        iconCache[bundleID] = icon
        return icon
    }

    func resolvedIcon(for item: PerAppTrafficItem) -> NSImage? {
        item.icon ?? cachedIcon(bundleID: item.id)
    }

    private func resolveIcon(bundleID: String) -> NSImage? {
        if bundleID.hasPrefix("/") {
            return nil
        }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        icon.size = NSSize(width: 18, height: 18)
        return icon
    }
}

// MARK: - Window Controller

final class PerAppTrafficDetailWindowController: NSWindowController, NSWindowDelegate {
    static let shared = PerAppTrafficDetailWindowController()

    private var detailViewModel: PerAppTrafficViewModel?

    private init() {
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func makeWindow() -> NSWindow? {
        guard let detailViewModel else { return nil }
        let hostingController = NSHostingController(
            rootView: LocalizedRootView {
                PerAppTrafficDetailView()
            }
                .environmentObject(LocalizationManager.shared)
                .environmentObject(detailViewModel)
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = LocalizationManager.shared.t("perApp.detail.title")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 980, height: 740))
        window.delegate = self
        return window
    }

    func bindMonitor(_ monitor: ProcessNetworkMonitor) {
        if detailViewModel == nil {
            detailViewModel = PerAppTrafficViewModel()
        }
        detailViewModel!.bind(to: monitor)
    }

    func show() {
        if window == nil {
            guard let window = makeWindow() else {
                LogManager.shared.log(
                    "Per-app traffic detail window opened before monitor binding",
                    level: .warn
                )
                return
            }
            self.window = window
        }
        window?.title = LocalizationManager.shared.t("perApp.detail.title")
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        LaunchAtLoginManager.shared.presentPromptIfNeeded(on: window)
    }

    func windowWillClose(_ notification: Notification) {
        LogManager.shared.log("Per-app traffic detail window will close")
        window?.contentViewController = nil
        window = nil
    }
}

// MARK: - Filter & Sort

enum PerAppFilterMode: String, CaseIterable, Sendable {
    case all
    case appsOnly
    case processesOnly
}

enum PerAppSortMode: String, CaseIterable {
    case totalDesc
    case downloadDesc
    case uploadDesc
    case downloadSpeedDesc
    case uploadSpeedDesc
}

// MARK: - Detail View

struct PerAppTrafficDetailView: View {
    @EnvironmentObject private var viewModel: PerAppTrafficViewModel
    @EnvironmentObject private var l10n: LocalizationManager
    @State private var sortMode: PerAppSortMode = .downloadSpeedDesc
    @State private var filterMode: PerAppFilterMode = .all
    @State private var dateRange: PerAppDateRange = .today

    private let downloadColumnWidth: CGFloat = 96
    private let uploadColumnWidth: CGFloat = 96
    private let speedColumnWidth: CGFloat = 104

    private var isToday: Bool { dateRange == .today }

    private var sourceItems: [PerAppTrafficItem] {
        isToday ? viewModel.items : viewModel.historicalItems
    }

    private func makeVisibleItems() -> [PerAppTrafficItem] {
        let filteredItems: [PerAppTrafficItem]
        switch filterMode {
        case .all:
            filteredItems = sourceItems
        case .appsOnly:
            filteredItems = sourceItems.filter { $0.isApp }
        case .processesOnly:
            filteredItems = sourceItems.filter { !$0.isApp }
        }

        let effectiveSort: PerAppSortMode
        if !isToday && (sortMode == .downloadSpeedDesc || sortMode == .uploadSpeedDesc) {
            effectiveSort = .totalDesc
        } else {
            effectiveSort = sortMode
        }

        return filteredItems.sorted { lhs, rhs in
            switch effectiveSort {
            case .totalDesc:
                if lhs.totalBytes != rhs.totalBytes {
                    return lhs.totalBytes > rhs.totalBytes
                }
            case .downloadDesc:
                if lhs.totalDownloaded != rhs.totalDownloaded {
                    return lhs.totalDownloaded > rhs.totalDownloaded
                }
            case .uploadDesc:
                if lhs.totalUploaded != rhs.totalUploaded {
                    return lhs.totalUploaded > rhs.totalUploaded
                }
            case .downloadSpeedDesc:
                if lhs.downloadBps != rhs.downloadBps {
                    return lhs.downloadBps > rhs.downloadBps
                }
            case .uploadSpeedDesc:
                if lhs.uploadBps != rhs.uploadBps {
                    return lhs.uploadBps > rhs.uploadBps
                }
            }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
    }

    private var sortOptions: [(String, PerAppSortMode)] {
        var options: [(String, PerAppSortMode)] = [
            (l10n.t("perApp.sort.total"), .totalDesc),
            (l10n.t("perApp.sort.download"), .downloadDesc),
            (l10n.t("perApp.sort.upload"), .uploadDesc)
        ]
        if isToday {
            options.append((l10n.t("perApp.sort.downloadSpeed"), .downloadSpeedDesc))
            options.append((l10n.t("perApp.sort.uploadSpeed"), .uploadSpeedDesc))
        }
        return options
    }

    var body: some View {
        let visibleItems = makeVisibleItems()
        let chartSnapshot = isToday
            ? PerAppTrafficSummaryBuilder.makeToday(items: visibleItems)
            : viewModel.historicalCharts.snapshot(for: filterMode)

        VStack(spacing: 0) {
            toolbar
                .zIndex(10)
            Divider()
            PerAppTrafficSummaryChartsView(
                snapshot: chartSnapshot,
                range: dateRange,
                isLoading: !isToday && viewModel.isLoadingHistorical
            )
            .equatable()
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .zIndex(2)
            Divider()
            summaryBar(items: visibleItems)
                .zIndex(1)
            Divider()
            content(items: visibleItems)
                .zIndex(0)
        }
        .frame(minWidth: 820, minHeight: 640)
        .flowWatchWindowSurface()
        .onChange(of: dateRange) { newRange in
            viewModel.loadHistoricalData(range: newRange)
            if newRange != .today && (sortMode == .downloadSpeedDesc || sortMode == .uploadSpeedDesc) {
                sortMode = .totalDesc
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            dateRangeControl
            filterControl
            Spacer(minLength: 12)
            sortControl
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
    }

    private var dateRangeControl: some View {
        FlowWatchSegmentedControl(
            options: PerAppDateRange.allCases.map { (dateRangeLabel($0), $0) },
            selection: $dateRange,
            tint: FlowWatchPalette.accent
        )
    }

    private var filterControl: some View {
        FlowWatchSegmentedControl(
            options: [
                (l10n.t("perApp.filter.all"), .all),
                (l10n.t("perApp.filter.apps"), .appsOnly),
                (l10n.t("perApp.filter.processes"), .processesOnly)
            ],
            selection: $filterMode,
            tint: FlowWatchPalette.accent
        )
    }

    private var sortControl: some View {
        FlowWatchMenuControl(
            options: sortOptions,
            selection: $sortMode,
            tint: FlowWatchPalette.accent,
            width: 190
        )
    }

    private func summaryBar(items: [PerAppTrafficItem]) -> some View {
        let totals = items.reduce(into: (download: UInt64(0), upload: UInt64(0))) { result, item in
            result.download &+= item.totalDownloaded
            result.upload &+= item.totalUploaded
        }
        return HStack(spacing: 10) {
            summaryMetric(
                title: l10n.t("perApp.summary.totalDownload"),
                value: formatBytes(totals.download),
                color: FlowWatchPalette.download
            )
            summaryMetric(
                title: l10n.t("perApp.summary.totalUpload"),
                value: formatBytes(totals.upload),
                color: FlowWatchPalette.upload
            )

            Spacer()

            if !isToday && viewModel.isLoadingHistorical {
                ProgressView()
                    .controlSize(.small)
                    .help(l10n.t("perApp.chart.loading"))
            } else {
                Text(String(format: l10n.t("perApp.appCount"), items.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func summaryMetric(title: String, value: String, color: Color) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private func content(items: [PerAppTrafficItem]) -> some View {
        if !isToday && viewModel.isLoadingHistorical {
            loadingState
        } else if items.isEmpty {
            emptyState
        } else {
            tableView(items: items)
        }
    }

    private var loadingState: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.regular)
            Text(l10n.t("perApp.chart.loading"))
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "network.slash")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(.secondary)
            Text(l10n.t("perApp.noData"))
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func tableView(items: [PerAppTrafficItem]) -> some View {
        FlowWatchThinScrollView {
            LazyVStack(spacing: 0, pinnedViews: []) {
                tableHeader

                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    detailRow(item, isAlternate: index % 2 == 1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private var tableHeader: some View {
        HStack(spacing: 10) {
            Text(l10n.t("perApp.header.app"))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(l10n.t("daily.download"))
                .frame(width: downloadColumnWidth, alignment: .trailing)
            Text(l10n.t("daily.upload"))
                .frame(width: uploadColumnWidth, alignment: .trailing)
            if isToday {
                Text(l10n.t("perApp.header.speed"))
                    .frame(width: speedColumnWidth, alignment: .trailing)
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    private func detailRow(_ item: PerAppTrafficItem, isAlternate: Bool) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                appIcon(for: item, resolvedIcon: viewModel.resolvedIcon(for: item))

                Text(item.displayName)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(formatBytes(item.totalDownloaded))
                .font(.system(size: 11, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(FlowWatchPalette.download)
                .frame(width: downloadColumnWidth, alignment: .trailing)

            Text(formatBytes(item.totalUploaded))
                .font(.system(size: 11, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(FlowWatchPalette.upload)
                .frame(width: uploadColumnWidth, alignment: .trailing)

            if isToday {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(formatSpeed(item.downloadBps) + " ↓")
                        .foregroundStyle(FlowWatchPalette.download.opacity(0.78))
                    Text(formatSpeed(item.uploadBps) + " ↑")
                        .foregroundStyle(FlowWatchPalette.upload.opacity(0.78))
                }
                .font(.system(size: 10, design: .monospaced))
                .monospacedDigit()
                .frame(width: speedColumnWidth, alignment: .trailing)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            isAlternate ? AnyShapeStyle(Color.primary.opacity(0.025)) : AnyShapeStyle(Color.clear),
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
    }

    private func appIcon(for item: PerAppTrafficItem, resolvedIcon: NSImage?) -> some View {
        Group {
            if let icon = resolvedIcon {
                Image(nsImage: icon)
                    .resizable()
            } else {
                Image(systemName: "app.dashed")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 20, height: 20)
    }

    private func dateRangeLabel(_ range: PerAppDateRange) -> String {
        switch range {
        case .today:
            return l10n.t("perApp.range.today")
        case .last7Days:
            return l10n.t("perApp.range.last7Days")
        case .last30Days:
            return l10n.t("perApp.range.last30Days")
        case .allTime:
            return l10n.t("perApp.range.allTime")
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let kb = Double(bytes) / 1024
        if kb >= 1024 * 1024 {
            return String(format: "%.2f GB", kb / (1024 * 1024))
        } else if kb >= 1024 {
            return String(format: "%.1f MB", kb / 1024)
        } else if kb >= 1 {
            return String(format: "%.0f KB", kb)
        } else {
            return "\(bytes) B"
        }
    }

    private func formatSpeed(_ bytesPerSecond: Double) -> String {
        let kb = max(bytesPerSecond, 0) / 1024
        if kb >= 1024 {
            return String(format: "%.1f MB/s", kb / 1024)
        } else if kb >= 1 {
            return String(format: "%.0f KB/s", kb)
        } else if bytesPerSecond > 0 {
            return String(format: "%.0f B/s", bytesPerSecond)
        } else {
            return "0 KB/s"
        }
    }
}
