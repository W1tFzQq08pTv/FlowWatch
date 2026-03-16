import SwiftUI
import AppKit
import Combine
import QuartzCore

@MainActor
final class StatusBarController: NSObject, ObservableObject, NSMenuDelegate {
    private let displayModeKey = "statusBarDisplayMode"
    private let maxColorRateKey = "maxColorRateMbps"
    private let colorRatePercentKey = "colorRatePercent"
    private let smoothTransitionKey = "statusBarSmoothTransition"
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

    // 插值动画状态
    private var displayedDownloadBps: Double = 0
    private var displayedUploadBps: Double = 0
    private var displayedTodayDownloaded: Double = 0
    private var displayedTodayUploaded: Double = 0
    private var startDownloadBps: Double = 0
    private var startUploadBps: Double = 0
    private var startTodayDownloaded: Double = 0
    private var startTodayUploaded: Double = 0
    private var targetDownloadBps: Double = 0
    private var targetUploadBps: Double = 0
    private var targetTodayDownloaded: Double = 0
    private var targetTodayUploaded: Double = 0
    private var lastRenderedKey: String = ""
    private var animationTimer: DispatchSourceTimer?
    private var animationStartTime: CFTimeInterval = 0
    private var animationDuration: CFTimeInterval {
        monitor.sampleInterval
    }

    private var smoothTransitionEnabled: Bool {
        if UserDefaults.standard.object(forKey: smoothTransitionKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: smoothTransitionKey)
    }

    private let cachedWhite = NSColor.white.usingColorSpace(.sRGB) ?? .white
    private let cachedYellow = NSColor.systemYellow.usingColorSpace(.sRGB) ?? .systemYellow
    private let cachedRed = NSColor.systemRed.usingColorSpace(.sRGB) ?? .systemRed

