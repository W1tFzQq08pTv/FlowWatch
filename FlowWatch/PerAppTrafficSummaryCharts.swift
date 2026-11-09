import Charts
import Foundation
import SwiftUI

enum PerAppTrafficSummaryConstants {
    nonisolated static var topLimit: Int { 5 }
    nonisolated static var maxTrendBuckets: Int { 60 }
    nonisolated static var otherSeriesID: String { "__flowwatch_other__" }
    nonisolated static var chartCardHeight: CGFloat { 228 }
    nonisolated static var xAxisEdgePadding: CGFloat { 22 }
    nonisolated static var compositionContentMaxWidth: CGFloat { 520 }
}

struct PerAppTrafficSummarySlice: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let totalBytes: UInt64
    let colorIndex: Int
    let isOther: Bool
}

struct PerAppTrafficTrendPoint: Identifiable, Equatable, Sendable {
    let bucketStart: Date
    let bucketEnd: Date
    let totalBytes: UInt64

    var id: Date { bucketStart }
}

struct PerAppTrafficTrendSeries: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let colorIndex: Int
    let isOther: Bool
    let points: [PerAppTrafficTrendPoint]
}

struct PerAppTrafficSummarySnapshot: Equatable, Sendable {
    let slices: [PerAppTrafficSummarySlice]
    let series: [PerAppTrafficTrendSeries]
    let totalBytes: UInt64
    let bucketDayCount: Int

    nonisolated static var empty: PerAppTrafficSummarySnapshot {
        PerAppTrafficSummarySnapshot(
            slices: [],
            series: [],
            totalBytes: 0,
            bucketDayCount: 1
        )
    }
}

struct PerAppTrafficHistoricalCharts: Equatable, Sendable {
    let all: PerAppTrafficSummarySnapshot
    let apps: PerAppTrafficSummarySnapshot
    let processes: PerAppTrafficSummarySnapshot

    nonisolated static var empty: PerAppTrafficHistoricalCharts {
        PerAppTrafficHistoricalCharts(all: .empty, apps: .empty, processes: .empty)
    }

    func snapshot(for filter: PerAppFilterMode) -> PerAppTrafficSummarySnapshot {
        switch filter {
        case .all:
            return all
        case .appsOnly:
            return apps
        case .processesOnly:
            return processes
        }
    }
}

enum PerAppTrafficSummaryBuilder {
    @MainActor
    static func makeToday(items: [PerAppTrafficItem]) -> PerAppTrafficSummarySnapshot {
        let ranked = items.compactMap { item -> RankedTraffic? in
            guard item.totalBytes > 0 else { return nil }
            return RankedTraffic(
                id: item.id,
                displayName: item.displayName,
                totalBytes: item.totalBytes
            )
        }
        return makeSnapshot(ranked: ranked, records: [], range: .today)
    }

    nonisolated static func makeHistoricalCharts(
        records: [AppDailyTrafficRecord],
        range: PerAppDateRange
    ) -> PerAppTrafficHistoricalCharts {
        let classified = records.map { record in
            ClassifiedRecord(
                source: record,
                isApp: record.isApp ?? isApplicationIdentifier(record.bundleID)
            )
        }

        return PerAppTrafficHistoricalCharts(
            all: makeHistoricalSnapshot(records: classified, range: range),
            apps: makeHistoricalSnapshot(
                records: classified.filter(\.isApp),
                range: range
            ),
            processes: makeHistoricalSnapshot(
                records: classified.filter { !$0.isApp },
                range: range
            )
        )
    }

    nonisolated private static func makeHistoricalSnapshot(
        records: [ClassifiedRecord],
        range: PerAppDateRange
    ) -> PerAppTrafficSummarySnapshot {
        var totals: [String: (displayName: String, totalBytes: UInt64)] = [:]
        totals.reserveCapacity(min(records.count, 128))

        for classified in records {
            let record = classified.source
            let bytes = record.downloadBytes &+ record.uploadBytes
            if var existing = totals[record.bundleID] {
                existing.displayName = record.displayName
                existing.totalBytes &+= bytes
                totals[record.bundleID] = existing
            } else {
                totals[record.bundleID] = (record.displayName, bytes)
            }
        }

        let ranked = totals.compactMap { id, value -> RankedTraffic? in
            guard value.totalBytes > 0 else { return nil }
            return RankedTraffic(
                id: id,
                displayName: value.displayName,
                totalBytes: value.totalBytes
            )
        }

        return makeSnapshot(
            ranked: ranked,
            records: records.map(\.source),
            range: range
        )
    }

