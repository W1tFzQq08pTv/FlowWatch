import AppKit
import Combine
import SwiftUI

final class TrafficStatisticsDetailWindowController: NSWindowController, NSWindowDelegate {
    static let shared = TrafficStatisticsDetailWindowController()

    private init() {
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func makeWindow() -> NSWindow {
        let hostingController = NSHostingController(
            rootView: LocalizedRootView { TrafficStatisticsDetailView() }
                .environmentObject(LocalizationManager.shared)
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = LocalizationManager.shared.t("statistics.title")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 720, height: 560))
        window.minSize = NSSize(width: 660, height: 500)
        window.delegate = self
        return window
    }

    func show() {
        if window == nil {
            self.window = makeWindow()
        }
        window?.title = LocalizationManager.shared.t("statistics.title")
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentViewController = nil
        window = nil
    }
}

struct TrafficStatisticsDetailView: View {
    @EnvironmentObject private var l10n: LocalizationManager
    @StateObject private var viewModel = TrafficStatisticsDetailViewModel()
    @State private var selectedSection: StatisticsSection = .overview

    private var summary: TrafficStatisticsSummary {
        viewModel.summary
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Divider()

            detailPane
        }
        .background(.regularMaterial)
        .frame(minWidth: 660, minHeight: 500)
        .onAppear {
            viewModel.reload()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 6) {
                ForEach(StatisticsSection.allCases) { section in
                    sidebarRow(section)
                }
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 218)
        .background(.regularMaterial)
    }

    private func sidebarRow(_ section: StatisticsSection) -> some View {
        let isSelected = selectedSection == section

        return Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                selectedSection = section
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(section.tint)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.t(section.titleKey))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)

                    Text(l10n.t(section.subtitleKey))
                        .font(.caption2)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? section.tint.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var detailPane: some View {
        FlowWatchThinScrollView {
            VStack(alignment: .leading, spacing: 16) {
                detailHeader

                if !summary.hasData {
                    emptyState
                }

                selectedContent
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(.ultraThinMaterial)
    }

    private var detailHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: selectedSection.systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(selectedSection.tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(l10n.t(selectedSection.titleKey))
                    .font(.system(size: 24, weight: .semibold))
                Text(l10n.t(selectedSection.descriptionKey))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Text(l10n.t("settings.data.localOnly"))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) {
            Divider()
                .opacity(0.45)
        }
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedSection {
        case .overview:
            overviewSection
        case .trends:
            trendSection
        case .fun:
            funSection
        }
    }

    private var emptyState: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(l10n.t("statistics.empty.title"))
                    .font(.headline)
                Text(l10n.t("statistics.empty.subtitle"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Divider()
                .opacity(0.35)
        }
    }

    private var overviewSection: some View {
        statisticsPanel(title: l10n.t("statistics.section.overview"), systemImage: "square.grid.2x2") {
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 10) {
                metricCard(
                    title: l10n.t("statistics.overview.totalDownload"),
                    value: TrafficStatsFormatter.bytes(summary.totalDownloaded),
                    caption: l10n.t("daily.download"),
                    tint: .blue
                )
                metricCard(
                    title: l10n.t("statistics.overview.totalUpload"),
                    value: TrafficStatsFormatter.bytes(summary.totalUploaded),
                    caption: l10n.t("daily.upload"),
                    tint: .orange
                )
                metricCard(
                    title: l10n.t("statistics.overview.totalTraffic"),
                    value: TrafficStatsFormatter.bytes(summary.totalBytes),
                    caption: l10n.t("statistics.range.allHistory"),
                    tint: .purple
                )
                metricCard(
                    title: l10n.t("statistics.overview.todayTraffic"),
                    value: TrafficStatsFormatter.bytes(summary.todayTotalBytes),
                    caption: l10n.t("daily.today"),
                    tint: .indigo
                )
                metricCard(
                    title: l10n.t("statistics.overview.yesterdayTraffic"),
                    value: TrafficStatsFormatter.bytes(summary.yesterdayTotalBytes),
                    caption: l10n.t("statistics.trend.dayOverDay.caption"),
                    tint: .mint
                )
                metricCard(
                    title: l10n.t("statistics.overview.recordDays"),
                    value: String(format: l10n.t("statistics.value.days"), summary.recordDays),
                    caption: l10n.t("daily.section.allHistory"),
                    tint: .green
                )
                metricCard(
                    title: l10n.t("statistics.overview.activeDays"),
                    value: String(format: l10n.t("statistics.value.days"), summary.activeDays),
                    caption: l10n.t("daily.fun.activeDays.subtitle"),
                    tint: .teal
                )
            }
        }
    }

    private var trendSection: some View {
        statisticsPanel(title: l10n.t("statistics.section.trends"), systemImage: "chart.xyaxis.line") {
            VStack(spacing: 8) {
                detailRow(
                    title: l10n.t("statistics.trend.last7Total"),
                    value: TrafficStatsFormatter.bytes(summary.last7TotalBytes),
                    caption: l10n.t("statistics.range.last7Days"),
                    tint: .blue
                )
                detailRow(
                    title: l10n.t("statistics.trend.last7Average"),
                    value: TrafficStatsFormatter.bytes(summary.last7AverageBytes),
                    caption: l10n.t("statistics.trend.naturalDays"),
                    tint: .indigo
                )
                detailRow(
                    title: l10n.t("statistics.trend.historyAverage"),
                    value: TrafficStatsFormatter.bytes(summary.historyAverageBytes),
                    caption: l10n.t("daily.section.allHistory"),
                    tint: .purple
                )
                detailRow(
                    title: l10n.t("statistics.trend.activeDayAverage"),
                    value: TrafficStatsFormatter.bytes(summary.activeDayAverageBytes),
                    caption: l10n.t("statistics.trend.activeDayAverage.caption"),
                    tint: .teal
                )
                detailRow(
                    title: l10n.t("statistics.trend.last30Total"),
                    value: TrafficStatsFormatter.bytes(summary.last30TotalBytes),
                    caption: l10n.t("statistics.range.last30Days"),
                    tint: .cyan
                )
                detailRow(
                    title: l10n.t("statistics.trend.last30Average"),
                    value: TrafficStatsFormatter.bytes(summary.last30AverageBytes),
                    caption: l10n.t("statistics.trend.naturalDays30"),
                    tint: .mint
                )
                detailRow(
                    title: l10n.t("daily.fun.dayOverDay.title"),
                    value: dayOverDayValue,
                    caption: l10n.t("statistics.trend.dayOverDay.caption"),
                    tint: dayOverDayTint
                )
                detailRow(
                    title: l10n.t("daily.fun.peak.title"),
                    value: TrafficStatsFormatter.bytes(summary.last7Peak?.bytes ?? 0),
                    caption: summary.last7Peak.map { dateText($0.date) } ?? l10n.t("daily.peak.noData"),
                    tint: .orange
                )
                detailRow(
                    title: l10n.t("statistics.trend.allTimePeak"),
                    value: TrafficStatsFormatter.bytes(summary.allTimePeak?.bytes ?? 0),
                    caption: summary.allTimePeak.map { dateText($0.date) } ?? l10n.t("daily.peak.noData"),
                    tint: .pink
                )
            }
        }
    }

    private var funSection: some View {
        statisticsPanel(title: l10n.t("daily.fun.title"), systemImage: "sparkles") {
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.pink)
                        .frame(width: 30)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(personaTitle)
                            .font(.system(size: 18, weight: .semibold))
                        Text(String(format: l10n.t("statistics.fun.personaSubtitle"), TrafficStatsFormatter.bytes(summary.last7TotalBytes)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) {
                    Divider()
                        .opacity(0.30)
                }

                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 10) {
                    metricCard(
                        title: l10n.t("daily.fun.coefficient.title"),
                        value: TrafficStatsFormatter.ratio(upload: summary.last7Uploaded, download: summary.last7Downloaded),
                        caption: l10n.t("daily.fun.coefficient.subtitle"),
                        tint: .purple
                    )
                    metricCard(
                        title: l10n.t("statistics.fun.downloadShare"),
                        value: TrafficStatsFormatter.percent(summary.last7DownloadShare),
                        caption: l10n.t("statistics.range.last7Days"),
                        tint: .blue
                    )
                    metricCard(
                        title: l10n.t("statistics.fun.uploadShare"),
                        value: TrafficStatsFormatter.percent(summary.last7UploadShare),
                        caption: l10n.t("statistics.range.last7Days"),
                        tint: .orange
                    )
                    metricCard(
                        title: l10n.t("statistics.fun.activeRate"),
                        value: TrafficStatsFormatter.percent(summary.activeRate),
                        caption: l10n.t("statistics.range.allHistory"),
                        tint: .green
                    )
                    metricCard(
                        title: l10n.t("statistics.fun.currentStreak"),
                        value: String(format: l10n.t("statistics.value.days"), summary.currentActiveStreak),
                        caption: l10n.t("statistics.fun.currentStreak.caption"),
                        tint: .teal
                    )
                    metricCard(
                        title: l10n.t("statistics.fun.longestStreak"),
                        value: String(format: l10n.t("statistics.value.days"), summary.longestActiveStreak),
                        caption: l10n.t("statistics.fun.longestStreak.caption"),
                        tint: .indigo
                    )
                    metricCard(
                        title: l10n.t("statistics.fun.quietDays"),
                        value: String(format: l10n.t("statistics.value.days"), summary.last7QuietDays),
                        caption: l10n.t("statistics.range.last7Days"),
                        tint: .secondary
                    )
                    metricCard(
                        title: l10n.t("statistics.fun.peakDownloadDate"),
                        value: dateText(summary.peakDownloadDate?.date),
                        caption: summary.peakDownloadDate.map { TrafficStatsFormatter.bytes($0.bytes) } ?? l10n.t("daily.peak.noData"),
                        tint: .blue
                    )
                    metricCard(
                        title: l10n.t("statistics.fun.peakUploadDate"),
                        value: dateText(summary.peakUploadDate?.date),
                        caption: summary.peakUploadDate.map { TrafficStatsFormatter.bytes($0.bytes) } ?? l10n.t("daily.peak.noData"),
                        tint: .orange
                    )
                    metricCard(
                        title: l10n.t("statistics.fun.mostActiveDate"),
                        value: dateText(summary.mostActiveDate?.date),
                        caption: summary.mostActiveDate.map { TrafficStatsFormatter.bytes($0.bytes) } ?? l10n.t("daily.peak.noData"),
                        tint: .orange
                    )
                    metricCard(
                        title: l10n.t("statistics.fun.recentActiveDate"),
                        value: dateText(summary.recentActiveDate),
                        caption: l10n.t("statistics.fun.recentActive.caption"),
                        tint: .green
                    )
                }
            }
        }
    }

    private var gridColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 180), spacing: 10),
            GridItem(.flexible(minimum: 180), spacing: 10)
        ]
    }

    private func statisticsPanel<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.primary)

            Divider()
                .opacity(0.35)

            content()
        }
        .padding(.vertical, 6)
    }

    private func metricCard(title: String, value: String, caption: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Circle()
                    .fill(tint)
                    .frame(width: 7, height: 7)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.80)

            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .overlay(alignment: .bottom) {
            Divider()
                .opacity(0.25)
        }
    }

    private func detailRow(title: String, value: String, caption: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.80)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Divider()
                .opacity(0.25)
        }
    }

    private var personaTitle: String {
        guard summary.last7TotalBytes > 0 else {
            return l10n.t("daily.persona.diver")
        }

        let totalGB = Double(summary.last7TotalBytes) / 1_073_741_824
        let tierKey: String
        if totalGB >= 50 {
            tierKey = "daily.persona.tier.heavy"
        } else if totalGB >= 10 {
            tierKey = "daily.persona.tier.active"
        } else {
            tierKey = "daily.persona.tier.light"
        }

        let roleKey: String
        if summary.last7Downloaded == 0 && summary.last7Uploaded > 0 {
            roleKey = "daily.persona.role.uploader"
        } else {
            let ratio = Double(summary.last7Uploaded) / max(Double(summary.last7Downloaded), 1)
            if ratio >= 2 {
                roleKey = "daily.persona.role.uploader"
            } else if ratio <= 0.5 {
                roleKey = "daily.persona.role.downloader"
            } else {
                roleKey = "daily.persona.role.balanced"
            }
        }

        return l10n.t(tierKey) + l10n.t(roleKey)
    }

    private var dayOverDayValue: String {
        switch summary.dayOverDay {
        case .even:
            return l10n.t("daily.dayOverDay.even")
        case .increased(let bytes):
            return "+\(TrafficStatsFormatter.bytes(bytes))"
        case .decreased(let bytes):
            return "-\(TrafficStatsFormatter.bytes(bytes))"
        }
    }

    private var dayOverDayTint: Color {
        switch summary.dayOverDay {
        case .even:
            return .secondary
        case .increased:
            return .green
        case .decreased:
            return .red
        }
    }

    private func dateText(_ date: Date?) -> String {
        guard let date else {
            return l10n.t("statistics.value.none")
        }
        let formatter = DateFormatter()
        formatter.locale = l10n.locale
        formatter.dateFormat = "MM/dd"
        return formatter.string(from: date)
    }
}

