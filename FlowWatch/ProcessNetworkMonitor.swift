import Foundation
import Combine
import AppKit

struct AppTrafficRate: Identifiable {
    let id: String
    let displayName: String
    let icon: NSImage?
    let isApp: Bool
    let downloadBps: Double
    let uploadBps: Double
    let totalDownloaded: UInt64
    let totalUploaded: UInt64
}

final class ProcessNetworkMonitor: ObservableObject {
    @Published var appTrafficRates: [AppTrafficRate] = []
    @Published var isEnabled: Bool = false

    private let enabledKey = "perAppMonitoring.enabled"
    private let intervalKey = "perAppMonitoring.sampleInterval"
    private var sampleInterval: TimeInterval {
        let stored = UserDefaults.standard.double(forKey: intervalKey)
        return stored >= 1 ? stored : 3.0
    }
    private let nettopTimeout: TimeInterval = 5.0
    private let maxConsecutiveFailures = 10

    private var consecutiveFailures = 0
    private var watchdogTimer: DispatchSourceTimer?
    private var lastSnapshot: [pid_t: (bytesIn: UInt64, bytesOut: UInt64)] = [:]
    private let resolver = AppInfoResolver.shared
    private let storage = ProcessTrafficStorage.shared
    private let queueKey = DispatchSpecificKey<UInt8>()
    private let queue = DispatchQueue(label: "com.flowwatch.processmonitor", qos: .utility)
    private var nettopProcess: Process?
    private var nettopPipe: Pipe?
    private var nettopBuffer = ""
    private var currentSampleLines: [String] = []
    private var lastSuccessfulSampleAt: Date?
    private var nettopStartedAt: Date?
    private var expectedTerminationPIDs: Set<pid_t> = []

    init() {
        queue.setSpecific(key: queueKey, value: 1)
        isEnabled = UserDefaults.standard.bool(forKey: enabledKey)
        if isEnabled {
            start()
        }
    }

