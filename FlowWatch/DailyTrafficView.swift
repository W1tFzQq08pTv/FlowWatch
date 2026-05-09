//
//  DailyTrafficView.swift
//  FlowWatch
//
//  每日流量统计视图
//

import SwiftUI
import AppKit
import Charts
import Combine
import Foundation
import QuartzCore

struct DailyTrafficView: View {
    @ObservedObject private var monitor: NetworkUsageMonitor
    @StateObject private var viewModel = DailyTrafficViewModel()
    @StateObject private var liveDisplay = DailyTrafficLiveDisplay()
    @State private var selectedRecord: DailyTrafficItem?
    @AppStorage("maxColorRateMbps") private var maxColorRateMbps: Double = 100
    @AppStorage("colorRatePercent") private var colorRatePercent: Double = 100
    @EnvironmentObject private var l10n: LocalizationManager

    init(monitor: NetworkUsageMonitor) {
        self.monitor = monitor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            metricSummary
            chartSection
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .frame(width: 384)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            liveDisplay.bind(to: monitor)
        }
        .onDisappear {
            liveDisplay.unbind()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(l10n.t("daily.title"))
                    .font(.system(size: 17, weight: .semibold))
                Text(l10n.t("daily.chart.last7Days"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(monitor.isActive ? Color.green : Color.secondary.opacity(0.5))
                    .frame(width: 7, height: 7)
                Text(monitor.isActive ? l10n.t("content.status.running") : l10n.t("content.status.paused"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(.controlBackgroundColor).opacity(0.45), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.secondary.opacity(0.08), lineWidth: 1)
            )
        }
    }

    private var metricSummary: some View {
        HStack(spacing: 10) {
            metricCard(
                title: l10n.t("daily.currentSpeed"),
                systemImage: "speedometer"
            ) {
                trafficMetricRow(
                    title: l10n.t("daily.upload"),
                    value: monitor.formattedSpeed(displayedUploadBps),
                    color: .orange,
                    valueColor: speedValueColor(for: displayedUploadBps)
                )
                trafficMetricRow(
                    title: l10n.t("daily.download"),
                    value: monitor.formattedSpeed(displayedDownloadBps),
                    color: .blue,
                    valueColor: speedValueColor(for: displayedDownloadBps)
                )
            }

            metricCard(
                title: l10n.t("daily.today"),
                systemImage: "calendar"
            ) {
                trafficMetricRow(
                    title: l10n.t("daily.upload"),
                    value: ByteAxisFormatter.formatBytes(displayedTodayUploaded),
                    color: .orange
                )
                trafficMetricRow(
                    title: l10n.t("daily.download"),
                    value: ByteAxisFormatter.formatBytes(displayedTodayDownloaded),
                    color: .blue
                )
            }
        }
    }

    private func metricCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 7) {
                content()
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(.controlBackgroundColor).opacity(0.62), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
        )
    }

    private func trafficMetricRow(
        title: String,
        value: String,
        color: Color,
        valueColor: Color = .primary
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text(l10n.t("daily.chart.last7Days"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                chartLegend
            }

            if #available(macOS 13.0, *) {
                chartView
            } else {
                Text(l10n.t("settings.requires.macos13"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
            }
        }
        .padding(12)
        .background(Color(.controlBackgroundColor).opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.08), lineWidth: 1)
        )
    }

    private var chartLegend: some View {
        HStack(spacing: 10) {
            legendItem(title: l10n.t("daily.download"), color: .blue)
            legendItem(title: l10n.t("daily.upload"), color: .orange)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func legendItem(title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
        }
    }

    private enum ByteAxisFormatter {
        static func formatBytes(_ bytes: Double) -> String {
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

        static func formatMB(_ value: Double) -> String {
            formatBytes(value * 1024 * 1024)
        }
    }

    private struct ByteFormatStyle: FormatStyle {
        typealias FormatInput = Double
        typealias FormatOutput = String

        func format(_ value: Double) -> String {
            ByteAxisFormatter.formatMB(value)
        }
    }

    private var displayedDownloadBps: Double {
        liveDisplay.isReady ? liveDisplay.downloadBps : monitor.downloadBps
    }

    private var displayedUploadBps: Double {
        liveDisplay.isReady ? liveDisplay.uploadBps : monitor.uploadBps
    }

    private var displayedTodayDownloaded: Double {
        liveDisplay.isReady ? liveDisplay.todayDownloaded : Double(monitor.todayDownloaded)
    }

    private var displayedTodayUploaded: Double {
        liveDisplay.isReady ? liveDisplay.todayUploaded : Double(monitor.todayUploaded)
    }

    private var chartRecords: [DailyTrafficItem] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let todayDownloadMB = displayedTodayDownloaded / (1024 * 1024)
        let todayUploadMB = displayedTodayUploaded / (1024 * 1024)

        return viewModel.records.map { record in
            guard calendar.isDate(record.date, inSameDayAs: today) else {
                return record
            }
            return DailyTrafficItem(
                date: record.date,
                dayLabel: record.dayLabel,
                downloadMB: todayDownloadMB,
                uploadMB: todayUploadMB
            )
        }
    }

    private var selectedChartRecord: DailyTrafficItem? {
        guard let selectedRecord else { return nil }
        return chartRecords.first(where: { $0.dayLabel == selectedRecord.dayLabel }) ?? selectedRecord
    }

    private var maxChartValue: Double {
        chartRecords.map { max($0.downloadMB, $0.uploadMB) }.max() ?? 0
    }

    private var yScaleDomain: ClosedRange<Double> {
        guard maxChartValue > 0 else { return -0.05...1.0 }
        let padding = max(maxChartValue * 0.12, 0.1)
        return (-padding)...(maxChartValue + padding)
    }

    private var yAxisValues: [Double] {
        guard maxChartValue > 0 else { return [0] }

        let step = niceStep(for: maxChartValue / 4)
        var values: [Double] = [0]
        var current = step
        var lastLabel = ByteAxisFormatter.formatMB(0)

        while current < maxChartValue {
            let label = ByteAxisFormatter.formatMB(current)
            if label != lastLabel {
                values.append(current)
                lastLabel = label
            }
            current += step
        }

        let maxLabel = ByteAxisFormatter.formatMB(maxChartValue)
        if lastLabel != maxLabel {
            values.append(maxChartValue)
        }

        return values
    }

    private func niceStep(for value: Double) -> Double {
        guard value > 0 else { return 1 }
        let exponent = floor(log10(value))
        let fraction = value / pow(10, exponent)
        let niceFraction: Double

        if fraction <= 1 {
            niceFraction = 1
        } else if fraction <= 2 {
            niceFraction = 2
        } else if fraction <= 5 {
            niceFraction = 5
        } else {
            niceFraction = 10
        }

        return niceFraction * pow(10, exponent)
    }

    @available(macOS 13.0, *)
    private var chartView: some View {
        let dateLabel = l10n.t("daily.chart.date")
        let typeLabel = l10n.t("daily.chart.type")
        let downloadLabel = l10n.t("daily.download")
        let uploadLabel = l10n.t("daily.upload")

        return Chart {
            ForEach(chartRecords) { record in
                LineMark(
                    x: .value(dateLabel, record.dayLabel),
                    y: .value(downloadLabel, record.downloadMB),
                    series: .value(typeLabel, downloadLabel)
                )
                .foregroundStyle(.blue)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)
                .symbol(Circle())
                .symbolSize(24)
            }

            ForEach(chartRecords) { record in
                LineMark(
                    x: .value(dateLabel, record.dayLabel),
                    y: .value(uploadLabel, record.uploadMB),
                    series: .value(typeLabel, uploadLabel)
                )
                .foregroundStyle(.orange)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)
                .symbol(Circle())
                .symbolSize(24)
            }

            if let selectedRecord = selectedChartRecord {
                PointMark(
                    x: .value(dateLabel, selectedRecord.dayLabel),
                    y: .value(downloadLabel, selectedRecord.downloadMB)
                )
                .foregroundStyle(.blue)
                .symbolSize(72)

                PointMark(
                    x: .value(dateLabel, selectedRecord.dayLabel),
                    y: .value(uploadLabel, selectedRecord.uploadMB)
                )
                .foregroundStyle(.orange)
                .symbolSize(72)
            }
        }
        .chartLegend(.hidden)
        .chartYScale(domain: yScaleDomain)
        .chartPlotStyle { plotArea in
            plotArea
                .padding(.top, 4)
                .padding(.bottom, 2)
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                let plotFrame = geo[proxy.plotAreaFrame]

                ZStack(alignment: .topLeading) {
                    MouseLocationTrackingView { location in
                        updateSelectedRecord(location: location, plotFrame: plotFrame, proxy: proxy)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if let selectedRecord = selectedChartRecord {
                        chartTooltip(for: selectedRecord)
                            .padding(.leading, 6)
                            .padding(.top, 2)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks { value in
                if let label = value.as(String.self) {
                    AxisValueLabel(label)
                        .font(.system(size: 9))
                        .foregroundStyle(Color.secondary.opacity(0.82))
                }
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                    .foregroundStyle(Color.secondary.opacity(0.18))
                AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.secondary.opacity(0.18))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: yAxisValues) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                    .foregroundStyle(Color.secondary.opacity(0.22))
                AxisValueLabel(ByteFormatStyle().format(value.as(Double.self) ?? 0))
                    .font(.system(size: 9))
                    .foregroundStyle(Color.secondary.opacity(0.82))
            }
        }
        .frame(minHeight: 170)
    }

    @available(macOS 13.0, *)
    private func updateSelectedRecord(
        location: CGPoint?,
        plotFrame: CGRect,
        proxy: ChartProxy
    ) {
        guard let location, plotFrame.contains(location) else {
            if selectedRecord != nil {
                selectedRecord = nil
            }
            return
        }

        let localX = location.x - plotFrame.origin.x
        let dayLabel: String? = proxy.value(atX: localX)
        guard let dayLabel,
              let record = chartRecords.first(where: { $0.dayLabel == dayLabel }) else {
            return
        }

        if selectedRecord?.dayLabel != record.dayLabel {
            selectedRecord = record
        }
    }

    @available(macOS 13.0, *)
    private func chartTooltip(for record: DailyTrafficItem) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(record.dayLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            tooltipMetric(title: l10n.t("daily.download"), value: ByteAxisFormatter.formatMB(record.downloadMB), color: .blue)
            tooltipMetric(title: l10n.t("daily.upload"), value: ByteAxisFormatter.formatMB(record.uploadMB), color: .orange)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Color(.windowBackgroundColor).opacity(0.94), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        )
    }

    private func tooltipMetric(title: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .monospacedDigit()
        }
        .font(.caption)
    }

    private func speedValueColor(for bytesPerSecond: Double) -> Color {
        let ratio = speedColorRatio(for: bytesPerSecond)
        let startColor = NSColor.labelColor.usingColorSpace(.sRGB) ?? .labelColor
        let yellow = NSColor.systemYellow.usingColorSpace(.sRGB) ?? .systemYellow
        let red = NSColor.systemRed.usingColorSpace(.sRGB) ?? .systemRed

        if ratio < 0.5 {
            return interpolatedColor(from: startColor, to: yellow, t: ratio / 0.5)
        } else {
            return interpolatedColor(from: yellow, to: red, t: (ratio - 0.5) / 0.5)
        }
    }

    private func speedColorRatio(for bytesPerSecond: Double) -> Double {
        let mbps = max(0, bytesPerSecond) * 8 / 1_000_000
        let percent = max(0, min(colorRatePercent, 100))
        let maxRate = max(0, maxColorRateMbps) * percent / 100
        guard maxRate > 0 else { return 0 }
        return max(0, min(mbps / maxRate, 1))
    }

    private func interpolatedColor(from start: NSColor, to end: NSColor, t: Double) -> Color {
        let clamped = CGFloat(max(0, min(1, t)))
        let red = start.redComponent + (end.redComponent - start.redComponent) * clamped
        let green = start.greenComponent + (end.greenComponent - start.greenComponent) * clamped
        let blue = start.blueComponent + (end.blueComponent - start.blueComponent) * clamped
        let alpha = start.alphaComponent + (end.alphaComponent - start.alphaComponent) * clamped

        return Color(nsColor: NSColor(red: red, green: green, blue: blue, alpha: alpha))
    }
}