private final class TrafficStatisticsDetailViewModel: ObservableObject {
    @Published private(set) var summary = TrafficStatisticsSummary.empty

    private let storage: DailyTrafficStorage

    init(storage: DailyTrafficStorage = .shared) {
        self.storage = storage
        reload()
    }

    func reload() {
        summary = TrafficStatisticsSummary(records: storage.getAllRecords())
    }
}

private enum StatisticsSection: String, CaseIterable, Identifiable {
    case overview
    case trends
    case fun

    var id: Self { self }

    var titleKey: String {
        switch self {
        case .overview:
            return "statistics.section.overview"
        case .trends:
            return "statistics.section.trends"
        case .fun:
            return "statistics.section.fun"
        }
    }

    var subtitleKey: String {
        switch self {
        case .overview:
            return "statistics.section.overview.subtitle"
        case .trends:
            return "statistics.section.trends.subtitle"
        case .fun:
            return "statistics.section.fun.subtitle"
        }
    }

    var descriptionKey: String {
        switch self {
        case .overview:
            return "statistics.section.overview.description"
        case .trends:
            return "statistics.section.trends.description"
        case .fun:
            return "statistics.section.fun.description"
        }
    }

    var systemImage: String {
        switch self {
        case .overview:
            return "square.grid.2x2"
        case .trends:
            return "chart.xyaxis.line"
        case .fun:
            return "sparkles"
        }
    }

