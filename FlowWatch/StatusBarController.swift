import SwiftUI
import AppKit
import Combine
import QuartzCore

@MainActor
final class StatusBarController: NSObject, ObservableObject {
    private let displayModeKey = "statusBarDisplayMode"
    private let maxColorRateKey = "maxColorRateMbps"
    private let colorRatePercentKey = "colorRatePercent"
    private let coloringEnabledKey = "statusBarColoringEnabled"
    private let smoothTransitionKey = "statusBarSmoothTransition"
    private let minimalSignalShowsTrafficTotalsKey = "minimalSignalShowsTrafficTotals"
    private let minimalSignalBlinkSpeedPercentKey = "minimalSignalBlinkSpeedPercent"
    private let mathCurveLoaderSelectionKey = "mathCurveLoaderSelection"
    private let mathCurveLoaderRandomSwitchIntervalMinutesKey = "mathCurveLoaderRandomSwitchIntervalMinutes"
    private let monitor: NetworkUsageMonitor
    private let processMonitor: ProcessNetworkMonitor
    private let statusItem: NSStatusItem
    private let updateManager = UpdateManager.shared
    private var dynamicIconView: NSView?
    private weak var updateMenuItem: NSMenuItem?
    private var maxColorRateMbps: Double {
        get {
            cachedMaxColorRateMbps
        }
        set {
            let clamped = max(0, newValue)
            cachedMaxColorRateMbps = clamped
            UserDefaults.standard.set(clamped, forKey: maxColorRateKey)
            updateStatusButtonContent()
        }
    }
    private var colorRatePercent: Double {
        get {
            cachedColorRatePercent
        }
        set {
            let clamped = max(0, min(newValue, 100))
            cachedColorRatePercent = clamped
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
    private var statusAnimationTimer: DispatchSourceTimer?
    private var statusAnimationTimerIntervalMilliseconds: Int?
    private var downloadBlinkPeriod: CFTimeInterval?
    private var uploadBlinkPeriod: CFTimeInterval?

    private struct CurveLoaderTransitionSnapshot {
        let preset: DynamicGraphicPreset
        let animationTimeMilliseconds: Double
        let phaseOffset: Double
        let startedAt: CFTimeInterval
    }

    private var activeCurveLoaderPreset: DynamicGraphicPreset?
    private var curveLoaderAnimationTimeMilliseconds: Double = 0
    private var curveLoaderLastFrameTime: CFTimeInterval?
    private var curveLoaderPhaseOffset: Double = Double.random(in: 0...1)
    private var curveLoaderSmoothedSpeedMultiplier: Double = 1
    private var curveLoaderNextSwitchTime: CFTimeInterval = 0
    private var curveLoaderTransitionSnapshot: CurveLoaderTransitionSnapshot?
    private var lastCurveLoaderSelectionRaw: String?
    private let minimalSignalBlinkMinimumMbps: Double = 0.03
    private let minimalSignalBlinkRelaxedMaximumMbps: Double = 20
    private let minimalSignalBlinkSensitiveMaximumMbps: Double = 8
    private let minimalSignalBlinkSlowestPeriod: CFTimeInterval = 1.05
    private let minimalSignalBlinkRelaxedFastestPeriod: CFTimeInterval = 0.55
    private let minimalSignalBlinkSensitiveFastestPeriod: CFTimeInterval = 0.22
    private let minimalSignalRedrawIntervalMilliseconds = 100
    private let curveLoaderRedrawIntervalMilliseconds = 100
    private let curveLoaderTransitionRedrawIntervalMilliseconds = 67
    private let curveLoaderPresetTransitionDuration: CFTimeInterval = 0.65
    private let curveLoaderImageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 240
        return cache
    }()
    private var cachedDisplayMode: FlowWatchApp.StatusBarDisplayMode = .speed
    private var cachedMaxColorRateMbps: Double = 100
    private var cachedColorRatePercent: Double = 100
    private var cachedColoringEnabled = true
    private var cachedSmoothTransitionEnabled = true
    private var cachedMinimalSignalShowsTrafficTotals = true
    private var cachedMinimalSignalBlinkSpeedPercent: Double = 50
    private var cachedMathCurveLoaderSelection: MathCurveLoaderSelection = .random
    private var cachedCurveLoaderRandomSwitchIntervalSeconds: CFTimeInterval = 10 * 60

    private var smoothTransitionEnabled: Bool {
        cachedSmoothTransitionEnabled
    }

    private var minimalSignalShowsTrafficTotals: Bool {
        cachedMinimalSignalShowsTrafficTotals
    }

    private var minimalSignalBlinkSpeedPercent: Double {
        cachedMinimalSignalBlinkSpeedPercent
    }

    private var mathCurveLoaderSelection: MathCurveLoaderSelection {
        cachedMathCurveLoaderSelection
    }

    private var curveLoaderRandomSwitchIntervalSeconds: CFTimeInterval {
        cachedCurveLoaderRandomSwitchIntervalSeconds
    }

    private var isColoringEnabled: Bool {
        cachedColoringEnabled
    }

    private let cachedWhite = NSColor.white.usingColorSpace(.sRGB) ?? .white
    private let cachedGreen = NSColor.systemGreen.usingColorSpace(.sRGB) ?? .systemGreen
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

    private var isShowingQuitConfirmation = false

    private var cancellables = Set<AnyCancellable>()
    private var menu: NSMenu = NSMenu()

    init(monitor: NetworkUsageMonitor, processMonitor: ProcessNetworkMonitor) {
        self.monitor = monitor
        self.processMonitor = processMonitor
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.isVisible = true
        super.init()
        refreshCachedPreferences()
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
        Publishers.CombineLatest4(monitor.$downloadBps, monitor.$uploadBps,
                                  monitor.$todayDownloaded, monitor.$todayUploaded)
            .throttle(for: .milliseconds(100), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] down, up, todayDown, todayUp in
                guard let self else { return }
                let todayDownD = Double(todayDown)
                let todayUpD = Double(todayUp)
                self.updateMinimalSignalBlinkPeriods(downloadBps: down, uploadBps: up)
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
        let keys = [
            displayModeKey,
            maxColorRateKey,
            colorRatePercentKey,
            coloringEnabledKey,
            smoothTransitionKey,
            minimalSignalShowsTrafficTotalsKey,
            minimalSignalBlinkSpeedPercentKey,
            mathCurveLoaderSelectionKey,
            mathCurveLoaderRandomSwitchIntervalMinutesKey
        ]
        for key in keys {
            defaults.addObserver(self, forKeyPath: key, options: [.new, .old], context: nil)
        }
    }

    private func refreshCachedPreferences() {
        let defaults = UserDefaults.standard

        if let stored = defaults.string(forKey: displayModeKey),
           let mode = FlowWatchApp.StatusBarDisplayMode(rawValue: stored) {
            cachedDisplayMode = mode
        } else {
            cachedDisplayMode = .speed
        }

        cachedMaxColorRateMbps = max(0, defaults.object(forKey: maxColorRateKey) as? Double ?? 100)

        if defaults.object(forKey: colorRatePercentKey) == nil {
            cachedColorRatePercent = 100
        } else {
            cachedColorRatePercent = max(0, min(defaults.double(forKey: colorRatePercentKey), 100))
        }

        if defaults.object(forKey: coloringEnabledKey) == nil {
            cachedColoringEnabled = true
        } else {
            cachedColoringEnabled = defaults.bool(forKey: coloringEnabledKey)
        }

        if defaults.object(forKey: smoothTransitionKey) == nil {
            cachedSmoothTransitionEnabled = true
        } else {
            cachedSmoothTransitionEnabled = defaults.bool(forKey: smoothTransitionKey)
        }

        if defaults.object(forKey: minimalSignalShowsTrafficTotalsKey) == nil {
            cachedMinimalSignalShowsTrafficTotals = true
        } else {
            cachedMinimalSignalShowsTrafficTotals = defaults.bool(forKey: minimalSignalShowsTrafficTotalsKey)
        }

        if defaults.object(forKey: minimalSignalBlinkSpeedPercentKey) == nil {
            cachedMinimalSignalBlinkSpeedPercent = 50
        } else {
            cachedMinimalSignalBlinkSpeedPercent = max(
                0,
                min(defaults.double(forKey: minimalSignalBlinkSpeedPercentKey), 100)
            )
        }

        if let stored = defaults.string(forKey: mathCurveLoaderSelectionKey),
           let selection = MathCurveLoaderSelection(rawValue: stored) {
            cachedMathCurveLoaderSelection = selection
        } else {
            cachedMathCurveLoaderSelection = .random
        }

        if defaults.object(forKey: mathCurveLoaderRandomSwitchIntervalMinutesKey) == nil {
            cachedCurveLoaderRandomSwitchIntervalSeconds = 10 * 60
        } else {
            let minutes = defaults.double(forKey: mathCurveLoaderRandomSwitchIntervalMinutesKey)
            cachedCurveLoaderRandomSwitchIntervalSeconds = max(1, min(minutes, 60)) * 60
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
        let watchedKeys = [
            displayModeKey,
            maxColorRateKey,
            colorRatePercentKey,
            coloringEnabledKey,
            smoothTransitionKey,
            minimalSignalShowsTrafficTotalsKey,
            minimalSignalBlinkSpeedPercentKey,
            mathCurveLoaderSelectionKey,
            mathCurveLoaderRandomSwitchIntervalMinutesKey
        ]
        guard watchedKeys.contains(keyPath) else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.refreshCachedPreferences()
            if [
                self.displayModeKey,
                self.maxColorRateKey,
                self.colorRatePercentKey,
                self.coloringEnabledKey,
                self.mathCurveLoaderSelectionKey
            ].contains(keyPath) {
                self.curveLoaderImageCache.removeAllObjects()
                self.lastRenderedKey = ""
            }
            if keyPath == self.mathCurveLoaderRandomSwitchIntervalMinutesKey {
                self.curveLoaderNextSwitchTime = CACurrentMediaTime() + self.curveLoaderRandomSwitchIntervalSeconds
            }
            self.updateStatusButtonContent()
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
                self?.updateManager.startAutomaticUpdateChecks()
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

        NotificationCenter.default.publisher(for: .flowWatchStatusBarColoringChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.refreshCachedPreferences()
                self.curveLoaderImageCache.removeAllObjects()
                self.lastRenderedKey = ""
                self.updateStatusButtonContent()
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
        Publishers.CombineLatest(updateManager.$status, updateManager.$canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshUpdateMenuItem()
            }
            .store(in: &cancellables)
    }

    /// 颜色量化步长（256 KB/s），对应 100 Mbps 上限约 50 级可辨色阶
    private let colorQuantStep: Double = 256_000

    private func currentRenderKey() -> String {
        if displayMode == .minimalSignal {
            return minimalSignalRenderKey(
                downloadBps: displayedDownloadBps,
                uploadBps: displayedUploadBps,
                todayDownloaded: displayedTodayDownloaded,
                todayUploaded: displayedTodayUploaded
            )
        }
        if displayMode == .curveLoader {
            return curveLoaderRenderKey(
                downloadBps: displayedDownloadBps,
                uploadBps: displayedUploadBps,
                todayDownloaded: displayedTodayDownloaded,
                todayUploaded: displayedTodayUploaded
            )
        }
        let downSpeed = monitor.fixedWidthCompactSpeed(displayedDownloadBps)
        let upSpeed = monitor.fixedWidthCompactSpeed(displayedUploadBps)
        let downTotal = monitor.fixedWidthDataAmount(UInt64(displayedTodayDownloaded))
        let upTotal = monitor.fixedWidthDataAmount(UInt64(displayedTodayUploaded))
        let downColor = Int(displayedDownloadBps / colorQuantStep)
        let upColor = Int(displayedUploadBps / colorQuantStep)
        return "\(displayMode.rawValue)|\(downSpeed)|\(upSpeed)|\(downTotal)|\(upTotal)|\(downColor)|\(upColor)"
    }

    private func updateStatusButtonContent() {
        syncStatusAnimationTimer()
        let key = currentRenderKey()
        if animationTimer != nil && key == lastRenderedKey { return }
        if isDynamicStatusMode && key == lastRenderedKey { return }
        lastRenderedKey = key

        guard let button = statusItem.button else { return }
        let desiredLength: CGFloat = isDynamicStatusMode && !minimalSignalShowsTrafficTotals
            ? 20
            : NSStatusItem.variableLength
        if statusItem.length != desiredLength {
            statusItem.length = desiredLength
        }

        switch displayMode {
        case .speed:
            renderSpeedOnly(into: button)
        case .total:
            renderTotalOnly(into: button)
        case .both:
            renderCombined(into: button)
        case .minimalSignal:
            renderMinimalSignal(into: button)
        case .curveLoader:
            renderCurveLoader(into: button)
        }
    }

    private var isDynamicStatusMode: Bool {
        displayMode == .minimalSignal || displayMode == .curveLoader
    }

    private func colorForSpeed(_ bytesPerSecond: Double) -> NSColor {
        guard isColoringEnabled else {
            return cachedWhite
        }
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

    private func colorForMinimalSignalSpeed(_ bytesPerSecond: Double) -> NSColor {
        guard isColoringEnabled else {
            return cachedWhite
        }
        let ratio = speedColorRatio(bytesPerSecond)
        if ratio < 0.5 {
            return interpolateColor(from: cachedGreen, to: cachedYellow, t: ratio / 0.5)
        } else {
            return interpolateColor(from: cachedYellow, to: cachedRed, t: (ratio - 0.5) / 0.5)
        }
    }

    private func speedColorRatio(_ bytesPerSecond: Double) -> Double {
        let mbps = max(0, bytesPerSecond) * 8 / 1_000_000
        let percent = max(0, min(colorRatePercent, 100))
        let maxRate = max(0, maxColorRateMbps) * percent / 100
        guard maxRate > 0 else {
            return 0
        }
        return max(0, min(mbps / maxRate, 1))
    }

    private func minimalSignalColorBucket(_ bytesPerSecond: Double) -> Int {
        Int((speedColorRatio(bytesPerSecond) * 20).rounded())
    }

    private func minimalSignalRenderKey(downloadBps: Double, uploadBps: Double, todayDownloaded: Double, todayUploaded: Double) -> String {
        let downColor = minimalSignalColorBucket(downloadBps)
        let upColor = minimalSignalColorBucket(uploadBps)
        let downAlpha = Int((blinkAlpha(for: downloadBlinkPeriod) * 20).rounded())
        let upAlpha = Int((blinkAlpha(for: uploadBlinkPeriod) * 20).rounded())
        let showsTotals = minimalSignalShowsTrafficTotals
        if showsTotals {
            let totals = minimalSignalDataAmountParts(
                uploadBytes: UInt64(todayUploaded),
                downloadBytes: UInt64(todayDownloaded)
            )
            let upTotal = "\(totals.up.value) \(totals.up.unit)"
            let downTotal = "\(totals.down.value) \(totals.down.unit)"
            return "\(displayMode.rawValue)|totals|\(upTotal)|\(downTotal)|\(downColor)|\(upColor)|\(downAlpha)|\(upAlpha)"
        }
        return "\(displayMode.rawValue)|dots|\(downColor)|\(upColor)|\(downAlpha)|\(upAlpha)"
    }

    private func curveLoaderRenderKey(downloadBps: Double, uploadBps: Double, todayDownloaded: Double, todayUploaded: Double) -> String {
        let now = CACurrentMediaTime()
        let preset = currentCurveLoaderPreset(at: now)
        let frame = Int((now * 1_000 / Double(currentStatusAnimationRedrawIntervalMilliseconds)).rounded(.down))
        let color = minimalSignalColorBucket(max(downloadBps, uploadBps))
        let speedBucket = Int((curveLoaderSpeedMultiplier(forSpeedBytesPerSecond: max(downloadBps, uploadBps)) * 20).rounded())
        let showsTotals = minimalSignalShowsTrafficTotals
        if showsTotals {
            let totals = minimalSignalDataAmountParts(
                uploadBytes: UInt64(todayUploaded),
                downloadBytes: UInt64(todayDownloaded)
            )
            let upTotal = "\(totals.up.value) \(totals.up.unit)"
            let downTotal = "\(totals.down.value) \(totals.down.unit)"
            return "\(displayMode.rawValue)|\(preset.rawValue)|\(frame)|\(color)|\(speedBucket)|totals|\(upTotal)|\(downTotal)"
        }
        return "\(displayMode.rawValue)|\(preset.rawValue)|\(frame)|\(color)|icon"
    }

    private func updateMinimalSignalBlinkPeriods(downloadBps: Double, uploadBps: Double) {
        downloadBlinkPeriod = blinkPeriod(forSpeedBytesPerSecond: downloadBps)
        uploadBlinkPeriod = blinkPeriod(forSpeedBytesPerSecond: uploadBps)
    }

    private func blinkPeriod(forSpeedBytesPerSecond bytesPerSecond: Double) -> CFTimeInterval? {
        let mbps = max(0, bytesPerSecond) * 8 / 1_000_000
        guard mbps >= minimalSignalBlinkMinimumMbps else {
            return nil
        }
        let speedRatio = minimalSignalBlinkSpeedPercent / 100
        let maximumMbps = minimalSignalBlinkRelaxedMaximumMbps - ((minimalSignalBlinkRelaxedMaximumMbps - minimalSignalBlinkSensitiveMaximumMbps) * speedRatio)
        let fastestPeriod = minimalSignalBlinkRelaxedFastestPeriod - ((minimalSignalBlinkRelaxedFastestPeriod - minimalSignalBlinkSensitiveFastestPeriod) * speedRatio)
        let range = maximumMbps - minimalSignalBlinkMinimumMbps
        let ratio = max(0, min((mbps - minimalSignalBlinkMinimumMbps) / range, 1))
        let emphasizedRatio = ratio.squareRoot()
        return minimalSignalBlinkSlowestPeriod - ((minimalSignalBlinkSlowestPeriod - fastestPeriod) * emphasizedRatio)
    }

    private func blinkAlpha(for period: CFTimeInterval?) -> CGFloat {
        guard let period else {
            return 1
        }
        let position = CACurrentMediaTime().truncatingRemainder(dividingBy: period) / period
        let pulse = 0.5 + 0.5 * cos(position * 2 * .pi)
        return CGFloat(0.12 + 0.88 * pulse)
    }

    private func curveLoaderSpeedMultiplier(forSpeedBytesPerSecond bytesPerSecond: Double) -> Double {
        let mbps = max(0, bytesPerSecond) * 8 / 1_000_000
        let speedRatio = minimalSignalBlinkSpeedPercent / 100
        let maximumMbps = minimalSignalBlinkRelaxedMaximumMbps - ((minimalSignalBlinkRelaxedMaximumMbps - minimalSignalBlinkSensitiveMaximumMbps) * speedRatio)
        guard maximumMbps > minimalSignalBlinkMinimumMbps else {
            return 1
        }
        let ratio = max(0, min((mbps - minimalSignalBlinkMinimumMbps) / (maximumMbps - minimalSignalBlinkMinimumMbps), 1))
        let emphasizedRatio = ratio.squareRoot()
        return 0.45 + emphasizedRatio * 2.55
    }

    private func currentCurveLoaderPreset(at now: CFTimeInterval) -> DynamicGraphicPreset {
        let selection = mathCurveLoaderSelection
        let selectionRaw = selection.rawValue
        if selectionRaw != lastCurveLoaderSelectionRaw {
            curveLoaderNextSwitchTime = 0
            lastCurveLoaderSelectionRaw = selectionRaw
        }

        switch selection {
        case .preset(let preset):
            if activeCurveLoaderPreset != preset {
                setActiveCurveLoaderPreset(preset, at: now)
                curveLoaderNextSwitchTime = 0
            }
            return preset
        case .random:
            if activeCurveLoaderPreset == nil || now >= curveLoaderNextSwitchTime {
                let nextPreset = randomCurveLoaderPreset(excluding: activeCurveLoaderPreset)
                setActiveCurveLoaderPreset(nextPreset, at: now)
                curveLoaderNextSwitchTime = now + curveLoaderRandomSwitchIntervalSeconds
            }
            return activeCurveLoaderPreset ?? .thinkingOrb(.working)
        }
    }

    private func randomCurveLoaderPreset(excluding current: DynamicGraphicPreset?) -> DynamicGraphicPreset {
        let presets = DynamicGraphicPreset.randomCases
        guard presets.count > 1 else {
            return presets.first ?? .thinkingOrb(.working)
        }
        let candidates = presets.filter { $0 != current }
        return candidates.randomElement() ?? presets.randomElement() ?? .thinkingOrb(.working)
    }

    private func setActiveCurveLoaderPreset(_ preset: DynamicGraphicPreset, at now: CFTimeInterval) {
        if let activeCurveLoaderPreset, activeCurveLoaderPreset != preset {
            curveLoaderTransitionSnapshot = CurveLoaderTransitionSnapshot(
                preset: activeCurveLoaderPreset,
                animationTimeMilliseconds: curveLoaderAnimationTimeMilliseconds,
                phaseOffset: curveLoaderPhaseOffset,
                startedAt: now
            )
        } else {
            curveLoaderTransitionSnapshot = nil
        }
        activeCurveLoaderPreset = preset
        curveLoaderAnimationTimeMilliseconds = 0
        curveLoaderLastFrameTime = now
        curveLoaderSmoothedSpeedMultiplier = 1
        curveLoaderPhaseOffset = Double.random(in: 0...1)
        lastRenderedKey = ""
    }

    private var currentStatusAnimationRedrawIntervalMilliseconds: Int {
        guard displayMode == .curveLoader else {
            return minimalSignalRedrawIntervalMilliseconds
        }
        return curveLoaderTransitionSnapshot == nil
            ? curveLoaderRedrawIntervalMilliseconds
            : curveLoaderTransitionRedrawIntervalMilliseconds
    }

    private func syncStatusAnimationTimer() {
        guard isDynamicStatusMode else {
            stopStatusAnimationTimer()
            return
        }
        let intervalMilliseconds = currentStatusAnimationRedrawIntervalMilliseconds
        if statusAnimationTimer != nil,
           statusAnimationTimerIntervalMilliseconds == intervalMilliseconds {
            return
        }

        cancelStatusAnimationTimer(resetCurveState: false)

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(intervalMilliseconds))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if self.isDynamicStatusMode {
                self.updateStatusButtonContent()
            } else {
                self.stopStatusAnimationTimer()
            }
        }
        timer.resume()
        statusAnimationTimer = timer
        statusAnimationTimerIntervalMilliseconds = intervalMilliseconds
    }

    private func stopStatusAnimationTimer() {
        cancelStatusAnimationTimer(resetCurveState: true)
    }

    private func cancelStatusAnimationTimer(resetCurveState: Bool) {
        statusAnimationTimer?.cancel()
        statusAnimationTimer = nil
        statusAnimationTimerIntervalMilliseconds = nil
        if resetCurveState {
            curveLoaderLastFrameTime = nil
            curveLoaderTransitionSnapshot = nil
            curveLoaderImageCache.removeAllObjects()
        }
    }

    private func makeMinimalSignalImage() -> NSImage? {
        if minimalSignalShowsTrafficTotals {
            return makeMinimalSignalTotalsImage()
        }
        let canvasSize = NSSize(width: 18, height: 18)

        return NSImage(size: canvasSize, flipped: false) { _ in
            self.drawMinimalSignalDots(originX: 6)

            return true
        }
    }

    private func makeCurveLoaderImage() -> NSImage? {
        if minimalSignalShowsTrafficTotals {
            return makeCurveLoaderTotalsImage()
        }

        let now = CACurrentMediaTime()
        return makeCurveLoaderIconImage(at: now)
    }

    private func makeCurveLoaderIconImage(at now: CFTimeInterval) -> NSImage? {
        let preset = currentCurveLoaderPreset(at: now)
        let speed = max(displayedDownloadBps, displayedUploadBps)
        let animationTime = curveLoaderAnimationTime(at: now, speedBytesPerSecond: speed)
        let color = colorForSpeed(speed)
        let iconSize = NSSize(width: 18, height: 18)
        let currentImage = cachedCurveLoaderImage(
            preset: preset,
            timeMilliseconds: animationTime,
            phaseOffset: curveLoaderPhaseOffset,
            color: color,
            size: iconSize
        )

        guard let currentImage else {
            return nil
        }

        guard let transitionSnapshot = curveLoaderTransitionSnapshot else {
            return currentImage
        }

        let rawProgress = (now - transitionSnapshot.startedAt) / curveLoaderPresetTransitionDuration
        guard rawProgress < 1 else {
            curveLoaderTransitionSnapshot = nil
            return currentImage
        }

        let progress = CGFloat(easeInOutSine(max(0, min(rawProgress, 1))))
        let previousTime = transitionSnapshot.animationTimeMilliseconds
            + max(0, now - transitionSnapshot.startedAt) * 1_000 * curveLoaderSmoothedSpeedMultiplier
        guard let previousImage = cachedCurveLoaderImage(
            preset: transitionSnapshot.preset,
            timeMilliseconds: previousTime,
            phaseOffset: transitionSnapshot.phaseOffset,
            color: color,
            size: iconSize
        ) else {
            return currentImage
        }

        return blendedCurveLoaderImage(
            previousImage: previousImage,
            currentImage: currentImage,
            progress: progress,
            size: iconSize
        )
    }

    private func cachedCurveLoaderImage(
        preset: DynamicGraphicPreset,
        timeMilliseconds: Double,
        phaseOffset: Double,
        color: NSColor,
        size: NSSize
    ) -> NSImage? {
        let quantizedTime = quantizedCurveLoaderTime(timeMilliseconds)
        let key = curveLoaderImageCacheKey(
            preset: preset,
            timeMilliseconds: quantizedTime,
            phaseOffset: phaseOffset,
            color: color,
            size: size
        )
        if let cachedImage = curveLoaderImageCache.object(forKey: key) {
            return cachedImage
        }
        guard let image = DynamicGraphicRenderer.makeImage(
            preset: preset,
            timeMilliseconds: quantizedTime,
            phaseOffset: phaseOffset,
            color: color,
            size: size
        ) else {
            return nil
        }
        curveLoaderImageCache.setObject(image, forKey: key)
        return image
    }

    private func quantizedCurveLoaderTime(_ timeMilliseconds: Double) -> Double {
        let interval = Double(max(1, currentStatusAnimationRedrawIntervalMilliseconds))
        return (timeMilliseconds / interval).rounded(.down) * interval
    }

    private func curveLoaderImageCacheKey(
        preset: DynamicGraphicPreset,
        timeMilliseconds: Double,
        phaseOffset: Double,
        color: NSColor,
        size: NSSize
    ) -> NSString {
        let normalizedColor = color.usingColorSpace(.sRGB) ?? color
        let red = Int((normalizedColor.redComponent * 255).rounded())
        let green = Int((normalizedColor.greenComponent * 255).rounded())
        let blue = Int((normalizedColor.blueComponent * 255).rounded())
        let alpha = Int((normalizedColor.alphaComponent * 255).rounded())
        let interval = Double(max(1, currentStatusAnimationRedrawIntervalMilliseconds))
        let frame = Int((timeMilliseconds / interval).rounded(.down))
        let phase = Int((phaseOffset * 1_000).rounded())
        let width = Int((size.width * 100).rounded())
        let height = Int((size.height * 100).rounded())
        return "\(preset.rawValue)|\(frame)|\(phase)|\(red),\(green),\(blue),\(alpha)|\(width)x\(height)" as NSString
    }

    private func curveLoaderAnimationTime(at now: CFTimeInterval, speedBytesPerSecond: Double) -> Double {
        let targetMultiplier = curveLoaderSpeedMultiplier(forSpeedBytesPerSecond: speedBytesPerSecond)
        guard let lastFrameTime = curveLoaderLastFrameTime else {
            curveLoaderLastFrameTime = now
            curveLoaderSmoothedSpeedMultiplier = targetMultiplier
            return curveLoaderAnimationTimeMilliseconds
        }

        let delta = min(max(now - lastFrameTime, 0), 0.20)
        curveLoaderLastFrameTime = now

        let smoothing = 1 - exp(-delta / 0.18)
        curveLoaderSmoothedSpeedMultiplier += (targetMultiplier - curveLoaderSmoothedSpeedMultiplier) * smoothing
        curveLoaderAnimationTimeMilliseconds += delta * 1_000 * curveLoaderSmoothedSpeedMultiplier
        return curveLoaderAnimationTimeMilliseconds
    }

    private func makeCurveLoaderTotalsImage() -> NSImage? {
        let now = CACurrentMediaTime()
        guard let icon = makeCurveLoaderIconImage(at: now) else {
            return nil
        }

        let totals = minimalSignalDataAmountParts(
            uploadBytes: UInt64(displayedTodayUploaded),
            downloadBytes: UInt64(displayedTodayDownloaded)
        )
        let up = totals.up
        let down = totals.down

        let attributes: [NSAttributedString.Key: Any] = [
            .font: cachedBadgeFont
        ]

        let upNumberAttr = NSAttributedString(
            string: up.value,
            attributes: attributes.merging([.foregroundColor: colorForSpeed(displayedUploadBps)]) { _, new in new }
        )
        let upUnitAttr = NSAttributedString(
            string: up.unit,
            attributes: attributes.merging([.foregroundColor: colorForSpeed(displayedUploadBps)]) { _, new in new }
        )
        let downNumberAttr = NSAttributedString(
            string: down.value,
            attributes: attributes.merging([.foregroundColor: colorForSpeed(displayedDownloadBps)]) { _, new in new }
        )
        let downUnitAttr = NSAttributedString(
            string: down.unit,
            attributes: attributes.merging([.foregroundColor: colorForSpeed(displayedDownloadBps)]) { _, new in new }
        )

        let iconSize = NSSize(width: 18, height: 18)
        let leadingPadding: CGFloat = 1
        let trailingPadding: CGFloat = 2
        let gap: CGFloat = 5
        let unitGap: CGFloat = 4
        let topRowCenterY: CGFloat = 14
        let bottomRowCenterY: CGFloat = 4
        let upNumberSize = upNumberAttr.size()
        let upUnitSize = upUnitAttr.size()
        let downNumberSize = downNumberAttr.size()
        let downUnitSize = downUnitAttr.size()
        let numberColumnWidth = max(upNumberSize.width, downNumberSize.width)
        let unitColumnWidth = max(upUnitSize.width, downUnitSize.width)
        let iconX = leadingPadding
        let textX = iconX + iconSize.width + gap
        let unitX = textX + numberColumnWidth + unitGap
        let canvasSize = NSSize(
            width: unitX + unitColumnWidth + trailingPadding,
            height: 18
        )

        return NSImage(size: canvasSize, flipped: false) { _ in
            icon.draw(in: NSRect(origin: NSPoint(x: iconX, y: 0), size: iconSize))
            upNumberAttr.draw(at: NSPoint(
                x: textX + numberColumnWidth - upNumberSize.width,
                y: topRowCenterY - upNumberSize.height / 2
            ))
            upUnitAttr.draw(at: NSPoint(
                x: unitX,
                y: topRowCenterY - upUnitSize.height / 2
            ))
            downNumberAttr.draw(at: NSPoint(
                x: textX + numberColumnWidth - downNumberSize.width,
                y: bottomRowCenterY - downNumberSize.height / 2
            ))
            downUnitAttr.draw(at: NSPoint(
                x: unitX,
                y: bottomRowCenterY - downUnitSize.height / 2
            ))
            return true
        }
    }

    private func makeMinimalSignalTotalsImage() -> NSImage? {
        let totals = minimalSignalDataAmountParts(
            uploadBytes: UInt64(displayedTodayUploaded),
            downloadBytes: UInt64(displayedTodayDownloaded)
        )
        let up = totals.up
        let down = totals.down

        let attributes: [NSAttributedString.Key: Any] = [
            .font: cachedBadgeFont
        ]

        let upNumberAttr = NSAttributedString(
            string: up.value,
            attributes: attributes.merging([.foregroundColor: colorForSpeed(displayedUploadBps)]) { _, new in new }
        )
        let upUnitAttr = NSAttributedString(
            string: up.unit,
            attributes: attributes.merging([.foregroundColor: colorForSpeed(displayedUploadBps)]) { _, new in new }
        )
        let downNumberAttr = NSAttributedString(
            string: down.value,
            attributes: attributes.merging([.foregroundColor: colorForSpeed(displayedDownloadBps)]) { _, new in new }
        )
        let downUnitAttr = NSAttributedString(
            string: down.unit,
            attributes: attributes.merging([.foregroundColor: colorForSpeed(displayedDownloadBps)]) { _, new in new }
        )

        let dotSize: CGFloat = 5
        let leadingPadding: CGFloat = 2
        let trailingPadding: CGFloat = 2
        let gap: CGFloat = 6
        let unitGap: CGFloat = 4
        let topRowCenterY: CGFloat = 14
        let bottomRowCenterY: CGFloat = 4
        let upNumberSize = upNumberAttr.size()
        let upUnitSize = upUnitAttr.size()
        let downNumberSize = downNumberAttr.size()
        let downUnitSize = downUnitAttr.size()
        let numberColumnWidth = max(upNumberSize.width, downNumberSize.width)
        let unitColumnWidth = max(upUnitSize.width, downUnitSize.width)
        let dotX = leadingPadding
        let textX = dotX + dotSize + gap
        let unitX = textX + numberColumnWidth + unitGap
        let canvasSize = NSSize(
            width: unitX + unitColumnWidth + trailingPadding,
            height: 18
        )

        return NSImage(size: canvasSize, flipped: false) { _ in
            self.drawMinimalSignalDots(originX: dotX)
            upNumberAttr.draw(at: NSPoint(
                x: textX + numberColumnWidth - upNumberSize.width,
                y: topRowCenterY - upNumberSize.height / 2
            ))
            upUnitAttr.draw(at: NSPoint(
                x: unitX,
                y: topRowCenterY - upUnitSize.height / 2
            ))
            downNumberAttr.draw(at: NSPoint(
                x: textX + numberColumnWidth - downNumberSize.width,
                y: bottomRowCenterY - downNumberSize.height / 2
            ))
            downUnitAttr.draw(at: NSPoint(
                x: unitX,
                y: bottomRowCenterY - downUnitSize.height / 2
            ))
            return true
        }
    }

    private func drawMinimalSignalDots(originX: CGFloat) {
        let dotSize: CGFloat = 5
        let uploadColor = colorForSpeed(displayedUploadBps)
            .withAlphaComponent(blinkAlpha(for: uploadBlinkPeriod))
        let downloadColor = colorForSpeed(displayedDownloadBps)
            .withAlphaComponent(blinkAlpha(for: downloadBlinkPeriod))

        uploadColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: originX, y: 12, width: dotSize, height: dotSize)).fill()

        downloadColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: originX, y: 2, width: dotSize, height: dotSize)).fill()
    }

    private func minimalSignalDataAmountParts(
        uploadBytes: UInt64,
        downloadBytes: UInt64
    ) -> (up: (value: String, unit: String), down: (value: String, unit: String)) {
        let up = dataAmountComponents(uploadBytes)
        let down = dataAmountComponents(downloadBytes)
        let upIntegerDigits = integerDigitCount(up.value)
        let downIntegerDigits = integerDigitCount(down.value)
        let shouldUseDecimal = abs(upIntegerDigits - downIntegerDigits) >= 2

        var upDecimals = shouldUseDecimal && upIntegerDigits < downIntegerDigits ? 1 : 0
        var downDecimals = shouldUseDecimal && downIntegerDigits < upIntegerDigits ? 1 : 0

        if upDecimals == 0 && downDecimals == 0 {
            upDecimals = 1
            downDecimals = 1
        }

        return (
            up: formattedDataAmountParts(up.value, unitIndex: up.unitIndex, decimals: upDecimals),
            down: formattedDataAmountParts(down.value, unitIndex: down.unitIndex, decimals: downDecimals)
        )
    }

    private func dataAmountComponents(_ bytes: UInt64) -> (value: Double, unitIndex: Int, unit: String) {
        let units = ["B", "kB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unitIndex = 0

        while value >= 1024, unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }

        return (value, unitIndex, units[unitIndex])
    }

    private func formattedDataAmountParts(
        _ value: Double,
        unitIndex: Int,
        decimals: Int
    ) -> (value: String, unit: String) {
        let units = ["B", "kB", "MB", "GB", "TB"]
        var displayValue = value
        var displayUnitIndex = unitIndex
        let scale = pow(10, Double(decimals))
        var rounded = (displayValue * scale).rounded() / scale

        if rounded >= 1024, displayUnitIndex < units.count - 1 {
            displayValue /= 1024
            displayUnitIndex += 1
            let nextScale = pow(10, Double(decimals))
            rounded = (displayValue * nextScale).rounded() / nextScale
        }

        let format = decimals > 0 ? "%.\(decimals)f" : "%.0f"
        return (String(format: format, rounded), units[displayUnitIndex])
    }

    private func integerDigitCount(_ value: Double) -> Int {
        let rounded = max(0, value.rounded())
        guard rounded >= 1 else {
            return 1
        }
        return Int(floor(log10(rounded))) + 1
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
            setStatusButtonImage(image, into: button, prefersDynamicIconView: false)
        } else {
            removeDynamicIconView()
            button.image = nil
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
            setStatusButtonImage(image, into: button, prefersDynamicIconView: false)
        }
    }

    private func renderCombined(into button: NSStatusBarButton) {
        if let image = makeCombinedBadgeImage() {
            setStatusButtonImage(image, into: button, prefersDynamicIconView: false)
        }
    }

    private func renderMinimalSignal(into button: NSStatusBarButton) {
        if let image = makeMinimalSignalImage() {
            setStatusButtonImage(
                image,
                into: button,
                prefersDynamicIconView: !minimalSignalShowsTrafficTotals
            )
        }
    }

    private func renderCurveLoader(into button: NSStatusBarButton) {
        if let image = makeCurveLoaderImage() {
            setStatusButtonImage(
                image,
                into: button,
                prefersDynamicIconView: !minimalSignalShowsTrafficTotals
            )
        }
    }

    private func setStatusButtonImage(
        _ image: NSImage,
        into button: NSStatusBarButton,
        prefersDynamicIconView: Bool
    ) {
        button.title = ""
        guard prefersDynamicIconView else {
            removeDynamicIconView()
            button.image = image
            return
        }

        if button.image != nil {
            button.image = nil
        }
        let iconView = ensureDynamicIconView(in: button)
        setDynamicIconImage(image, in: iconView)
        iconView.isHidden = false
        positionDynamicIconView(iconView, in: button, imageSize: image.size)
    }

    private func ensureDynamicIconView(in button: NSStatusBarButton) -> NSView {
        if let dynamicIconView, dynamicIconView.superview === button {
            return dynamicIconView
        }
        let iconView = NSView(frame: .zero)
        iconView.wantsLayer = true
        iconView.layerContentsRedrawPolicy = .never
        iconView.layer?.contentsGravity = .resizeAspect
        iconView.layer?.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        button.addSubview(iconView)
        dynamicIconView = iconView
        return iconView
    }

    private func setDynamicIconImage(_ image: NSImage, in iconView: NSView) {
        var proposedRect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        iconView.layer?.contents = cgImage
        iconView.layer?.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        CATransaction.commit()
    }

    private func positionDynamicIconView(
        _ iconView: NSView,
        in button: NSStatusBarButton,
        imageSize: NSSize
    ) {
        let width = min(max(imageSize.width, 18), max(button.bounds.width, 18))
        let height = min(max(imageSize.height, 18), max(button.bounds.height, 18))
        let frame = NSRect(
            x: (button.bounds.width - width) / 2,
            y: (button.bounds.height - height) / 2,
            width: width,
            height: height
        )
        if iconView.frame != frame {
            iconView.frame = frame
        }
    }

    private func removeDynamicIconView() {
        dynamicIconView?.layer?.contents = nil
        dynamicIconView?.removeFromSuperview()
        dynamicIconView = nil
    }

    private var displayMode: FlowWatchApp.StatusBarDisplayMode {
        get {
            cachedDisplayMode
        }
        set {
            cachedDisplayMode = newValue
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

    @objc private func openStatisticsDetail() {
        LogManager.shared.log("Open traffic statistics detail window")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            TrafficStatisticsDetailWindowController.shared.show(monitor: self.monitor)
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
        updateMenuItem.isEnabled = updateManager.canActivateUpdateMenu

        switch updateManager.status {
        case .updateAvailable, .downloading, .readyToInstall, .installOnQuit, .remindLater, .installing:
            applyUpdateMenuHighlight(to: updateMenuItem, title: title)
        default:
            break
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
        if let version = resolvedCachedVersion(for: status) {
            switch status {
            case .downloading(_, let progress):
                if let progress {
                    return String(format: LocalizationManager.shared.t("menu.updateDownloading"), Int((progress * 100).rounded()))
                }
                return LocalizationManager.shared.t("menu.updateDownloadingIndeterminate")
            case .readyToInstall:
                return String(format: LocalizationManager.shared.t("menu.updateReady"), version)
            case .installOnQuit:
                return String(format: LocalizationManager.shared.t("menu.updateOnQuit"), version)
            case .installing:
                return LocalizationManager.shared.t("menu.updating")
            case .remindLater:
                return String(format: LocalizationManager.shared.t("menu.updateDeferred"), version)
            case .skipped:
                return String(format: LocalizationManager.shared.t("menu.updateSkipped"), version)
            default:
                return String(format: LocalizationManager.shared.t("menu.updateAvailable"), version)
            }
        }
        switch status {
        case .idle:
            return LocalizationManager.shared.t("menu.checkUpdate")
        case .upToDate:
            return LocalizationManager.shared.t("menu.upToDate")
        case .failed:
            return LocalizationManager.shared.t("menu.updateFailed")
        case .updateAvailable(let update):
            return String(format: LocalizationManager.shared.t("menu.updateAvailable"), update.version)
        case .checking, .downloading, .readyToInstall, .installOnQuit, .remindLater, .installing, .skipped:
            return LocalizationManager.shared.t("menu.checkUpdate")
        }
    }

    private func resolvedCachedVersion(for status: UpdateManager.UpdateStatus) -> String? {
        switch status {
        case .updateAvailable(let update), .downloading(let update, _), .readyToInstall(let update),
             .installOnQuit(let update), .remindLater(let update, _), .installing(let update), .skipped(let update):
            return update.version
        default:
            return updateManager.cachedLatestVersion
        }
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

        if isDynamicStatusMode {
            syncStatusAnimationTimer()
        } else {
            updateStatusButtonContent()
        }

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
        if displayMode == .minimalSignal {
            return minimalSignalRenderKey(
                downloadBps: targetDownloadBps,
                uploadBps: targetUploadBps,
                todayDownloaded: targetTodayDownloaded,
                todayUploaded: targetTodayUploaded
            )
        }
        if displayMode == .curveLoader {
            return curveLoaderRenderKey(
                downloadBps: targetDownloadBps,
                uploadBps: targetUploadBps,
                todayDownloaded: targetTodayDownloaded,
                todayUploaded: targetTodayUploaded
            )
        }
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

    private func easeInOutSine(_ t: Double) -> Double {
        0.5 - cos(max(0, min(t, 1)) * .pi) / 2
    }

    private func blendedCurveLoaderImage(
        previousImage: NSImage,
        currentImage: NSImage,
        progress: CGFloat,
        size: NSSize
    ) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            previousImage.draw(
                in: rect,
                from: NSRect(origin: .zero, size: previousImage.size),
                operation: .sourceOver,
                fraction: max(0, 1 - progress),
                respectFlipped: false,
                hints: nil
            )
            currentImage.draw(
                in: rect,
                from: NSRect(origin: .zero, size: currentImage.size),
                operation: .sourceOver,
                fraction: min(1, progress),
                respectFlipped: false,
                hints: nil
            )
            return true
        }
    }

    private func rebuildMenu() {
        let newMenu = NSMenu()
        let statisticsItem = NSMenuItem(title: LocalizationManager.shared.t("menu.statisticsDetail"), action: #selector(openStatisticsDetail), keyEquivalent: "")
        statisticsItem.target = self
        statisticsItem.image = menuSymbol(named: "chart.bar.xaxis", accessibilityDescription: statisticsItem.title)
        newMenu.addItem(statisticsItem)
        if processMonitor.isEnabled {
            let perAppItem = NSMenuItem(title: LocalizationManager.shared.t("menu.perAppTraffic"), action: #selector(openPerAppDetail), keyEquivalent: "")
            perAppItem.target = self
            perAppItem.image = menuSymbol(named: "chart.pie", accessibilityDescription: perAppItem.title)
            newMenu.addItem(perAppItem)
        }
        newMenu.addItem(.separator())
        let settingsItem = NSMenuItem(title: LocalizationManager.shared.t("menu.settings"), action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.target = self
        settingsItem.image = menuSymbol(named: "gearshape", accessibilityDescription: settingsItem.title)
        newMenu.addItem(settingsItem)
        let checkUpdateItem = NSMenuItem(title: LocalizationManager.shared.t("menu.checkUpdate"), action: #selector(checkForUpdates), keyEquivalent: "")
        checkUpdateItem.target = self
        checkUpdateItem.image = menuSymbol(named: "arrow.up.circle", accessibilityDescription: checkUpdateItem.title)
        updateMenuItem = checkUpdateItem
        newMenu.addItem(checkUpdateItem)
        let aboutItem = NSMenuItem(title: LocalizationManager.shared.t("menu.about"), action: #selector(openAbout), keyEquivalent: "")
        aboutItem.target = self
        aboutItem.image = menuSymbol(named: "info.circle", accessibilityDescription: aboutItem.title)
        newMenu.addItem(aboutItem)
        newMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: LocalizationManager.shared.t("menu.quit"), action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        quitItem.image = menuSymbol(named: "power", accessibilityDescription: quitItem.title)
        newMenu.addItem(quitItem)
        menu = newMenu
        statusItem.menu = menu
        refreshUpdateMenuItem()
    }

    private func menuSymbol(named name: String, accessibilityDescription: String) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: accessibilityDescription)?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = true
        return image
    }

    deinit {
        let defaults = UserDefaults.standard
        let keys = [
            displayModeKey,
            maxColorRateKey,
            colorRatePercentKey,
            coloringEnabledKey,
            smoothTransitionKey,
            minimalSignalShowsTrafficTotalsKey,
            minimalSignalBlinkSpeedPercentKey,
            mathCurveLoaderSelectionKey,
            mathCurveLoaderRandomSwitchIntervalMinutesKey
        ]
        for key in keys {
            defaults.removeObserver(self, forKeyPath: key)
        }
    }
}