struct DailyTrafficItem: Identifiable {
    let date: Date
    let dayLabel: String
    let downloadMB: Double
    let uploadMB: Double

    var id: String { dayLabel }
}

@MainActor
private final class DailyTrafficLiveDisplay: ObservableObject {
    @Published private(set) var isReady = false
    @Published private(set) var downloadBps: Double = 0
    @Published private(set) var uploadBps: Double = 0
    @Published private(set) var todayDownloaded: Double = 0
    @Published private(set) var todayUploaded: Double = 0

    private let smoothTransitionKey = "statusBarSmoothTransition"
    private var sampleInterval: TimeInterval = 5.0
    private var cancellables = Set<AnyCancellable>()
    private var animationTimer: DispatchSourceTimer?
    private var animationStartTime: CFTimeInterval = 0

    private var startDownloadBps: Double = 0
    private var startUploadBps: Double = 0
    private var startTodayDownloaded: Double = 0
    private var startTodayUploaded: Double = 0
    private var targetDownloadBps: Double = 0
    private var targetUploadBps: Double = 0
    private var targetTodayDownloaded: Double = 0
    private var targetTodayUploaded: Double = 0

    private var smoothTransitionEnabled: Bool {
        if UserDefaults.standard.object(forKey: smoothTransitionKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: smoothTransitionKey)
    }