    var tint: Color {
        switch self {
        case .overview:
            return .blue
        case .trends:
            return .purple
        case .fun:
            return .pink
        }
    }
}

private struct TrafficStatisticsSummary {
    let totalDownloaded: UInt64
    let totalUploaded: UInt64
    let totalBytes: UInt64
    let recordDays: Int
    let activeDays: Int
    let todayTotalBytes: UInt64
    let yesterdayTotalBytes: UInt64
    let last7Downloaded: UInt64
    let last7Uploaded: UInt64
    let last7TotalBytes: UInt64
    let last7AverageBytes: UInt64
    let last30TotalBytes: UInt64
    let last30AverageBytes: UInt64
    let historyAverageBytes: UInt64
    let activeDayAverageBytes: UInt64
    let last7DownloadShare: Double
    let last7UploadShare: Double
    let activeRate: Double
    let last7QuietDays: Int
    let currentActiveStreak: Int
    let longestActiveStreak: Int
    let dayOverDay: TrafficDayOverDay
    let last7Peak: TrafficDayHighlight?
    let allTimePeak: TrafficDayHighlight?
    let peakDownloadDate: TrafficDayHighlight?
    let peakUploadDate: TrafficDayHighlight?
    let mostActiveDate: TrafficDayHighlight?
    let recentActiveDate: Date?

