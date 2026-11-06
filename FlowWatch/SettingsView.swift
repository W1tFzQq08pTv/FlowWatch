import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @AppStorage(StatusBarLayout.defaultsKey) private var statusBarLayoutRaw = ""
    @AppStorage("statusBarDisplayMode") private var statusBarDisplayModeRaw: String = FlowWatchApp.StatusBarDisplayMode.speed.rawValue
    @AppStorage("maxColorRateMbps") private var maxColorRateMbps: Double = 100
    @AppStorage("colorRatePercent") private var colorRatePercent: Double = 100
    @AppStorage("statusBarColoringEnabled") private var statusBarColoringEnabled: Bool = true
    @AppStorage("perAppMonitoring.enabled") private var perAppMonitoringEnabled: Bool = false
    @AppStorage("perAppMonitoring.sampleInterval") private var perAppSampleInterval: Double = 3.0
    @AppStorage("statusBar.sampleInterval") private var sampleInterval: Double = 5.0
    @AppStorage("statusBarSmoothTransition") private var smoothTransition: Bool = true
    @AppStorage("minimalSignalShowsTrafficTotals") private var minimalSignalShowsTrafficTotals: Bool = true
    @AppStorage("minimalSignalBlinkSpeedPercent") private var minimalSignalBlinkSpeedPercent: Double = 50
    @AppStorage("mathCurveLoaderSelection") private var mathCurveLoaderSelectionRaw: String = MathCurveLoaderSelection.random.rawValue
    @AppStorage("mathCurveLoaderRandomSwitchIntervalMinutes") private var mathCurveLoaderRandomSwitchIntervalMinutes: Double = 10
    @AppStorage("logging.enabled") private var loggingEnabled: Bool = true
    @ObservedObject private var updateManager = UpdateManager.shared
    @Namespace private var sidebarSelectionNamespace
    @State private var selectedSection: SettingsSection? = .general
    @State private var isShowingResetAlert = false
    @State private var resetAlertMode: ResetAlertMode?
    @State private var launchAtLoginEnabled = false
    @State private var launchAtLoginStatus: SMAppService.Status?
    @State private var launchAtLoginErrorMessage: String?
    @FocusState private var focusedField: FocusField?
    @EnvironmentObject private var l10n: LocalizationManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Divider()

            FlowWatchThinScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    detailHeader
                    selectedContent
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .flowWatchMainPaneSurface()
        }
        .flowWatchWindowSurface()
        .frame(minWidth: 860, minHeight: 580)
        .onAppear {
            refreshLaunchAtLoginState()
            DispatchQueue.main.async {
                focusedField = nil
            }
        }
        .onChange(of: isShowingResetAlert) { isPresented in
            guard isPresented else { return }
            let mode = resetAlertMode
            FlowWatchDialogController.shared.present(
                title: l10n.t("alert.reset.title"),
                message: l10n.t(mode == .allHistory ? "alert.reset.all" : "alert.reset.today"),
                confirmTitle: l10n.t(mode == .allHistory ? "common.clear" : "common.reset"),
                cancelTitle: l10n.t("common.cancel"), isDestructive: true,
                completion: { confirmed in
                    isShowingResetAlert = false
                    guard confirmed else { return }
                    if mode == .today { NotificationCenter.default.post(name: .flowWatchResetToday, object: nil) }
                    if mode == .allHistory { NotificationCenter.default.post(name: .flowWatchResetAllHistory, object: nil) }
                }
            )
        }
        .onChange(of: launchAtLoginErrorMessage) { message in
            guard let message else { return }
            FlowWatchDialogController.shared.present(title: l10n.t("alert.launchAtLogin.errorTitle"),
                message: message, confirmTitle: l10n.t("common.ok"), completion: { _ in launchAtLoginErrorMessage = nil })
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            FlowWatchSidebarHeader()
            VStack(spacing: 6) {
                ForEach(SettingsSection.allCases) { section in
                    sidebarRow(section)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: sidebarWidth)
        .background(FlowWatchPalette.canvas)
    }

    private func sidebarRow(_ section: SettingsSection) -> some View {
        FlowWatchNavigationRow(
            title: l10n.t(section.titleKey), icon: section.systemImage,
            isSelected: currentSection == section, selectionNamespace: sidebarSelectionNamespace
        ) { selectedSection = section }
    }

    private var currentSection: SettingsSection {
        selectedSection ?? .general
    }

    private var sidebarWidth: CGFloat {
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let longestTitleWidth = SettingsSection.allCases
            .map { section in
                let title = l10n.t(section.titleKey) as NSString
                return title.size(withAttributes: [.font: font]).width
            }
            .max() ?? 0
        let horizontalChrome: CGFloat = 94
        return min(max(ceil(longestTitleWidth + horizontalChrome), 176), 260)
    }

    private var detailHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(l10n.t(currentSection.titleKey))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                if let subtitleKey = currentSection.subtitleKey {
                    Text(l10n.t(subtitleKey))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch currentSection {
        case .general:
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("FlowWatch").font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text(l10n.t("ui.settingsCaption")).font(.system(size: 13)).foregroundStyle(.secondary)
                    Text(l10n.t("ui.aboutCaption")).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                FlowWatchLineSphere().frame(width: 150, height: 150)
            }
            .padding(24)
            .flowWatchGlassPanel()
            settingsPanel(title: l10n.t("settings.group.language")) {
                optionSelector(
                    AppLanguage.allCases.map { (languageLabel($0), $0) },
                    selection: Binding(
                        get: { l10n.language },
                        set: { l10n.language = $0 }
                    )
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
            }
        case .statusBar:
            settingsPanel(title: l10n.t("settings.section.displayContent")) {
                statusBarComponentControls
                if statusBarLayout.enabled.contains(.traffic) {
                    rowDivider
                    settingsRow(title: l10n.t("settings.displayContent.label")) {
                        FlowWatchMenuControl(
                            options: StatusBarLayout.TrafficContent.allCases.map { (l10n.t($0.titleKey), $0) },
                            selection: layoutBinding(\.content), tint: currentSection.tint, width: 220
                        )
                    }
                    settingsRow(title: l10n.t("settings.layout.direction")) {
                        FlowWatchMenuControl(
                            options: StatusBarLayout.Direction.allCases.map { (l10n.t($0.titleKey), $0) },
                            selection: layoutBinding(\.direction), tint: currentSection.tint, width: 220
                        )
                    }
                    if statusBarLayout.direction == .both {
                        settingsRow(title: l10n.t("settings.layout.arrangement")) {
                            FlowWatchMenuControl(
                                options: StatusBarLayout.Arrangement.allCases.map { (l10n.t($0.titleKey), $0) },
                                selection: layoutBinding(\.arrangement), tint: currentSection.tint, width: 220
                            )
                        }
                        settingsRow(title: l10n.t("settings.layout.downloadFirst")) {
                            ModernSwitch(isOn: layoutBinding(\.downloadFirst), tint: currentSection.tint)
                        }
                    }
                }
                if statusBarLayout.isAnimated {
                    if statusBarLayout.enabled.contains(.animation) {
                        rowDivider
                        settingsRow(
                            title: l10n.t("settings.curveLoader.selection"),
                            detail: l10n.t("settings.curveLoader.selection.desc")
                        ) {
                            FlowWatchMenuControl(
                                options: mathCurveLoaderOptions,
                                selection: mathCurveLoaderSelectionBinding,
                                tint: currentSection.tint,
                                width: 260
                            )
                        }
                        if currentMathCurveLoaderSelection == .random {
                            rowDivider
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(l10n.t("settings.curveLoader.randomSwitchInterval"))
                                            .font(.system(size: 13, weight: .medium))
                                        Text(l10n.t("settings.curveLoader.randomSwitchInterval.desc"))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer()
                                    Text(String(
                                        format: l10n.t("settings.curveLoader.randomSwitchInterval.value"),
                                        Int(mathCurveLoaderRandomSwitchIntervalMinutesBinding.wrappedValue.rounded())
                                    ))
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                }
                                ModernSlider(
                                    value: mathCurveLoaderRandomSwitchIntervalMinutesBinding,
                                    range: 1...60,
                                    step: 1,
                                    tint: currentSection.tint
                                )
                                .accessibilityLabel(l10n.t("settings.curveLoader.randomSwitchInterval"))
                            }
                            .padding(.vertical, 8)
                        }
                    }
                    rowDivider
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(l10n.t(statusBarLayout.enabled.contains(.animation) ? "settings.curveLoader.animationSpeed" : "settings.minimalSignal.blinkSpeed"))
                                    .font(.system(size: 13, weight: .medium))
                                Text(l10n.t(statusBarLayout.enabled.contains(.animation) ? "settings.curveLoader.animationSpeed.desc" : "settings.minimalSignal.blinkSpeed.desc"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            Text("\(Int(minimalSignalBlinkSpeedPercent.rounded()))%")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        ModernSlider(value: minimalSignalBlinkSpeedBinding, range: 0...100, step: 1, tint: currentSection.tint)
                            .accessibilityLabel(l10n.t(statusBarLayout.enabled.contains(.animation) ? "settings.curveLoader.animationSpeed" : "settings.minimalSignal.blinkSpeed"))
                    }
                    .padding(.vertical, 8)
                }
            }
            settingsPanel(title: l10n.t("settings.group.numberUpdates")) {
                settingsRow(title: l10n.t("settings.statusBar.interval")) {
                    sampleIntervalPicker
                }
                rowDivider
                settingsRow(
                    title: l10n.t("settings.smoothTransition.toggle"),
                    detail: l10n.t("settings.smoothTransition.desc")
                ) {
                    ModernSwitch(isOn: $smoothTransition, tint: currentSection.tint)
                }
            }
        case .coloring:
            settingsPanel(title: l10n.t("settings.group.colorRules")) {
                settingsRow(
                    title: l10n.t("settings.coloring.toggle"),
                    detail: l10n.t("settings.coloring.toggle.desc")
                ) {
                    ModernSwitch(isOn: statusBarColoringEnabledBinding, tint: currentSection.tint)
                }
                rowDivider
                settingsRow(
                    title: l10n.t("settings.maxColorRate.limitTitle"),
                    detail: l10n.t("settings.maxColorRate.desc")
                ) {
                    HStack(spacing: 6) {
                        TextField(
                            "",
                            value: maxColorRateInputBinding,
                            format: .number.precision(.fractionLength(0))
                        )
                        .frame(width: 72)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.plain)
                        .focused($focusedField, equals: .maxColorRate)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .flowWatchGlassPanel(
                            cornerRadius: 7,
                            material: .thin,
                            strokeOpacity: focusedField == .maxColorRate ? 0.24 : 0.12,
                            shadowOpacity: 0.02
                        )
                        .flowWatchHover(.field)
                        .accessibilityLabel(l10n.t("settings.maxColorRate.limitTitle"))
                        Text("Mbps")
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!statusBarColoringEnabled)
                .opacity(statusBarColoringEnabled ? 1 : 0.5)
                rowDivider
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(l10n.t("settings.maxColorRate.intensityTitle"))
                        Spacer()
                        Text("\(Int(colorRatePercent.rounded()))%")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    ModernSlider(value: colorRatePercentBinding, range: 0...100, step: 1, tint: currentSection.tint)
                        .accessibilityLabel(l10n.t("settings.maxColorRate.intensityTitle"))
                    colorPreviewStrip
                }
                .padding(.vertical, 8)
                .disabled(!statusBarColoringEnabled)
                .opacity(statusBarColoringEnabled ? 1 : 0.5)
            }
        case .launch:
            settingsPanel(title: l10n.t("settings.group.login")) {
                launchAtLoginRow
            }
        case .updates:
            settingsPanel(title: l10n.t("settings.group.updatePolicy")) {
                settingsRow(
                    title: l10n.t("settings.update.autoCheck"),
                    detail: l10n.t("settings.update.autoCheckHint")
                ) {
                    ModernSwitch(
                        isOn: Binding(
                            get: { updateManager.autoCheckEnabled },
                            set: { newValue in
                                updateManager.setAutomaticChecksEnabled(newValue)
                                if newValue {
                                    NotificationCenter.default.post(name: .flowWatchCheckForUpdates, object: nil)
                                }
                            }
                        ),
                        tint: currentSection.tint
                    )
                }
                rowDivider
                settingsRow(
                    title: l10n.t("settings.update.autoDownload"),
                    detail: l10n.t("settings.update.autoDownloadHint")
                ) {
                    ModernSwitch(
                        isOn: Binding(
                            get: { updateManager.autoDownloadEnabled },
                            set: { updateManager.setAutomaticDownloadsEnabled($0) }
                        ),
                        tint: currentSection.tint,
                        isEnabled: updateManager.autoCheckEnabled
                    )
                }
                Text(l10n.t("settings.update.appManagementHint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            settingsPanel(title: l10n.t("settings.group.updateStatus")) {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(updateInfoLines, id: \.self) { line in
                            Text(line)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 10) {
                        Button(l10n.t("menu.checkUpdate")) {
                            updateManager.checkForUpdates(userInitiated: true)
                        }
                        .buttonStyle(FlowWatchActionButtonStyle(tint: currentSection.tint))
                        Button(l10n.t("update.recheckSkipped")) {
                            updateManager.recheckSkippedVersions()
                        }
                        .buttonStyle(FlowWatchActionButtonStyle(tint: currentSection.tint))
                    }
                }
                .padding(.vertical, 8)
            }
        case .logging:
            settingsPanel(title: l10n.t("settings.group.logs")) {
                settingsRow(
                    title: l10n.t("settings.logging.toggle"),
                    detail: l10n.t("settings.logging.hint")
                ) {
                    ModernSwitch(isOn: Binding(
                        get: { loggingEnabled },
                        set: { newValue in
                            loggingEnabled = newValue
                            LogManager.shared.log("Logging enabled: \(newValue)")
                        }
                    ), tint: currentSection.tint)
                }
            }
            settingsPanel(title: l10n.t("settings.group.logsLocation")) {
                settingsRow(
                    title: l10n.t("settings.logging.openFolder"),
                    detail: String(format: l10n.t("settings.logging.path"), displayPath(LogManager.shared.logsDirectoryPath))
                ) {
                    Button(l10n.t("settings.logging.openFolder")) {
                        let url = URL(fileURLWithPath: LogManager.shared.logsDirectoryPath)
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                        LogManager.shared.log("Open logs directory from settings")
                    }
                    .buttonStyle(FlowWatchActionButtonStyle(tint: currentSection.tint))
                }
            }
        case .perApp:
            settingsPanel(title: l10n.t("settings.group.perAppCapture")) {
                settingsRow(
                    title: l10n.t("settings.perApp.toggle"),
                    detail: l10n.t("settings.perApp.desc")
                ) {
                    ModernSwitch(isOn: Binding(
                        get: { perAppMonitoringEnabled },
                        set: { newValue in
                            perAppMonitoringEnabled = newValue
                            LogManager.shared.log("Per-app monitoring enabled: \(newValue)")
                            NotificationCenter.default.post(name: .flowWatchPerAppMonitoringChanged, object: nil)
                        }
                    ), tint: currentSection.tint)
                }
                rowDivider
                settingsRow(title: l10n.t("settings.perApp.interval")) {
                    perAppIntervalPicker
                }
            }
        case .data:
            settingsPanel(title: l10n.t("settings.group.dataActions")) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(l10n.t("settings.data.desc"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Button(l10n.t("settings.data.resetToday"), role: .destructive) {
                            resetAlertMode = .today
                            isShowingResetAlert = true
                        }
                        .buttonStyle(FlowWatchActionButtonStyle(tint: .red, isDestructive: true))
                        Button(l10n.t("settings.data.clearAllHistory"), role: .destructive) {
                            resetAlertMode = .allHistory
                            isShowingResetAlert = true
                        }
                        .buttonStyle(FlowWatchActionButtonStyle(tint: .red, isDestructive: true))
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private var sampleIntervalPicker: some View {
        optionSelector(
            [1.0, 2.0, 3.0, 5.0].map {
                (String(format: l10n.t("settings.statusBar.interval.value"), Int($0)), $0)
            },
            selection: Binding(
                get: { sampleInterval },
                set: { newValue in
                    sampleInterval = newValue
                    NotificationCenter.default.post(name: .flowWatchSampleIntervalChanged, object: nil)
                }
            )
        )
    }

    private var perAppIntervalPicker: some View {
        optionSelector(
            [1.0, 3.0, 5.0, 10.0].map {
                (String(format: l10n.t("settings.perApp.interval.value"), Int($0)), $0)
            },
            selection: Binding(
                get: { perAppSampleInterval },
                set: { newValue in
                    perAppSampleInterval = newValue
                    NotificationCenter.default.post(name: .flowWatchPerAppIntervalChanged, object: nil)
                }
            )
        )
    }

    @ViewBuilder
    private var launchAtLoginRow: some View {
        if #available(macOS 13.0, *) {
            settingsRow(
                title: l10n.t("settings.launchAtLogin.toggle"),
                detail: launchAtLoginStatus.flatMap { launchAtLoginHintText(for: $0) }
            ) {
                ModernSwitch(isOn: Binding(
                    get: { launchAtLoginEnabled },
                    set: { newValue in
                        toggleLaunchAtLogin(to: newValue)
                    }
                ), tint: currentSection.tint)
            }
        } else {
            settingsRow(
                title: l10n.t("settings.launchAtLogin.toggle"),
                detail: l10n.t("settings.requires.macos13")
            ) {
                ModernSwitch(isOn: .constant(false), tint: currentSection.tint, isEnabled: false)
            }
        }
    }

    private var updateInfoLines: [String] {
        var lines: [String] = []
        switch updateManager.status {
        case .checking:
            lines.append(l10n.t("menu.checkingUpdate"))
        case .downloading(_, let progress):
            if let progress {
                lines.append(String(format: l10n.t("settings.update.downloading"), Int((progress * 100).rounded())))
            } else {
                lines.append(l10n.t("update.state.downloading.title"))
            }
        case .readyToInstall(let update):
            lines.append(String(format: l10n.t("settings.update.ready"), update.version))
        case .installOnQuit(let update):
            lines.append(String(format: l10n.t("settings.update.installOnQuit"), update.version))
        case .remindLater(let update, let date):
            lines.append(String(format: l10n.t("settings.update.remindLater"), update.version, formattedUpdateDate(date)))
        case .skipped(let update):
            lines.append(String(format: l10n.t("settings.update.skipped"), update.version))
        case .failed(let message):
            lines.append(message)
        default:
            break
        }
        if let cachedVersion = updateManager.cachedLatestVersion {
            lines.append(String(format: l10n.t("settings.update.available"), cachedVersion))
        }
        lines.append(String(format: l10n.t("settings.update.lastCheck"), formattedLastCheck()))
        lines.append(String(format: l10n.t("settings.update.nextCheck"), formattedNextCheck()))
        return lines
    }

    private func formattedUpdateDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = l10n.locale
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func settingsPanel<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }

            Divider()
                .opacity(0.45)

            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .flowWatchGlassPanel()
    }

    private func settingsRow<Control: View>(
        title: String,
        detail: String? = nil,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 16)
            control().accessibilityElement(children: .contain).accessibilityLabel(title)
        }
        .padding(.vertical, 6)
    }

    private var rowDivider: some View {
        Divider()
            .opacity(0.30)
    }

    private var colorPreviewStrip: some View {
        HStack(spacing: 8) {
            colorPreviewItem(title: l10n.t("settings.color.preview.low"), color: previewSpeedColor(mbps: maxColorRateMbps * 0.12))
            colorPreviewItem(title: l10n.t("settings.color.preview.medium"), color: previewSpeedColor(mbps: maxColorRateMbps * 0.50))
            colorPreviewItem(title: l10n.t("settings.color.preview.high"), color: previewSpeedColor(mbps: maxColorRateMbps))
        }
    }

    private func colorPreviewItem(title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .flowWatchGlassCapsule(material: .thin)
    }

    private func previewSpeedColor(mbps: Double) -> Color {
        guard statusBarColoringEnabled else {
            return .primary
        }
        let percent = max(0, min(colorRatePercent, 100))
        let maxRate = max(0, maxColorRateMbps) * percent / 100
        guard maxRate > 0 else {
            return .primary
        }
        let ratio = max(0, min(mbps / maxRate, 1))
        let start = colorScheme == .dark ? NSColor(srgbRed: 0.957, green: 0.957, blue: 0.949, alpha: 1) : NSColor(srgbRed: 0.098, green: 0.102, blue: 0.11, alpha: 1)
        let yellow = NSColor.systemYellow.usingColorSpace(.sRGB) ?? .systemYellow
        let red = NSColor.systemRed.usingColorSpace(.sRGB) ?? .systemRed

        if ratio < 0.5 {
            return interpolateColor(from: start, to: yellow, t: ratio / 0.5)
        }
        return interpolateColor(from: yellow, to: red, t: (ratio - 0.5) / 0.5)
    }

    private func interpolateColor(from start: NSColor, to end: NSColor, t: Double) -> Color {
        let clamped = CGFloat(max(0, min(1, t)))
        let red = start.redComponent + (end.redComponent - start.redComponent) * clamped
        let green = start.greenComponent + (end.greenComponent - start.greenComponent) * clamped
        let blue = start.blueComponent + (end.blueComponent - start.blueComponent) * clamped
        let alpha = start.alphaComponent + (end.alphaComponent - start.alphaComponent) * clamped

        return Color(nsColor: NSColor(red: red, green: green, blue: blue, alpha: alpha))
    }

    private var statusBarLayout: StatusBarLayout {
        StatusBarLayout.load(rawValue: statusBarLayoutRaw, legacyMode: statusBarDisplayModeRaw,
                             showsTotals: minimalSignalShowsTrafficTotals)
    }

    private func layoutBinding<Value>(_ keyPath: WritableKeyPath<StatusBarLayout, Value>) -> Binding<Value> {
        Binding(get: { statusBarLayout[keyPath: keyPath] }, set: { value in
            var layout = statusBarLayout
            layout[keyPath: keyPath] = value
            statusBarLayoutRaw = layout.rawValue
        })
    }

    private var statusBarComponentControls: some View {
        StatusBarComponentEditor(layout: Binding(
            get: { statusBarLayout },
            set: { statusBarLayoutRaw = $0.rawValue }
        ), tint: currentSection.tint)
    }

    private var mathCurveLoaderOptions: [(String, String)] {
        [(l10n.t("settings.curveLoader.random"), MathCurveLoaderSelection.random.rawValue)]
            + DynamicGraphicPreset.allCases.map { ($0.displayName, $0.rawValue) }
    }

    private var currentMathCurveLoaderSelection: MathCurveLoaderSelection {
        MathCurveLoaderSelection(rawValue: mathCurveLoaderSelectionRaw) ?? .random
    }

    private var mathCurveLoaderSelectionBinding: Binding<String> {
        Binding(
            get: {
                currentMathCurveLoaderSelection.rawValue
            },
            set: { newValue in
                mathCurveLoaderSelectionRaw = MathCurveLoaderSelection(rawValue: newValue)?.rawValue
                    ?? MathCurveLoaderSelection.random.rawValue
            }
        )
    }

    private var mathCurveLoaderRandomSwitchIntervalMinutesBinding: Binding<Double> {
        Binding(
            get: {
                max(1, min(mathCurveLoaderRandomSwitchIntervalMinutes.rounded(), 60))
            },
            set: { newValue in
                mathCurveLoaderRandomSwitchIntervalMinutes = max(1, min(newValue.rounded(), 60))
            }
        )
    }

    private func optionSelector<Value: Hashable>(
        _ options: [(String, Value)],
        selection: Binding<Value>
    ) -> some View {
        FlowWatchSegmentedControl(options: options, selection: selection)
    }

    private enum ResetAlertMode {
        case today
        case allHistory
    }

    private enum FocusField {
        case maxColorRate
    }

    private enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
        case general
        case statusBar
        case coloring
        case launch
        case updates
        case logging
        case perApp
        case data

        var id: Self { self }

        var titleKey: String {
            switch self {
            case .general:
                return "settings.section.general"
            case .statusBar:
                return "settings.section.statusBar"
            case .coloring:
                return "settings.section.coloring"
            case .launch:
                return "settings.section.launch"
            case .updates:
                return "settings.section.updates"
            case .logging:
                return "settings.section.logging"
            case .perApp:
                return "settings.section.perApp"
            case .data:
                return "settings.section.data"
            }
        }

        var subtitleKey: String? {
            switch self {
            case .general:
                return "settings.subtitle.general"
            case .statusBar:
                return "settings.subtitle.statusBar"
            case .coloring:
                return "settings.subtitle.coloring"
            case .launch:
                return "settings.subtitle.launch"
            case .updates:
                return "settings.subtitle.updates"
            case .logging:
                return "settings.subtitle.logging"
            case .perApp:
                return "settings.subtitle.perApp"
            case .data:
                return "settings.subtitle.data"
            }
        }

        var systemImage: String {
            switch self {
            case .general:
                return "gearshape"
            case .statusBar:
                return "menubar.rectangle"
            case .coloring:
                return "paintpalette"
            case .launch:
                return "power"
            case .updates:
                return "arrow.triangle.2.circlepath"
            case .logging:
                return "doc.text"
            case .perApp:
                return "app.badge"
            case .data:
                return "internaldrive"
            }
        }

        var tint: Color {
            FlowWatchPalette.accent
        }
    }

    private var maxColorRateInputBinding: Binding<Double> {
        Binding(
            get: { maxColorRateMbps },
            set: { newValue in
                maxColorRateMbps = max(0, newValue)
            }
        )
    }

    private var colorRatePercentBinding: Binding<Double> {
        Binding(
            get: { min(max(colorRatePercent, 0), 100) },
            set: { newValue in
                colorRatePercent = max(0, min(newValue, 100))
            }
        )
    }

    private var statusBarColoringEnabledBinding: Binding<Bool> {
        Binding(
            get: { statusBarColoringEnabled },
            set: { newValue in
                statusBarColoringEnabled = newValue
                UserDefaults.standard.set(newValue, forKey: "statusBarColoringEnabled")
                NotificationCenter.default.post(name: .flowWatchStatusBarColoringChanged, object: nil)
            }
        )
    }

    private var minimalSignalBlinkSpeedBinding: Binding<Double> {
        Binding(
            get: { min(max(minimalSignalBlinkSpeedPercent, 0), 100) },
            set: { newValue in
                minimalSignalBlinkSpeedPercent = max(0, min(newValue, 100))
            }
        )
    }

    private func refreshLaunchAtLoginState() {
        guard #available(macOS 13.0, *) else { return }
        launchAtLoginEnabled = LaunchAtLoginManager.shared.isEnabled
        launchAtLoginStatus = LaunchAtLoginManager.shared.status
    }

    @available(macOS 13.0, *)
    private func toggleLaunchAtLogin(to enabled: Bool) {
        do {
            try LaunchAtLoginManager.shared.setEnabled(enabled)
            LogManager.shared.log("Launch at login set to \(enabled)")
        } catch {
            refreshLaunchAtLoginState()
            if LaunchAtLoginManager.shared.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
                launchAtLoginErrorMessage = l10n.t("alert.launchAtLogin.needsApproval")
            } else {
                launchAtLoginErrorMessage = String(format: l10n.t("alert.launchAtLogin.failed"), error.localizedDescription)
            }
            LogManager.shared.log("Failed to set launch at login: \(error)", level: .error)
        }

        refreshLaunchAtLoginState()
    }

    @available(macOS 13.0, *)
    private func launchAtLoginHintText(for status: SMAppService.Status) -> String? {
        switch status {
        case .enabled:
            return l10n.t("settings.launchAtLogin.hint.enabled")
        case .notRegistered:
            return l10n.t("settings.launchAtLogin.hint.notRegistered")
        case .requiresApproval:
            return l10n.t("settings.launchAtLogin.hint.requiresApproval")
        case .notFound:
            return l10n.t("settings.launchAtLogin.hint.notFound")
        @unknown default:
            return nil
        }
    }

    private func languageLabel(_ language: AppLanguage) -> String {
        switch language {
        case .system:
            return l10n.t("settings.language.system")
        case .zhHans:
            return l10n.t("settings.language.zhHans")
        case .en:
            return l10n.t("settings.language.en")
        }
    }

    private func displayPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return path.replacingOccurrences(of: home, with: "~")
        }
        return path
    }

    private func formattedLastCheck() -> String {
        guard let date = updateManager.lastCheckDate else {
            return l10n.t("settings.update.never")
        }
        return formatDateTime(date)
    }

    private func formattedNextCheck() -> String {
        if !updateManager.autoCheckEnabled {
            return l10n.t("settings.update.disabled")
        }
        guard let date = updateManager.nextCheckDate else {
            return l10n.t("settings.update.pending")
        }
        return formatDateTime(date)
    }

    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = l10n.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct ModernSwitch: View {
    @Binding var isOn: Bool
    let tint: Color
    var isEnabled: Bool = true
    @Environment(\.isEnabled) private var environmentEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            guard isEnabled && environmentEnabled else { return }
            withAnimation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.85)) {
                isOn.toggle()
            }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? FlowWatchPalette.ink : FlowWatchPalette.well)
                    .frame(width: 46, height: 26)

                Circle()
                    .fill(isOn ? FlowWatchPalette.inverse : FlowWatchPalette.elevated)
                    .frame(width: 20, height: 20)
                    .overlay(
                        Circle()
                            .stroke(Color.primary.opacity(isOn ? 0.20 : 0.10), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(isOn ? 0.14 : 0.07), radius: 3, x: 0, y: 1)
                    .padding(3)
            }
            .overlay(
                Capsule()
                    .stroke(FlowWatchPalette.edge.opacity(0.6), lineWidth: 1)
            )
            .opacity(isEnabled && environmentEnabled ? 1 : 0.4)
        }
        .buttonStyle(FlowWatchHoverButtonStyle())
        .disabled(!isEnabled)
        .accessibilityValue(L10n.t(isOn ? "ui.on" : "ui.off"))
    }
}