    func bind(to monitor: NetworkUsageMonitor) {
        unbind()
        sampleInterval = max(monitor.sampleInterval, 0.1)
        snapTo(
            downloadBps: monitor.downloadBps,
            uploadBps: monitor.uploadBps,
            todayDownloaded: Double(monitor.todayDownloaded),
            todayUploaded: Double(monitor.todayUploaded)
        )

        Publishers.CombineLatest4(
            monitor.$downloadBps,
            monitor.$uploadBps,
            monitor.$todayDownloaded,
            monitor.$todayUploaded
        )
        .throttle(for: .milliseconds(100), scheduler: DispatchQueue.main, latest: true)
        .sink { [weak self] downloadBps, uploadBps, todayDownloaded, todayUploaded in
            self?.moveTo(
                downloadBps: downloadBps,
                uploadBps: uploadBps,
                todayDownloaded: Double(todayDownloaded),
                todayUploaded: Double(todayUploaded)
            )
        }
        .store(in: &cancellables)

        monitor.$sampleInterval
            .receive(on: DispatchQueue.main)
            .sink { [weak self] interval in
                self?.sampleInterval = max(interval, 0.1)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, !self.smoothTransitionEnabled else { return }
                self.snapTo(
                    downloadBps: self.targetDownloadBps,
                    uploadBps: self.targetUploadBps,
                    todayDownloaded: self.targetTodayDownloaded,
                    todayUploaded: self.targetTodayUploaded
                )
            }
            .store(in: &cancellables)
    }

