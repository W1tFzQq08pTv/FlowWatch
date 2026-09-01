//
//  UpdateManager.swift
//  FlowWatch
//
//  Created by xida huang on 1/22/26.
//

import AppKit
import Combine
import Foundation
import Sparkle

@MainActor
final class UpdateManager: NSObject, ObservableObject {
    static let shared = UpdateManager()

    struct UpdateInfo: Equatable {
        let version: String
        let build: String
        let downloadURL: URL?
        let downloadContentLength: UInt64
        let title: String?
        let releaseNotesURL: URL?
        let informationURL: URL?
        let isCritical: Bool
        let isMajorUpgrade: Bool
        let isInformationOnly: Bool
    }

    enum UpdateStatus: Equatable {
        case idle
        case checking
        case updateAvailable(UpdateInfo)
        case downloading(UpdateInfo, progress: Double?)
        case readyToInstall(UpdateInfo)
        case installOnQuit(UpdateInfo)
        case remindLater(UpdateInfo, until: Date)
        case installing(UpdateInfo)
        case upToDate
        case skipped(UpdateInfo)
        case failed(message: String)
    }

    @Published private(set) var status: UpdateStatus = .idle
    @Published private(set) var lastCheckDate: Date?
    @Published private(set) var nextCheckDate: Date?
    @Published private(set) var cachedLatestVersion: String?
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var autoCheckEnabled = true
    @Published private(set) var autoDownloadEnabled = true

    var isUpdateActionInProgress: Bool {
        switch status {
        case .checking, .downloading, .installing:
            return true
        default:
            return false
        }
    }

    var hasPendingUserDecision: Bool {
        pendingUpdateReply != nil || pendingReadyReply != nil
    }

    var canActivateUpdateMenu: Bool {
        currentUpdate != nil || canCheckForUpdates
    }

    private let autoCheckEnabledKey = "update.autoCheckEnabled"
    private let autoDownloadEnabledKey = "update.autoDownloadEnabled"
    private let cachedLatestVersionKey = "update.cachedLatestVersion"
    private let reminderDateKey = "update.reminderDate"
    private let reminderVersionKey = "update.reminderVersion"
    private let reminderInterval: TimeInterval = 24 * 60 * 60
    private let githubReleasesURL = URL(string: "https://github.com/W1tFzQq08pTv/FlowWatch/releases")!

    private var updater: SPUUpdater?
    private var userDriver: FlowWatchUpdateUserDriver?
    private var canCheckForUpdatesObservation: NSKeyValueObservation?
    private var automaticChecksObservation: NSKeyValueObservation?
    private let downloadCache = UpdateDownloadCache()
    private let cacheServer = CachedUpdateHTTPServer()
    private var currentUpdate: UpdateInfo?
    private var pendingUpdateReply: ((SPUUserUpdateChoice) -> Void)?
    private var pendingReadyReply: ((SPUUserUpdateChoice) -> Void)?
    private var expectedDownloadLength: UInt64 = 0
    private var receivedDownloadLength: UInt64 = 0
    private var lastPublishedProgress: Double = -1
    private var lastProgressPublishDate = Date.distantPast
    private var installOnQuitAuthorized = false
    private var installNowAuthorized = false
    private var userInitiatedCheck = false
    private var cachedUpdateFileURL: URL?
    private var cachedUpdateServerURL: URL?
    private var immediateInstallationBlock: (() -> Void)?
    private var didPerformQAAction = false

    override init() {
        super.init()
        LogManager.shared.log("UpdateManager initialized with GitHub Release update source")
        registerPreferenceDefaults()
        loadCachedLatestVersion()
        clearCachedVersionIfNeeded()
        configureUpdater()
    }

    func checkForUpdates(userInitiated: Bool) {
        LogManager.shared.log("Check for updates (userInitiated=\(userInitiated))")
        if userInitiated, presentPendingUpdateIfAvailable() { return }
        checkSparkle(userInitiated: userInitiated)
    }

    func startAutomaticUpdateChecks() {
        refreshSparklePreferences()
        refreshSparkleScheduleDates()
    }

