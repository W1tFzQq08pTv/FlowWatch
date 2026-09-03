import AppKit
import Charts
import SwiftUI

struct StatisticsChartDashboard: View {
    private let preparedDays: [StatisticsChartDay]

    @EnvironmentObject private var l10n: LocalizationManager
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedRange: StatisticsChartRange = .thirtyDays
    @State private var displayMode: StatisticsChartDisplayMode = .trend
    @State private var selectedDate: Date?

    init(records: [DailyTrafficRecord]) {
        self.preparedDays = StatisticsChartDataBuilder.days(
            from: records,
            count: StatisticsChartRange.ninetyDays.dayCount,
            calendar: .current
        )
    }

    var body: some View {
        let days = chartDays

        VStack(alignment: .leading, spacing: 14) {
            dashboardControls

            if days.contains(where: { $0.totalBytes > 0 }) {
                trendCard(days: days)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 280), spacing: 14)],
                    alignment: .leading,
                    spacing: 14
                ) {
                    compositionCard(days: days)
                    weekdayCard(days: days)
                }
            } else {
                emptyState
            }
        }
        .onChange(of: selectedRange) { _ in
            selectedDate = nil
        }
    }

    private var chartDays: [StatisticsChartDay] {
        Array(preparedDays.suffix(selectedRange.dayCount))
    }

    private var dashboardControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                rangePicker
                Spacer(minLength: 12)
                modePicker
            }

            VStack(alignment: .leading, spacing: 10) {
                rangePicker
                modePicker
            }
        }
    }

    private var rangePicker: some View {
        StatisticsChartSegmentedPicker(
            items: StatisticsChartRange.allCases.map {
                StatisticsChartPickerItem(
                    value: $0,
                    title: l10n.t($0.titleKey),
                    systemImage: nil
                )
            },
            selection: $selectedRange,
            accessibilityLabel: l10n.t("statistics.chart.trend.title")
        )
    }

    private var modePicker: some View {
        StatisticsChartSegmentedPicker(
            items: StatisticsChartDisplayMode.allCases.map {
                StatisticsChartPickerItem(
                    value: $0,
                    title: l10n.t($0.titleKey),
                    systemImage: $0.systemImage
                )
            },
            selection: $displayMode,
            accessibilityLabel: l10n.t("daily.chart.type")
        )
    }

    private func trendCard(days: [StatisticsChartDay]) -> some View {
        let averageBytes = days.map(\.totalBytes).reduce(0, +) / Double(max(days.count, 1))

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                sectionHeader(
                    title: l10n.t("statistics.chart.trend.title"),
                    subtitle: l10n.t("statistics.chart.trend.subtitle"),
                    systemImage: "chart.xyaxis.line"
                )

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(l10n.t("statistics.chart.average"))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(StatisticsChartFormatter.bytes(averageBytes))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .accessibilityElement(children: .combine)
            }

            chartLegend
            trendChart(days: days, averageBytes: averageBytes)
        }
        .padding(16)
        .statisticsChartCard()
    }

    private var chartLegend: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                legendItem(
                    title: l10n.t("daily.download"),
                    color: downloadLegendColor,
                    systemImage: "arrow.down",
                    dashPattern: []
                )
                legendItem(
                    title: l10n.t("daily.upload"),
                    color: uploadLegendColor,
                    systemImage: "arrow.up",
                    dashPattern: uploadLegendDashPattern
                )
                legendItem(
                    title: l10n.t("statistics.chart.average"),
                    color: .secondary,
                    systemImage: nil,
                    dashPattern: [7, 4]
                )
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 14) {
                    legendItem(
                        title: l10n.t("daily.download"),
                        color: downloadLegendColor,
                        systemImage: "arrow.down",
                        dashPattern: []
                    )
                    legendItem(
                        title: l10n.t("daily.upload"),
                        color: uploadLegendColor,
                        systemImage: "arrow.up",
                        dashPattern: uploadLegendDashPattern
                    )
                }
                legendItem(
                    title: l10n.t("statistics.chart.average"),
                    color: .secondary,
                    systemImage: nil,
                    dashPattern: [7, 4]
                )
            }
        }
        .font(.caption)
    }

    private var downloadLegendColor: Color {
        if differentiateWithoutColor && displayMode == .stacked {
            return Color.primary.opacity(0.78)
        }
        return StatisticsChartColors.download
    }

    private var uploadLegendColor: Color {
        if differentiateWithoutColor && displayMode == .stacked {
            return Color.primary.opacity(0.36)
        }
        return StatisticsChartColors.upload
    }

    private var uploadLegendDashPattern: [CGFloat] {
        differentiateWithoutColor && displayMode == .trend ? [2, 3] : []
    }

    private func legendItem(
        title: String,
        color: Color,
        systemImage: String?,
        dashPattern: [CGFloat]
    ) -> some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(color)
                    .frame(width: 12)
            }

            if systemImage == nil || differentiateWithoutColor {
                Canvas { context, size in
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: size.height / 2))
                    path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                    context.stroke(
                        path,
                        with: .color(color),
                        style: StrokeStyle(
                            lineWidth: 1.4,
                            lineCap: .round,
                            dash: dashPattern
                        )
                    )
                }
                .frame(width: 18, height: 8)
            }

            Text(title)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private func trendChart(days: [StatisticsChartDay], averageBytes: Double) -> some View {
        let axisScale = StatisticsChartAxisScale(
            maximum: max(days.map(\.totalBytes).max() ?? 0, averageBytes) * 1.08
        )
        let selectedDay = selectedDate.flatMap { date in
            StatisticsChartDataBuilder.closestDay(to: date, in: days)
        }
        let dateLabel = l10n.t("daily.chart.date")
        let typeLabel = l10n.t("daily.chart.type")
        let downloadLabel = l10n.t("daily.download")
        let uploadLabel = l10n.t("daily.upload")
        let dailyTotalLabel = l10n.t("statistics.chart.dailyTotal")
        let axisDateFormatter = StatisticsChartFormatter.dateFormatter(
            locale: l10n.locale,
            template: "Md"
        )
        let downloadBarGradient = LinearGradient(
            colors: differentiateWithoutColor
                ? [Color.primary.opacity(0.88), Color.primary.opacity(0.62)]
                : [
                    StatisticsChartColors.download.opacity(0.95),
                    StatisticsChartColors.download.opacity(0.62)
                ],
            startPoint: .top,
            endPoint: .bottom
        )
        let uploadBarGradient = LinearGradient(
            colors: differentiateWithoutColor
                ? [Color.primary.opacity(0.46), Color.primary.opacity(0.24)]
                : [
                    StatisticsChartColors.upload.opacity(0.95),
                    StatisticsChartColors.upload.opacity(0.62)
                ],
            startPoint: .top,
            endPoint: .bottom
        )

        return Chart {
            if displayMode == .trend {
                trendSeriesMarks(
                    days: days,
                    dateLabel: dateLabel,
                    typeLabel: typeLabel,
                    downloadLabel: downloadLabel,
                    uploadLabel: uploadLabel
                )
            } else {
                stackedBarMarks(
                    days: days,
                    selectedDay: selectedDay,
                    dateLabel: dateLabel,
                    downloadLabel: downloadLabel,
                    uploadLabel: uploadLabel,
                    totalLabel: dailyTotalLabel,
                    downloadGradient: downloadBarGradient,
                    uploadGradient: uploadBarGradient
                )
            }

            RuleMark(y: .value(l10n.t("statistics.chart.average"), averageBytes))
                .foregroundStyle(Color.secondary.opacity(colorScheme == .dark ? 0.78 : 0.62))
                .lineStyle(StrokeStyle(lineWidth: 1.1, lineCap: .round, dash: [7, 4]))

            if let selectedDay {
                RuleMark(x: .value(dateLabel, selectedDay.date))
                    .foregroundStyle(Color.primary.opacity(colorScheme == .dark ? 0.34 : 0.22))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))

                if displayMode == .trend {
                    PointMark(
                        x: .value(dateLabel, selectedDay.date),
                        y: .value(downloadLabel, selectedDay.downloadBytes)
                    )
                    .foregroundStyle(StatisticsChartColors.download)
                    .symbol(Circle())
                    .symbolSize(76)

                    PointMark(
                        x: .value(dateLabel, selectedDay.date),
                        y: .value(uploadLabel, selectedDay.uploadBytes)
                    )
                    .foregroundStyle(StatisticsChartColors.upload)
                    .symbol(.diamond)
                    .symbolSize(86)
                } else {
                    PointMark(
                        x: .value(dateLabel, selectedDay.date),
                        y: .value(dailyTotalLabel, selectedDay.totalBytes)
                    )
                    .foregroundStyle(StatisticsChartColors.total)
                    .symbol(Circle())
                    .symbolSize(72)
                }
            }
        }
        .chartLegend(.hidden)
        .chartXScale(range: .plotDimension(startPadding: 10, endPadding: 10))
        .chartYScale(domain: axisScale.domain)
        .chartXAxis {
            AxisMarks(values: xAxisDates(from: days)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
                    .foregroundStyle(Color.secondary.opacity(colorScheme == .dark ? 0.16 : 0.10))

                if let date = value.as(Date.self) {
                    AxisValueLabel {
                        Text(axisDateFormatter.string(from: date))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: axisScale.tickValues) { value in
                let bytes = value.as(Double.self) ?? 0

                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
                    .foregroundStyle(
                        Color.secondary.opacity(
                            bytes == 0
                                ? (colorScheme == .dark ? 0.24 : 0.16)
                                : (colorScheme == .dark ? 0.16 : 0.10)
                        )
                    )

                if bytes > 0 {
                    AxisValueLabel(axisScale.label(for: bytes))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                let plotFrame = geometry[proxy.plotAreaFrame]

                ZStack(alignment: .topLeading) {
                    StatisticsChartMouseTrackingView { location in
                        updateSelection(
                            location: location,
                            plotFrame: plotFrame,
                            proxy: proxy,
                            days: days
                        )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if let selectedDay,
                       let localX = proxy.position(forX: selectedDay.date) {
                        trendTooltip(day: selectedDay)
                            .fixedSize()
                            .position(
                                x: tooltipX(
                                    anchorX: plotFrame.minX + localX,
                                    availableWidth: geometry.size.width
                                ),
                                y: plotFrame.minY + 48
                            )
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .frame(minHeight: 248)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: displayMode)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: selectedRange)
        .accessibilityLabel(
            "\(l10n.t("statistics.chart.trend.title")), \(l10n.t(selectedRange.titleKey))"
        )
        .accessibilityValue(
            "\(l10n.t("statistics.chart.total")) \(StatisticsChartFormatter.bytes(days.map(\.totalBytes).reduce(0, +))), \(l10n.t("statistics.chart.average")) \(StatisticsChartFormatter.bytes(averageBytes))"
        )
    }

    @ChartContentBuilder
    private func trendSeriesMarks(
        days: [StatisticsChartDay],
        dateLabel: String,
        typeLabel: String,
        downloadLabel: String,
        uploadLabel: String
    ) -> some ChartContent {
        ForEach(days) { day in
            LineMark(
                x: .value(dateLabel, day.date),
                y: .value(downloadLabel, day.downloadBytes),
                series: .value(typeLabel, downloadLabel)
            )
            .foregroundStyle(StatisticsChartColors.download)
            .lineStyle(
                StrokeStyle(
                    lineWidth: 1.7,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            .interpolationMethod(.monotone)
        }

        ForEach(days) { day in
            LineMark(
                x: .value(dateLabel, day.date),
                y: .value(uploadLabel, day.uploadBytes),
                series: .value(typeLabel, uploadLabel)
            )
            .foregroundStyle(StatisticsChartColors.upload)
            .lineStyle(
                StrokeStyle(
                    lineWidth: 1.7,
                    lineCap: .round,
                    lineJoin: .round,
                    dash: differentiateWithoutColor ? [2, 3] : []
                )
            )
            .interpolationMethod(.monotone)
        }
    }

    @ChartContentBuilder
    private func stackedBarMarks(
        days: [StatisticsChartDay],
        selectedDay: StatisticsChartDay?,
        dateLabel: String,
        downloadLabel: String,
        uploadLabel: String,
        totalLabel: String,
        downloadGradient: LinearGradient,
        uploadGradient: LinearGradient
    ) -> some ChartContent {
        ForEach(days) { day in
            BarMark(
                x: .value(dateLabel, day.date),
                yStart: .value(totalLabel, 0.0),
                yEnd: .value(downloadLabel, day.downloadBytes),
                width: .fixed(selectedRange.barWidth)
            )
            .foregroundStyle(downloadGradient)
            .opacity(selectedDay == nil || selectedDay?.id == day.id ? 1 : 0.46)

            BarMark(
                x: .value(dateLabel, day.date),
                yStart: .value(downloadLabel, day.downloadBytes),
                yEnd: .value(uploadLabel, day.totalBytes),
                width: .fixed(selectedRange.barWidth)
            )
            .foregroundStyle(uploadGradient)
            .opacity(selectedDay == nil || selectedDay?.id == day.id ? 1 : 0.46)
        }
    }

    private func updateSelection(
        location: CGPoint?,
        plotFrame: CGRect,
        proxy: ChartProxy,
        days: [StatisticsChartDay]
    ) {
        guard let location, plotFrame.contains(location) else {
            if selectedDate != nil {
                selectedDate = nil
            }
            return
        }

        let localX = location.x - plotFrame.minX
        let hoveredDate: Date? = proxy.value(atX: localX)
        guard let hoveredDate,
              let closestDay = StatisticsChartDataBuilder.closestDay(
                  to: hoveredDate,
                  in: days
              ) else {
            return
        }

        if selectedDate != closestDay.date {
            selectedDate = closestDay.date
        }
    }

    private func tooltipX(anchorX: CGFloat, availableWidth: CGFloat) -> CGFloat {
        let tooltipWidth: CGFloat = 178
        let horizontalPadding: CGFloat = 8
        let preferredX = anchorX + tooltipWidth / 2 + 12

        if preferredX + tooltipWidth / 2 <= availableWidth - horizontalPadding {
            return preferredX
        }

        return max(horizontalPadding + tooltipWidth / 2, anchorX - tooltipWidth / 2 - 12)
    }

    private func trendTooltip(day: StatisticsChartDay) -> some View {
        let dateFormatter = StatisticsChartFormatter.dateFormatter(
            locale: l10n.locale,
            template: "MMMdE"
        )

        return VStack(alignment: .leading, spacing: 7) {
            Text(dateFormatter.string(from: day.date))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)

            Divider()
                .opacity(0.45)

            tooltipMetric(
                title: l10n.t("daily.download"),
                value: StatisticsChartFormatter.bytes(day.downloadBytes),
                color: StatisticsChartColors.download,
                systemImage: "arrow.down"
            )
            tooltipMetric(
                title: l10n.t("daily.upload"),
                value: StatisticsChartFormatter.bytes(day.uploadBytes),
                color: StatisticsChartColors.upload,
                systemImage: "arrow.up"
            )
            tooltipMetric(
                title: l10n.t("statistics.chart.dailyTotal"),
                value: StatisticsChartFormatter.bytes(day.totalBytes),
                color: StatisticsChartColors.total,
                systemImage: "sum"
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(width: 178, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.10), radius: 12, x: 0, y: 5)
    }

    private func tooltipMetric(
        title: String,
        value: String,
        color: Color,
        systemImage: String
    ) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 12)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
    }

    private func compositionCard(days: [StatisticsChartDay]) -> some View {
        let downloadBytes = days.map(\.downloadBytes).reduce(0, +)
        let uploadBytes = days.map(\.uploadBytes).reduce(0, +)
        let totalBytes = downloadBytes + uploadBytes
        let downloadShare = totalBytes > 0 ? downloadBytes / totalBytes : 0
        let uploadShare = max(0, 1 - downloadShare)
        let compositionAccessibilityValue = [
            "\(l10n.t("statistics.chart.total")) \(StatisticsChartFormatter.bytes(totalBytes))",
            "\(l10n.t("daily.download")) \(StatisticsChartFormatter.bytes(downloadBytes)), \(StatisticsChartFormatter.percent(downloadShare))",
            "\(l10n.t("daily.upload")) \(StatisticsChartFormatter.bytes(uploadBytes)), \(StatisticsChartFormatter.percent(uploadShare))"
        ].joined(separator: ", ")

        return VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                title: l10n.t("statistics.chart.composition.title"),
                subtitle: l10n.t("statistics.chart.composition.subtitle"),
                systemImage: "chart.pie"
            )

            HStack(spacing: 18) {
                StatisticsCompositionRing(
                    downloadShare: downloadShare,
                    centerTitle: l10n.t("statistics.chart.total"),
                    centerValue: StatisticsChartFormatter.bytes(totalBytes)
                )
                .frame(width: 126, height: 126)

                VStack(alignment: .leading, spacing: 15) {
                    compositionMetric(
                        title: l10n.t("daily.download"),
                        bytes: downloadBytes,
                        share: downloadShare,
                        color: StatisticsChartColors.download,
                        systemImage: "arrow.down",
                        isDashed: false
                    )
                    compositionMetric(
                        title: l10n.t("daily.upload"),
                        bytes: uploadBytes,
                        share: uploadShare,
                        color: StatisticsChartColors.upload,
                        systemImage: "arrow.up",
                        isDashed: true
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 226, alignment: .topLeading)
        .statisticsChartCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(l10n.t("statistics.chart.composition.title"))
        .accessibilityValue(compositionAccessibilityValue)
    }

    private func compositionMetric(
        title: String,
        bytes: Double,
        share: Double,
        color: Color,
        systemImage: String,
        isDashed: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(title)
                    .foregroundStyle(.secondary)
            } icon: {
                HStack(spacing: 5) {
                    Image(systemName: systemImage)
                        .foregroundStyle(color)

                    if differentiateWithoutColor {
                        Canvas { context, size in
                            var path = Path()
                            path.move(to: CGPoint(x: 0, y: size.height / 2))
                            path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                            context.stroke(
                                path,
                                with: .color(.primary.opacity(isDashed ? 0.52 : 0.82)),
                                style: StrokeStyle(
                                    lineWidth: 1.5,
                                    lineCap: .round,
                                    dash: isDashed ? [2, 3] : []
                                )
                            )
                        }
                        .frame(width: 16, height: 8)
                    }
                }
            }
            .font(.caption.weight(.medium))

            Text(StatisticsChartFormatter.percent(share))
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)

            Text(StatisticsChartFormatter.bytes(bytes))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func weekdayCard(days: [StatisticsChartDay]) -> some View {
        let weekdayItems = StatisticsChartDataBuilder.weekdays(
            from: days,
            locale: l10n.locale,
            timeZone: .current
        )
        let peakID = weekdayItems.max(by: { $0.averageBytes < $1.averageBytes })?.id
        let axisScale = StatisticsChartAxisScale(
            maximum: (weekdayItems.map(\.averageBytes).max() ?? 0) * 1.12
        )

        return VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                title: l10n.t("statistics.chart.weekday.title"),
                subtitle: l10n.t("statistics.chart.weekday.subtitle"),
                systemImage: "calendar.badge.clock"
            )

            Chart(weekdayItems) { item in
                BarMark(
                    x: .value(l10n.t("daily.chart.date"), item.label),
                    y: .value(l10n.t("statistics.chart.average"), item.averageBytes),
                    width: .ratio(0.58)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            StatisticsChartColors.total.opacity(item.id == peakID ? 0.98 : 0.66),
                            StatisticsChartColors.download.opacity(item.id == peakID ? 0.72 : 0.36)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .accessibilityLabel(item.label)
                .accessibilityValue(StatisticsChartFormatter.bytes(item.averageBytes))
            }
            .chartLegend(.hidden)
            .chartYScale(domain: axisScale.domain)
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: axisScale.tickValues) { value in
                    let bytes = value.as(Double.self) ?? 0
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
                        .foregroundStyle(Color.secondary.opacity(colorScheme == .dark ? 0.16 : 0.10))

                    if bytes > 0 {
                        AxisValueLabel(axisScale.label(for: bytes))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(minHeight: 150)
            .accessibilityLabel(l10n.t("statistics.chart.weekday.title"))
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 226, alignment: .topLeading)
        .statisticsChartCard()
    }

    private func sectionHeader(
        title: String,
        subtitle: String,
        systemImage: String
    ) -> some View {
        HStack(alignment: .center, spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            FlowWatchInfoTip(text: subtitle)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 13) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            HStack(spacing: 7) {
                Text(l10n.t("statistics.chart.noData.title"))
                    .font(.headline)

                FlowWatchInfoTip(text: l10n.t("statistics.chart.noData.subtitle"))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 250)
        .padding(20)
        .statisticsChartCard()
        .accessibilityElement(children: .combine)
    }

    private func xAxisDates(from days: [StatisticsChartDay]) -> [Date] {
        guard days.count > 1 else {
            return days.map(\.date)
        }

        let desiredCount = min(selectedRange.axisLabelCount, days.count)
        guard desiredCount > 1 else {
            return [days[0].date]
        }

        let lastIndex = days.count - 1
        let indices = (0..<desiredCount).map { index in
            Int(
                (Double(index) * Double(lastIndex) / Double(desiredCount - 1)).rounded()
            )
        }

        return Array(Set(indices)).sorted().map { days[$0].date }
    }
}

private enum StatisticsChartRange: Int, CaseIterable, Identifiable {
    case sevenDays = 7
    case thirtyDays = 30
    case ninetyDays = 90

    var id: Self { self }
    var dayCount: Int { rawValue }

    var titleKey: String {
        switch self {
        case .sevenDays:
            return "statistics.chart.range.7"
        case .thirtyDays:
            return "statistics.chart.range.30"
        case .ninetyDays:
            return "statistics.chart.range.90"
        }
    }

    var axisLabelCount: Int {
        switch self {
        case .sevenDays:
            return 4
        case .thirtyDays:
            return 6
        case .ninetyDays:
            return 7
        }
    }

    var barWidth: CGFloat {
        switch self {
        case .sevenDays:
            return 20
        case .thirtyDays:
            return 7
        case .ninetyDays:
            return 3
        }
    }
}

private enum StatisticsChartDisplayMode: String, CaseIterable, Identifiable {
    case trend
    case stacked

    var id: Self { self }

    var titleKey: String {
        switch self {
        case .trend:
            return "statistics.chart.mode.trend"
        case .stacked:
            return "statistics.chart.mode.stacked"
        }
    }

    var systemImage: String {
        switch self {
        case .trend:
            return "chart.xyaxis.line"
        case .stacked:
            return "chart.bar.fill"
        }
    }
}

private struct StatisticsChartPickerItem<Selection: Hashable> {
    let value: Selection
    let title: String
    let systemImage: String?
}

private struct StatisticsChartSegmentedPicker<Selection: Hashable>: View {
    let items: [StatisticsChartPickerItem<Selection>]
    @Binding var selection: Selection
    let accessibilityLabel: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                let isSelected = selection == item.value

                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
                        selection = item.value
                    }
                } label: {
                    HStack(spacing: 5) {
                        if let systemImage = item.systemImage {
                            Image(systemName: systemImage)
                                .font(.system(size: 10, weight: .semibold))
                        }
                        Text(item.title)
                            .lineLimit(1)
                    }
                    .font(.caption.weight(isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .frame(minWidth: 42)
                    .background(
                        isSelected
                            ? StatisticsChartColors.total.opacity(0.14)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(
                                isSelected
                                    ? StatisticsChartColors.total.opacity(0.22)
                                    : Color.clear,
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(.plain)
                .help(item.title)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct StatisticsCompositionRing: View {
    let downloadShare: Double
    let centerTitle: String
    let centerValue: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    private var clampedDownloadShare: CGFloat {
        CGFloat(max(0, min(downloadShare, 1)))
    }

    private var hasBothDirections: Bool {
        clampedDownloadShare > 0 && clampedDownloadShare < 1
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.10), lineWidth: 14)

            Circle()
                .trim(from: 0, to: max(0, clampedDownloadShare - (hasBothDirections ? 0.008 : 0)))
                .stroke(
                    AngularGradient(
                        colors: differentiateWithoutColor
                            ? [Color.primary.opacity(0.68), Color.primary.opacity(0.92)]
                            : [
                                StatisticsChartColors.download.opacity(0.72),
                                StatisticsChartColors.download
                            ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Circle()
                .trim(from: min(1, clampedDownloadShare + (hasBothDirections ? 0.008 : 0)), to: 1)
                .stroke(
                    AngularGradient(
                        colors: differentiateWithoutColor
                            ? [Color.primary.opacity(0.24), Color.primary.opacity(0.46)]
                            : [
                                StatisticsChartColors.upload.opacity(0.68),
                                StatisticsChartColors.upload
                            ],
                        center: .center
                    ),
                    style: StrokeStyle(
                        lineWidth: 14,
                        lineCap: .round,
                        dash: differentiateWithoutColor ? [2, 3] : []
                    )
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 3) {
                Text(centerTitle)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(centerValue)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.66)
            }
            .padding(22)
        }
        .padding(7)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.32), value: clampedDownloadShare)
        .accessibilityHidden(true)
    }
}

private struct StatisticsChartDay: Identifiable, Equatable {
    let date: Date
    let downloadBytes: Double
    let uploadBytes: Double

    var id: Date { date }
    var totalBytes: Double { downloadBytes + uploadBytes }
}

private struct StatisticsChartWeekday: Identifiable {
    let id: Int
    let label: String
    let averageBytes: Double
}

private enum StatisticsChartDataBuilder {
    static func days(
        from records: [DailyTrafficRecord],
        count: Int,
        calendar: Calendar
    ) -> [StatisticsChartDay] {
        let safeCount = min(max(count, 1), StatisticsChartRange.ninetyDays.dayCount)
        let today = calendar.startOfDay(for: Date())
        guard let startDate = calendar.date(
            byAdding: .day,
            value: -(safeCount - 1),
            to: today
        ) else {
            return []
        }

        let rangeDates: [(date: Date, id: String)] = (0..<safeCount).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: startDate) else {
                return nil
            }
            return (date, dateID(for: date, calendar: calendar))
        }
        let rangeIDs = Set(rangeDates.map(\.id))
        var totalsByID: [String: (download: Double, upload: Double)] = [:]

        for record in records {
            guard rangeIDs.contains(record.id) else { continue }

            let current = totalsByID[record.id] ?? (0, 0)
            totalsByID[record.id] = (
                current.download + Double(record.downloadBytes),
                current.upload + Double(record.uploadBytes)
            )
        }

        return rangeDates.map { entry in
            let totals = totalsByID[entry.id] ?? (0, 0)
            return StatisticsChartDay(
                date: entry.date,
                downloadBytes: totals.download,
                uploadBytes: totals.upload
            )
        }
    }

    private static func dateID(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year,
              let month = components.month,
              let day = components.day else {
            return ""
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func closestDay(
        to date: Date,
        in days: [StatisticsChartDay]
    ) -> StatisticsChartDay? {
        guard !days.isEmpty else { return nil }

        var lowerBound = 0
        var upperBound = days.count

        while lowerBound < upperBound {
            let midpoint = lowerBound + (upperBound - lowerBound) / 2
            if days[midpoint].date < date {
                lowerBound = midpoint + 1
            } else {
                upperBound = midpoint
            }
        }

        if lowerBound == 0 {
            return days[0]
        }
        if lowerBound == days.count {
            return days[days.count - 1]
        }

        let earlier = days[lowerBound - 1]
        let later = days[lowerBound]
        return abs(earlier.date.timeIntervalSince(date))
            <= abs(later.date.timeIntervalSince(date)) ? earlier : later
    }

    static func weekdays(
        from days: [StatisticsChartDay],
        locale: Locale,
        timeZone: TimeZone
    ) -> [StatisticsChartWeekday] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone

        var totals: [Int: (bytes: Double, count: Int)] = [:]
        for day in days {
            let weekday = calendar.component(.weekday, from: day.date)
            let current = totals[weekday] ?? (0, 0)
            totals[weekday] = (current.bytes + day.totalBytes, current.count + 1)
        }

        let formatter = StatisticsChartFormatter.dateFormatter(
            locale: locale,
            template: "EEE"
        )
        let symbols = formatter.shortStandaloneWeekdaySymbols ?? formatter.shortWeekdaySymbols ?? []

        return (0..<7).map { offset in
            let weekday = ((calendar.firstWeekday - 1 + offset) % 7) + 1
            let total = totals[weekday] ?? (0, 0)
            let average = total.count > 0 ? total.bytes / Double(total.count) : 0
            let fallbackLabel = String(weekday)
            let label = symbols.indices.contains(weekday - 1)
                ? symbols[weekday - 1]
                : fallbackLabel

            return StatisticsChartWeekday(
                id: weekday,
                label: label,
                averageBytes: average
            )
        }
    }
}

private struct StatisticsChartAxisScale {
    let domain: ClosedRange<Double>
    let tickValues: [Double]

    private let unit: StatisticsChartByteUnit

    init(maximum: Double) {
        guard maximum > 0 else {
            domain = 0...1
            tickValues = [0, 1]
            unit = .bytes
            return
        }

        let rawStep = maximum / 4
        let exponent = floor(log10(max(rawStep, 1)))
        let magnitude = pow(10, exponent)
        let fraction = rawStep / magnitude
        let multiplier: Double

        if fraction <= 1 {
            multiplier = 1
        } else if fraction <= 2 {
            multiplier = 2
        } else if fraction <= 5 {
            multiplier = 5
        } else {
            multiplier = 10
        }

        let step = max(multiplier * magnitude, 1)
        let upper = max(step, ceil(maximum / step) * step)
        domain = 0...upper

        var ticks: [Double] = []
        var value = 0.0
        while value <= upper + step * 0.25 {
            ticks.append(value)
            value += step
        }
        tickValues = ticks
        unit = StatisticsChartByteUnit.best(for: upper)
    }

    func label(for bytes: Double) -> String {
        let value = bytes / unit.divisor
        let formatted: String

        if value >= 100 || value.rounded() == value {
            formatted = String(format: "%.0f", value)
        } else if value >= 10 {
            formatted = String(format: "%.1f", value)
        } else {
            formatted = String(format: "%.2g", value)
        }

        return "\(formatted) \(unit.symbol)"
    }
}

private enum StatisticsChartByteUnit {
    case bytes
    case kilobytes
    case megabytes
    case gigabytes
    case terabytes

    var divisor: Double {
        switch self {
        case .bytes:
            return 1
        case .kilobytes:
            return 1_024
        case .megabytes:
            return 1_048_576
        case .gigabytes:
            return 1_073_741_824
        case .terabytes:
            return 1_099_511_627_776
        }
    }

    var symbol: String {
        switch self {
        case .bytes:
            return "B"
        case .kilobytes:
            return "K"
        case .megabytes:
            return "M"
        case .gigabytes:
            return "G"
        case .terabytes:
            return "T"
        }
    }

    static func best(for bytes: Double) -> Self {
        switch bytes {
        case 1_099_511_627_776...:
            return .terabytes
        case 1_073_741_824...:
            return .gigabytes
        case 1_048_576...:
            return .megabytes
        case 1_024...:
            return .kilobytes
        default:
            return .bytes
        }
    }
}

private enum StatisticsChartFormatter {
    private static let dateFormatterCache: NSCache<NSString, DateFormatter> = {
        let cache = NSCache<NSString, DateFormatter>()
        cache.countLimit = 12
        return cache
    }()

    static func bytes(_ bytes: Double) -> String {
        let safeBytes = max(bytes, 0)
        let unit = StatisticsChartByteUnit.best(for: safeBytes)
        let value = safeBytes / unit.divisor
        let formatted: String

        if value >= 100 {
            formatted = String(format: "%.0f", value.rounded())
        } else if value >= 10 {
            formatted = String(format: "%.1f", value)
        } else if unit == .bytes {
            formatted = String(format: "%.0f", value.rounded())
        } else {
            formatted = String(format: "%.2f", value)
        }

        return "\(formatted) \(unit.symbol)"
    }

    static func percent(_ share: Double) -> String {
        String(format: "%.0f%%", max(0, min(share, 1)) * 100)
    }

    static func dateFormatter(locale: Locale, template: String) -> DateFormatter {
        let timeZone = TimeZone.current
        let cacheKey = "\(locale.identifier)|\(timeZone.identifier)|\(template)" as NSString
        if let formatter = dateFormatterCache.object(forKey: cacheKey) {
            return formatter
        }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        dateFormatterCache.setObject(formatter, forKey: cacheKey)
        return formatter
    }
}

private enum StatisticsChartColors {
    static let download = FlowWatchPalette.download
    static let upload = FlowWatchPalette.upload
    static let total = FlowWatchPalette.total
}

private struct StatisticsChartCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                Divider().opacity(0.38)
            }
    }
}

private extension View {
    func statisticsChartCard() -> some View {
        modifier(StatisticsChartCardModifier())
    }
}

private struct StatisticsChartMouseTrackingView: View {
    let onMove: (CGPoint?) -> Void

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case let .active(location):
                    onMove(location)
                case .ended:
                    onMove(nil)
                }
            }
    }
}