    var hasData: Bool {
        totalBytes > 0
    }

    static let empty = TrafficStatisticsSummary(records: [])

    init(records: [DailyTrafficRecord]) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var recordsById: [String: DailyTrafficRecord] = [:]
        for record in records {
            recordsById[record.id] = record
        }
        let recentRecords = (0..<7).reversed().compactMap { dayOffset -> DailyTrafficRecord? in
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else {
                return nil
            }
            let emptyRecord = DailyTrafficRecord(date: date)
            return recordsById[emptyRecord.id] ?? emptyRecord
        }
        let recent30Records = (0..<30).reversed().compactMap { dayOffset -> DailyTrafficRecord? in
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else {
                return nil
            }
            let emptyRecord = DailyTrafficRecord(date: date)
            return recordsById[emptyRecord.id] ?? emptyRecord
        }

        totalDownloaded = records.reduce(0) { $0 &+ $1.downloadBytes }
        totalUploaded = records.reduce(0) { $0 &+ $1.uploadBytes }
        totalBytes = totalDownloaded &+ totalUploaded
        recordDays = records.count
        activeDays = records.filter { Self.totalBytes(for: $0) > 0 }.count

        todayTotalBytes = recentRecords.last.map(Self.totalBytes(for:)) ?? 0
        if recentRecords.count >= 2 {
            yesterdayTotalBytes = Self.totalBytes(for: recentRecords[recentRecords.count - 2])
        } else {
            yesterdayTotalBytes = 0
        }
        last7Downloaded = recentRecords.reduce(0) { $0 &+ $1.downloadBytes }
        last7Uploaded = recentRecords.reduce(0) { $0 &+ $1.uploadBytes }
        last7TotalBytes = last7Downloaded &+ last7Uploaded
        last7AverageBytes = last7TotalBytes / 7
        last30TotalBytes = recent30Records.reduce(0) { $0 &+ Self.totalBytes(for: $1) }
        last30AverageBytes = last30TotalBytes / 30
        historyAverageBytes = recordDays > 0 ? totalBytes / UInt64(recordDays) : 0
        activeDayAverageBytes = activeDays > 0 ? totalBytes / UInt64(activeDays) : 0
        last7DownloadShare = last7TotalBytes > 0 ? Double(last7Downloaded) / Double(last7TotalBytes) : 0
        last7UploadShare = last7TotalBytes > 0 ? Double(last7Uploaded) / Double(last7TotalBytes) : 0
        activeRate = recordDays > 0 ? Double(activeDays) / Double(recordDays) : 0
        last7QuietDays = recentRecords.filter { Self.totalBytes(for: $0) == 0 }.count
        let activeDates = Set(records.filter { Self.totalBytes(for: $0) > 0 }.map(\.id))
        currentActiveStreak = Self.currentStreak(activeDates: activeDates, endingAt: today, calendar: calendar)
        longestActiveStreak = Self.longestStreak(records: records)