    nonisolated private static func makeSnapshot(
        ranked: [RankedTraffic],
        records: [AppDailyTrafficRecord],
        range: PerAppDateRange
    ) -> PerAppTrafficSummarySnapshot {
        let ordered = ranked.sorted { lhs, rhs in
            if lhs.totalBytes == rhs.totalBytes {
                let nameOrder = lhs.displayName.localizedStandardCompare(rhs.displayName)
                if nameOrder == .orderedSame {
                    return lhs.id < rhs.id
                }
                return nameOrder == .orderedAscending
            }
            return lhs.totalBytes > rhs.totalBytes
        }
        let leaders = Array(ordered.prefix(PerAppTrafficSummaryConstants.topLimit))
        let leaderIDs = Set(leaders.map(\.id))
        let totalBytes = ordered.reduce(UInt64(0)) { $0 &+ $1.totalBytes }
        let leaderBytes = leaders.reduce(UInt64(0)) { $0 &+ $1.totalBytes }
        let otherBytes = totalBytes >= leaderBytes ? totalBytes - leaderBytes : 0
        let leaderNameCounts = Dictionary(grouping: leaders, by: \.displayName)
            .mapValues(\.count)
        var leaderNameOccurrences: [String: Int] = [:]

        var slices = leaders.enumerated().map { index, item in
            leaderNameOccurrences[item.displayName, default: 0] += 1
            let occurrence = leaderNameOccurrences[item.displayName] ?? 1
            let displayName = (leaderNameCounts[item.displayName] ?? 0) > 1
                ? "\(item.displayName) · \(occurrence)"
                : item.displayName
            return PerAppTrafficSummarySlice(
                id: item.id,
                displayName: displayName,
                totalBytes: item.totalBytes,
                colorIndex: index,
                isOther: false
            )
        }
        if otherBytes > 0 {
            slices.append(
                PerAppTrafficSummarySlice(
                    id: PerAppTrafficSummaryConstants.otherSeriesID,
                    displayName: "",
                    totalBytes: otherBytes,
                    colorIndex: PerAppTrafficSummaryConstants.topLimit,
                    isOther: true
                )
            )
        }

        guard range != .today,
              !records.isEmpty,
              !slices.isEmpty,
              let bounds = chartBounds(records: records, range: range) else {
            return PerAppTrafficSummarySnapshot(
                slices: slices,
                series: [],
                totalBytes: totalBytes,
                bucketDayCount: 1
            )
        }

        let calendar = Calendar.current
        let totalDayCount = max(
            1,
            (calendar.dateComponents([.day], from: bounds.start, to: bounds.end).day ?? 0) + 1
        )
        let bucketDayCount = max(
            1,
            Int(ceil(Double(totalDayCount) / Double(PerAppTrafficSummaryConstants.maxTrendBuckets)))
        )
        let bucketCount = Int(ceil(Double(totalDayCount) / Double(bucketDayCount)))
        var values: [String: [UInt64]] = [:]
        values.reserveCapacity(slices.count)
        for slice in slices {
            values[slice.id] = [UInt64](repeating: 0, count: bucketCount)
        }

        for record in records {
            let day = calendar.startOfDay(for: record.date)
            let offset = calendar.dateComponents([.day], from: bounds.start, to: day).day ?? -1
            guard offset >= 0, offset < totalDayCount else { continue }
            let bucketIndex = min(offset / bucketDayCount, bucketCount - 1)
            let seriesID = leaderIDs.contains(record.bundleID)
                ? record.bundleID
                : PerAppTrafficSummaryConstants.otherSeriesID
            guard values[seriesID] != nil else { continue }
            values[seriesID]![bucketIndex] &+= record.downloadBytes &+ record.uploadBytes
        }

        let series = slices.map { slice in
            let bucketValues = values[slice.id] ?? []
            let points = bucketValues.enumerated().compactMap { bucketIndex, bytes -> PerAppTrafficTrendPoint? in
                let dayOffset = bucketIndex * bucketDayCount
                guard let bucketStart = calendar.date(
                    byAdding: .day,
                    value: dayOffset,
                    to: bounds.start
                ) else {
                    return nil
                }
                let naturalDayCount = min(bucketDayCount, totalDayCount - dayOffset)
                guard let bucketEnd = calendar.date(
                    byAdding: .day,
                    value: max(naturalDayCount - 1, 0),
                    to: bucketStart
                ) else {
                    return nil
                }
                return PerAppTrafficTrendPoint(
                    bucketStart: bucketStart,
                    bucketEnd: bucketEnd,
                    totalBytes: bytes
                )
            }
            return PerAppTrafficTrendSeries(
                id: slice.id,
                displayName: slice.displayName,
                colorIndex: slice.colorIndex,
                isOther: slice.isOther,
                points: points
            )
        }

        return PerAppTrafficSummarySnapshot(
            slices: slices,
            series: series,
            totalBytes: totalBytes,
            bucketDayCount: bucketDayCount
        )
    }

