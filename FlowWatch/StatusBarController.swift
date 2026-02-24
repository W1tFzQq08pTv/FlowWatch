import SwiftUI
import AppKit
import Combine

@MainActor
final class StatusBarController: NSObject, ObservableObject {
    private let displayModeKey = "statusBarDisplayMode"
    private let maxColorRateKey = "maxColorRateMbps"
    private let colorRatePercentKey = "colorRatePercent"
    private let smoothTransitionKey = "statusBar.smoothTransition"
    private let monitor: NetworkUsageMonitor
    private let processMonitor: ProcessNetworkMonitor
    private let statusItem: NSStatusItem
    private let updateManager = UpdateManager.shared
    private weak var updateMenuItem: NSMenuItem?
    private var maxColorRateMbps: Double {
        get {
            UserDefaults.standard.object(forKey: maxColorRateKey) as? Double ?? 100
        }
        set {
            let clamped = max(0, newValue)
            UserDefaults.standard.set(clamped, forKey: maxColorRateKey)
            updateStatusButtonContent()
        }
    }
    private var colorRatePercent: Double {
        get {
            if UserDefaults.standard.object(forKey: colorRatePercentKey) == nil {
                return 100
            }
            return UserDefaults.standard.double(forKey: colorRatePercentKey)
        }
        set {
            let clamped = max(0, min(newValue, 100))
            UserDefaults.standard.set(clamped, forKey: colorRatePercentKey)
            updateStatusButtonContent()
        }
    }
    private var cancellables = Set<AnyCancellable>()
    private var menu: NSMenu = NSMenu()

    init(monitor: NetworkUsageMonitor, processMonitor: ProcessNetworkMonitor) {
        self.monitor = monitor
        self.processMonitor = processMonitor
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.isVisible = true
        super.init()
        PerAppTrafficDetailWindowController.shared.bindMonitor(processMonitor)
        configureStatusButton()
        bindMonitor()
        bindUserDefaults()
        bindNotifications()
        bindUpdateManager()
        bindProcessMonitor()
        updateStatusButtonContent()
        scheduleAutomaticUpdateCheck()
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        rebuildMenu()
        statusItem.menu = menu
        button.imagePosition = .imageOnly
        button.focusRingType = .none
    }