    func unbind() {
        stopAnimation()
        cancellables.removeAll()
    }

    private func moveTo(
        downloadBps: Double,
        uploadBps: Double,
        todayDownloaded: Double,
        todayUploaded: Double
    ) {
        if !isReady || !smoothTransitionEnabled {
            snapTo(
                downloadBps: downloadBps,
                uploadBps: uploadBps,
                todayDownloaded: todayDownloaded,
                todayUploaded: todayUploaded
            )
            return
        }

        startDownloadBps = self.downloadBps
        startUploadBps = self.uploadBps
        startTodayDownloaded = self.todayDownloaded
        startTodayUploaded = self.todayUploaded
        targetDownloadBps = downloadBps
        targetUploadBps = uploadBps
        targetTodayDownloaded = todayDownloaded
        targetTodayUploaded = todayUploaded

        let noChange = startDownloadBps == targetDownloadBps
            && startUploadBps == targetUploadBps
            && startTodayDownloaded == targetTodayDownloaded
            && startTodayUploaded == targetTodayUploaded
        guard !noChange else { return }

        animationStartTime = CACurrentMediaTime()

        guard animationTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            self?.animationTick()
        }
        timer.resume()
        animationTimer = timer
    }

    private func snapTo(
        downloadBps: Double,
        uploadBps: Double,
        todayDownloaded: Double,
        todayUploaded: Double
    ) {
        stopAnimation()
        self.downloadBps = downloadBps
        self.uploadBps = uploadBps
        self.todayDownloaded = todayDownloaded
        self.todayUploaded = todayUploaded
        targetDownloadBps = downloadBps
        targetUploadBps = uploadBps
        targetTodayDownloaded = todayDownloaded
        targetTodayUploaded = todayUploaded
        isReady = true
    }

    private func animationTick() {
        let elapsed = CACurrentMediaTime() - animationStartTime
        let progress = min(elapsed / sampleInterval, 1.0)
        let eased = easeOutCubic(progress)

        downloadBps = startDownloadBps + (targetDownloadBps - startDownloadBps) * eased
        uploadBps = startUploadBps + (targetUploadBps - startUploadBps) * eased
        todayDownloaded = startTodayDownloaded + (targetTodayDownloaded - startTodayDownloaded) * eased
        todayUploaded = startTodayUploaded + (targetTodayUploaded - startTodayUploaded) * eased

        if progress >= 1.0 {
            snapTo(
                downloadBps: targetDownloadBps,
                uploadBps: targetUploadBps,
                todayDownloaded: targetTodayDownloaded,
                todayUploaded: targetTodayUploaded
            )
        }
    }

    private func stopAnimation() {
        animationTimer?.cancel()
        animationTimer = nil
    }

    private func easeOutCubic(_ t: Double) -> Double {
        1 - pow(1 - t, 3)
    }

    deinit {
        animationTimer?.cancel()
    }
}

