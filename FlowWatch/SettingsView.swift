import SwiftUI
import AppKit
import ServiceManagement

struct SettingsView: View {
    @AppStorage("statusBarDisplayMode") private var statusBarDisplayModeRaw: String = FlowWatchApp.StatusBarDisplayMode.speed.rawValue
    @AppStorage("maxColorRateMbps") private var maxColorRateMbps: Double = 100
    @AppStorage("colorRatePercent") private var colorRatePercent: Double = 100
    @AppStorage("update.autoCheckEnabled") private var autoCheckEnabled: Bool = true
    @AppStorage("perAppMonitoring.enabled") private var perAppMonitoringEnabled: Bool = false
    @AppStorage("perAppMonitoring.sampleInterval") private var perAppSampleInterval: Double = 3.0
    @AppStorage("statusBar.sampleInterval") private var sampleInterval: Double = 5.0
    @AppStorage("statusBarSmoothTransition") private var smoothTransition: Bool = true
    @AppStorage("minimalSignalShowsTrafficTotals") private var minimalSignalShowsTrafficTotals: Bool = true
    @AppStorage("logging.enabled") private var loggingEnabled: Bool = true
    @ObservedObject private var updateManager = UpdateManager.shared
    @State private var selectedSection: SettingsSection? = .general
    @State private var isShowingResetAlert = false
    @State private var resetAlertMode: ResetAlertMode?
    @State private var launchAtLoginEnabled = false
    @State private var launchAtLoginStatus: SMAppService.Status?
    @State private var launchAtLoginErrorMessage: String?
    @FocusState private var focusedField: FocusField?
    @EnvironmentObject private var l10n: LocalizationManager

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
            .background(Color(.textBackgroundColor).opacity(0.28))
        }
        .frame(minWidth: 860, minHeight: 580)
        .onAppear {
            refreshLaunchAtLoginState()
            DispatchQueue.main.async {
                focusedField = nil
            }
        }
        .alert(l10n.t("alert.reset.title"), isPresented: $isShowingResetAlert) {
            Button(l10n.t("common.cancel"), role: .cancel) {}
            Button(resetAlertMode == .allHistory ? l10n.t("common.clear") : l10n.t("common.reset"), role: .destructive) {
                switch resetAlertMode {
                case .today:
                    NotificationCenter.default.post(name: .flowWatchResetToday, object: nil)
                case .allHistory:
                    NotificationCenter.default.post(name: .flowWatchResetAllHistory, object: nil)
                case .none:
                    break
                }
            }
        } message: {
            switch resetAlertMode {
            case .today:
                Text(l10n.t("alert.reset.today"))
            case .allHistory:
                Text(l10n.t("alert.reset.all"))
            case .none:
                Text("")
            }
        }
        .alert(l10n.t("alert.launchAtLogin.errorTitle"), isPresented: Binding(
            get: { launchAtLoginErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    launchAtLoginErrorMessage = nil
                }
            }
        )) {
            Button(l10n.t("common.ok")) {}
        } message: {
            Text(launchAtLoginErrorMessage ?? "")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 6) {
                ForEach(SettingsSection.allCases) { section in
                    sidebarRow(section)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 238)
        .background(.regularMaterial)
    }

    private func sidebarRow(_ section: SettingsSection) -> some View {
        let isSelected = currentSection == section

        return Button {
            selectedSection = section
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : section.tint)
                    .frame(width: 28, height: 28)
                    .background(
                        (isSelected ? Color.white.opacity(0.16) : section.tint.opacity(0.12)),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.t(section.titleKey))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                    if let subtitleKey = section.subtitleKey {
                        Text(l10n.t(subtitleKey))
                            .font(.caption2)
                            .foregroundStyle(isSelected ? Color.white.opacity(0.78) : Color.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(
                isSelected ? section.tint : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    private var currentSection: SettingsSection {
        selectedSection ?? .general
    }

    private var detailHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: currentSection.systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(currentSection.tint)
                .frame(width: 42, height: 42)
                .background(currentSection.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(l10n.t(currentSection.titleKey))
                    .font(.system(size: 24, weight: .semibold))
                if let subtitleKey = currentSection.subtitleKey {
                    Text(l10n.t(subtitleKey))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            sectionStatusBadge
        }
        .padding(16)
        .background(currentSection.tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(currentSection.tint.opacity(0.16), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var sectionStatusBadge: some View {
        switch currentSection {
        case .general:
            statusBadge(title: l10n.t("settings.language"), value: languageLabel(l10n.language), tint: currentSection.tint)
        case .statusBar:
            statusBadge(title: l10n.t("settings.statusBar.interval"), value: String(format: l10n.t("settings.statusBar.interval.value"), Int(sampleInterval)), tint: currentSection.tint)
        case .coloring:
            statusBadge(title: l10n.t("settings.maxColorRate.intensityTitle"), value: "\(Int(colorRatePercent.rounded()))%", tint: currentSection.tint)
        case .launch:
            statusBadge(title: l10n.t("settings.launchAtLogin.toggle"), value: launchAtLoginEnabled ? l10n.t("settings.state.on") : l10n.t("settings.state.off"), tint: currentSection.tint)
        case .updates:
            statusBadge(title: l10n.t("settings.update.autoCheck"), value: autoCheckEnabled ? l10n.t("settings.state.on") : l10n.t("settings.state.off"), tint: currentSection.tint)
        case .logging:
            statusBadge(title: l10n.t("settings.logging.toggle"), value: loggingEnabled ? l10n.t("settings.state.on") : l10n.t("settings.state.off"), tint: currentSection.tint)
        case .perApp:
            statusBadge(title: l10n.t("settings.perApp.toggle"), value: perAppMonitoringEnabled ? l10n.t("settings.state.on") : l10n.t("settings.state.off"), tint: currentSection.tint)
        case .data:
            statusBadge(title: l10n.t("settings.section.data"), value: l10n.t("settings.data.localOnly"), tint: currentSection.tint)
        }
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch currentSection {
        case .general:
            overviewGrid
            settingsPanel(title: l10n.t("settings.group.language"), systemImage: "globe") {
                settingsRow(title: l10n.t("settings.language")) {
                    optionSelector(
                        AppLanguage.allCases.map { (languageLabel($0), $0) },
                        selection: Binding(
                            get: { l10n.language },
                            set: { l10n.language = $0 }
                        )
                    )
                }
            }
        case .statusBar:
            settingsPanel(title: l10n.t("settings.group.statusDisplay"), systemImage: "menubar.rectangle") {
                settingsRow(title: l10n.t("settings.displayContent.label")) {
                    optionSelector(
                        FlowWatchApp.StatusBarDisplayMode.allCases.map { (l10n.t($0.titleKey), $0.rawValue) },
                        selection: $statusBarDisplayModeRaw
                    )
                }
                if FlowWatchApp.StatusBarDisplayMode(rawValue: statusBarDisplayModeRaw) == .minimalSignal {
                    rowDivider
                    settingsRow(
                        title: l10n.t("settings.minimalSignal.showTotals"),
                        detail: l10n.t("settings.minimalSignal.showTotals.desc")
                    ) {
                        ModernSwitch(isOn: $minimalSignalShowsTrafficTotals, tint: currentSection.tint)
                    }
                }
            }
            settingsPanel(title: l10n.t("settings.group.numberUpdates"), systemImage: "timer") {
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
            settingsPanel(title: l10n.t("settings.group.colorRules"), systemImage: "paintpalette") {
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
                        .background(Color(.windowBackgroundColor).opacity(0.82), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(currentSection.tint.opacity(focusedField == .maxColorRate ? 0.42 : 0.14), lineWidth: 1)
                        )
                        Text("Mbps")
                            .foregroundStyle(.secondary)
                    }
                }
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
                    colorPreviewStrip
                }
                .padding(.vertical, 8)
            }
        case .launch:
            settingsPanel(title: l10n.t("settings.group.login"), systemImage: "power") {
                launchAtLoginRow
            }
        case .updates:
            settingsPanel(title: l10n.t("settings.group.updatePolicy"), systemImage: "arrow.triangle.2.circlepath") {
                settingsRow(
                    title: l10n.t("settings.update.autoCheck"),
                    detail: l10n.t("settings.update.hint")
                ) {
                    ModernSwitch(
                        isOn: Binding(
                            get: { autoCheckEnabled },
                            set: { newValue in
                                autoCheckEnabled = newValue
                                LogManager.shared.log("Auto update check enabled: \(newValue)")
                                if newValue {
                                    NotificationCenter.default.post(name: .flowWatchCheckForUpdates, object: nil)
                                }
                            }
                        ),
                        tint: currentSection.tint
                    )
                }
            }
            settingsPanel(title: l10n.t("settings.group.updateStatus"), systemImage: "clock") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(updateInfoLines, id: \.self) { line in
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }
        case .logging:
            settingsPanel(title: l10n.t("settings.group.logs"), systemImage: "doc.text") {
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
            settingsPanel(title: l10n.t("settings.group.logsLocation"), systemImage: "folder") {
                settingsRow(
                    title: l10n.t("settings.logging.openFolder"),
                    detail: String(format: l10n.t("settings.logging.path"), displayPath(LogManager.shared.logsDirectoryPath))
                ) {
                    Button(l10n.t("settings.logging.openFolder")) {
                        let url = URL(fileURLWithPath: LogManager.shared.logsDirectoryPath)
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                        LogManager.shared.log("Open logs directory from settings")
                    }
                    .buttonStyle(ModernActionButtonStyle(tint: currentSection.tint))
                }
            }
        case .perApp:
            settingsPanel(title: l10n.t("settings.group.perAppCapture"), systemImage: "app.badge") {
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
            settingsPanel(title: l10n.t("settings.group.dataActions"), systemImage: "internaldrive") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(l10n.t("settings.data.desc"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Button(l10n.t("settings.data.resetToday"), role: .destructive) {
                            resetAlertMode = .today
                            isShowingResetAlert = true
                        }
                        .buttonStyle(ModernActionButtonStyle(tint: .red, isDestructive: true))
                        Button(l10n.t("settings.data.clearAllHistory"), role: .destructive) {
                            resetAlertMode = .allHistory
                            isShowingResetAlert = true
                        }
                        .buttonStyle(ModernActionButtonStyle(tint: .red, isDestructive: true))
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
        if updateManager.status == .checking {
            lines.append(l10n.t("menu.checkingUpdate"))
        }
        if let cachedVersion = updateManager.cachedLatestVersion {
            lines.append(String(format: l10n.t("settings.update.available"), cachedVersion))
        }
        lines.append(String(format: l10n.t("settings.update.lastCheck"), formattedLastCheck()))
        lines.append(String(format: l10n.t("settings.update.nextCheck"), formattedNextCheck()))
        return lines
    }

    private var overviewGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 138), spacing: 10)],
            alignment: .leading,
            spacing: 10
        ) {
            overviewTile(
                title: l10n.t("settings.overview.display"),
                value: currentDisplayModeLabel,
                systemImage: "menubar.rectangle",
                tint: SettingsSection.statusBar.tint
            )
            overviewTile(
                title: l10n.t("settings.overview.sample"),
                value: String(format: l10n.t("settings.statusBar.interval.value"), Int(sampleInterval)),
                systemImage: "timer",
                tint: SettingsSection.statusBar.tint
            )
            overviewTile(
                title: l10n.t("settings.overview.transition"),
                value: smoothTransition ? l10n.t("settings.state.on") : l10n.t("settings.state.off"),
                systemImage: "waveform.path.ecg",
                tint: SettingsSection.coloring.tint
            )
            overviewTile(
                title: l10n.t("settings.overview.perApp"),
                value: perAppMonitoringEnabled ? l10n.t("settings.state.on") : l10n.t("settings.state.off"),
                systemImage: "app.badge",
                tint: SettingsSection.perApp.tint
            )
        }
    }

    private func overviewTile(title: String, value: String, systemImage: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.controlBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
        )
    }

    private func settingsPanel<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(currentSection.tint)
                    .frame(width: 24, height: 24)
                    .background(currentSection.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }

            Divider()
                .opacity(0.45)

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(.controlBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
        )
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
            control()
        }
        .padding(.vertical, 6)
    }

    private var rowDivider: some View {
        Divider()
            .opacity(0.45)
    }

    private func statusBadge(title: String, value: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.controlBackgroundColor).opacity(0.72), in: Capsule())
        .overlay(
            Capsule()
                .stroke(tint.opacity(0.14), lineWidth: 1)
        )
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
        .background(Color(.windowBackgroundColor).opacity(0.72), in: Capsule())
    }

    private func previewSpeedColor(mbps: Double) -> Color {
        let percent = max(0, min(colorRatePercent, 100))
        let maxRate = max(0, maxColorRateMbps) * percent / 100
        guard maxRate > 0 else {
            return .primary
        }
        let ratio = max(0, min(mbps / maxRate, 1))
        let start = NSColor.labelColor.usingColorSpace(.sRGB) ?? .labelColor
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

    private var currentDisplayModeLabel: String {
        let mode = FlowWatchApp.StatusBarDisplayMode(rawValue: statusBarDisplayModeRaw) ?? .speed
        return l10n.t(mode.titleKey)
    }

    private func optionSelector<Value: Hashable>(
        _ options: [(String, Value)],
        selection: Binding<Value>
    ) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let isSelected = selection.wrappedValue == option.1

                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        selection.wrappedValue = option.1
                    }
                } label: {
                    Text(option.0)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(minWidth: 46)
                        .background(
                            isSelected ? currentSection.tint : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color(.windowBackgroundColor).opacity(0.82), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.16), value: selection.wrappedValue)
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
            switch self {
            case .general:
                return .blue
            case .statusBar:
                return .indigo
            case .coloring:
                return .orange
            case .launch:
                return .green
            case .updates:
                return .teal
            case .logging:
                return .gray
            case .perApp:
                return .purple
            case .data:
                return .red
            }
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
        if !autoCheckEnabled {
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

private struct ModernSwitch: View {
    @Binding var isOn: Bool
    let tint: Color
    var isEnabled: Bool = true

    var body: some View {
        Button {
            guard isEnabled else { return }
            withAnimation(.spring(response: 0.24, dampingFraction: 0.78)) {
                isOn.toggle()
            }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? tint : Color.secondary.opacity(0.18))
                    .frame(width: 46, height: 26)

                Circle()
                    .fill(Color(.windowBackgroundColor))
                    .frame(width: 20, height: 20)
                    .shadow(color: Color.black.opacity(isOn ? 0.18 : 0.10), radius: 3, x: 0, y: 1)
                    .padding(3)
            }
            .overlay(
                Capsule()
                    .stroke(isOn ? tint.opacity(0.28) : Color.secondary.opacity(0.16), lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

private struct ModernActionButtonStyle: ButtonStyle {
    let tint: Color
    var isDestructive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(isDestructive ? Color.red : tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                (isDestructive ? Color.red : tint).opacity(configuration.isPressed ? 0.18 : 0.10),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke((isDestructive ? Color.red : tint).opacity(0.18), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private struct ModernSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let progress = CGFloat(normalizedValue)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.14))
                    .frame(height: 8)

                Capsule()
                    .fill(tint)
                    .frame(width: width * progress, height: 8)

                Circle()
                    .fill(Color(.windowBackgroundColor))
                    .frame(width: 18, height: 18)
                    .shadow(color: Color.black.opacity(0.16), radius: 4, x: 0, y: 1)
                    .overlay(
                        Circle()
                            .stroke(tint.opacity(0.35), lineWidth: 1)
                    )
                    .offset(x: max(0, min(width - 18, width * progress - 9)))
            }
            .frame(height: 28)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        updateValue(locationX: gesture.location.x, width: width)
                    }
            )
        }
        .frame(height: 28)
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
