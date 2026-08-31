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
    enum UpdateStatus: Equatable {
        case idle
        case checking
        case updating
        case upToDate
        case updateAvailable(version: String)
        case failed(message: String)
    }

    @Published private(set) var status: UpdateStatus = .idle
    @Published private(set) var lastCheckDate: Date?
    @Published private(set) var nextCheckDate: Date?
    @Published private(set) var cachedLatestVersion: String?
    @Published private(set) var canCheckForUpdates = false

    var usesIntegratedUpdater: Bool {
        installMethod == .dmg
    }

    private let installMethod: InstallMethod
    private let lastCheckKey = "update.lastCheckTimestamp"
    private let autoCheckEnabledKey = "update.autoCheckEnabled"
    private let cachedLatestVersionKey = "update.cachedLatestVersion"
    private let autoCheckInterval: TimeInterval = 60 * 60 * 24
    private let initialAutoCheckDelay: TimeInterval = 5
    private let homebrewFormula = "flowwatch"
    private let notificationCenter = UpdateNotificationCenter.shared
    private var autoCheckTimer: Timer?
    private var updaterController: SPUStandardUpdaterController?
    private var canCheckForUpdatesObservation: NSKeyValueObservation?

    init(installMethod: InstallMethod = InstallMethodDetector.detect()) {
        self.installMethod = installMethod
        super.init()
        LogManager.shared.log("UpdateManager initialized with install method: \(installMethod.rawValue)")
        loadLastCheckDate()
        loadCachedLatestVersion()
        clearCachedVersionIfNeeded()
        configureUpdater()
        startAutomaticUpdateChecks()
        NotificationCenter.default.addObserver(self, selector: #selector(handleUserDefaultsChanged), name: UserDefaults.didChangeNotification, object: nil)
    }

    func checkForUpdates(userInitiated: Bool) {
        LogManager.shared.log("Check for updates (userInitiated=\(userInitiated))")
        switch installMethod {
        case .homebrew:
            recordLastCheck()
            checkHomebrew(userInitiated: userInitiated)
        case .dmg:
            checkSparkle(userInitiated: userInitiated)
        }
    }

    func checkForUpdatesIfNeeded() {
        guard installMethod == .homebrew else { return }
        guard shouldAutoCheck() else { return }
        checkForUpdates(userInitiated: false)
    }

    func startAutomaticUpdateChecks() {
        switch installMethod {
        case .homebrew:
            canCheckForUpdates = status != .updating
            scheduleAutoCheckTimer()
        case .dmg:
            applySparkleUpdatePreferences()
            refreshSparkleScheduleDates()
        }
    }

    func performCachedUpdateAction() -> Bool {
        guard cachedLatestVersion != nil else { return false }
        guard canCheckForUpdates, status != .checking else { return false }
        LogManager.shared.log("Perform cached update action (installMethod=\(installMethod))")
        switch installMethod {
        case .homebrew:
            copyBrewUpgradeCommand()
        case .dmg:
            checkSparkle(userInitiated: true)
        }
        return true
    }

    private func configureUpdater() {
        guard installMethod == .dmg else { return }
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        updaterController = controller
        canCheckForUpdatesObservation = controller.updater.observe(
            \.canCheckForUpdates,
            options: [.initial, .new]
        ) { [weak self] updater, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.canCheckForUpdates = updater.canCheckForUpdates
                if updater.canCheckForUpdates {
                    self.applySparkleUpdatePreferences()
                    self.refreshSparkleScheduleDates()
                }
            }
        }
        DispatchQueue.main.async { [weak self] in
            self?.applySparkleUpdatePreferences()
            self?.refreshSparkleScheduleDates()
        }
    }

    private func applySparkleUpdatePreferences() {
        guard let updater = updaterController?.updater else { return }
        let automaticUpdatesEnabled = isAutoCheckEnabled()
        var didChange = false
        if updater.automaticallyChecksForUpdates != automaticUpdatesEnabled {
            updater.automaticallyChecksForUpdates = automaticUpdatesEnabled
            didChange = true
        }
        if updater.automaticallyDownloadsUpdates != automaticUpdatesEnabled {
            updater.automaticallyDownloadsUpdates = automaticUpdatesEnabled
            didChange = true
        }
        if didChange {
            LogManager.shared.log("Sparkle automatic checks and installs enabled: \(automaticUpdatesEnabled)")
        }
    }

    private func checkSparkle(userInitiated: Bool) {
        guard let updaterController else {
            status = .failed(message: LocalizationManager.shared.t("update.dmg.unavailable"))
            return
        }
        guard updaterController.updater.canCheckForUpdates else {
            LogManager.shared.log("Sparkle update check is not ready")
            return
        }
        status = .checking
        LogManager.shared.log("Starting Sparkle update check (userInitiated=\(userInitiated))")
        if userInitiated {
            updaterController.checkForUpdates(nil)
        } else if updaterController.updater.automaticallyChecksForUpdates {
            updaterController.updater.checkForUpdatesInBackground()
        }
    }

    private func checkHomebrew(userInitiated: Bool) {
        status = .checking
        let currentVersion = AppVersion.shortVersion
        let formula = homebrewFormula
        LogManager.shared.log("Checking Homebrew updates (currentVersion=\(currentVersion), userInitiated=\(userInitiated))")
        Task.detached { [weak self] in
            do {
                let latestVersion = try Self.fetchHomebrewVersion(formula: formula)
                let isNewer = Self.compareVersions(latestVersion, currentVersion) == .orderedDescending
                await MainActor.run {
                    guard let self else { return }
                    if isNewer {
                        let shouldNotify = self.cachedLatestVersion != latestVersion
                        self.storeCachedLatestVersion(latestVersion)
                        LogManager.shared.log("Homebrew update available: \(latestVersion)")
                        self.status = .updateAvailable(version: latestVersion)
                        if shouldNotify {
                            self.notifyHomebrewUpdateAvailable(version: latestVersion)
                        }
                    } else {
                        self.storeCachedLatestVersion(nil)
                        self.status = .upToDate
                        LogManager.shared.log("Homebrew is up to date")
                        if userInitiated {
                            self.notifyUpToDate()
                        }
                        self.status = .idle
                    }
                }
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    self.status = .failed(message: self.message(for: error))
                    self.notifyCheckFailed(message: self.message(for: error))
                    LogManager.shared.log("Homebrew update check failed: \(error)", level: .error)
                    self.status = .idle
                }
            }
        }
    }

    private func notifyUpToDate() {
        notificationCenter.post(
            title: LocalizationManager.shared.t("update.check.upToDate.title"),
            body: LocalizationManager.shared.t("update.check.upToDate.message")
        )
    }

    private func notifyCheckFailed(message: String) {
        notificationCenter.post(
            title: LocalizationManager.shared.t("update.check.failed.title"),
            body: String(format: LocalizationManager.shared.t("update.check.failed.message"), message)
        )
    }

    private func notifyUpdateAvailable(version: String, messageKey: String, primaryAction: @escaping () -> Void) {
        notificationCenter.post(
            title: String(format: LocalizationManager.shared.t("update.available.title"), version),
            body: LocalizationManager.shared.t(messageKey),
            action: primaryAction
        )
    }


    private func notifyHomebrewUpdateAvailable(version: String) {
        let messageKey = "update.available.message.brew"
        notifyUpdateAvailable(version: version, messageKey: messageKey) { [weak self] in
            self?.copyBrewUpgradeCommand()
        }
    }
    private func copyBrewUpgradeCommand() {
        let command = "brew upgrade \(homebrewFormula)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        LogManager.shared.log("Copied brew upgrade command to clipboard")
        notificationCenter.post(
            title: LocalizationManager.shared.t("update.command.copied"),
            body: LocalizationManager.shared.t("update.command.copied.message")
        )
    }

    private func recordLastCheck() {
        let now = Date()
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: lastCheckKey)
        lastCheckDate = now
        if installMethod == .homebrew {
            scheduleAutoCheckTimer()
        }
    }

    private func shouldAutoCheck() -> Bool {
        guard isAutoCheckEnabled() else { return false }
        let lastTimestamp = UserDefaults.standard.double(forKey: lastCheckKey)
        if lastTimestamp <= 0 {
            return true
        }
        let lastDate = Date(timeIntervalSince1970: lastTimestamp)
        return Date().timeIntervalSince(lastDate) >= autoCheckInterval
    }

    private func isAutoCheckEnabled() -> Bool {
        if UserDefaults.standard.object(forKey: autoCheckEnabledKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: autoCheckEnabledKey)
    }

    private func loadLastCheckDate() {
        let timestamp = UserDefaults.standard.double(forKey: lastCheckKey)
        if timestamp > 0 {
            lastCheckDate = Date(timeIntervalSince1970: timestamp)
        } else {
            lastCheckDate = nil
        }
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
        }
    }

    private func scheduleAutoCheckTimer() {
        autoCheckTimer?.invalidate()
        autoCheckTimer = nil
        guard installMethod == .homebrew else { return }

        let now = Date()

        // 检查是否已经错过了应该执行的检查
        if shouldAutoCheck() {
            LogManager.shared.log("Missed auto check detected, triggering immediate check")
            // 延迟一小段时间执行，避免应用启动时立即执行
            autoCheckTimer = Timer.scheduledTimer(withTimeInterval: initialAutoCheckDelay, repeats: false) { [weak self] _ in
                self?.handleAutoCheckTimerFired()
            }
            nextCheckDate = now.addingTimeInterval(initialAutoCheckDelay)
            return
        }

        guard let nextDate = computeNextCheckDate(now: now) else {
            nextCheckDate = nil
            LogManager.shared.log("Auto check disabled or not scheduled")
            return
        }
        if let existingNext = nextCheckDate, abs(existingNext.timeIntervalSince(nextDate)) < 1 {
            return
        }
        nextCheckDate = nextDate
        let interval = max(1, nextDate.timeIntervalSinceNow)
        autoCheckTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.handleAutoCheckTimerFired()
        }
        LogManager.shared.log("Next auto check scheduled at \(nextDate)")
    }

    private func computeNextCheckDate(now: Date) -> Date? {
        guard isAutoCheckEnabled() else { return nil }
        guard let lastCheckDate else {
            return now.addingTimeInterval(initialAutoCheckDelay)
        }
        var next = lastCheckDate.addingTimeInterval(autoCheckInterval)
        while next <= now {
            next = next.addingTimeInterval(autoCheckInterval)
        }
        return next
    }

    private func refreshSparkleScheduleDates() {
        guard installMethod == .dmg,
              let updater = updaterController?.updater else { return }
        if let sparkleLastCheckDate = updater.lastUpdateCheckDate {
            lastCheckDate = sparkleLastCheckDate
        }
        guard updater.automaticallyChecksForUpdates else {
            nextCheckDate = nil
            return
        }
        let baseDate = updater.lastUpdateCheckDate ?? Date()
        nextCheckDate = baseDate.addingTimeInterval(updater.updateCheckInterval)
    }

    private func handleAutoCheckTimerFired() {
        guard isAutoCheckEnabled() else {
            scheduleAutoCheckTimer()
            return
        }
        LogManager.shared.log("Auto check timer fired")
        checkForUpdates(userInitiated: false)
    }

    @objc private func handleUserDefaultsChanged() {
        let keysToCheck = installMethod == .homebrew
            ? [autoCheckEnabledKey, lastCheckKey]
            : [autoCheckEnabledKey]
        let currentState = defaultsSignature(for: keysToCheck)
        if let lastDefaultsSignature, lastDefaultsSignature == currentState {
            return
        }
        lastDefaultsSignature = currentState
        loadLastCheckDate()
        loadCachedLatestVersion()
        clearCachedVersionIfNeeded()
        startAutomaticUpdateChecks()
    }

    private func defaultsSignature(for keys: [String]) -> String {
        let defaults = UserDefaults.standard
        return keys.map { key in
            if key == autoCheckEnabledKey {
                let value = defaults.bool(forKey: key)
                return "\(key)=\(value)"
            }
            if key == lastCheckKey {
                let value = defaults.double(forKey: key)
                return "\(key)=\(value)"
            }
            return "\(key)="
        }.joined(separator: ";")
    }

    private var lastDefaultsSignature: String?

    private func message(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut:
                return LocalizationManager.shared.t("update.network.error")
            default:
                break
            }
        }
        if let brewError = error as? HomebrewError {
            switch brewError {
            case .notFound:
                return LocalizationManager.shared.t("update.brew.notFound")
            case .invalidOutput:
                return LocalizationManager.shared.t("update.check.failed.title")
            case .commandFailed(let message):
                if message.isEmpty {
                    return LocalizationManager.shared.t("update.check.failed.title")
                }
                return String(format: LocalizationManager.shared.t("update.brew.commandFailed"), message)
            }
        }
        return error.localizedDescription
    }

    nonisolated private static func fetchHomebrewVersion(formula: String) throws -> String {
        // Refresh all tap indexes before checking version (15s timeout, skip on failure)
        _ = try? runBrew(arguments: ["update"], timeout: 15)
        let output = try runBrew(arguments: ["info", "--json=v2", formula])
        let data = Data(output.utf8)
        let response = try JSONDecoder().decode(BrewInfoResponse.self, from: data)
        if let stable = response.formulae.first?.versions?.stable, !stable.isEmpty {
            return stable
        }
        if let caskVersion = response.casks.first?.version, !caskVersion.isEmpty {
            return caskVersion
        }
        throw HomebrewError.invalidOutput
    }

    nonisolated private static func runBrew(arguments: [String], timeout: TimeInterval? = nil) throws -> String {
        guard let brewURL = brewExecutableURL() else {
            throw HomebrewError.notFound
        }

        let process = Process()
        process.executableURL = brewURL
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            throw HomebrewError.commandFailed(error.localizedDescription)
        }

        // Read pipe data asynchronously to avoid deadlock when output exceeds pipe buffer
        var outputData = Data()
        let readGroup = DispatchGroup()
        readGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            outputData = pipe.fileHandleForReading.readDataToEndOfFile()
            readGroup.leave()
        }

        if let timeout {
            let semaphore = DispatchSemaphore(value: 0)
            DispatchQueue.global(qos: .utility).async {
                process.waitUntilExit()
                semaphore.signal()
            }
            if semaphore.wait(timeout: .now() + timeout) == .timedOut {
                process.terminate()
                throw HomebrewError.commandFailed("timed out after \(Int(timeout))s")
            }
        } else {
            process.waitUntilExit()
        }

        readGroup.wait()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            throw HomebrewError.commandFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output
    }

    nonisolated private static func brewExecutableURL() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew",
            "/usr/bin/brew"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    nonisolated private static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = versionComponents(from: lhs)
        let right = versionComponents(from: rhs)
        let maxCount = max(left.count, right.count)
        for index in 0..<maxCount {
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
        if !buffer.isEmpty {
            components.append(Int(buffer) ?? 0)
        }
        return components
    }
}