    private func bindMonitor() {
        monitor.$downloadBps
            .combineLatest(monitor.$uploadBps, monitor.$todayDownloaded, monitor.$todayUploaded)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _, _ in
                self?.updateStatusButtonContent()
            }
            .store(in: &cancellables)
    }

    private func bindUserDefaults() {
        let defaults = UserDefaults.standard
        let keys = [displayModeKey, maxColorRateKey, colorRatePercentKey, smoothTransitionKey]
        for key in keys {
            defaults.addObserver(self, forKeyPath: key, options: [.new, .old], context: nil)
        }
    }

    override nonisolated func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        guard let keyPath = keyPath else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }
        let watchedKeys = [displayModeKey, maxColorRateKey, colorRatePercentKey, smoothTransitionKey]
        guard watchedKeys.contains(keyPath) else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }
        Task { @MainActor [weak self] in
            self?.updateStatusButtonContent()
        }
    }

    private func bindNotifications() {
        NotificationCenter.default.publisher(for: .flowWatchResetToday)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.performResetToday()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .flowWatchResetAllHistory)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.performResetAllHistory()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: .flowWatchLanguageChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .flowWatchCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateManager.checkForUpdates(userInitiated: true)
                self?.refreshUpdateMenuItem()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .flowWatchPerAppMonitoringChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let enabled = UserDefaults.standard.bool(forKey: "perAppMonitoring.enabled")
                self.processMonitor.setEnabled(enabled)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .flowWatchPerAppIntervalChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let interval = UserDefaults.standard.double(forKey: "perAppMonitoring.sampleInterval")
                self.processMonitor.updateInterval(interval)
            }
            .store(in: &cancellables)
    }

    private func bindProcessMonitor() {
        processMonitor.$isEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
            }
            .store(in: &cancellables)
    }

    private func bindUpdateManager() {
        updateManager.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshUpdateMenuItem()
            }
            .store(in: &cancellables)
    }

    private func updateStatusButtonContent() {
        guard let button = statusItem.button else { return }
        button.image = nil
        button.imagePosition = .imageOnly

        switch displayMode {
        case .speed:
            renderSpeedOnly(into: button)
        case .total:
            renderTotalOnly(into: button)
        case .both:
            renderCombined(into: button)
        }
    }

    private func colorForSpeed(_ bytesPerSecond: Double) -> NSColor {
        let mbps = max(0, bytesPerSecond) * 8 / 1_000_000
        let percent = max(0, min(colorRatePercent, 100))
        let maxRate = max(0, maxColorRateMbps) * percent / 100
        guard maxRate > 0 else {
            return normalizedColor(.white)
        }
        let ratio = max(0, min(mbps / maxRate, 1))

        let start = normalizedColor(.white)
        let mid = normalizedColor(.systemYellow)
        let end = normalizedColor(.systemRed)

        if ratio < 0.5 {
            return interpolateColor(from: start, to: mid, t: ratio / 0.5)
        } else {
            return interpolateColor(from: mid, to: end, t: (ratio - 0.5) / 0.5)
        }
    }

    private func normalizedColor(_ color: NSColor) -> NSColor {
        color.usingColorSpace(.sRGB) ?? color
    }

    private func interpolateColor(from start: NSColor, to end: NSColor, t: Double) -> NSColor {
        let clampedT = CGFloat(max(0, min(1, t)))
        let startColor = normalizedColor(start)
        let endColor = normalizedColor(end)

        let red = startColor.redComponent + (endColor.redComponent - startColor.redComponent) * clampedT
        let green = startColor.greenComponent + (endColor.greenComponent - startColor.greenComponent) * clampedT
        let blue = startColor.blueComponent + (endColor.blueComponent - startColor.blueComponent) * clampedT
        let alpha = startColor.alphaComponent + (endColor.alphaComponent - startColor.alphaComponent) * clampedT

        return NSColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    private func makeSpeedBadgeImage() -> NSImage? {
        let up = monitor.fixedWidthCompactSpeed(monitor.uploadBps)
        let down = monitor.fixedWidthCompactSpeed(monitor.downloadBps)
        let upLine = "\(up)↑"
        let downLine = "\(down)↓"
        let text = "\(upLine)\n\(downLine)"

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = -3

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 6.5, weight: .semibold),
            .paragraphStyle: paragraph
        ]

        let attr = NSMutableAttributedString(string: text, attributes: attributes)
        let upLength = (upLine as NSString).length
        let downLength = (downLine as NSString).length
        attr.addAttribute(.foregroundColor, value: colorForSpeed(monitor.uploadBps), range: NSRange(location: 0, length: upLength))
        attr.addAttribute(.foregroundColor, value: colorForSpeed(monitor.downloadBps), range: NSRange(location: upLength + 1, length: downLength))

        let size = attr.size()
        let canvas = NSImage(size: NSSize(width: max(42, size.width), height: max(13, size.height)))

        canvas.lockFocus()
        attr.draw(at: NSPoint(
            x: (canvas.size.width - size.width) / 2,
            y: (canvas.size.height - size.height) / 2
        ))
        canvas.unlockFocus()
        canvas.isTemplate = false
        return canvas
    }

    private func makeTotalBadgeImage() -> NSImage? {
        let up = monitor.fixedWidthDataAmount(monitor.todayUploaded)
        let down = monitor.fixedWidthDataAmount(monitor.todayDownloaded)
        let upLine = "\(up)↑"
        let downLine = "\(down)↓"
        let text = "\(upLine)\n\(downLine)"

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = -3

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 6.5, weight: .semibold),
            .paragraphStyle: paragraph,
            .foregroundColor: NSColor.white
        ]

        let attr = NSMutableAttributedString(string: text, attributes: attributes)
        let upLength = (upLine as NSString).length
        let downLength = (downLine as NSString).length
        attr.addAttribute(.foregroundColor, value: colorForSpeed(monitor.uploadBps), range: NSRange(location: 0, length: upLength))
        attr.addAttribute(.foregroundColor, value: colorForSpeed(monitor.downloadBps), range: NSRange(location: upLength + 1, length: downLength))
        let size = attr.size()
        let canvas = NSImage(size: NSSize(width: max(46, size.width), height: max(14, size.height)))

        canvas.lockFocus()
        attr.draw(at: NSPoint(
            x: (canvas.size.width - size.width) / 2,
            y: (canvas.size.height - size.height) / 2
        ))
        canvas.unlockFocus()
        canvas.isTemplate = false
        return canvas
    }

    private func makeCombinedBadgeImage() -> NSImage? {
        let totalsUp = monitor.fixedWidthDataAmount(monitor.todayUploaded) + "↑"
        let totalsDown = monitor.fixedWidthDataAmount(monitor.todayDownloaded) + "↓"
        let speedUp = monitor.fixedWidthCompactSpeed(monitor.uploadBps) + "↑"
        let speedDown = monitor.fixedWidthCompactSpeed(monitor.downloadBps) + "↓"

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = -3
        let font = NSFont.monospacedSystemFont(ofSize: 6.5, weight: .semibold)

        let totalsText = "\(totalsUp)\n\(totalsDown)"
        let totalsAttr = NSMutableAttributedString(
            string: totalsText,
            attributes: [
                .font: font,
                .paragraphStyle: paragraph,
                .foregroundColor: NSColor.white
            ]
        )

        let speedText = "\(speedUp)\n\(speedDown)"
        let speedAttr = NSMutableAttributedString(
            string: speedText,
            attributes: [
                .font: font,
                .paragraphStyle: paragraph
            ]
        )
        let upLength = (speedUp as NSString).length
        speedAttr.addAttribute(.foregroundColor, value: colorForSpeed(monitor.uploadBps), range: NSRange(location: 0, length: upLength))
        speedAttr.addAttribute(.foregroundColor, value: colorForSpeed(monitor.downloadBps), range: NSRange(location: upLength + 1, length: (speedDown as NSString).length))

        let spacer: CGFloat = 6
        let totalSize = totalsAttr.size()
        let speedSize = speedAttr.size()
        let canvasSize = NSSize(width: max(52, totalSize.width) + spacer + max(52, speedSize.width),
                                height: max(max(14, totalSize.height), max(14, speedSize.height)))
        let canvas = NSImage(size: canvasSize)
        canvas.lockFocus()
        totalsAttr.draw(at: NSPoint(
            x: 0,
            y: (canvasSize.height - totalSize.height) / 2
        ))
        speedAttr.draw(at: NSPoint(
            x: max(52, totalSize.width) + spacer,
            y: (canvasSize.height - speedSize.height) / 2
        ))
        canvas.unlockFocus()
        canvas.isTemplate = false
        return canvas
    }

    private func renderSpeedOnly(into button: NSStatusBarButton) {
        if let image = makeSpeedBadgeImage() {
            button.image = image
            button.title = ""
        } else {
            let down = monitor.fixedWidthCompactSpeed(monitor.downloadBps)
            let up = monitor.fixedWidthCompactSpeed(monitor.uploadBps)
            let upLine = "\(up)↑"
            let downLine = "\(down)↓"
            let text = upLine + " " + downLine
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
            ]
            let attr = NSMutableAttributedString(string: text, attributes: attributes)
            let upLength = (upLine as NSString).length
            let downLength = (downLine as NSString).length
            attr.addAttribute(.foregroundColor, value: colorForSpeed(monitor.uploadBps), range: NSRange(location: 0, length: upLength))
            attr.addAttribute(.foregroundColor, value: colorForSpeed(monitor.downloadBps), range: NSRange(location: upLength + 1, length: downLength))
            button.attributedTitle = attr
        }
    }

    private func renderTotalOnly(into button: NSStatusBarButton) {
        if let image = makeTotalBadgeImage() {
            button.image = image
            button.title = ""
        }
    }

    private func renderCombined(into button: NSStatusBarButton) {
        if let image = makeCombinedBadgeImage() {
            button.image = image
            button.title = ""
        }
    }

    private var displayMode: FlowWatchApp.StatusBarDisplayMode {
        get {
            if let stored = UserDefaults.standard.string(forKey: displayModeKey),
               let mode = FlowWatchApp.StatusBarDisplayMode(rawValue: stored) {
                return mode
            }
            return .speed
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: displayModeKey)
        }
    }

    private func performResetToday() {
        LogManager.shared.log("Reset today from status bar")
        monitor.resetTodayTraffic()
        ProcessTrafficStorage.shared.clearTodayRecords()
    }

    private func performResetAllHistory() {
        LogManager.shared.log("Clear all history from status bar")
        monitor.clearAllTrafficHistory()
        ProcessTrafficStorage.shared.clearAllRecords()
    }

    private func makeDailyTrafficMenuItem() -> NSMenuItem {
        let hostingView = NSHostingView(
            rootView: LocalizedRootView { DailyTrafficView() }
                .environmentObject(LocalizationManager.shared)
        )
        hostingView.layoutSubtreeIfNeeded()
        var size = hostingView.fittingSize
        size.height += 36
        hostingView.frame = NSRect(origin: .zero, size: size)

        let item = NSMenuItem()
        item.view = hostingView
        return item
    }

    @objc private func openSettings() {
        LogManager.shared.log("Open settings window")
        SettingsWindowController.shared.show()
    }

    @objc private func openAbout() {
        LogManager.shared.log("Open about window")
        AboutWindowController.shared.show()
    }

    @objc private func checkForUpdates() {
        LogManager.shared.log("Check for updates from status bar")
        if updateManager.performCachedUpdateAction() {
            refreshUpdateMenuItem()
            return
        }
        updateManager.checkForUpdates(userInitiated: true)
        refreshUpdateMenuItem()
    }

    @objc private func quitApp() {
        LogManager.shared.log("Quit requested from status bar")
        let alert = NSAlert()
        alert.messageText = LocalizationManager.shared.t("quit.confirm.title")
        alert.informativeText = LocalizationManager.shared.t("quit.confirm.message")
        alert.alertStyle = .warning
        alert.addButton(withTitle: LocalizationManager.shared.t("common.cancel"))
        alert.addButton(withTitle: LocalizationManager.shared.t("common.quit"))

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            NSApplication.shared.terminate(nil)
        }
    }

    private func scheduleAutomaticUpdateCheck() {
        updateManager.startAutomaticUpdateChecks()
    }

    private func refreshUpdateMenuItem() {
        guard let updateMenuItem else { return }
        let title = updateMenuTitle(for: updateManager.status)
        updateMenuItem.attributedTitle = nil
        updateMenuItem.title = title
        updateMenuItem.isEnabled = updateManager.canCheckForUpdates
            && updateManager.status != .checking
            && updateManager.status != .updating

        if case .updateAvailable = updateManager.status {
            applyUpdateMenuHighlight(to: updateMenuItem, title: title)
        } else if updateManager.cachedLatestVersion != nil {
            applyUpdateMenuHighlight(to: updateMenuItem, title: title)
        }
    }

    private func applyUpdateMenuHighlight(to updateMenuItem: NSMenuItem, title: String) {
        let baseFont = NSFont.menuFont(ofSize: 0)
        let boldFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.labelColor,
            .font: boldFont
            ]
            updateMenuItem.attributedTitle = NSAttributedString(string: title, attributes: attributes)
    }

    private func updateMenuTitle(for status: UpdateManager.UpdateStatus) -> String {
        if case .checking = status {
            return LocalizationManager.shared.t("menu.checkingUpdate")
        }
        if case .updating = status {
            return LocalizationManager.shared.t("menu.updating")
        }
        if let version = resolvedCachedVersion(for: status) {
            return String(format: LocalizationManager.shared.t("menu.updateAvailable"), version)
        }
        switch status {
        case .idle:
            return LocalizationManager.shared.t("menu.checkUpdate")
        case .upToDate:
            return LocalizationManager.shared.t("menu.upToDate")
        case .failed:
            return LocalizationManager.shared.t("menu.updateFailed")
        case .updateAvailable(let version):
            return String(format: LocalizationManager.shared.t("menu.updateAvailable"), version)
        case .checking, .updating:
            return LocalizationManager.shared.t("menu.checkUpdate")
        }
    }

    private func resolvedCachedVersion(for status: UpdateManager.UpdateStatus) -> String? {
        if case .updateAvailable(let version) = status {
            return version
        }
        return updateManager.cachedLatestVersion
    }
    
    @objc private func openPerAppDetail() {
        LogManager.shared.log("Open per-app traffic detail window")
        PerAppTrafficDetailWindowController.shared.show()
    }

    private func rebuildMenu() {
        let newMenu = NSMenu()
        newMenu.addItem(makeDailyTrafficMenuItem())
        newMenu.addItem(.separator())
        if processMonitor.isEnabled {
            let perAppItem = NSMenuItem(title: LocalizationManager.shared.t("menu.perAppTraffic"), action: #selector(openPerAppDetail), keyEquivalent: "")
            perAppItem.target = self
            newMenu.addItem(perAppItem)
            newMenu.addItem(.separator())
        }
        let settingsItem = NSMenuItem(title: LocalizationManager.shared.t("menu.settings"), action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.target = self
        newMenu.addItem(settingsItem)
        let checkUpdateItem = NSMenuItem(title: LocalizationManager.shared.t("menu.checkUpdate"), action: #selector(checkForUpdates), keyEquivalent: "")
        checkUpdateItem.target = self
        updateMenuItem = checkUpdateItem
        newMenu.addItem(checkUpdateItem)
        let aboutItem = NSMenuItem(title: LocalizationManager.shared.t("menu.about"), action: #selector(openAbout), keyEquivalent: "")
        aboutItem.target = self
        newMenu.addItem(aboutItem)
        newMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: LocalizationManager.shared.t("menu.quit"), action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        newMenu.addItem(quitItem)
        menu = newMenu
        statusItem.menu = menu
        refreshUpdateMenuItem()
    }

    deinit {
        let defaults = UserDefaults.standard
        let keys = [displayModeKey, maxColorRateKey, colorRatePercentKey, smoothTransitionKey]
        for key in keys {
            defaults.removeObserver(self, forKeyPath: key)
        }
    }
}
