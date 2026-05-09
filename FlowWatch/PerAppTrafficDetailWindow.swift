import SwiftUI
import AppKit
import Combine

// MARK: - Date Range

enum PerAppDateRange: String, CaseIterable {
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

    var totalBytes: UInt64 { totalDownloaded + totalUploaded }
}

// MARK: - ViewModel

@MainActor
final class PerAppTrafficViewModel: ObservableObject {
    @Published var items: [PerAppTrafficItem] = []
    @Published var historicalItems: [PerAppTrafficItem] = []

    private var cancellable: AnyCancellable?

    func bind(to monitor: ProcessNetworkMonitor) {
        cancellable = monitor.$appTrafficRates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rates in
                self?.items = rates.map { rate in
                    PerAppTrafficItem(
                        id: rate.id,
                        displayName: rate.displayName,
                        icon: rate.icon,
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
        DispatchQueue.global(qos: .userInitiated).async {
            let storage = ProcessTrafficStorage.shared
            let aggregated: [(bundleID: String, displayName: String, downloadBytes: UInt64, uploadBytes: UInt64)]

            switch range {
            case .today:
                return
            case .last7Days:
                let end = Date()
                let start = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: end))!
                aggregated = storage.getAggregatedRecords(from: start, to: end)
            case .last30Days:
                let end = Date()
                let start = Calendar.current.date(byAdding: .day, value: -29, to: Calendar.current.startOfDay(for: end))!
                aggregated = storage.getAggregatedRecords(from: start, to: end)
            case .allTime:
                aggregated = storage.getAllRecordsAggregated()
            }

            DispatchQueue.main.async {
                self.historicalItems = aggregated.map { record -> PerAppTrafficItem in
                    let icon = self.resolveIcon(bundleID: record.bundleID)
                    let isApp = record.bundleID.contains(".") && !record.bundleID.hasPrefix("/")
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
            }
        }
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

    private func makeWindow() -> NSWindow {
        let hostingController = NSHostingController(
            rootView: LocalizedRootView { PerAppTrafficDetailView() }
                .environmentObject(LocalizationManager.shared)
                .environmentObject(detailViewModel!)
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = LocalizationManager.shared.t("perApp.detail.title")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 720, height: 520))
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
            self.window = makeWindow()
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

enum PerAppFilterMode: String, CaseIterable {
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
    @State private var sortMode: PerAppSortMode = .totalDesc
    @State private var filterMode: PerAppFilterMode = .all
    @State private var dateRange: PerAppDateRange = .today

    private let downloadColumnWidth: CGFloat = 96
    private let uploadColumnWidth: CGFloat = 96
    private let speedColumnWidth: CGFloat = 104

    private var isToday: Bool { dateRange == .today }

    private var sourceItems: [PerAppTrafficItem] {
        isToday ? viewModel.items : viewModel.historicalItems
    }

    private var filteredItems: [PerAppTrafficItem] {
        switch filterMode {
        case .all:
            return sourceItems
        case .appsOnly:
            return sourceItems.filter { $0.isApp }
        case .processesOnly:
            return sourceItems.filter { !$0.isApp }
        }
    }

    private var sortedItems: [PerAppTrafficItem] {
        let effectiveSort: PerAppSortMode
        if !isToday && (sortMode == .downloadSpeedDesc || sortMode == .uploadSpeedDesc) {
            effectiveSort = .totalDesc
        } else {
            effectiveSort = sortMode
        }

        return filteredItems.sorted { a, b in
            switch effectiveSort {
            case .totalDesc:
                return a.totalBytes > b.totalBytes
            case .downloadDesc:
                return a.totalDownloaded > b.totalDownloaded
            case .uploadDesc:
                return a.totalUploaded > b.totalUploaded
            case .downloadSpeedDesc:
                return a.downloadBps > b.downloadBps
            case .uploadSpeedDesc:
                return a.uploadBps > b.uploadBps
            }
        }
    }

    private var totalDownloaded: UInt64 {
        sortedItems.reduce(0) { $0 &+ $1.totalDownloaded }
    }

    private var totalUploaded: UInt64 {
        sortedItems.reduce(0) { $0 &+ $1.totalUploaded }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            summaryBar
            Divider()
            content
        }
        .frame(minWidth: 640, minHeight: 420)
        .onChange(of: dateRange) { newRange in
            if newRange != .today {
                viewModel.loadHistoricalData(range: newRange)
            }
            if newRange != .today && (sortMode == .downloadSpeedDesc || sortMode == .uploadSpeedDesc) {
                sortMode = .totalDesc
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("", selection: $dateRange) {
                ForEach(PerAppDateRange.allCases, id: \.self) { range in
                    Text(dateRangeLabel(range)).tag(range)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 280)

            Picker("", selection: $filterMode) {
                Text(l10n.t("perApp.filter.all")).tag(PerAppFilterMode.all)
                Text(l10n.t("perApp.filter.apps")).tag(PerAppFilterMode.appsOnly)
                Text(l10n.t("perApp.filter.processes")).tag(PerAppFilterMode.processesOnly)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 210)

            Spacer(minLength: 12)

            Picker("", selection: $sortMode) {
                Text(l10n.t("perApp.sort.total")).tag(PerAppSortMode.totalDesc)
                Text(l10n.t("perApp.sort.download")).tag(PerAppSortMode.downloadDesc)
                Text(l10n.t("perApp.sort.upload")).tag(PerAppSortMode.uploadDesc)
                if isToday {
                    Text(l10n.t("perApp.sort.downloadSpeed")).tag(PerAppSortMode.downloadSpeedDesc)
                    Text(l10n.t("perApp.sort.uploadSpeed")).tag(PerAppSortMode.uploadSpeedDesc)
                }
            }
            .labelsHidden()
            .frame(width: 170)
        }
        .controlSize(.small)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.windowBackgroundColor))
    }

    private var summaryBar: some View {
        HStack(spacing: 10) {
            summaryMetric(
                title: l10n.t("perApp.summary.totalDownload"),
                value: formatBytes(totalDownloaded),
                color: .blue
            )
            summaryMetric(
                title: l10n.t("perApp.summary.totalUpload"),
                value: formatBytes(totalUploaded),
                color: .orange
            )

            Spacer()

            Text(String(format: l10n.t("perApp.appCount"), sortedItems.count))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.controlBackgroundColor).opacity(0.30))
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
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.windowBackgroundColor).opacity(0.82), in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var content: some View {
        if sortedItems.isEmpty {
            emptyState
        } else {
            tableView
        }
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
        .background(Color(.windowBackgroundColor))
    }

    private var tableView: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: []) {
                tableHeader

                ForEach(Array(sortedItems.enumerated()), id: \.element.id) { index, item in
                    detailRow(item, isAlternate: index % 2 == 1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.windowBackgroundColor))
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
                appIcon(for: item)

                Text(item.displayName)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(formatBytes(item.totalDownloaded))
                .font(.system(size: 11, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.blue)
                .frame(width: downloadColumnWidth, alignment: .trailing)

            Text(formatBytes(item.totalUploaded))
                .font(.system(size: 11, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.orange)
                .frame(width: uploadColumnWidth, alignment: .trailing)

            if isToday {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(formatSpeed(item.downloadBps) + " ↓")
                        .foregroundStyle(.blue.opacity(0.78))
                    Text(formatSpeed(item.uploadBps) + " ↑")
                        .foregroundStyle(.orange.opacity(0.78))
                }
                .font(.system(size: 10, design: .monospaced))
                .monospacedDigit()
                .frame(width: speedColumnWidth, alignment: .trailing)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            (isAlternate ? Color(.controlBackgroundColor).opacity(0.30) : Color.clear),
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
    }

    private func appIcon(for item: PerAppTrafficItem) -> some View {
        Group {
            if let icon = item.icon {
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