extension UpdateManager: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        storeCachedLatestVersion(version)
        status = .updateAvailable(version: version)
        LogManager.shared.log("Sparkle update available: \(version)")
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        storeCachedLatestVersion(nil)
        status = .upToDate
        LogManager.shared.log("Sparkle reports FlowWatch is up to date")
    }

    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        status = .updating
        LogManager.shared.log("Sparkle is downloading update \(item.displayVersionString)")
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        status = .updating
        LogManager.shared.log("Sparkle is installing update \(item.displayVersionString)")
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        refreshSparkleScheduleDates()
        if case .checking = status {
            status = .idle
        } else if case .updating = status,
                  let cachedLatestVersion {
            status = .updateAvailable(version: cachedLatestVersion)
        }
        if case .upToDate = status {
            LogManager.shared.log("Sparkle update cycle finished: no update available")
        } else if let error {
            LogManager.shared.log("Sparkle update cycle finished: \(error.localizedDescription)", level: .error)
        } else {
            LogManager.shared.log("Sparkle update cycle finished")
        }
    }

    func updater(_ updater: SPUUpdater, willScheduleUpdateCheckAfterDelay delay: TimeInterval) {
        nextCheckDate = Date().addingTimeInterval(delay)
    }

    func updaterWillNotScheduleUpdateCheck(_ updater: SPUUpdater) {
        nextCheckDate = nil
    }
}

private enum HomebrewError: Error {
    case notFound
    case invalidOutput
    case commandFailed(String)
}

private struct BrewInfoResponse: Decodable {
    let formulae: [BrewFormula]
    let casks: [BrewCask]
}

private struct BrewFormula: Decodable {
    let versions: BrewVersions?
}

private struct BrewVersions: Decodable {
    let stable: String?
}

private struct BrewCask: Decodable {
    let version: String?
}