    nonisolated private static func chartBounds(
        records: [AppDailyTrafficRecord],
        range: PerAppDateRange
    ) -> (start: Date, end: Date)? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        switch range {
        case .today:
            return (today, today)
        case .last7Days:
            guard let start = calendar.date(byAdding: .day, value: -6, to: today) else { return nil }
            return (start, today)
        case .last30Days:
            guard let start = calendar.date(byAdding: .day, value: -29, to: today) else { return nil }
            return (start, today)
        case .allTime:
            let dates = records.map { calendar.startOfDay(for: $0.date) }
            guard let start = dates.min(), let end = dates.max() else { return nil }
            return (start, end)
        }
    }

    nonisolated private static func isApplicationIdentifier(_ identifier: String) -> Bool {
        if identifier.hasPrefix("/") {
            return identifier.hasSuffix(".app")
        }
        return identifier.contains(".")
    }
}

private struct RankedTraffic: Sendable {
    let id: String
    let displayName: String
    let totalBytes: UInt64
}

private struct ClassifiedRecord: Sendable {
    let source: AppDailyTrafficRecord
    let isApp: Bool
}

// MARK: - Summary Dashboard

struct PerAppTrafficSummaryChartsView: View, Equatable {
    let snapshot: PerAppTrafficSummarySnapshot
    let range: PerAppDateRange
    let isLoading: Bool

    @EnvironmentObject private var l10n: LocalizationManager
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    static func == (
        lhs: PerAppTrafficSummaryChartsView,
        rhs: PerAppTrafficSummaryChartsView
    ) -> Bool {
        lhs.snapshot == rhs.snapshot
            && lhs.range == rhs.range
            && lhs.isLoading == rhs.isLoading
    }