        if let todayRecord = recentRecords.last, recentRecords.count >= 2 {
            let yesterdayRecord = recentRecords[recentRecords.count - 2]
            dayOverDay = Self.makeDayOverDay(today: todayRecord, yesterday: yesterdayRecord)
        } else {
            dayOverDay = .even
        }

        last7Peak = Self.highlight(from: recentRecords)
        allTimePeak = Self.highlight(from: records)
        peakDownloadDate = Self.highlight(from: records, value: \.downloadBytes)
        peakUploadDate = Self.highlight(from: records, value: \.uploadBytes)
        mostActiveDate = Self.highlight(from: records)
        recentActiveDate = records
            .filter { Self.totalBytes(for: $0) > 0 }
            .max(by: { $0.date < $1.date })?
            .date
    }

    nonisolated private static func highlight(from records: [DailyTrafficRecord]) -> TrafficDayHighlight? {
        guard let record = records
            .filter({ totalBytes(for: $0) > 0 })
            .max(by: { totalBytes(for: $0) < totalBytes(for: $1) }) else {
            return nil
        }
        return TrafficDayHighlight(date: record.date, bytes: totalBytes(for: record))
    }

    nonisolated private static func highlight(
        from records: [DailyTrafficRecord],
        value: (DailyTrafficRecord) -> UInt64
    ) -> TrafficDayHighlight? {
        guard let record = records
            .filter({ value($0) > 0 })
            .max(by: { value($0) < value($1) }) else {
            return nil
        }
        return TrafficDayHighlight(date: record.date, bytes: value(record))
    }

    nonisolated private static func makeDayOverDay(today: DailyTrafficRecord, yesterday: DailyTrafficRecord) -> TrafficDayOverDay {
        let todayTotal = totalBytes(for: today)
        let yesterdayTotal = totalBytes(for: yesterday)
        if todayTotal == yesterdayTotal {
            return .even
        }
        if todayTotal > yesterdayTotal {
            return .increased(todayTotal - yesterdayTotal)
        }
        return .decreased(yesterdayTotal - todayTotal)
    }

    nonisolated private static func totalBytes(for record: DailyTrafficRecord) -> UInt64 {
        record.downloadBytes &+ record.uploadBytes
    }

    nonisolated private static func currentStreak(activeDates: Set<String>, endingAt date: Date, calendar: Calendar) -> Int {
        var streak = 0
        var currentDate = calendar.startOfDay(for: date)

        while true {
            let id = DailyTrafficRecord.dateId(from: currentDate)
            guard activeDates.contains(id) else {
                return streak
            }
            streak += 1
            guard let previousDate = calendar.date(byAdding: .day, value: -1, to: currentDate) else {
                return streak
            }
            currentDate = previousDate
        }
    }

    nonisolated private static func longestStreak(records: [DailyTrafficRecord]) -> Int {
        let activeRecords = records
            .filter { totalBytes(for: $0) > 0 }
            .sorted { $0.date < $1.date }
        guard !activeRecords.isEmpty else {
            return 0
        }

        let calendar = Calendar.current
        var longest = 1
        var current = 1

        for index in 1..<activeRecords.count {
            let previous = calendar.startOfDay(for: activeRecords[index - 1].date)
            let date = calendar.startOfDay(for: activeRecords[index].date)
            let dayDelta = calendar.dateComponents([.day], from: previous, to: date).day ?? 0

            if dayDelta == 1 {
                current += 1
            } else if dayDelta > 1 {
                current = 1
            }

            longest = max(longest, current)
        }

        return longest
    }
}

