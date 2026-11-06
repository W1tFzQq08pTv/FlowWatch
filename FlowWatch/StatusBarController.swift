import SwiftUI
import AppKit
import Combine
import QuartzCore

@MainActor
final class StatusBarController: NSObject, ObservableObject {
    private let layoutKey = StatusBarLayout.defaultsKey
    private var layout = StatusBarLayout()
    private var layoutRenderKey = ""
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
    private var statusBitmapContext: CGContext?
    private let statusBitmapColorSpace = CGColorSpaceCreateDeviceRGB()
    private let quickPanel = FlowWatchFloatingPanel()
    private let quickPanelState = FlowWatchQuickPanelState()
    private var shortcutMonitor: Any?
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
    private var trafficImageCache: (key: String, image: NSImage)?
    private var lastAccessibilityValue = ""
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
        cache.countLimit = 32
        cache.totalCostLimit = 512 * 1024
        return cache
    }()
    private var cachedMaxColorRateMbps: Double = 100
    private var cachedColorRatePercent: Double = 100
    private var cachedColoringEnabled = true
    private var cachedSmoothTransitionEnabled = true
    private var cachedMinimalSignalBlinkSpeedPercent: Double = 50
    private var cachedMathCurveLoaderSelection: MathCurveLoaderSelection = .random
    private var cachedCurveLoaderRandomSwitchIntervalSeconds: CFTimeInterval = 10 * 60

    private var smoothTransitionEnabled: Bool {
        cachedSmoothTransitionEnabled
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

    private var isShowingQuitConfirmation = false

    private var cancellables = Set<AnyCancellable>()

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
        updateStatusButtonContent()
        scheduleAutomaticUpdateCheck()
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(toggleQuickPanel)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.setAccessibilityLabel("FlowWatch")
        let hoverView = StatusBarHoverView(frame: button.bounds.insetBy(dx: 1, dy: 2))
        hoverView.autoresizingMask = [.width, .height]
        button.addSubview(hoverView, positioned: .below, relativeTo: nil)
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.modifierFlags.contains(.command) else { return event }
            #if DEBUG
            // Runtime-only appearance previews keep visual QA out of the user's system preferences.
            if event.modifierFlags.contains(.option) {
                switch event.keyCode {
                case 18: NSApp.appearance = NSAppearance(named: .aqua); return nil
                case 19: NSApp.appearance = NSAppearance(named: .darkAqua); return nil
                case 29: NSApp.appearance = nil; return nil
                case 49: self.toggleQuickPanel(); return nil
                default: break
                }
            }
            #endif
            switch event.charactersIgnoringModifiers?.lowercased() {
            case ",": self.quickPanel.hide(); self.openSettings(); return nil
            case "q": self.quickPanel.hide(); self.quitApp(); return nil
            default: return event
            }
        }
        button.imagePosition = .imageOnly
        button.focusRingType = .none
    }

    private func bindMonitor() {
        Publishers.CombineLatest4(monitor.$downloadBps, monitor.$uploadBps,
                                  monitor.$todayDownloaded, monitor.$todayUploaded)
            .debounce(for: .milliseconds(10), scheduler: DispatchQueue.main)
            .removeDuplicates { previous, next in
                previous.0 == next.0 && previous.1 == next.1 && previous.2 == next.2 && previous.3 == next.3
            }
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
            layoutKey,
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
        layout = StatusBarLayout.load(defaults: defaults)
        layoutRenderKey = layout.rawValue

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
            layoutKey,
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
                self.layoutKey,
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
            self.updateMinimalSignalBlinkPeriods(downloadBps: self.displayedDownloadBps, uploadBps: self.displayedUploadBps)
            self.lastRenderedKey = ""
            self.updateStatusButtonContent()
        }
    }

    private func bindNotifications() {
        NotificationCenter.default.publisher(for: .flowWatchOpenSettings)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.quickPanel.hide(); self?.openSettings() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .flowWatchQuitRequested)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.quickPanel.hide(); self?.quitApp() }
            .store(in: &cancellables)
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
        
        NotificationCenter.default.publisher(for: .flowWatchCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateManager.startAutomaticUpdateChecks()
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

    /// 颜色量化步长（256 KB/s），对应 100 Mbps 上限约 50 级可辨色阶
    private let colorQuantStep: Double = 256_000

    private func currentRenderKey() -> String {
        composedRenderKey(download: displayedDownloadBps, upload: displayedUploadBps,
                          downloaded: displayedTodayDownloaded, uploaded: displayedTodayUploaded)
    }

    private func composedRenderKey(download: Double, upload: Double, downloaded: Double, uploaded: Double) -> String {
        var parts = [layoutRenderKey, String(isColoringEnabled), String(colorRatePercent), String(maxColorRateMbps)]
        if layout.enabled.contains(.traffic) {
            parts.append(trafficRenderKey(download: download, upload: upload, downloaded: downloaded, uploaded: uploaded))
        }
        if layout.enabled.contains(.signal) {
            parts.append(minimalSignalRenderKey(downloadBps: download, uploadBps: upload))
        }
        if layout.enabled.contains(.animation) {
            parts.append(curveLoaderRenderKey(downloadBps: download, uploadBps: upload))
        }
        return parts.joined(separator: "|")
    }

    private func trafficRenderKey(download: Double, upload: Double, downloaded: Double, uploaded: Double) -> String {
        var parts = [layoutRenderKey, String(isColoringEnabled), String(colorRatePercent), String(maxColorRateMbps)]
        for isUpload in [false, true] {
            guard layout.direction == .both || (isUpload ? layout.direction == .upload : layout.direction == .download) else { continue }
            let speed = isUpload ? upload : download
            if layout.content != .total { parts.append(monitor.fixedWidthCompactSpeed(speed)) }
            if layout.content != .speed { parts.append(monitor.fixedWidthDataAmount(UInt64(max(0, isUpload ? uploaded : downloaded)))) }
            if isColoringEnabled { parts.append(String(Int(speed / colorQuantStep))) }
        }
        return parts.joined(separator: "|")
    }

    private func updateStatusButtonContent() {
        syncStatusAnimationTimer()
        let key = currentRenderKey()
        guard key != lastRenderedKey, let button = statusItem.button else { return }
        lastRenderedKey = key
        let images = layout.visibleComponents.compactMap { component -> NSImage? in
            switch component {
            case .traffic: return makeTrafficImage()
            case .animation: return makeCurveLoaderIconImage(at: CACurrentMediaTime())
            case .signal:
                return NSImage(size: NSSize(width: 12, height: 18), flipped: false) { _ in
                    self.drawMinimalSignalDots(originX: 3.5)
                    return true
                }
            }
        }
        let gap: CGFloat = 5
        let width = images.reduce(CGFloat(0)) { $0 + $1.size.width } + CGFloat(max(0, images.count - 1)) * gap
        let size = NSSize(width: max(18, width), height: 18)
        let length = max(24, width + 8)
        if statusItem.length != length { statusItem.length = length }
        if !isDynamicStatusMode || !setDynamicStatusComponents(images, size: size, in: button) {
            let image = NSImage(size: size, flipped: false) { _ in
                var x: CGFloat = 0
                for image in images {
                    image.draw(in: NSRect(x: x, y: (18 - image.size.height) / 2,
                                         width: image.size.width, height: image.size.height))
                    x += image.size.width + gap
                }
                return true
            }
            setStatusButtonImage(image, into: button, prefersDynamicIconView: isDynamicStatusMode)
        }
        let accessibilityValue = "↑ \(monitor.fixedWidthCompactSpeed(displayedUploadBps))  ↓ \(monitor.fixedWidthCompactSpeed(displayedDownloadBps))"
        if accessibilityValue != lastAccessibilityValue {
            button.setAccessibilityValue(accessibilityValue)
            lastAccessibilityValue = accessibilityValue
        }
    }

    private var isDynamicStatusMode: Bool { layout.isAnimated }

    private func makeTrafficImage() -> NSImage {
        let key = trafficRenderKey(download: displayedDownloadBps, upload: displayedUploadBps,
                                   downloaded: displayedTodayDownloaded, uploaded: displayedTodayUploaded)
            + "|\(statusItem.button?.window?.backingScaleFactor ?? 2)"
        if let cached = trafficImageCache, cached.key == key { return cached.image }
        var directions: [Bool] = layout.direction == .upload ? [true] : layout.direction == .download ? [false] : [true, false]
        if layout.downloadFirst { directions.reverse() }
        let stacked = layout.arrangement == .stacked && directions.count == 2
        let font = NSFont.monospacedSystemFont(ofSize: 6.5, weight: .semibold)
        let rows = directions.map { isUpload -> NSAttributedString in
            let speed = monitor.fixedWidthCompactSpeed(isUpload ? displayedUploadBps : displayedDownloadBps)
            let total = monitor.fixedWidthDataAmount(UInt64(max(0, isUpload ? displayedTodayUploaded : displayedTodayDownloaded)))
            let value: String
            switch layout.content {
            case .speed: value = speed
            case .total: value = total
            case .both: value = total + "  " + speed
            }
            return NSAttributedString(string: value, attributes: [
                .font: font,
                .foregroundColor: colorForSpeed(isUpload ? displayedUploadBps : displayedDownloadBps)
            ])
        }
        let width = stacked ? rows.map { $0.size().width }.max() ?? 0
            : rows.reduce(CGFloat(0)) { $0 + $1.size().width } + CGFloat(rows.count - 1) * 6
        let image = rasterizedStatusImage(size: NSSize(width: ceil(width), height: 18)) { _ in
            var x: CGFloat = 0
            for (index, row) in rows.enumerated() {
                let size = row.size()
                let centerY: CGFloat = stacked ? (index == 0 ? 13.5 : 4.5) : 9
                row.draw(at: NSPoint(x: stacked ? width - size.width : x, y: centerY - size.height / 2))
                x += size.width + 6
            }
            return true
        }
        trafficImageCache = (key, image)
        return image
    }

    private func rasterizedStatusImage(size: NSSize, drawingHandler: @escaping (NSRect) -> Bool) -> NSImage {
        let scale = statusItem.button?.window?.backingScaleFactor ?? 2
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: max(1, Int(ceil(size.width * scale))),
            pixelsHigh: max(1, Int(ceil(size.height * scale))), bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bitmapFormat: [.alphaFirst], bytesPerRow: 0, bitsPerPixel: 0
        ), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
            return NSImage(size: size, flipped: false, drawingHandler: drawingHandler)
        }
        bitmap.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        graphics.cgContext.clear(CGRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh))
        graphics.cgContext.scaleBy(x: scale, y: scale)
        _ = drawingHandler(NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        return image
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

    private func minimalSignalRenderKey(downloadBps: Double, uploadBps: Double) -> String {
        let downColor = minimalSignalColorBucket(downloadBps)
        let upColor = minimalSignalColorBucket(uploadBps)
        let downAlpha = Int((blinkAlpha(for: downloadBlinkPeriod) * 20).rounded())
        let upAlpha = Int((blinkAlpha(for: uploadBlinkPeriod) * 20).rounded())
        return "signal|\(downColor)|\(upColor)|\(downAlpha)|\(upAlpha)"
    }

    private func curveLoaderRenderKey(downloadBps: Double, uploadBps: Double) -> String {
        let now = CACurrentMediaTime()
        let preset = currentCurveLoaderPreset(at: now)
        let frame = Int((now * 1_000 / Double(currentStatusAnimationRedrawIntervalMilliseconds)).rounded(.down))
        let color = minimalSignalColorBucket(max(downloadBps, uploadBps))
        let speedBucket = Int((curveLoaderSpeedMultiplier(forSpeedBytesPerSecond: max(downloadBps, uploadBps)) * 20).rounded())
        return "animation|\(preset.rawValue)|\(frame)|\(color)|\(speedBucket)"
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
        guard layout.enabled.contains(.animation) else {
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
        timer.schedule(deadline: .now(), repeating: .milliseconds(intervalMilliseconds), leeway: .milliseconds(10))
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
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let cost = max(1, Int(size.width * size.height * scale * scale * 4))
        curveLoaderImageCache.setObject(image, forKey: key, cost: cost)
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

    private func setDynamicStatusComponents(_ images: [NSImage], size: NSSize, in button: NSStatusBarButton) -> Bool {
        let scale = button.window?.backingScaleFactor ?? 2
        let pixelWidth = max(1, Int(ceil(size.width * scale)))
        let pixelHeight = max(1, Int(ceil(size.height * scale)))
        if statusBitmapContext?.width != pixelWidth || statusBitmapContext?.height != pixelHeight {
            statusBitmapContext = CGContext(data: nil, width: pixelWidth, height: pixelHeight,
                                            bitsPerComponent: 8, bytesPerRow: 0,
                                            space: statusBitmapColorSpace,
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }
        guard let context = statusBitmapContext else { return false }
        context.clear(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.saveGState()
        context.scaleBy(x: scale, y: scale)
        var x: CGFloat = 0
        for image in images {
            let bitmap = image.representations.compactMap { ($0 as? NSBitmapImageRep)?.cgImage }.first
            var rect = NSRect(origin: .zero, size: image.size)
            guard let cgImage = bitmap ?? image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
                context.restoreGState()
                return false
            }
            context.draw(cgImage, in: CGRect(x: x, y: (size.height - image.size.height) / 2,
                                             width: image.size.width, height: image.size.height))
            x += image.size.width + 5
        }
        context.restoreGState()
        guard let cgImage = context.makeImage() else { return false }
        if !button.title.isEmpty { button.title = "" }
        if button.image != nil { button.image = nil }
        let iconView = ensureDynamicIconView(in: button)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        iconView.layer?.contents = cgImage
        iconView.layer?.contentsScale = scale
        CATransaction.commit()
        iconView.isHidden = false
        positionDynamicIconView(iconView, in: button, imageSize: size)
        return true
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
        statusBitmapContext = nil
        dynamicIconView?.layer?.contents = nil
        dynamicIconView?.removeFromSuperview()
        dynamicIconView = nil
    }

    private func performResetToday() {
        LogManager.shared.log("Reset today from status bar")
        monitor.resetTodayTraffic()
        for scope in TrafficAccountingScope.allCases {
            ProcessTrafficStorage.storage(for: scope).clearTodayRecords()
        }
    }

    private func performResetAllHistory() {
        LogManager.shared.log("Clear all history from status bar")
        monitor.clearAllTrafficHistory()
        for scope in TrafficAccountingScope.allCases {
            ProcessTrafficStorage.storage(for: scope).clearAllRecords()
        }
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
            return
        }
        updateManager.checkForUpdates(userInitiated: true)
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

        FlowWatchDialogController.shared.present(
            title: L10n.t("quit.confirm.title"), message: L10n.t("quit.confirm.message"),
            confirmTitle: L10n.t("common.quit"), cancelTitle: L10n.t("common.cancel"), isDestructive: true,
            completion: { [weak self] confirmed in
                self?.isShowingQuitConfirmation = false
                if confirmed { NSApplication.shared.terminate(nil) }
            }
        )
    }

    private func scheduleAutomaticUpdateCheck() {
        updateManager.startAutomaticUpdateChecks()
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
        composedRenderKey(download: targetDownloadBps, upload: targetUploadBps,
                          downloaded: targetTodayDownloaded, uploaded: targetTodayUploaded)
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

    @objc private func toggleQuickPanel() {
        if quickPanel.isVisible { quickPanel.hide(); return }
        guard let button = statusItem.button else { return }
        quickPanelState.focusedTarget = nil
        let content = FlowWatchQuickPanelView(
            monitor: monitor, processMonitor: processMonitor, state: quickPanelState,
            updateTitle: { [weak self] in
                guard let self else { return "" }
                return self.updateMenuTitle(for: self.updateManager.status)
            }, action: { [weak self] action in self?.performQuickAction(action) }
        )
        .environmentObject(LocalizationManager.shared)
        quickPanel.show(content: content, anchor: button, onKey: { [weak self] event in
            guard let self, !event.modifierFlags.contains(.command) else { return false }
            switch event.keyCode {
            case 123: self.quickPanelState.advance(-1)
            case 124: self.quickPanelState.advance(1)
            case 48, 125, 126:
                self.quickPanelState.moveFocus(
                    backward: event.keyCode == 126 || (event.keyCode == 48 && event.modifierFlags.contains(.shift)),
                    perAppEnabled: self.processMonitor.isEnabled, updateEnabled: self.updateManager.canActivateUpdateMenu
                )
            case 36, 49, 76:
                guard let target = self.quickPanelState.focusedTarget else { return false }
                switch target {
                case .action(let action):
                    guard action != .perApp || self.processMonitor.isEnabled else { return true }
                    guard action != .update || self.updateManager.canActivateUpdateMenu else { return true }
                    self.performQuickAction(action)
                }
            default: return false
            }
            return true
        }) { [weak self] in self?.statusItem.button?.highlight(false) }
        button.highlight(true)
    }

    private func performQuickAction(_ action: FlowWatchQuickPanelView.Action) {
        quickPanel.hide()
        switch action {
        case .statistics: openStatisticsDetail()
        case .perApp: openPerAppDetail()
        case .settings: openSettings()
        case .update: checkForUpdates()
        case .about: openAbout()
        case .quit: quitApp()
        }
    }

    deinit {
        if let shortcutMonitor { NSEvent.removeMonitor(shortcutMonitor) }
        let defaults = UserDefaults.standard
        let keys = [
            layoutKey,
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