    func setAutomaticChecksEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: autoCheckEnabledKey)
        autoCheckEnabled = enabled
        updater?.automaticallyChecksForUpdates = enabled
        refreshSparkleScheduleDates()
        LogManager.shared.log("Automatic update checks enabled: \(enabled)")
    }

    func setAutomaticDownloadsEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: autoDownloadEnabledKey)
        autoDownloadEnabled = enabled
        LogManager.shared.log("Automatic update downloads enabled: \(enabled)")
    }

    func performCachedUpdateAction() -> Bool {
        if presentPendingUpdateIfAvailable() { return true }
        if currentUpdate != nil {
            UpdateWindowController.shared.show()
            return true
        }
        guard cachedLatestVersion != nil,
              canCheckForUpdates,
              !isUpdateActionInProgress else { return false }
        checkSparkle(userInitiated: true)
        return true
    }

    func showUpdateWindow() {
        guard currentUpdate != nil else {
            checkForUpdates(userInitiated: true)
            return
        }
        UpdateWindowController.shared.show()
    }

    func installNow() {
        installOnQuitAuthorized = false
        installNowAuthorized = true
        if let immediateInstallationBlock {
            self.immediateInstallationBlock = nil
            status = currentUpdate.map(UpdateStatus.installing) ?? .idle
            immediateInstallationBlock()
            return
        }
        if let reply = pendingReadyReply {
            pendingReadyReply = nil
            status = currentUpdate.map(UpdateStatus.installing) ?? .idle
            reply(.install)
            return
        }
        guard let reply = consumePendingUpdateReply() else { return }
        beginSparkleInstallation(reply: reply, installOnQuit: false)
    }

    func installOnQuit() {
        installOnQuitAuthorized = true
        installNowAuthorized = false
        if let reply = pendingReadyReply {
            pendingReadyReply = nil
            if let currentUpdate { status = .installOnQuit(currentUpdate) }
            reply(.dismiss)
            return
        }
        guard let reply = consumePendingUpdateReply() else {
            if let currentUpdate { status = .installOnQuit(currentUpdate) }
            return
        }
        beginSparkleInstallation(reply: reply, installOnQuit: true)
    }

    func remindLater() {
        guard let currentUpdate else { return }
        installNowAuthorized = false
        installOnQuitAuthorized = false
        let reminderDate = Date().addingTimeInterval(reminderInterval)
        UserDefaults.standard.set(reminderDate, forKey: reminderDateKey)
        UserDefaults.standard.set(currentUpdate.version, forKey: reminderVersionKey)
        status = .remindLater(currentUpdate, until: reminderDate)
        pendingReadyReply?(.dismiss)
        pendingReadyReply = nil
        consumePendingUpdateReply()?(.dismiss)
        UpdateWindowController.shared.close()
        LogManager.shared.log("Update reminder deferred until \(reminderDate)")
    }

    func skipVersion() {
        guard let currentUpdate else { return }
        guard !currentUpdate.isCritical else {
            remindLater()
            return
        }
        clearReminder()
        installNowAuthorized = false
        installOnQuitAuthorized = false
        downloadCache.cancel()
        status = .skipped(currentUpdate)
        pendingReadyReply?(.skip)
        pendingReadyReply = nil
        consumePendingUpdateReply()?(.skip)
        UpdateWindowController.shared.close()
        LogManager.shared.log("User skipped update \(currentUpdate.version)")
    }

    func openReleaseNotes() {
        let url = currentUpdate?.releaseNotesURL
            ?? currentUpdate?.informationURL
            ?? currentUpdate.map { githubReleasesURL.appendingPathComponent("tag/v\($0.version)") }
            ?? githubReleasesURL
        NSWorkspace.shared.open(url)
    }

    func recheckSkippedVersions() {
        clearReminder()
        checkForUpdates(userInitiated: true)
    }

    private func registerPreferenceDefaults() {
        UserDefaults.standard.register(defaults: [
            autoCheckEnabledKey: true,
            autoDownloadEnabledKey: true
        ])
        autoCheckEnabled = UserDefaults.standard.bool(forKey: autoCheckEnabledKey)
        autoDownloadEnabled = UserDefaults.standard.bool(forKey: autoDownloadEnabledKey)
    }

    private func configureUpdater() {
        let driver = FlowWatchUpdateUserDriver(manager: self)
        let updater = SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: driver,
            delegate: self
        )
        userDriver = driver
        self.updater = updater

        do {
            try updater.start()
        } catch {
            status = .failed(message: error.localizedDescription)
            LogManager.shared.log("Unable to start Sparkle updater: \(error.localizedDescription)", level: .error)
            return
        }

        canCheckForUpdatesObservation = updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            DispatchQueue.main.async { self?.canCheckForUpdates = updater.canCheckForUpdates }
        }
        automaticChecksObservation = updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            DispatchQueue.main.async { self?.autoCheckEnabled = updater.automaticallyChecksForUpdates }
        }
        updater.automaticallyChecksForUpdates = autoCheckEnabled
        // Sparkle's automatic download mode also schedules installation on quit.
        // FlowWatch only prefetches the archive and never authorizes installation here.
        updater.automaticallyDownloadsUpdates = false
        refreshSparkleScheduleDates()
    }

    private func refreshSparklePreferences() {
        guard let updater else { return }
        autoCheckEnabled = updater.automaticallyChecksForUpdates
    }

    private func checkSparkle(userInitiated: Bool) {
        guard let updater else {
            status = .failed(message: LocalizationManager.shared.t("update.dmg.unavailable"))
            return
        }
        guard updater.canCheckForUpdates else {
            LogManager.shared.log("Sparkle update check is not ready")
            return
        }
        userInitiatedCheck = userInitiated
        status = .checking
        if userInitiated {
            updater.checkForUpdates()
        } else if updater.automaticallyChecksForUpdates {
            updater.checkForUpdatesInBackground()
        }
    }

    private func presentPendingUpdateIfAvailable() -> Bool {
        guard currentUpdate != nil,
              pendingUpdateReply != nil || pendingReadyReply != nil else { return false }
        UpdateWindowController.shared.show()
        return true
    }

    private func consumePendingUpdateReply() -> ((SPUUserUpdateChoice) -> Void)? {
        defer { pendingUpdateReply = nil }
        return pendingUpdateReply
    }

    private func loadCachedLatestVersion() {
        cachedLatestVersion = UserDefaults.standard.string(forKey: cachedLatestVersionKey)
    }

    private func storeCachedLatestVersion(_ version: String?) {
        if let version {
            UserDefaults.standard.set(version, forKey: cachedLatestVersionKey)
        } else {
            UserDefaults.standard.removeObject(forKey: cachedLatestVersionKey)
        }
        cachedLatestVersion = version
    }

    private func clearCachedVersionIfNeeded() {
        guard let cachedLatestVersion else { return }
        if Self.compareVersions(cachedLatestVersion, AppVersion.shortVersion) != .orderedDescending {
            storeCachedLatestVersion(nil)
            clearReminder()
        }
    }

    private func clearReminder() {
        UserDefaults.standard.removeObject(forKey: reminderDateKey)
        UserDefaults.standard.removeObject(forKey: reminderVersionKey)
    }

    private func isReminderDeferred(for update: UpdateInfo) -> Bool {
        guard UserDefaults.standard.string(forKey: reminderVersionKey) == update.version,
              let reminderDate = UserDefaults.standard.object(forKey: reminderDateKey) as? Date else { return false }
        return reminderDate > Date()
    }

    private func refreshSparkleScheduleDates() {
        guard let updater else { return }
        if let sparkleLastCheckDate = updater.lastUpdateCheckDate { lastCheckDate = sparkleLastCheckDate }
        guard updater.automaticallyChecksForUpdates else {
            nextCheckDate = nil
            return
        }
        nextCheckDate = (updater.lastUpdateCheckDate ?? Date()).addingTimeInterval(updater.updateCheckInterval)
    }

    func showPermissionRequest(reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(
            automaticUpdateChecks: autoCheckEnabled,
            automaticUpdateDownloading: false,
            sendSystemProfile: false
        ))
    }

    func userInitiatedUpdateCheckDidStart() {
        status = .checking
    }

    func showUpdateFound(
        item: SUAppcastItem,
        state: SPUUserUpdateState,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        let update = makeUpdateInfo(from: item)
        currentUpdate = update
        cachedUpdateFileURL = downloadCache.existingFileURL(
            version: update.version,
            build: update.build,
            expectedLength: update.downloadContentLength
        )
        pendingUpdateReply = reply
        storeCachedLatestVersion(update.version)

        if isReminderDeferred(for: update), !state.userInitiated {
            let date = UserDefaults.standard.object(forKey: reminderDateKey) as? Date ?? Date()
            status = .remindLater(update, until: date)
            consumePendingUpdateReply()?(.dismiss)
            return
        }

        switch state.stage {
        case .notDownloaded:
            status = .updateAvailable(update)
        case .downloaded:
            status = .readyToInstall(update)
        case .installing:
            status = installOnQuitAuthorized ? .installOnQuit(update) : .installing(update)
        @unknown default:
            status = .updateAvailable(update)
        }

        let shouldShowWindow = state.userInitiated || shouldShowQAUpdateWindow
        if state.stage == .notDownloaded, autoDownloadEnabled, update.downloadURL != nil {
            prefetchUpdate(update, showWindow: shouldShowWindow)
        } else if shouldShowWindow {
            UpdateWindowController.shared.show()
        } else {
            postUpdateNotification(for: update, isDownloaded: state.stage == .downloaded)
        }
    }

    func updateNotFound(error: Error, acknowledgement: @escaping () -> Void) {
        storeCachedLatestVersion(nil)
        currentUpdate = nil
        cachedUpdateFileURL = nil
        status = .upToDate
        acknowledgement()
        if userInitiatedCheck { UpdateWindowController.shared.show() }
    }

    func updaterFailed(error: Error, acknowledgement: @escaping () -> Void) {
        status = .failed(message: error.localizedDescription)
        acknowledgement()
        if userInitiatedCheck { UpdateWindowController.shared.show() }
    }

    func downloadStarted() {
        guard let currentUpdate else { return }
        expectedDownloadLength = 0
        receivedDownloadLength = 0
        lastPublishedProgress = -1
        status = .downloading(currentUpdate, progress: nil)
    }

    func setExpectedDownloadLength(_ length: UInt64) {
        expectedDownloadLength = length
        publishDownloadProgress(force: true)
    }

    func receiveDownloadData(length: UInt64) {
        receivedDownloadLength &+= length
        publishDownloadProgress(force: false)
    }

    func extractionStarted() {
        guard let currentUpdate else { return }
        status = installOnQuitAuthorized ? .installOnQuit(currentUpdate) : .installing(currentUpdate)
    }

    func extractionProgress(_ progress: Double) {
        guard !installOnQuitAuthorized, let currentUpdate else { return }
        status = .installing(currentUpdate)
        let percent = Int((progress * 100).rounded())
        if percent % 10 == 0 { LogManager.shared.log("Extracting update: \(percent)%") }
    }

    func readyToInstall(reply: @escaping (SPUUserUpdateChoice) -> Void) {
        guard let currentUpdate else {
            reply(.dismiss)
            return
        }
        if installOnQuitAuthorized {
            status = .installOnQuit(currentUpdate)
            reply(.dismiss)
        } else if installNowAuthorized {
            status = .installing(currentUpdate)
            reply(.install)
        } else {
            pendingReadyReply = reply
            status = .readyToInstall(currentUpdate)
            UpdateWindowController.shared.show()
        }
    }

    func installingUpdate() {
        if let currentUpdate { status = .installing(currentUpdate) }
    }

    func updateInstallationDidFinish(acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }

    func dismissUpdateInstallation() {
        pendingUpdateReply = nil
        pendingReadyReply = nil
        immediateInstallationBlock = nil
        cacheServer.stop()
        UpdateWindowController.shared.close()
    }

    func showCurrentUpdateInFocus() {
        if currentUpdate != nil { UpdateWindowController.shared.show() }
    }

    private func makeUpdateInfo(from item: SUAppcastItem) -> UpdateInfo {
        UpdateInfo(
            version: item.displayVersionString,
            build: item.versionString,
            downloadURL: item.fileURL,
            downloadContentLength: item.contentLength,
            title: item.title,
            releaseNotesURL: item.releaseNotesURL,
            informationURL: item.infoURL,
            isCritical: item.isCriticalUpdate,
            isMajorUpgrade: item.isMajorUpgrade,
            isInformationOnly: item.isInformationOnlyUpdate
        )
    }

    private func publishDownloadProgress(force: Bool) {
        guard let currentUpdate else { return }
        guard expectedDownloadLength > 0 else {
            status = .downloading(currentUpdate, progress: nil)
            return
        }
        let progress = min(Double(receivedDownloadLength) / Double(expectedDownloadLength), 1)
        let now = Date()
        guard force || progress - lastPublishedProgress >= 0.01 || now.timeIntervalSince(lastProgressPublishDate) >= 0.15 else { return }
        lastPublishedProgress = progress
        lastProgressPublishDate = now
        status = .downloading(currentUpdate, progress: progress)
    }

    private func prefetchUpdate(_ update: UpdateInfo, showWindow: Bool) {
        guard let downloadURL = update.downloadURL else { return }
        if let cached = downloadCache.existingFileURL(
            version: update.version,
            build: update.build,
            expectedLength: update.downloadContentLength
        ) {
            cachedUpdateFileURL = cached
            status = .readyToInstall(update)
            if showWindow {
                UpdateWindowController.shared.show()
            } else if !isReminderDeferred(for: update) {
                postUpdateNotification(for: update, isDownloaded: true)
            }
            performQAActionIfNeeded()
            return
        }

        lastPublishedProgress = -1
        lastProgressPublishDate = .distantPast
        status = .downloading(update, progress: nil)
        if showWindow { UpdateWindowController.shared.show() }
        downloadCache.download(
            from: downloadURL,
            version: update.version,
            build: update.build,
            expectedLength: update.downloadContentLength
        ) { [weak self] progress in
            self?.publishPrefetchProgress(update: update, progress: progress)
        } completion: { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let fileURL):
                self.cachedUpdateFileURL = fileURL
                if !self.isReminderDeferred(for: update) {
                    self.status = .readyToInstall(update)
                    self.postUpdateNotification(for: update, isDownloaded: true)
                }
                LogManager.shared.log("Update \(update.version) prefetched without scheduling installation")
                self.performQAActionIfNeeded()
            case .failure(let error):
                guard (error as NSError).code != NSURLErrorCancelled else { return }
                self.status = .updateAvailable(update)
                LogManager.shared.log("Update prefetch failed: \(error.localizedDescription)", level: .error)
                if !showWindow {
                    self.postUpdateNotification(for: update, isDownloaded: false)
                }
            }
        }
    }

    private func publishPrefetchProgress(update: UpdateInfo, progress: Double?) {
        let now = Date()
        if let progress {
            guard progress - lastPublishedProgress >= 0.01
                || now.timeIntervalSince(lastProgressPublishDate) >= 0.15 else { return }
            lastPublishedProgress = progress
        }
        lastProgressPublishDate = now
        status = .downloading(update, progress: progress)
    }

    private func beginSparkleInstallation(
        reply: @escaping (SPUUserUpdateChoice) -> Void,
        installOnQuit: Bool
    ) {
        downloadCache.cancel()
        let continueInstallation = { [weak self] in
            guard let self else { return }
            if let currentUpdate {
                status = installOnQuit ? .installOnQuit(currentUpdate) : .installing(currentUpdate)
            }
            LogManager.shared.log(installOnQuit
                ? "User chose to install update when FlowWatch quits"
                : "User chose to install update now")
            reply(.install)
        }

        guard let cachedUpdateFileURL else {
            continueInstallation()
            return
        }
        cacheServer.start(fileURL: cachedUpdateFileURL) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let serverURL):
                    self.cachedUpdateServerURL = serverURL
                case .failure(let error):
                    self.cachedUpdateServerURL = nil
                    LogManager.shared.log("Unable to serve prefetched update: \(error.localizedDescription)", level: .error)
                }
                continueInstallation()
            }
        }
    }

    private func postUpdateNotification(for update: UpdateInfo, isDownloaded: Bool) {
        let titleKey = update.isCritical ? "update.notification.critical.title" : "update.notification.title"
        let bodyKey = isDownloaded ? "update.notification.ready.body" : "update.notification.available.body"
        UpdateNotificationCenter.shared.post(
            title: String(format: LocalizationManager.shared.t(titleKey), update.version),
            body: LocalizationManager.shared.t(bodyKey)
        ) { [weak self] in
            self?.showUpdateWindow()
        }
    }

    private var shouldShowQAUpdateWindow: Bool {
        Bundle.main.bundleIdentifier == "com.hxd.FlowWatch.UpdateQA"
            && UserDefaults.standard.bool(forKey: "update.qa.showWindow")
    }

    private func performQAActionIfNeeded() {
        guard !didPerformQAAction,
              Bundle.main.bundleIdentifier == "com.hxd.FlowWatch.UpdateQA",
              let action = UserDefaults.standard.string(forKey: "update.qa.action"),
              !action.isEmpty else { return }
        didPerformQAAction = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            LogManager.shared.log("Perform updater QA action: \(action)")
            switch action {
            case "installNow": self.installNow()
            case "installOnQuit": self.installOnQuit()
            case "remindLater": self.remindLater()
            case "skipVersion": self.skipVersion()
            default: break
            }
        }
    }

    nonisolated private static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = versionComponents(from: lhs)
        let right = versionComponents(from: rhs)
        for index in 0..<max(left.count, right.count) {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l < r { return .orderedAscending }
            if l > r { return .orderedDescending }
        }
        return .orderedSame
    }

    nonisolated private static func versionComponents(from version: String) -> [Int] {
        var components: [Int] = []
        var buffer = ""
        for char in version {
            if char.isNumber {
                buffer.append(char)
            } else if !buffer.isEmpty {
                components.append(Int(buffer) ?? 0)
                buffer.removeAll(keepingCapacity: true)
            }
        }
        if !buffer.isEmpty { components.append(Int(buffer) ?? 0) }
        return components
    }
}