    deinit {
        performOnQueueSync {
            stopMonitoring(logStop: false, clearPublishedRates: false)
        }
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: enabledKey)
        isEnabled = enabled
        if enabled {
            start()
        } else {
            stop()
        }
    }

    func updateInterval(_ interval: TimeInterval) {
        let clamped = min(max(interval, 1), 30)
        UserDefaults.standard.set(clamped, forKey: intervalKey)
        LogManager.shared.log("Per-app sample interval updated to \(clamped)s")
        performOnQueueSync {
            guard watchdogTimer != nil || nettopProcess != nil else { return }
            stopMonitoring(logStop: false, clearPublishedRates: false)
            startMonitoring()
        }
    }

    func start() {
        performOnQueueSync {
            startMonitoring()
        }
    }

    func stop() {
        performOnQueueSync {
            stopMonitoring(logStop: true, clearPublishedRates: true)
        }
    }

    func saveData() {
        storage.saveIfNeeded(force: true)
    }

    private func performOnQueue(_ work: @escaping () -> Void) {
        if DispatchQueue.getSpecific(key: queueKey) == 1 {
            work()
        } else {
            queue.async(execute: work)
        }
    }

    private func performOnQueueSync(_ work: () -> Void) {
        if DispatchQueue.getSpecific(key: queueKey) == 1 {
            work()
        } else {
            queue.sync(execute: work)
        }
    }

    private func startMonitoring() {
        guard watchdogTimer == nil, nettopProcess == nil else { return }
        LogManager.shared.log("ProcessNetworkMonitor started")
        consecutiveFailures = 0
        lastSnapshot.removeAll()
        resetStreamingState()
        launchNettopProcess()
        startWatchdog()
    }

    private func stopMonitoring(logStop: Bool, clearPublishedRates: Bool) {
        stopWatchdog()
        stopNettopProcess()
        lastSnapshot.removeAll()
        resetStreamingState()
        if clearPublishedRates {
            DispatchQueue.main.async { [weak self] in
                self?.appTrafficRates = []
            }
        }
        if logStop {
            LogManager.shared.log("ProcessNetworkMonitor stopped")
        }
    }

    private func resetStreamingState() {
        nettopBuffer.removeAll(keepingCapacity: false)
        currentSampleLines.removeAll(keepingCapacity: false)
        lastSuccessfulSampleAt = nil
        nettopStartedAt = nil
    }

    private func startWatchdog() {
        guard watchdogTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + watchdogThreshold, repeating: 1.0)
        timer.setEventHandler { [weak self] in
            self?.checkWatchdog()
        }
        timer.resume()
        watchdogTimer = timer
    }

    private func stopWatchdog() {
        watchdogTimer?.cancel()
        watchdogTimer = nil
    }

    private var watchdogThreshold: TimeInterval {
        sampleInterval + nettopTimeout
    }

    private func checkWatchdog() {
        guard let process = nettopProcess else { return }
        let referenceDate = lastSuccessfulSampleAt ?? nettopStartedAt ?? Date()
        let stallDuration = Date().timeIntervalSince(referenceDate)
        guard stallDuration > watchdogThreshold else { return }

        registerFailure(
            "nettop stream stalled for \(Int(stallDuration.rounded()))s, restarting (pid=\(process.processIdentifier))",
            level: .warn
        )
    }

    private func launchNettopProcess() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        process.arguments = [
            "-P",
            "-L", "0",
            "-s", String(Int(sampleInterval.rounded())),
            "-J", "bytes_in,bytes_out",
            "-n"
        ]

        let pipe = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self else { return }
            self.performOnQueue {
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    return
                }
                self.handleNettopOutput(data)
            }
        }

        process.terminationHandler = { [weak self] terminatedProcess in
            self?.performOnQueue {
                self?.handleNettopTermination(terminatedProcess)
            }
        }

        do {
            try process.run()
            pipe.fileHandleForWriting.closeFile()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            pipe.fileHandleForReading.closeFile()
            pipe.fileHandleForWriting.closeFile()
            registerFailure("nettop launch failed: \(error)", level: .error)
            return
        }

        nettopProcess = process
        nettopPipe = pipe
        nettopStartedAt = Date()
        lastSuccessfulSampleAt = nil
        LogManager.shared.log(
            "nettop stream started (pid=\(process.processIdentifier), interval=\(Int(sampleInterval.rounded()))s)"
        )
    }

    private func stopNettopProcess() {
        guard let process = nettopProcess else {
            nettopPipe?.fileHandleForReading.readabilityHandler = nil
            nettopPipe?.fileHandleForReading.closeFile()
            nettopPipe?.fileHandleForWriting.closeFile()
            nettopPipe = nil
            return
        }

        expectedTerminationPIDs.insert(process.processIdentifier)
        nettopProcess = nil

        let pipe = nettopPipe
        nettopPipe = nil
        pipe?.fileHandleForReading.readabilityHandler = nil
        pipe?.fileHandleForReading.closeFile()
        pipe?.fileHandleForWriting.closeFile()

        if process.isRunning {
            process.terminate()
            let pid = process.processIdentifier
            queue.asyncAfter(deadline: .now() + 0.5) {
                if process.isRunning {
                    kill(pid, SIGKILL)
                }
            }
        }
    }

    private func handleNettopTermination(_ process: Process) {
        let pid = process.processIdentifier

        if expectedTerminationPIDs.remove(pid) != nil {
            return
        }

        guard nettopProcess === process else { return }

        if currentSampleLines.count > 1 {
            flushCurrentSample()
        }

        nettopPipe?.fileHandleForReading.readabilityHandler = nil
        nettopPipe = nil
        nettopProcess = nil

        registerFailure(
            "nettop exited unexpectedly (pid=\(pid), reason=\(terminationReasonDescription(process.terminationReason)), status=\(process.terminationStatus))",
            level: .warn
        )
    }

    private func terminationReasonDescription(_ reason: Process.TerminationReason) -> String {
        switch reason {
        case .exit:
            return "exit"
        case .uncaughtSignal:
            return "signal"
        @unknown default:
            return "unknown"
        }
    }

    private func handleNettopOutput(_ data: Data) {
        nettopBuffer += String(decoding: data, as: UTF8.self)

        while let newlineIndex = nettopBuffer.firstIndex(of: "\n") {
            let line = String(nettopBuffer[..<newlineIndex])
            nettopBuffer.removeSubrange(...newlineIndex)
            consumeNettopLine(line)
        }
    }

    private func consumeNettopLine(_ rawLine: String) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }

        if isHeaderLine(line) {
            flushCurrentSample()
            currentSampleLines = [line]
            return
        }

        guard !currentSampleLines.isEmpty else { return }
        currentSampleLines.append(line)
    }

    private func isHeaderLine(_ line: String) -> Bool {
        let columns = line
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        return columns.contains("bytes_in") && columns.contains("bytes_out")
    }

    private func flushCurrentSample() {
        guard !currentSampleLines.isEmpty else { return }
        let output = currentSampleLines.joined(separator: "\n")
        currentSampleLines.removeAll(keepingCapacity: true)
        handleSampleOutput(output)
    }

    private func registerFailure(_ message: String, level: LogManager.Level) {
        consecutiveFailures += 1
        LogManager.shared.log(
            "\(message); consecutiveFailures=\(consecutiveFailures)",
            level: level
        )

        if consecutiveFailures >= maxConsecutiveFailures {
            LogManager.shared.log(
                "nettop consecutive failures reached \(consecutiveFailures), auto-stopping ProcessNetworkMonitor",
                level: .error
            )
            disableMonitoringDueToFailures()
            return
        }

        restartNettopProcess()
    }

    private func restartNettopProcess() {
        stopNettopProcess()
        resetStreamingState()
        lastSnapshot.removeAll()
        guard isEnabled else { return }
        launchNettopProcess()
    }

    private func disableMonitoringDueToFailures() {
        stopMonitoring(logStop: true, clearPublishedRates: true)
        UserDefaults.standard.set(false, forKey: enabledKey)
        DispatchQueue.main.async { [weak self] in
            self?.isEnabled = false
        }
    }

    private func handleSampleOutput(_ output: String) {
        consecutiveFailures = 0
        lastSuccessfulSampleAt = Date()

        let parsed = parseNettopOutput(output)

        let previous = lastSnapshot
        var newSnapshot: [pid_t: (bytesIn: UInt64, bytesOut: UInt64)] = [:]

        // Step 1: Compute delta per PID, then aggregate by bundleID
        var bundleDeltas: [String: (info: AppInfo, deltaIn: UInt64, deltaOut: UInt64)] = [:]

        for entry in parsed {
            newSnapshot[entry.pid] = (bytesIn: entry.bytesIn, bytesOut: entry.bytesOut)

            var deltaIn: UInt64 = 0
            var deltaOut: UInt64 = 0
            if let prev = previous[entry.pid] {
                deltaIn = entry.bytesIn >= prev.bytesIn ? entry.bytesIn - prev.bytesIn : 0
                deltaOut = entry.bytesOut >= prev.bytesOut ? entry.bytesOut - prev.bytesOut : 0
            }

            let info = resolver.resolve(pid: entry.pid, processName: entry.processName)
            let key = info.bundleID
            if var existing = bundleDeltas[key] {
                existing.deltaIn += deltaIn
                existing.deltaOut += deltaOut
                bundleDeltas[key] = existing
            } else {
                bundleDeltas[key] = (info: info, deltaIn: deltaIn, deltaOut: deltaOut)
            }
        }

        lastSnapshot = newSnapshot

        // Step 2: Persist deltas and build rates
        var rates: [AppTrafficRate] = []

        for (bundleID, data) in bundleDeltas {
            if data.deltaIn > 0 || data.deltaOut > 0 {
                storage.addBytes(
                    bundleID: bundleID,
                    displayName: data.info.displayName,
                    downloadBytes: data.deltaIn,
                    uploadBytes: data.deltaOut
                )
            }

            let todayRecord = storage.getTodayRecord(bundleID: bundleID)

            rates.append(AppTrafficRate(
                id: bundleID,
                displayName: data.info.displayName,
                icon: data.info.icon,
                isApp: data.info.isApp,
                downloadBps: Double(data.deltaIn) / sampleInterval,
                uploadBps: Double(data.deltaOut) / sampleInterval,
                totalDownloaded: todayRecord?.downloadBytes ?? 0,
                totalUploaded: todayRecord?.uploadBytes ?? 0
            ))
        }

        // Include apps from storage that aren't currently active
        for record in storage.getTodayRecords() {
            if bundleDeltas[record.bundleID] == nil {
                let info = resolver.resolve(pid: 0, processName: record.displayName)
                rates.append(AppTrafficRate(
                    id: record.bundleID,
                    displayName: record.displayName,
                    icon: info.icon,
                    isApp: info.isApp,
                    downloadBps: 0,
                    uploadBps: 0,
                    totalDownloaded: record.downloadBytes,
                    totalUploaded: record.uploadBytes
                ))
            }
        }

        rates.sort { ($0.totalDownloaded + $0.totalUploaded) > ($1.totalDownloaded + $1.totalUploaded) }

        DispatchQueue.main.async { [weak self] in
            self?.appTrafficRates = rates
        }
    }

    private struct NettopEntry {
        let pid: pid_t
        let processName: String
        let bytesIn: UInt64
        let bytesOut: UInt64
    }

    private func parseNettopOutput(_ output: String) -> [NettopEntry] {
        var entries: [NettopEntry] = []
        let lines = output.components(separatedBy: "\n")

        // nettop CSV format:
        // First line is header, subsequent lines are data
        // Format: "process.pid,bytes_in,bytes_out"
        var headerParsed = false
        var bytesInIndex = 1
        var bytesOutIndex = 2

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let columns = trimmed.components(separatedBy: ",")

            if !headerParsed {
                // Parse header to find column indices
                for (index, col) in columns.enumerated() {
                    let cleaned = col.trimmingCharacters(in: .whitespaces).lowercased()
                    if cleaned == "bytes_in" { bytesInIndex = index }
                    if cleaned == "bytes_out" { bytesOutIndex = index }
                }
                headerParsed = true
                continue
            }

            guard columns.count > max(bytesInIndex, bytesOutIndex) else { continue }

            let processField = columns[0].trimmingCharacters(in: .whitespaces)

            // Process field format: "processName.pid" (-P flag = process mode)
            guard let pidInfo = parseProcessField(processField) else { continue }

            let bytesIn = UInt64(columns[bytesInIndex].trimmingCharacters(in: .whitespaces)) ?? 0
            let bytesOut = UInt64(columns[bytesOutIndex].trimmingCharacters(in: .whitespaces)) ?? 0

            entries.append(NettopEntry(
                pid: pidInfo.pid,
                processName: pidInfo.name,
                bytesIn: bytesIn,
                bytesOut: bytesOut
            ))
        }

        return entries
    }

    private func parseProcessField(_ field: String) -> (name: String, pid: pid_t)? {
        // Format: "processName.PID" — split on last dot
        guard let lastDotIndex = field.lastIndex(of: ".") else { return nil }
        let name = String(field[field.startIndex..<lastDotIndex])
        let pidString = String(field[field.index(after: lastDotIndex)...])
        guard let pid = pid_t(pidString) else { return nil }
        return (name: name, pid: pid)
    }
}
