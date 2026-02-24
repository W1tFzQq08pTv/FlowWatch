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
    @AppStorage("statusBar.smoothTransition") private var smoothTransition: Bool = false
    @AppStorage("logging.enabled") private var loggingEnabled: Bool = true
    @ObservedObject private var updateManager = UpdateManager.shared
    @State private var isShowingResetAlert = false
    @State private var resetAlertMode: ResetAlertMode?
    @State private var launchAtLoginEnabled = false
    @State private var launchAtLoginStatus: SMAppService.Status?
    @State private var launchAtLoginErrorMessage: String?
    @FocusState private var focusedField: FocusField?
    @EnvironmentObject private var l10n: LocalizationManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            
            GroupBox {
                HStack {
                    Text(l10n.t("settings.language"))
                    Spacer()
                    Picker("", selection: Binding(
                        get: { l10n.language },
                        set: { l10n.language = $0 }
                    )) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(languageLabel(language)).tag(language)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220, alignment: .trailing)
                }
                .frame(maxWidth: .infinity)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(l10n.t("settings.displayContent.label"))
                        Spacer()
                        Picker("", selection: $statusBarDisplayModeRaw) {
                            ForEach(FlowWatchApp.StatusBarDisplayMode.allCases, id: \.rawValue) { mode in
                                Text(l10n.t(mode.titleKey)).tag(mode.rawValue)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 220, alignment: .trailing)
                    }
                    .frame(maxWidth: .infinity)

                    Toggle(l10n.t("settings.smoothTransition.toggle"), isOn: $smoothTransition)
                    Text(l10n.t("settings.smoothTransition.desc"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                sectionLabel(l10n.t("settings.section.statusBar"), systemImage: "menubar.rectangle")
            }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(l10n.t("settings.maxColorRate.limitTitle"))
                            Spacer()
                            HStack(spacing: 6) {
                                TextField(
                                    "",
                                    value: maxColorRateInputBinding,
                                    format: .number.precision(.fractionLength(0))
                                )
                                .frame(width: 72)
                                .multilineTextAlignment(.trailing)
                                .textFieldStyle(.roundedBorder)
                                .focused($focusedField, equals: .maxColorRate)
                                Text("Mbps")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        HStack {
                            Text(l10n.t("settings.maxColorRate.intensityTitle"))
                            Spacer()
                            Text("\(Int(colorRatePercent.rounded()))%")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: colorRatePercentBinding, in: 0...100, step: 1)
                        Text(l10n.t("settings.maxColorRate.desc"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                sectionLabel(l10n.t("settings.section.coloring"), systemImage: "paintpalette")
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    if #available(macOS 13.0, *) {
                        Toggle(l10n.t("settings.launchAtLogin.toggle"), isOn: Binding(
                            get: { launchAtLoginEnabled },
                            set: { newValue in
                                toggleLaunchAtLogin(to: newValue)
                            }
                        ))

                        if let status = launchAtLoginStatus,
                           let hint = launchAtLoginHintText(for: status) {
                            Text(hint)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Toggle(l10n.t("settings.launchAtLogin.toggle"), isOn: .constant(false))
                            .disabled(true)
                        Text(l10n.t("settings.requires.macos13"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                sectionLabel(l10n.t("settings.section.launch"), systemImage: "power")
            }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(l10n.t("settings.update.autoCheck"), isOn: Binding(
                            get: { autoCheckEnabled },
                            set: { newValue in
                                autoCheckEnabled = newValue
                                LogManager.shared.log("Auto update check enabled: \(newValue)")
                                if newValue {
                                    NotificationCenter.default.post(name: .flowWatchCheckForUpdates, object: nil)
                                }
                            }
                        ))
                        if updateManager.status == .checking {
                            Text(l10n.t("menu.checkingUpdate"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let cachedVersion = updateManager.cachedLatestVersion {
                            Text(String(format: l10n.t("settings.update.available"), cachedVersion))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(String(format: l10n.t("settings.update.lastCheck"), formattedLastCheck()))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(format: l10n.t("settings.update.nextCheck"), formattedNextCheck()))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(l10n.t("settings.update.hint"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                sectionLabel(l10n.t("settings.section.updates"), systemImage: "arrow.triangle.2.circlepath")
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(l10n.t("settings.logging.toggle"), isOn: Binding(
                        get: { loggingEnabled },
                        set: { newValue in
                            loggingEnabled = newValue
                            LogManager.shared.log("Logging enabled: \(newValue)")
                        }
                    ))
                    Text(l10n.t("settings.logging.hint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        let url = URL(fileURLWithPath: LogManager.shared.logsDirectoryPath)
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                        LogManager.shared.log("Open logs directory from settings")
                    } label: {
                        Text(String(format: l10n.t("settings.logging.path"), displayPath(LogManager.shared.logsDirectoryPath)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.link)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                sectionLabel(l10n.t("settings.section.logging"), systemImage: "doc.text")
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(l10n.t("settings.perApp.toggle"), isOn: Binding(
                        get: { perAppMonitoringEnabled },
                        set: { newValue in
                            perAppMonitoringEnabled = newValue
                            LogManager.shared.log("Per-app monitoring enabled: \(newValue)")
                            NotificationCenter.default.post(name: .flowWatchPerAppMonitoringChanged, object: nil)
                        }
                    ))
                    HStack {
                        Text(l10n.t("settings.perApp.interval"))
                        Picker("", selection: Binding(
                            get: { perAppSampleInterval },
                            set: { newValue in
                                perAppSampleInterval = newValue
                                NotificationCenter.default.post(name: .flowWatchPerAppIntervalChanged, object: nil)
                            }
                        )) {
                            Text(String(format: l10n.t("settings.perApp.interval.value"), 1)).tag(1.0)
                            Text(String(format: l10n.t("settings.perApp.interval.value"), 3)).tag(3.0)
                            Text(String(format: l10n.t("settings.perApp.interval.value"), 5)).tag(5.0)
                            Text(String(format: l10n.t("settings.perApp.interval.value"), 10)).tag(10.0)
                        }
                        .labelsHidden()
                        .frame(width: 80)
                    }
                    Text(l10n.t("settings.perApp.desc"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                sectionLabel(l10n.t("settings.section.perApp"), systemImage: "app.badge")
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Button(l10n.t("settings.data.resetToday"), role: .destructive) {
                        resetAlertMode = .today
                        isShowingResetAlert = true
                    }
                    Button(l10n.t("settings.data.clearAllHistory"), role: .destructive) {
                        resetAlertMode = .allHistory
                        isShowingResetAlert = true
                    }
                    Text(l10n.t("settings.data.desc"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                sectionLabel(l10n.t("settings.section.data"), systemImage: "internaldrive")
            }
        }
        .padding(20)
        .frame(minWidth: 420, alignment: .topLeading)
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

    private var header: some View {
        VStack(alignment: .center, spacing: 6) {
            Text(l10n.t("settings.subtitle"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }

    private enum ResetAlertMode {
        case today
        case allHistory
    }

    private enum FocusField {
        case maxColorRate
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

    private func sectionLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(title)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

#if DEBUG
#Preview {
    SettingsView()
        .environmentObject(LocalizationManager.shared)
        .environment(\.locale, LocalizationManager.shared.locale)
}
#endif