extension UpdateManager: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let update = makeUpdateInfo(from: item)
        currentUpdate = update
        storeCachedLatestVersion(update.version)
        LogManager.shared.log("Sparkle update available: \(update.version)")
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        storeCachedLatestVersion(nil)
        currentUpdate = nil
        status = .upToDate
        LogManager.shared.log("Sparkle reports FlowWatch is up to date")
    }

    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        currentUpdate = makeUpdateInfo(from: item)
        if let cachedUpdateServerURL {
            request.url = cachedUpdateServerURL
            request.cachePolicy = .reloadIgnoringLocalCacheData
            LogManager.shared.log("Sparkle will verify the prefetched local update archive")
        }
        LogManager.shared.log("Sparkle is downloading update \(item.displayVersionString)")
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        let update = makeUpdateInfo(from: item)
        currentUpdate = update
        status = .readyToInstall(update)
        cacheServer.stop()
        cachedUpdateServerURL = nil
        LogManager.shared.log("Sparkle downloaded update \(item.displayVersionString)")
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        let update = makeUpdateInfo(from: item)
        currentUpdate = update
        status = installOnQuitAuthorized ? .installOnQuit(update) : .installing(update)
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        refreshSparkleScheduleDates()
        userInitiatedCheck = false
        if case .checking = status { status = .idle }
        if let error {
            LogManager.shared.log("Sparkle update cycle finished: \(error.localizedDescription)", level: .error)
        }
    }

    func updater(_ updater: SPUUpdater, willScheduleUpdateCheckAfterDelay delay: TimeInterval) {
        nextCheckDate = Date().addingTimeInterval(delay)
    }

    func updaterWillNotScheduleUpdateCheck(_ updater: SPUUpdater) {
        nextCheckDate = nil
    }

    func updater(
        _ updater: SPUUpdater,
        userDidMake choice: SPUUserUpdateChoice,
        forUpdate updateItem: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        LogManager.shared.log("Sparkle recorded update choice \(choice.rawValue) for \(updateItem.displayVersionString)")
    }

    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock: @escaping () -> Void
    ) -> Bool {
        guard installOnQuitAuthorized else { return false }
        self.immediateInstallationBlock = immediateInstallationBlock
        return true
    }
}
