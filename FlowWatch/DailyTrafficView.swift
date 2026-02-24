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

struct DailyTrafficView: View {
    @StateObject private var viewModel = DailyTrafficViewModel()
    @State private var selectedRecord: DailyTrafficItem?
    @EnvironmentObject private var l10n: LocalizationManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(l10n.t("daily.title"))
                .font(.headline)

            summarySection

            Divider()

            funStatsSection

            if #available(macOS 13.0, *) {
                chartView
            } else {
                Text(l10n.t("settings.requires.macos13"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func sectionHeader(_ key: String) -> some View {
        Text(l10n.t(key))
            .font(.caption)
            .foregroundColor(.secondary)
    }

    private var summarySection: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 10) {
                summaryCard {
                    sectionHeader("daily.section.last7days")
                    HStack(alignment: .top, spacing: 14) {
                        metricColumn(
                            titleKey: "daily.download",
                            value: ByteAxisFormatter.formatMB(viewModel.totalDownloadMB),
                            subtitle: String(format: l10n.t("daily.avg"), ByteAxisFormatter.formatMB(viewModel.averageDownloadMB))
                        )
                        metricColumn(
                            titleKey: "daily.upload",
                            value: ByteAxisFormatter.formatMB(viewModel.totalUploadMB),
                            subtitle: String(format: l10n.t("daily.avg"), ByteAxisFormatter.formatMB(viewModel.averageUploadMB))
                        )
                    }
                }

                summaryCard {
                    HStack(spacing: 4) {
                        sectionHeader("daily.section.allHistory")
                        if viewModel.allTimeDaysCount > 0 {
                            Text(String(format: l10n.t("daily.section.allHistory.days"), viewModel.allTimeDaysCount))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    HStack(alignment: .top, spacing: 14) {
                        metricColumn(
                            titleKey: "daily.download",
                            value: ByteAxisFormatter.formatMB(viewModel.allTimeDownloadMB),
                            subtitle: String(format: l10n.t("daily.avg"), ByteAxisFormatter.formatMB(viewModel.allTimeAverageDownloadMB))
                        )
                        metricColumn(
                            titleKey: "daily.upload",
                            value: ByteAxisFormatter.formatMB(viewModel.allTimeUploadMB),
                            subtitle: String(format: l10n.t("daily.avg"), ByteAxisFormatter.formatMB(viewModel.allTimeAverageUploadMB))
                        )
                    }
                }
            }
        } label: {
            EmptyView()
        }
    }

    private func summaryCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(.controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private func metricColumn(titleKey: String, value: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(l10n.t(titleKey))
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .monospacedDigit()
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var funStatsSection: some View {
        GroupBox {
            let columns = [
                GridItem(.flexible(minimum: 120), spacing: 12),
                GridItem(.flexible(minimum: 120), spacing: 12)
            ]

            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    funStatCard(
                        title: l10n.t("daily.fun.peak.title"),
                        value: peakDayText,
                        subtitle: peakDayValueText,
                        systemImage: "flame",
                        tint: .orange
                    )
                    funStatCard(
                        title: l10n.t("daily.fun.activeDays.title"),
                        value: "\(activeDaysCount)/7",
                        subtitle: l10n.t("daily.fun.activeDays.subtitle"),
                        systemImage: "calendar",
                        tint: .blue
                    )
                    funStatCard(
                        title: l10n.t("daily.fun.coefficient.title"),
                        value: uploadDownloadCoefficientText,
                        subtitle: l10n.t("daily.fun.coefficient.subtitle"),
                        systemImage: "arrow.up.arrow.down",
                        tint: .purple
                    )
                    funStatCard(
                        title: l10n.t("daily.fun.persona.title"),
                        value: personaTitle,
                        subtitle: personaSubtitle,
                        systemImage: "sparkles",
                        tint: .pink
                    )
                }

                if let dayOverDay = dayOverDayText {
                    funStatWideCard(
                        title: l10n.t("daily.fun.dayOverDay.title"),
                        value: dayOverDay.value,
                        subtitle: dayOverDay.subtitle,
                        systemImage: dayOverDay.systemImage,
                        tint: dayOverDay.value == l10n.t("daily.dayOverDay.even") ? .gray : (dayOverDay.value.hasPrefix("+") ? .green : .red)
                    )
                }
            }
        } label: {
            EmptyView()
        }
    }

    private func funStatCard(
        title: String,
        value: String,
        subtitle: String?,
        systemImage: String,
        tint: Color
    ) -> some View {
        let rangeText = l10n.t("daily.fun.range.last7days")
        let showRangeInTitle = title == l10n.t("daily.fun.activeDays.title")
            || title == l10n.t("daily.fun.persona.title")
        let displayTitle = showRangeInTitle ? "\(title) · \(rangeText)" : title

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 20, height: 20)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text(displayTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .monospacedDigit()

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(" ")
                    .font(.system(size: 10))
                    .hidden()
            }
            if !showRangeInTitle,
               title != l10n.t("daily.fun.peak.title"),
               subtitle?.contains(rangeText) != true {
                Text(rangeText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                Text(" ")
                    .font(.system(size: 10))
                    .hidden()
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 92, maxHeight: 92, alignment: .topLeading)
        .background(Color(.controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private func funStatWideCard(
        title: String,
        value: String,
        subtitle: String?,
        systemImage: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text(value)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private var activeDaysCount: Int {
        viewModel.records.filter { ($0.downloadMB + $0.uploadMB) > 0.01 }.count
    }

    private var peakDay: DailyTrafficItem? {
        viewModel.records.max(by: { ($0.downloadMB + $0.uploadMB) < ($1.downloadMB + $1.uploadMB) })
    }

    private var peakDayText: String {
        guard let peakDay else { return "—" }
        return peakDay.dayLabel
    }

    private var peakDayValueText: String {
        guard let peakDay else { return l10n.t("daily.peak.noData") }
        let weekday = weekdayText(for: peakDay.date)
        let total = ByteAxisFormatter.formatMB(peakDay.downloadMB + peakDay.uploadMB)
        return "\(weekday) · \(total)"
    }

    private var uploadDownloadCoefficientText: String {
        let download = viewModel.totalDownloadMB
        let upload = viewModel.totalUploadMB
        guard upload > 0 || download > 0 else { return "0.00×" }
        if download <= 0.0001 {
            return "∞"
        }
        let ratio = upload / download
        return coefficientText(ratio)
    }

    private var personaTitle: String {
        let total = viewModel.totalDownloadMB + viewModel.totalUploadMB
        if total <= 0.01 {
            return l10n.t("daily.persona.diver")
        }
        let totalGB = total / 1024
        let tierKey: String
        if totalGB >= 50 {
            tierKey = "daily.persona.tier.heavy"
        } else if totalGB >= 10 {
            tierKey = "daily.persona.tier.active"
        } else {
            tierKey = "daily.persona.tier.light"
        }

        let ratio = viewModel.totalUploadMB / max(viewModel.totalDownloadMB, 0.0001)
        let roleKey: String
        if ratio >= 2.0 {
            roleKey = "daily.persona.role.uploader"
        } else if ratio <= 0.5 {
            roleKey = "daily.persona.role.downloader"
        } else {
            roleKey = "daily.persona.role.balanced"
        }

        return l10n.t(tierKey) + l10n.t(roleKey)
    }

    private var personaSubtitle: String {
        let total = viewModel.totalDownloadMB + viewModel.totalUploadMB
        guard total > 0 else { return l10n.t("daily.persona.subtitle.noTraffic") }
        let uploadText = ByteAxisFormatter.formatMB(viewModel.totalUploadMB)
        let downloadText = ByteAxisFormatter.formatMB(viewModel.totalDownloadMB)
        return String(format: l10n.t("daily.persona.subtitle.format"), uploadText, downloadText)
    }

    private struct DayOverDayDisplay {
        let value: String
        let subtitle: String
        let systemImage: String
    }

    private var dayOverDayText: DayOverDayDisplay? {
        guard viewModel.records.count >= 2 else { return nil }
        guard let today = viewModel.records.last else { return nil }
        let yesterday = viewModel.records[viewModel.records.count - 2]
        let todayTotal = today.downloadMB + today.uploadMB
        let yesterdayTotal = yesterday.downloadMB + yesterday.uploadMB
        let delta = todayTotal - yesterdayTotal
        if abs(delta) < 0.01 {
            return DayOverDayDisplay(
                value: l10n.t("daily.dayOverDay.even"),
                subtitle: String(format: l10n.t("daily.dayOverDay.subtitle"), today.dayLabel, yesterday.dayLabel),
                systemImage: "equal"
            )
        }

        let deltaText = ByteAxisFormatter.formatMB(abs(delta))
        if delta > 0 {
            return DayOverDayDisplay(
                value: "+\(deltaText)",
                subtitle: String(format: l10n.t("daily.dayOverDay.subtitle"), today.dayLabel, yesterday.dayLabel),
                systemImage: "arrow.up"
            )
        } else {
            return DayOverDayDisplay(
                value: "-\(deltaText)",
                subtitle: String(format: l10n.t("daily.dayOverDay.subtitle"), today.dayLabel, yesterday.dayLabel),
                systemImage: "arrow.down"
            )
        }
    }

    private func percentText(_ value: Double) -> String {
        let clamped = max(0, min(1, value))
        return "\(Int((clamped * 100).rounded()))%"
    }

    private func coefficientText(_ ratio: Double) -> String {
        if ratio.isNaN { return "0.00×" }
        if ratio.isInfinite { return "∞" }
        if ratio >= 10 {
            return "\(String(format: "%.1f", ratio))×"
        } else {
            return "\(String(format: "%.2f", ratio))×"
        }
    }

    private enum ByteAxisFormatter {
        static func formatBytes(_ bytes: Double) -> String {
            let units = ["B", "K", "M", "G", "T"] // 使用更短的单位缩写
            var value = bytes
            var unitIndex = 0

            while value >= 1024 && unitIndex < units.count - 1 {
                value /= 1024
                unitIndex += 1
            }

            if value >= 100, unitIndex < units.count - 1 {
                value /= 1024
                unitIndex += 1
            }

            let roundedValue = value.isNaN ? 0 : value
            let stringValue: String
            if roundedValue >= 100 {
                stringValue = String(format: "%.0f", roundedValue.rounded())
            } else {
                let rounded = (roundedValue * 10).rounded() / 10
                if rounded.truncatingRemainder(dividingBy: 1) == 0 {
                    stringValue = String(format: "%.0f", rounded)
                } else {
                    stringValue = String(format: "%.1f", rounded)
                }
            }
            return "\(stringValue) \(units[unitIndex])"
        }

        static func formatMB(_ value: Double) -> String {
            formatBytes(value * 1024 * 1024)
        }
    }

    private func weekdayText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = l10n.locale
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    private struct ByteFormatStyle: FormatStyle {
        typealias FormatInput = Double
        typealias FormatOutput = String

        func format(_ value: Double) -> String {
            ByteAxisFormatter.formatMB(value)
        }
    }

    private var yAxisValues: [Double] {
        let maxValue = viewModel.records.map { max($0.downloadMB, $0.uploadMB) }.max() ?? 0
        guard maxValue > 0 else { return [0] }

        let step = niceStep(for: maxValue / 4)
        var values: [Double] = []
        var current = 0.0
        var lastLabel: String?

        while current <= maxValue {
            let label = ByteAxisFormatter.formatMB(current)
            if label != lastLabel {
                values.append(current)
                lastLabel = label
            }
            current += step
        }

        let maxLabel = ByteAxisFormatter.formatMB(maxValue)
        if lastLabel != maxLabel {
            if let last = values.last, (maxValue - last) < step * 0.5 {
                values[values.count - 1] = maxValue
            } else {
                values.append(maxValue)
            }
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
        let downloadGuide = l10n.t("daily.chart.downloadGuide")
        let uploadGuide = l10n.t("daily.chart.uploadGuide")
        let downloadHighlight = l10n.t("daily.chart.downloadHighlight")
        let uploadHighlight = l10n.t("daily.chart.uploadHighlight")
        return Chart {
            ForEach(viewModel.records) { record in
                LineMark(
                    x: .value(dateLabel, record.dayLabel),
                    y: .value(downloadLabel, record.downloadMB),
                    series: .value(typeLabel, downloadLabel)
                )
                .foregroundStyle(.blue)
                .symbol(Circle())
                .symbolSize(20)
            }

            ForEach(viewModel.records) { record in
                LineMark(
                    x: .value(dateLabel, record.dayLabel),
                    y: .value(uploadLabel, record.uploadMB),
                    series: .value(typeLabel, uploadLabel)
                )
                .foregroundStyle(.orange)
                .symbol(Circle())
                .symbolSize(20)
            }

            if let selectedRecord {
                RuleMark(y: .value(downloadGuide, selectedRecord.downloadMB))
                    .foregroundStyle(.blue.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

                RuleMark(y: .value(uploadGuide, selectedRecord.uploadMB))
                    .foregroundStyle(.orange.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

                PointMark(
                    x: .value(dateLabel, selectedRecord.dayLabel),
                    y: .value(downloadHighlight, selectedRecord.downloadMB)
                )
                .foregroundStyle(.blue)
                .symbolSize(60)

                PointMark(
                    x: .value(dateLabel, selectedRecord.dayLabel),
                    y: .value(uploadHighlight, selectedRecord.uploadMB)
                )
                .foregroundStyle(.orange)
                .symbolSize(60)
            }
        }
        .chartForegroundStyleScale([downloadLabel: .blue, uploadLabel: .orange])
        .chartLegend(position: .top, alignment: .leading)
        .chartOverlay { proxy in
            GeometryReader { geo in
                let plotFrame = geo[proxy.plotAreaFrame]

                ZStack(alignment: .topLeading) {
                    MouseLocationTrackingView { location in
                        guard let location else {
                            if selectedRecord != nil {
                                selectedRecord = nil
                            }
                            return
                        }

                        guard plotFrame.contains(location) else {
                            if selectedRecord != nil {
                                selectedRecord = nil
                            }
                            return
                        }

                        let localX = location.x - plotFrame.origin.x
                        let dayLabel: String? = proxy.value(atX: localX)
                        guard let dayLabel,
                              let record = viewModel.records.first(where: { $0.dayLabel == dayLabel }) else {
                            return
                        }

                        if selectedRecord?.dayLabel != record.dayLabel {
                            selectedRecord = record
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if let selectedRecord {
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
                }
                AxisGridLine()
                AxisTick()
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: yAxisValues) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    .foregroundStyle(Color.secondary.opacity(0.4))
                AxisValueLabel(ByteFormatStyle().format(value.as(Double.self) ?? 0))
                    .font(.system(size: 9)) // 使用更小的字体
            }
        }
        .frame(minHeight: 160)
        .layoutPriority(1)
    }

    @available(macOS 13.0, *)
    private func chartTooltip(for record: DailyTrafficItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(record.dayLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 7, height: 7)
                    Text(String(format: l10n.t("daily.tooltip.download"), ByteAxisFormatter.formatMB(record.downloadMB)))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                }
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 7, height: 7)
                    Text(String(format: l10n.t("daily.tooltip.upload"), ByteAxisFormatter.formatMB(record.uploadMB)))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                }
            }
        }
        .padding(8)
        .background(Color(.windowBackgroundColor).opacity(0.92), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }
}

struct DailyTrafficItem: Identifiable {
    let id = UUID()
    let date: Date
    let dayLabel: String
    let downloadMB: Double
    let uploadMB: Double
}

final class DailyTrafficViewModel: ObservableObject {
    @Published var records: [DailyTrafficItem] = []

    private var updateTimer: Timer?
    private let storage: DailyTrafficStorage
    private var menuObservers: [NSObjectProtocol] = []

    private static let dayLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM/dd"
        return f
    }()

    private static let idFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private var allRecords: [DailyTrafficRecord] {
        storage.getAllRecords()
    }

    var totalDownloadMB: Double {
        records.reduce(0) { $0 + $1.downloadMB }
    }

    var totalUploadMB: Double {
        records.reduce(0) { $0 + $1.uploadMB }
    }

    var averageDownloadMB: Double {
        guard !records.isEmpty else { return 0 }
        return totalDownloadMB / Double(records.count)
    }

    var averageUploadMB: Double {
        guard !records.isEmpty else { return 0 }
        return totalUploadMB / Double(records.count)
    }

    var allTimeDownloadMB: Double {
        allRecords.reduce(0) { $0 + Double($1.downloadBytes) / (1024 * 1024) }
    }

    var allTimeUploadMB: Double {
        allRecords.reduce(0) { $0 + Double($1.uploadBytes) / (1024 * 1024) }
    }

    var allTimeAverageDownloadMB: Double {
        guard !allRecords.isEmpty else { return 0 }
        return allTimeDownloadMB / Double(allRecords.count)
    }

    var allTimeAverageUploadMB: Double {
        guard !allRecords.isEmpty else { return 0 }
        return allTimeUploadMB / Double(allRecords.count)
    }

    var allTimeDaysCount: Int {
        allRecords.count
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
        var items: [DailyTrafficItem] = []
        let storedRecords = allRecords
        let dayLabelFmt = Self.dayLabelFormatter
        let idFmt = Self.idFormatter

        let todayId = idFmt.string(from: Date())
        let todayDate = today
        if let todayRecord = storedRecords.first(where: { $0.id == todayId }) {
            let downloadMB = Double(todayRecord.downloadBytes) / (1024 * 1024)
            let uploadMB = Double(todayRecord.uploadBytes) / (1024 * 1024)
            items.append(DailyTrafficItem(date: todayDate, dayLabel: dayLabelFmt.string(from: todayDate), downloadMB: downloadMB, uploadMB: uploadMB))
        } else {
            items.append(DailyTrafficItem(date: todayDate, dayLabel: dayLabelFmt.string(from: todayDate), downloadMB: 0, uploadMB: 0))
        }

        for dayOffset in 1..<7 {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            let dayLabel = dayLabelFmt.string(from: date)
            let recordId = idFmt.string(from: date)

            if let record = storedRecords.first(where: { $0.id == recordId }) {
                let downloadMB = Double(record.downloadBytes) / (1024 * 1024)
                let uploadMB = Double(record.uploadBytes) / (1024 * 1024)
                items.append(DailyTrafficItem(date: date, dayLabel: dayLabel, downloadMB: downloadMB, uploadMB: uploadMB))
            } else {
                items.append(DailyTrafficItem(date: date, dayLabel: dayLabel, downloadMB: 0, uploadMB: 0))
            }
        }

        items.sort { $0.date < $1.date }

        DispatchQueue.main.async { [weak self] in
            self?.records = items
        }
    }
}

// Preview removed for compatibility

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