    var body: some View {
        Group {
            if isLoading {
                loadingCard
            } else if snapshot.slices.isEmpty {
                emptyCard
            } else if range == .today {
                compositionCard
            } else {
                HStack(alignment: .top, spacing: 12) {
                    compositionCard
                        .frame(width: 380)
                    trendCard
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var compositionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader(
                title: l10n.t("perApp.summaryCharts.composition.title"),
                subtitle: l10n.t("perApp.summaryCharts.composition.subtitle"),
                systemImage: "chart.pie.fill",
                badge: nil
            )

            HStack(spacing: 16) {
                donutChart
                    .frame(width: 132, height: 132)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(snapshot.slices) { slice in
                        legendRow(slice)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: PerAppTrafficSummaryConstants.compositionContentMaxWidth)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(
            height: PerAppTrafficSummaryConstants.chartCardHeight,
            alignment: .topLeading
        )
        .perAppSummaryChartCard(accent: FlowWatchPalette.accent)
    }

    private var donutChart: some View {
        FlowWatchRingChart(
            segments: snapshot.slices.map {
                FlowWatchRingChart.Segment(
                    value: Double($0.totalBytes),
                    color: PerAppTrafficSummaryPalette.color(at: $0.colorIndex)
                )
            },
            centerTitle: l10n.t("perApp.summary.totalUsage"),
            centerValue: PerAppSummaryChartFormatter.bytes(Double(snapshot.totalBytes))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(l10n.t("perApp.summaryCharts.composition.title"))
        .accessibilityValue(PerAppSummaryChartFormatter.bytes(Double(snapshot.totalBytes)))
    }

    private var trendCard: some View {
        let maximum = snapshot.series.flatMap(\.points).map { Double($0.totalBytes) }.max() ?? 0

        return VStack(alignment: .leading, spacing: 10) {
            cardHeader(
                title: l10n.t("perApp.summaryCharts.trend.title"),
                subtitle: l10n.t("perApp.summaryCharts.trend.subtitle"),
                systemImage: "chart.xyaxis.line",
                badge: snapshot.bucketDayCount > 1
                    ? String(
                        format: l10n.t("perApp.summaryCharts.bucketDays"),
                        snapshot.bucketDayCount
                    )
                    : nil
            )

            Chart {
                ForEach(snapshot.series) { series in
                    ForEach(series.points) { point in
                        LineMark(
                            x: .value(l10n.t("perApp.summaryCharts.time"), point.bucketStart),
                            y: .value(l10n.t("perApp.summaryCharts.usage"), Double(point.totalBytes)),
                            series: .value("Series", series.id)
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(PerAppTrafficSummaryPalette.color(at: series.colorIndex))
                        .lineStyle(
                            StrokeStyle(
                                lineWidth: series.isOther ? 1.4 : FlowWatchChartStyle.lineWidth,
                                lineCap: .round,
                                lineJoin: .round,
                                dash: trendDash(for: series)
                            )
                        )

                        if series.points.count <= 30 {
                            PointMark(
                                x: .value(l10n.t("perApp.summaryCharts.time"), point.bucketStart),
                                y: .value(l10n.t("perApp.summaryCharts.usage"), Double(point.totalBytes))
                            )
                            .foregroundStyle(PerAppTrafficSummaryPalette.color(at: series.colorIndex))
                            .symbolSize(series.isOther ? 10 : 14)
                        }
                    }
                }
            }
            .chartLegend(.hidden)
            .chartYScale(domain: 0...max(maximum * 1.12, 1))
            .flowWatchChartPlot()
            .chartXScale(
                range: .plotDimension(
                    startPadding: PerAppTrafficSummaryConstants.xAxisEdgePadding,
                    endPadding: PerAppTrafficSummaryConstants.xAxisEdgePadding
                )
            )
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(axisDateLabel(date))
                                .font(FlowWatchChartStyle.axisFont)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    let isBaseline = (value.as(Double.self) ?? 0) == 0
                    AxisGridLine(stroke: FlowWatchChartStyle.gridStroke(isBaseline: isBaseline))
                        .foregroundStyle(FlowWatchChartStyle.gridColor(isBaseline: isBaseline))
                    AxisValueLabel {
                        if let bytes = value.as(UInt64.self) {
                            Text(PerAppSummaryChartFormatter.bytes(Double(bytes)))
                                .font(FlowWatchChartStyle.axisFont)
                                .foregroundStyle(.secondary)
                        } else if let bytes = value.as(Double.self) {
                            Text(PerAppSummaryChartFormatter.bytes(bytes))
                                .font(FlowWatchChartStyle.axisFont)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(minHeight: 154)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(
            height: PerAppTrafficSummaryConstants.chartCardHeight,
            alignment: .topLeading
        )
        .perAppSummaryChartCard(accent: Color(red: 0.48, green: 0.42, blue: 0.96))
    }

    private func trendDash(for series: PerAppTrafficTrendSeries) -> [CGFloat] {
        guard differentiateWithoutColor else { return series.isOther ? [5, 4] : [] }
        let patterns: [[CGFloat]] = [[], [6, 3], [2, 3], [7, 3, 2, 3], [3, 2, 3, 5], [1, 3]]
        return patterns[min(max(series.colorIndex, 0), patterns.count - 1)]
    }

    private func cardHeader(
        title: String,
        subtitle: String,
        systemImage: String,
        badge: String?
    ) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            if let badge {
                Text(badge)
                    .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func legendRow(_ slice: PerAppTrafficSummarySlice) -> some View {
        let share = snapshot.totalBytes > 0
            ? Double(slice.totalBytes) / Double(snapshot.totalBytes)
            : 0

        return HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 2)
                .fill(PerAppTrafficSummaryPalette.color(at: slice.colorIndex))
                .frame(width: 7, height: 7)
                .overlay {
                    if differentiateWithoutColor {
                        Text("\(slice.colorIndex + 1)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(FlowWatchPalette.ink)
                            .frame(width: 12, height: 12)
                            .background(FlowWatchPalette.surface, in: Circle())
                    }
                }

            Text(seriesLabel(name: slice.displayName, isOther: slice.isOther))
                .font(.system(size: 10.5, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            Text(PerAppSummaryChartFormatter.percent(share))
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .flowWatchHelp(
            "\(seriesLabel(name: slice.displayName, isOther: slice.isOther)) · "
                + PerAppSummaryChartFormatter.bytes(Double(slice.totalBytes))
        )
    }

    private var loadingCard: some View {
        VStack(spacing: 9) {
            FlowWatchProgressView()

            Text(l10n.t("perApp.chart.loading"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .perAppSummaryChartCard(accent: FlowWatchPalette.accent)
    }

    private var emptyCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.pie")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.secondary)
            Text(l10n.t("perApp.noData"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .perAppSummaryChartCard(accent: FlowWatchPalette.accent)
    }

    private func seriesLabel(name: String, isOther: Bool) -> String {
        isOther ? l10n.t("perApp.summaryCharts.others") : name
    }

    private func axisDateLabel(_ date: Date) -> String {
        if range == .allTime && snapshot.bucketDayCount >= 14 {
            return date.formatted(.dateTime.year().month(.twoDigits))
        }
        return date.formatted(.dateTime.month(.twoDigits).day(.twoDigits))
    }
}

private enum PerAppTrafficSummaryPalette {
    @MainActor
    static func color(at index: Int) -> Color {
        let colors: [Color] = [
            FlowWatchPalette.download,
            FlowWatchPalette.upload,
            FlowWatchPalette.total,
            Color(red: 0.21, green: 0.63, blue: 0.60),
            Color(red: 0.78, green: 0.55, blue: 0.22),
            Color.secondary.opacity(0.58)
        ]
        return colors[min(max(index, 0), colors.count - 1)]
    }
}

private enum PerAppSummaryChartFormatter {
    nonisolated static func bytes(_ bytes: Double) -> String {
        let safeBytes = max(bytes.isFinite ? bytes : 0, 0)
        let units = ["B", "K", "M", "G", "T"]
        var value = safeBytes
        var unitIndex = 0

        while value >= 1024, unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }

        guard unitIndex > 0 else {
            return "\(Int(value.rounded())) B"
        }

        let format: String
        if value >= 100 {
            format = "%.0f %@"
        } else if value >= 10 {
            format = "%.1f %@"
        } else {
            format = "%.2f %@"
        }
        return String(format: format, value, units[unitIndex])
    }

    nonisolated static func percent(_ share: Double) -> String {
        let clampedShare = min(max(share.isFinite ? share : 0, 0), 1)
        return String(format: "%.0f%%", clampedShare * 100)
    }
}

private struct PerAppSummaryChartCardModifier: ViewModifier {
    let accent: Color

    func body(content: Content) -> some View {
        content.flowWatchGlassPanel()
    }
}

private extension View {
    func perAppSummaryChartCard(accent: Color) -> some View {
        modifier(PerAppSummaryChartCardModifier(accent: accent))
    }
}