private struct ModernSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let tint: Color
    @State private var activeBar: Double?
    @State private var previousBar: Double?
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let progress = CGFloat(normalizedValue)

            HStack(alignment: .center, spacing: 0) {
                ForEach(0..<64) { index in
                    let distance = activeBar.map { abs(Double(index) - $0) } ?? 100
                    let trail = previousBar.map { abs(Double(index) - $0) } ?? 100
                    let lift = reduceMotion ? 0 : 16 * exp(-pow(distance / 3, 2)) + 6 * exp(-pow(trail / 5, 2))
                    Capsule()
                        .fill(Double(index) / 63 <= Double(progress) ? FlowWatchPalette.ink : FlowWatchPalette.ink.opacity(0.13))
                        .frame(width: 3, height: 20 + lift)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 48)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                guard isEnabled else { activeBar = nil; previousBar = nil; return }
                switch phase {
                case .active(let location):
                    withAnimation(reduceMotion ? nil : .interactiveSpring(response: 0.18, dampingFraction: 0.72)) {
                        activeBar = Double(location.x / width) * 63
                    }
                case .ended:
                    withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.65)) { activeBar = nil; previousBar = nil }
                }
            }
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { gesture in
                    previousBar = activeBar
                    activeBar = Double(gesture.location.x / width) * 63
                    updateValue(locationX: gesture.location.x, width: width)
                }
                .onEnded { _ in
                    withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.65)) { activeBar = nil; previousBar = nil }
                }
            )
        }
        .frame(height: 48)
        .focusable()
        .onMoveCommand { direction in
            if direction == .left || direction == .down { adjust(-1) }
            if direction == .right || direction == .up { adjust(1) }
        }
        .accessibilityValue(String(format: "%.0f", value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: adjust(1)
            case .decrement: adjust(-1)
            @unknown default: break
            }
        }
    }

    private func adjust(_ direction: Double) {
        value = min(range.upperBound, max(range.lowerBound, value + direction * (step > 0 ? step : (range.upperBound - range.lowerBound) / 100)))
    }

    private var normalizedValue: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return max(0, min((value - range.lowerBound) / span, 1))
    }

    private func updateValue(locationX: CGFloat, width: CGFloat) {
        let ratio = max(0, min(Double(locationX / width), 1))
        let rawValue = range.lowerBound + ratio * (range.upperBound - range.lowerBound)
        let steppedValue: Double
        if step > 0 {
            steppedValue = ((rawValue - range.lowerBound) / step).rounded() * step + range.lowerBound
        } else {
            steppedValue = rawValue
        }
        value = max(range.lowerBound, min(steppedValue, range.upperBound))
    }
}

#if DEBUG
#Preview {
    SettingsView()
        .environmentObject(LocalizationManager.shared)
        .environment(\.locale, LocalizationManager.shared.locale)
}
#endif