final class DailyTrafficViewModel: ObservableObject {
    @Published var records: [DailyTrafficItem] = []

    private var updateTimer: Timer?
    private let storage: DailyTrafficStorage
    private var menuObservers: [NSObjectProtocol] = []

    private static let dayLabelFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        return formatter
    }()

    private var allRecords: [DailyTrafficRecord] {
        storage.getAllRecords()
    }

    init(storage: DailyTrafficStorage = .shared) {
        self.storage = storage
        loadData()

        let openObserver = NotificationCenter.default.addObserver(
            forName: .flowWatchMenuWillOpen, object: nil, queue: .main
        ) { [weak self] _ in
            self?.loadData()
            self?.startUpdateTimer()
        }
        let closeObserver = NotificationCenter.default.addObserver(
            forName: .flowWatchMenuDidClose, object: nil, queue: .main
        ) { [weak self] _ in
            self?.stopUpdateTimer()
        }
        menuObservers = [openObserver, closeObserver]
    }

    deinit {
        updateTimer?.invalidate()
        for observer in menuObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func startUpdateTimer() {
        guard updateTimer == nil else { return }
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.loadData()
        }
    }

    private func stopUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    private func loadData() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let storedRecords = allRecords
        let formatter = Self.dayLabelFormatter
        var items: [DailyTrafficItem] = []

        for dayOffset in (0..<7).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else {
                continue
            }

            let recordId = DailyTrafficRecord.dateId(from: date)
            let record = storedRecords.first(where: { $0.id == recordId })
            let downloadMB = Double(record?.downloadBytes ?? 0) / (1024 * 1024)
            let uploadMB = Double(record?.uploadBytes ?? 0) / (1024 * 1024)

            items.append(
                DailyTrafficItem(
                    date: date,
                    dayLabel: formatter.string(from: date),
                    downloadMB: downloadMB,
                    uploadMB: uploadMB
                )
            )
        }

        DispatchQueue.main.async { [weak self] in
            self?.records = items
        }
    }
}

#if DEBUG
#Preview {
    DailyTrafficView(monitor: NetworkUsageMonitor())
        .environmentObject(LocalizationManager.shared)
        .environment(\.locale, LocalizationManager.shared.locale)
}
#endif

private struct MouseLocationTrackingView: NSViewRepresentable {
    let onMove: (CGPoint?) -> Void

    func makeNSView(context: Context) -> TrackingNSView {
        let view = TrackingNSView()
        view.onMove = onMove
        return view
    }

    func updateNSView(_ nsView: TrackingNSView, context: Context) {
        nsView.onMove = onMove
    }
}

private final class TrackingNSView: NSView {
    var onMove: ((CGPoint?) -> Void)?
    private var trackingAreaRef: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }

        let options: NSTrackingArea.Options = [
            .activeAlways,
            .mouseMoved,
            .mouseEnteredAndExited,
            .inVisibleRect
        ]
        let area = NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let location = convert(event.locationInWindow, from: nil)
        onMove?(location)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onMove?(nil)
    }
}
