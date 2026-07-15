//
//  UpdateManager.swift
//  FlowWatch
//
//  Created by xida huang on 1/22/26.
//

import AppKit
import Combine
import Foundation

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

    private let installMethod: InstallMethod
    private let lastCheckKey = "update.lastCheckTimestamp"
    private let autoCheckEnabledKey = "update.autoCheckEnabled"
    private let cachedLatestVersionKey = "update.cachedLatestVersion"
    private let cachedReleaseURLKey = "update.cachedReleaseURL"
    private let cachedDownloadURLKey = "update.cachedDownloadURL"
    private let autoCheckInterval: TimeInterval = 60 * 60 * 24
    private let initialAutoCheckDelay: TimeInterval = 5
    private let homebrewFormula = "flowwatch"
    private let notificationCenter = UpdateNotificationCenter.shared
    private static let githubReleaseAPIURL = URL(string: "https://api.github.com/repos/W1tFzQq08pTv/FlowWatch/releases/latest")
    private static let githubReleasePageURL = "https://github.com/W1tFzQq08pTv/FlowWatch/releases/latest"
    private static let githubUserAgent = "FlowWatch"
    private var autoCheckTimer: Timer?
    private var cachedReleaseURL: String?
    private var cachedDownloadURL: String?

    init(installMethod: InstallMethod = InstallMethodDetector.detect()) {
        self.installMethod = installMethod
        super.init()
        LogManager.shared.log("UpdateManager initialized with install method: \(installMethod.rawValue)")
        loadLastCheckDate()
        loadCachedLatestVersion()
        clearCachedVersionIfNeeded()
        scheduleAutoCheckTimer()
        NotificationCenter.default.addObserver(self, selector: #selector(handleUserDefaultsChanged), name: UserDefaults.didChangeNotification, object: nil)
    }

    var canCheckForUpdates: Bool {
        switch installMethod {
        case .homebrew:
            return status != .updating
        case .dmg:
            return status != .updating
        }
    }

    func checkForUpdates(userInitiated: Bool) {
        LogManager.shared.log("Check for updates (userInitiated=\(userInitiated))")
        recordLastCheck()
        switch installMethod {
        case .homebrew:
            checkHomebrew(userInitiated: userInitiated)
        case .dmg:
            checkGitHubRelease(userInitiated: userInitiated)
        }
    }

    func checkForUpdatesIfNeeded() {
        guard shouldAutoCheck() else { return }
        checkForUpdates(userInitiated: false)
    }

    func startAutomaticUpdateChecks() {
        scheduleAutoCheckTimer()
    }

    func performCachedUpdateAction() -> Bool {
        guard cachedLatestVersion != nil else { return false }
        guard canCheckForUpdates, status != .checking else { return false }
        LogManager.shared.log("Perform cached update action (installMethod=\(installMethod))")
        switch installMethod {
        case .homebrew:
            copyBrewUpgradeCommand()
        case .dmg:
            openUpdateURL(releaseURLString: cachedReleaseURL, downloadURLString: cachedDownloadURL)
        }
        return true
    }

    private func checkGitHubRelease(userInitiated: Bool) {
        status = .checking
        let currentVersion = AppVersion.shortVersion
        LogManager.shared.log("Checking GitHub release (currentVersion=\(currentVersion), userInitiated=\(userInitiated))")
        Task.detached { [weak self] in
            do {
                let release = try await Self.fetchLatestRelease()
                let latestVersion = Self.normalizedVersion(release.tagName)
                guard !latestVersion.isEmpty else {
                    throw GitHubUpdateError.invalidRelease
                }
                let isNewer = Self.compareVersions(latestVersion, currentVersion) == .orderedDescending
                await MainActor.run {
                    guard let self else { return }
                    if isNewer {
                        let shouldNotify = self.cachedLatestVersion != latestVersion
                        self.storeCachedLatestRelease(
                            version: latestVersion,
                            releaseURL: release.htmlURL,
                            downloadURL: release.dmgDownloadURL
                        )
                        LogManager.shared.log("GitHub release update available: \(latestVersion)")
                        self.status = .updateAvailable(version: latestVersion)
                        if shouldNotify {
                            self.notifyGitHubUpdateAvailable(
                                version: latestVersion,
                                releaseURLString: release.htmlURL,
                                downloadURLString: release.dmgDownloadURL
                            )
                        }
                    } else {
                        self.storeCachedLatestRelease(version: nil, releaseURL: nil, downloadURL: nil)
                        self.status = .upToDate
                        LogManager.shared.log("GitHub release is up to date")
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
                    LogManager.shared.log("GitHub update check failed: \(error)", level: .error)
                    self.status = .idle
                }
            }
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
                        self.storeCachedLatestRelease(version: latestVersion, releaseURL: nil, downloadURL: nil)
                        LogManager.shared.log("Homebrew update available: \(latestVersion)")
                        self.status = .updateAvailable(version: latestVersion)
                        if shouldNotify {
                            self.notifyHomebrewUpdateAvailable(version: latestVersion)
                        }
                    } else {
                        self.storeCachedLatestRelease(version: nil, releaseURL: nil, downloadURL: nil)
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

    private func notifyGitHubUpdateAvailable(version: String, releaseURLString: String?, downloadURLString: String?) {
        let messageKey = "update.available.message.dmg"
        notifyUpdateAvailable(version: version, messageKey: messageKey) { [weak self] in
            LogManager.shared.log("Open GitHub release page (version=\(version))")
            self?.openUpdateURL(releaseURLString: releaseURLString, downloadURLString: downloadURLString)
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

    private func openUpdateURL(releaseURLString: String?, downloadURLString _: String?) {
        let fallback = Self.githubReleasePageURL
        let urlString = releaseURLString ?? fallback
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    private func recordLastCheck() {
        let now = Date()
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: lastCheckKey)
        lastCheckDate = now
        scheduleAutoCheckTimer()
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
        cachedReleaseURL = UserDefaults.standard.string(forKey: cachedReleaseURLKey)
        cachedDownloadURL = UserDefaults.standard.string(forKey: cachedDownloadURLKey)
    }

    private func storeCachedLatestRelease(version: String?, releaseURL: String?, downloadURL: String?) {
        if let version {
            UserDefaults.standard.set(version, forKey: cachedLatestVersionKey)
            if let releaseURL {
                UserDefaults.standard.set(releaseURL, forKey: cachedReleaseURLKey)
            } else {
                UserDefaults.standard.removeObject(forKey: cachedReleaseURLKey)
            }
            if let downloadURL {
                UserDefaults.standard.set(downloadURL, forKey: cachedDownloadURLKey)
            } else {
                UserDefaults.standard.removeObject(forKey: cachedDownloadURLKey)
            }
        } else {
            UserDefaults.standard.removeObject(forKey: cachedLatestVersionKey)
            UserDefaults.standard.removeObject(forKey: cachedReleaseURLKey)
            UserDefaults.standard.removeObject(forKey: cachedDownloadURLKey)
        }
        cachedLatestVersion = version
        cachedReleaseURL = releaseURL
        cachedDownloadURL = downloadURL
    }

    private func clearCachedVersionIfNeeded() {
        guard let cachedLatestVersion else { return }
        if Self.compareVersions(cachedLatestVersion, AppVersion.shortVersion) != .orderedDescending {
            storeCachedLatestRelease(version: nil, releaseURL: nil, downloadURL: nil)
        }
    }

    private func scheduleAutoCheckTimer() {
        autoCheckTimer?.invalidate()
        autoCheckTimer = nil

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

    private func handleAutoCheckTimerFired() {
        guard isAutoCheckEnabled() else {
            scheduleAutoCheckTimer()
            return
        }
        LogManager.shared.log("Auto check timer fired")
        checkForUpdates(userInitiated: false)
    }

    @objc private func handleUserDefaultsChanged() {
        let keysToCheck = [autoCheckEnabledKey, lastCheckKey]
        let currentState = defaultsSignature(for: keysToCheck)
        if let lastDefaultsSignature, lastDefaultsSignature == currentState {
            return
        }
        lastDefaultsSignature = currentState
        loadLastCheckDate()
        loadCachedLatestVersion()
        clearCachedVersionIfNeeded()
        scheduleAutoCheckTimer()
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

    nonisolated private static func fetchLatestRelease() async throws -> GitHubRelease {
        do {
            return try await fetchLatestReleaseFromAPI()
        } catch {
            return try await fetchLatestReleaseFromRedirect()
        }
    }

    nonisolated private static func fetchLatestReleaseFromAPI() async throws -> GitHubRelease {
        guard let url = githubReleaseAPIURL else {
            throw GitHubUpdateError.invalidRelease
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(githubUserAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubUpdateError.invalidRelease
        }
        if httpResponse.statusCode == 403,
           httpResponse.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0" {
            throw GitHubUpdateError.rateLimited
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw GitHubUpdateError.invalidRelease
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(GitHubRelease.self, from: data)
    }

    nonisolated private static func fetchLatestReleaseFromRedirect() async throws -> GitHubRelease {
        guard let url = URL(string: githubReleasePageURL) else {
            throw GitHubUpdateError.invalidRelease
        }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let finalURL = response.url else {
            throw GitHubUpdateError.invalidRelease
        }
        let tag = finalURL.lastPathComponent
        guard !tag.isEmpty else {
            throw GitHubUpdateError.invalidRelease
        }
        let htmlURL = "https://github.com/W1tFzQq08pTv/FlowWatch/releases/tag/\(tag)"
        let downloadURL = "https://github.com/W1tFzQq08pTv/FlowWatch/releases/download/\(tag)/FlowWatch.dmg"
        let asset = GitHubAsset(name: "FlowWatch.dmg", browserDownloadURL: downloadURL)
        return GitHubRelease(tagName: tag, htmlURL: htmlURL, assets: [asset])
    }

    nonisolated private static func normalizedVersion(_ version: String) -> String {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }

    private func message(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut:
                return LocalizationManager.shared.t("update.network.error")
            default:
                break
            }
        }
        if let githubError = error as? GitHubUpdateError {
            switch githubError {
            case .invalidRelease:
                return LocalizationManager.shared.t("update.github.invalidRelease")
            case .rateLimited:
                return LocalizationManager.shared.t("update.github.rateLimited")
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

private enum HomebrewError: Error {
    case notFound
    case invalidOutput
    case commandFailed(String)
}

private enum GitHubUpdateError: Error {
    case invalidRelease
    case rateLimited
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String
    let assets: [GitHubAsset]

    init(tagName: String, htmlURL: String, assets: [GitHubAsset]) {
        self.tagName = tagName
        self.htmlURL = htmlURL
        self.assets = assets
    }

    var dmgDownloadURL: String? {
        assets.first { $0.name.lowercased().hasSuffix(".dmg") }?.browserDownloadURL
    }

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets
    }
}

private struct GitHubAsset: Decodable {
    let name: String
    let browserDownloadURL: String

    init(name: String, browserDownloadURL: String) {
        self.name = name
        self.browserDownloadURL = browserDownloadURL
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
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