    private let cachedBadgeFont = NSFont.monospacedSystemFont(ofSize: 6.5, weight: .semibold)
    private let cachedFallbackFont = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
    private let cachedParagraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineSpacing = -3
        return style.copy() as! NSParagraphStyle
    }()

    private var dailyTrafficMenuItem: NSMenuItem?
    private var isShowingQuitConfirmation = false

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
        menu.delegate = self
        button.imagePosition = .imageOnly
        button.focusRingType = .none
    }

    private func bindMonitor() {
        Publishers.CombineLatest4(monitor.$downloadBps, monitor.$uploadBps,
                                  monitor.$todayDownloaded, monitor.$todayUploaded)
            .throttle(for: .milliseconds(100), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] down, up, todayDown, todayUp in
                guard let self else { return }
                let todayDownD = Double(todayDown)
                let todayUpD = Double(todayUp)
                if self.smoothTransitionEnabled {
                    self.startAnimation(targetDown: down, targetUp: up,
                                        targetTodayDown: todayDownD, targetTodayUp: todayUpD)
                } else {
                    self.displayedDownloadBps = down
                    self.displayedUploadBps = up
                    self.displayedTodayDownloaded = todayDownD
                    self.displayedTodayUploaded = todayUpD
                    self.stopAnimation()
                    self.updateStatusButtonContent()
                }
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
                self?.dailyTrafficMenuItem = nil
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

        NotificationCenter.default.publisher(for: .flowWatchSampleIntervalChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let interval = UserDefaults.standard.double(forKey: "statusBar.sampleInterval")
                self.monitor.updateInterval(to: interval)
            }
            .store(in: &cancellables)
    }

    private func bindProcessMonitor() {
        processMonitor.$isEnabled
            .removeDuplicates()
            .dropFirst()
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

    /// 颜色量化步长（256 KB/s），对应 100 Mbps 上限约 50 级可辨色阶
    private let colorQuantStep: Double = 256_000

    private func currentRenderKey() -> String {
        let downSpeed = monitor.fixedWidthCompactSpeed(displayedDownloadBps)
        let upSpeed = monitor.fixedWidthCompactSpeed(displayedUploadBps)
        let downTotal = monitor.fixedWidthDataAmount(UInt64(displayedTodayDownloaded))
        let upTotal = monitor.fixedWidthDataAmount(UInt64(displayedTodayUploaded))
        let downColor = Int(displayedDownloadBps / colorQuantStep)
        let upColor = Int(displayedUploadBps / colorQuantStep)
        return "\(displayMode.rawValue)|\(downSpeed)|\(upSpeed)|\(downTotal)|\(upTotal)|\(downColor)|\(upColor)"
    }

    private func updateStatusButtonContent() {
        let key = currentRenderKey()
        if animationTimer != nil && key == lastRenderedKey { return }
        lastRenderedKey = key

        guard let button = statusItem.button else { return }

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
            return cachedWhite
        }
        let ratio = max(0, min(mbps / maxRate, 1))

        if ratio < 0.5 {
            return interpolateColor(from: cachedWhite, to: cachedYellow, t: ratio / 0.5)
        } else {
            return interpolateColor(from: cachedYellow, to: cachedRed, t: (ratio - 0.5) / 0.5)
        }
    }

    private func interpolateColor(from start: NSColor, to end: NSColor, t: Double) -> NSColor {
        let clampedT = CGFloat(max(0, min(1, t)))

        let red = start.redComponent + (end.redComponent - start.redComponent) * clampedT
        let green = start.greenComponent + (end.greenComponent - start.greenComponent) * clampedT
        let blue = start.blueComponent + (end.blueComponent - start.blueComponent) * clampedT
        let alpha = start.alphaComponent + (end.alphaComponent - start.alphaComponent) * clampedT

        return NSColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    private func makeSpeedBadgeImage() -> NSImage? {
        let up = monitor.fixedWidthCompactSpeed(displayedUploadBps)
        let down = monitor.fixedWidthCompactSpeed(displayedDownloadBps)
        let upLine = "\(up)↑"
        let downLine = "\(down)↓"
        let text = "\(upLine)\n\(downLine)"

        let attributes: [NSAttributedString.Key: Any] = [
            .font: cachedBadgeFont,
            .paragraphStyle: cachedParagraphStyle
        ]

        let attr = NSMutableAttributedString(string: text, attributes: attributes)
        let upLength = (upLine as NSString).length
        let downLength = (downLine as NSString).length
        attr.addAttribute(.foregroundColor, value: colorForSpeed(displayedUploadBps), range: NSRange(location: 0, length: upLength))
        attr.addAttribute(.foregroundColor, value: colorForSpeed(displayedDownloadBps), range: NSRange(location: upLength + 1, length: downLength))

        let size = attr.size()
        let canvasSize = NSSize(width: max(42, size.width), height: max(13, size.height))
        return NSImage(size: canvasSize, flipped: false) { _ in
            attr.draw(at: NSPoint(
                x: (canvasSize.width - size.width) / 2,
                y: (canvasSize.height - size.height) / 2
            ))
            return true
        }
    }

    private func makeTotalBadgeImage() -> NSImage? {
        let up = monitor.fixedWidthDataAmount(UInt64(displayedTodayUploaded))
        let down = monitor.fixedWidthDataAmount(UInt64(displayedTodayDownloaded))
        let upLine = "\(up)↑"
        let downLine = "\(down)↓"
        let text = "\(upLine)\n\(downLine)"

        let attributes: [NSAttributedString.Key: Any] = [
            .font: cachedBadgeFont,
            .paragraphStyle: cachedParagraphStyle,
            .foregroundColor: NSColor.white
        ]

        let attr = NSMutableAttributedString(string: text, attributes: attributes)
        let upLength = (upLine as NSString).length
        let downLength = (downLine as NSString).length
        attr.addAttribute(.foregroundColor, value: colorForSpeed(displayedUploadBps), range: NSRange(location: 0, length: upLength))
        attr.addAttribute(.foregroundColor, value: colorForSpeed(displayedDownloadBps), range: NSRange(location: upLength + 1, length: downLength))
        let size = attr.size()
        let canvasSize = NSSize(width: max(46, size.width), height: max(14, size.height))
        return NSImage(size: canvasSize, flipped: false) { _ in
            attr.draw(at: NSPoint(
                x: (canvasSize.width - size.width) / 2,
                y: (canvasSize.height - size.height) / 2
            ))
            return true
        }
    }

    private func makeCombinedBadgeImage() -> NSImage? {
        let totalsUp = monitor.fixedWidthDataAmount(UInt64(displayedTodayUploaded)) + "↑"
        let totalsDown = monitor.fixedWidthDataAmount(UInt64(displayedTodayDownloaded)) + "↓"
        let speedUp = monitor.fixedWidthCompactSpeed(displayedUploadBps) + "↑"
        let speedDown = monitor.fixedWidthCompactSpeed(displayedDownloadBps) + "↓"

        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: cachedBadgeFont,
            .paragraphStyle: cachedParagraphStyle
        ]

        let totalsText = "\(totalsUp)\n\(totalsDown)"
        let totalsAttr = NSMutableAttributedString(string: totalsText, attributes: baseAttrs)
        let totalsUpLength = (totalsUp as NSString).length
        totalsAttr.addAttribute(.foregroundColor, value: colorForSpeed(displayedUploadBps), range: NSRange(location: 0, length: totalsUpLength))
        totalsAttr.addAttribute(.foregroundColor, value: colorForSpeed(displayedDownloadBps), range: NSRange(location: totalsUpLength + 1, length: (totalsDown as NSString).length))

        let speedText = "\(speedUp)\n\(speedDown)"
        let speedAttr = NSMutableAttributedString(string: speedText, attributes: baseAttrs)
        let upLength = (speedUp as NSString).length
        speedAttr.addAttribute(.foregroundColor, value: colorForSpeed(displayedUploadBps), range: NSRange(location: 0, length: upLength))
        speedAttr.addAttribute(.foregroundColor, value: colorForSpeed(displayedDownloadBps), range: NSRange(location: upLength + 1, length: (speedDown as NSString).length))

        let spacer: CGFloat = 6
        let totalSize = totalsAttr.size()
        let speedSize = speedAttr.size()
        let canvasSize = NSSize(width: max(52, totalSize.width) + spacer + max(52, speedSize.width),
                                height: max(max(14, totalSize.height), max(14, speedSize.height)))
        return NSImage(size: canvasSize, flipped: false) { _ in
            totalsAttr.draw(at: NSPoint(
                x: 0,
                y: (canvasSize.height - totalSize.height) / 2
            ))
            speedAttr.draw(at: NSPoint(
                x: max(52, totalSize.width) + spacer,
                y: (canvasSize.height - speedSize.height) / 2
            ))
            return true
        }
    }

    private func renderSpeedOnly(into button: NSStatusBarButton) {
        if let image = makeSpeedBadgeImage() {
            button.image = image
            button.title = ""
        } else {
            let down = monitor.fixedWidthCompactSpeed(displayedDownloadBps)
            let up = monitor.fixedWidthCompactSpeed(displayedUploadBps)
            let upLine = "\(up)↑"
            let downLine = "\(down)↓"
            let text = upLine + " " + downLine
            let attributes: [NSAttributedString.Key: Any] = [
                .font: cachedFallbackFont
            ]
            let attr = NSMutableAttributedString(string: text, attributes: attributes)
            let upLength = (upLine as NSString).length
            let downLength = (downLine as NSString).length
            attr.addAttribute(.foregroundColor, value: colorForSpeed(displayedUploadBps), range: NSRange(location: 0, length: upLength))
            attr.addAttribute(.foregroundColor, value: colorForSpeed(displayedDownloadBps), range: NSRange(location: upLength + 1, length: downLength))
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
        DispatchQueue.main.async {
            SettingsWindowController.shared.show()
        }
    }

    @objc private func openAbout() {
        LogManager.shared.log("Open about window")
        DispatchQueue.main.async {
            AboutWindowController.shared.show()
        }
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
        DispatchQueue.main.async { [weak self] in
            self?.presentQuitConfirmationIfNeeded()
        }
    }

    private func presentQuitConfirmationIfNeeded() {
        guard !isShowingQuitConfirmation else { return }
        isShowingQuitConfirmation = true

        let alert = NSAlert()
        alert.messageText = LocalizationManager.shared.t("quit.confirm.title")
        alert.informativeText = LocalizationManager.shared.t("quit.confirm.message")
        alert.alertStyle = .warning
        alert.addButton(withTitle: LocalizationManager.shared.t("common.cancel"))
        alert.addButton(withTitle: LocalizationManager.shared.t("common.quit"))

        // 状态栏菜单触发退出时使用独立 modal alert，避免挂到某个窗口的 sheet 后
        // 造成窗口无法关闭、确认框不可见的情况。
        NSApp.activate(ignoringOtherApps: true)
        LogManager.shared.log("Present quit confirmation alert")

        let response = alert.runModal()
        isShowingQuitConfirmation = false
        LogManager.shared.log("Quit confirmation response: \(response.rawValue)")

        if response == .alertSecondButtonReturn {
            LogManager.shared.log("Quit confirmed, terminating app")
            NSApplication.shared.terminate(nil)
        } else {
            LogManager.shared.log("Quit cancelled")
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
        DispatchQueue.main.async {
            PerAppTrafficDetailWindowController.shared.show()
        }
    }

    private func startAnimation(targetDown: Double, targetUp: Double,
                                targetTodayDown: Double, targetTodayUp: Double) {
        startDownloadBps = displayedDownloadBps
        startUploadBps = displayedUploadBps
        startTodayDownloaded = displayedTodayDownloaded
        startTodayUploaded = displayedTodayUploaded
        targetDownloadBps = targetDown
        targetUploadBps = targetUp
        targetTodayDownloaded = targetTodayDown
        targetTodayUploaded = targetTodayUp

        let noChange = startDownloadBps == targetDown && startUploadBps == targetUp
            && startTodayDownloaded == targetTodayDown && startTodayUploaded == targetTodayUp
        if noChange {
            updateStatusButtonContent()
            return
        }

        animationStartTime = CACurrentMediaTime()

        guard animationTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            self?.animationTick()
        }
        timer.resume()
        animationTimer = timer
    }

    private func animationTick() {
        let elapsed = CACurrentMediaTime() - animationStartTime
        let progress = min(elapsed / animationDuration, 1.0)
        let eased = easeOutCubic(progress)

        displayedDownloadBps = startDownloadBps + (targetDownloadBps - startDownloadBps) * eased
        displayedUploadBps = startUploadBps + (targetUploadBps - startUploadBps) * eased
        displayedTodayDownloaded = startTodayDownloaded + (targetTodayDownloaded - startTodayDownloaded) * eased
        displayedTodayUploaded = startTodayUploaded + (targetTodayUploaded - startTodayUploaded) * eased

        updateStatusButtonContent()

        if progress >= 1.0 {
            stopAnimation()
        } else if currentRenderKey() == targetRenderKey() {
            // 格式化输出已收敛到目标值，提前终止动画
            displayedDownloadBps = targetDownloadBps
            displayedUploadBps = targetUploadBps
            displayedTodayDownloaded = targetTodayDownloaded
            displayedTodayUploaded = targetTodayUploaded
            stopAnimation()
        }
    }

    private func targetRenderKey() -> String {
        let downSpeed = monitor.fixedWidthCompactSpeed(targetDownloadBps)
        let upSpeed = monitor.fixedWidthCompactSpeed(targetUploadBps)
        let downTotal = monitor.fixedWidthDataAmount(UInt64(targetTodayDownloaded))
        let upTotal = monitor.fixedWidthDataAmount(UInt64(targetTodayUploaded))
        let downColor = Int(targetDownloadBps / colorQuantStep)
        let upColor = Int(targetUploadBps / colorQuantStep)
        return "\(displayMode.rawValue)|\(downSpeed)|\(upSpeed)|\(downTotal)|\(upTotal)|\(downColor)|\(upColor)"
    }

    private func stopAnimation() {
        animationTimer?.cancel()
        animationTimer = nil
    }

    private func easeOutCubic(_ t: Double) -> Double {
        1 - pow(1 - t, 3)
    }

    private func rebuildMenu() {
        let newMenu = NSMenu()
        if let existing = dailyTrafficMenuItem, menu.index(of: existing) != -1 {
            menu.removeItem(existing)
            newMenu.addItem(existing)
        } else {
            let item = makeDailyTrafficMenuItem()
            dailyTrafficMenuItem = item
            newMenu.addItem(item)
        }
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
        menu.delegate = self
        statusItem.menu = menu
        refreshUpdateMenuItem()
    }

    // MARK: - NSMenuDelegate

    nonisolated func menuWillOpen(_ menu: NSMenu) {
        NotificationCenter.default.post(name: .flowWatchMenuWillOpen, object: nil)
    }

    nonisolated func menuDidClose(_ menu: NSMenu) {
        NotificationCenter.default.post(name: .flowWatchMenuDidClose, object: nil)
    }

    deinit {
        let defaults = UserDefaults.standard
        let keys = [displayModeKey, maxColorRateKey, colorRatePercentKey, smoothTransitionKey]
        for key in keys {
            defaults.removeObserver(self, forKeyPath: key)
        }
    }
}