private struct TrafficDayHighlight {
    let date: Date
    let bytes: UInt64
}

private enum TrafficDayOverDay {
    case even
    case increased(UInt64)
    case decreased(UInt64)
}

private enum TrafficStatsFormatter {
    static func bytes(_ bytes: UInt64) -> String {
        format(Double(bytes))
    }

    static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", max(0, min(value, 1)) * 100)
    }

    static func ratio(upload: UInt64, download: UInt64) -> String {
        if upload == 0 && download == 0 {
            return "0.00x"
        }
        if download == 0 {
            return "∞"
        }
        return String(format: "%.2fx", Double(upload) / Double(download))
    }

    private static func format(_ bytes: Double) -> String {
        let units = ["B", "K", "M", "G", "T"]
        var value = max(bytes, 0)
        var unitIndex = 0

        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }

        let stringValue: String
        if value >= 100 {
            stringValue = String(format: "%.0f", value.rounded())
        } else if value >= 10 {
            stringValue = String(format: "%.1f", value)
        } else if unitIndex == 0 {
            stringValue = String(format: "%.0f", value)
        } else {
            stringValue = String(format: "%.1f", value)
        }

        return "\(stringValue) \(units[unitIndex])"
    }
}

#if DEBUG
#Preview {
    TrafficStatisticsDetailView()
        .environmentObject(LocalizationManager.shared)
        .environment(\.locale, LocalizationManager.shared.locale)
}
#endif
