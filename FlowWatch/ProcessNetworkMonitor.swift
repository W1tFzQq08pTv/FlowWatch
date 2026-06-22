import AppKit
import Combine
import Darwin
import Foundation

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
    private let nettopTimeout: TimeInterval = 5.0
    private let maxConsecutiveFailures = 10

    private var sampleInterval: TimeInterval {
        let stored = UserDefaults.standard.double(forKey: intervalKey)
        return stored >= 1 ? stored : 3.0
    }

    private var consecutiveFailures = 0
    private var sampleTimer: DispatchSourceTimer?
    private var sampleTimeoutWorkItem: DispatchWorkItem?
    private var lastSnapshot: [pid_t: (bytesIn: UInt64, bytesOut: UInt64)] = [:]
    private var lastSuccessfulSampleAt: Date?
    private let resolver = AppInfoResolver.shared
    private let storage = ProcessTrafficStorage.shared
    private let queueKey = DispatchSpecificKey<UInt8>()
    private let queue = DispatchQueue(label: "com.flowwatch.processmonitor", qos: .utility)
    private var activeSampleContext: SampleContext?
    private var expectedTerminationPIDs: Set<pid_t> = []

    private final class SampleContext {
        let process: Process
        let outputPipe: Pipe
        let errorPipe: Pipe

        private let lock = NSLock()
        private var outputBuffer = Data()
        private var errorBuffer = Data()

        init(process: Process, outputPipe: Pipe, errorPipe: Pipe) {
            self.process = process
            self.outputPipe = outputPipe
            self.errorPipe = errorPipe
        }

        func consumeAvailableData(from handle: FileHandle, isError: Bool) -> Bool {
            lock.lock()
            let data = handle.availableData
            guard !data.isEmpty else {
                lock.unlock()
                return false
            }
            if isError {
                errorBuffer.append(data)
            } else {
                outputBuffer.append(data)
            }
            lock.unlock()
            return true
        }

        func stopReading() {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
        }

        func drainBuffers() -> (output: Data, error: Data) {
            lock.lock()
            var output = outputBuffer
            var error = errorBuffer
            outputBuffer.removeAll(keepingCapacity: false)
            errorBuffer.removeAll(keepingCapacity: false)
            output.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
            error.append(errorPipe.fileHandleForReading.readDataToEndOfFile())
            lock.unlock()
            return (output: output, error: error)
        }
    }

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
            guard sampleTimer != nil || activeSampleContext != nil else { return }
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
        guard sampleTimer == nil, activeSampleContext == nil else { return }
        LogManager.shared.log("ProcessNetworkMonitor started")
        consecutiveFailures = 0
        lastSnapshot.removeAll()
        lastSuccessfulSampleAt = nil
        startSampleTimer()
        runSampleIfNeeded()
    }

    private func stopMonitoring(logStop: Bool, clearPublishedRates: Bool) {
        stopSampleTimer()
        stopActiveSample()
        lastSnapshot.removeAll()
        lastSuccessfulSampleAt = nil
        if clearPublishedRates {
            DispatchQueue.main.async { [weak self] in
                self?.appTrafficRates = []
            }
        }
        if logStop {
            LogManager.shared.log("ProcessNetworkMonitor stopped")
        }
    }

    private func startSampleTimer() {
        guard sampleTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + sampleInterval, repeating: sampleInterval)
        timer.setEventHandler { [weak self] in
            self?.runSampleIfNeeded()
        }
        timer.resume()
        sampleTimer = timer
    }

    private func stopSampleTimer() {
        sampleTimer?.cancel()
        sampleTimer = nil
    }

    private func runSampleIfNeeded() {
        guard isEnabled, activeSampleContext == nil else { return }
        launchSampleProcess()
    }

    private func launchSampleProcess() {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let context = SampleContext(process: process, outputPipe: outputPipe, errorPipe: errorPipe)

        process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        process.arguments = [
            "-P",
            "-L", "1",
            "-J", "bytes_in,bytes_out",
            "-n"
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        startReading(from: outputPipe.fileHandleForReading, context: context, isError: false)
        startReading(from: errorPipe.fileHandleForReading, context: context, isError: true)
        process.terminationHandler = { [weak self] finishedProcess in
            self?.performOnQueue {
                self?.handleSampleTermination(
                    finishedProcess,
                    context: context
                )
            }
        }

        activeSampleContext = context

        do {
            try process.run()
            scheduleSampleTimeout(for: context)
        } catch {
            activeSampleContext = nil
            context.stopReading()
            registerFailure("nettop launch failed: \(error)", level: .error)
        }
    }

    private func startReading(from handle: FileHandle, context: SampleContext, isError: Bool) {
        handle.readabilityHandler = { readableHandle in
            let hasData = context.consumeAvailableData(from: readableHandle, isError: isError)
            if !hasData {
                readableHandle.readabilityHandler = nil
            }
        }
    }

    private func scheduleSampleTimeout(for context: SampleContext) {
        cancelSampleTimeout()
        let timeoutWorkItem = DispatchWorkItem { [weak self, weak context] in
            guard let self, let context else { return }
            guard self.activeSampleContext === context else { return }

            let process = context.process
            let pid = process.processIdentifier
            self.expectedTerminationPIDs.insert(pid)
            self.activeSampleContext = nil
            self.cancelSampleTimeout()

            if process.isRunning {
                process.terminate()
                self.queue.asyncAfter(deadline: .now() + 0.5) {
                    if process.isRunning {
                        kill(pid, SIGKILL)
                    }
                }
            }

            self.registerFailure("nettop single sample timed out (pid=\(pid))", level: .warn)
        }
        sampleTimeoutWorkItem = timeoutWorkItem
        queue.asyncAfter(deadline: .now() + nettopTimeout, execute: timeoutWorkItem)
    }

    private func cancelSampleTimeout() {
        sampleTimeoutWorkItem?.cancel()
        sampleTimeoutWorkItem = nil
    }

    private func stopActiveSample() {
        cancelSampleTimeout()

        guard let context = activeSampleContext else { return }
        activeSampleContext = nil

        let process = context.process
        let pid = process.processIdentifier
        expectedTerminationPIDs.insert(pid)

        if process.isRunning {
            process.terminate()
            queue.asyncAfter(deadline: .now() + 0.5) {
                if process.isRunning {
                    kill(pid, SIGKILL)
                }
            }
        }
    }

    private func handleSampleTermination(
        _ process: Process,
        context: SampleContext
    ) {
        if activeSampleContext === context {
            activeSampleContext = nil
            cancelSampleTimeout()
        }

        context.stopReading()

        let pid = process.processIdentifier
        let drained = context.drainBuffers()
        let output = String(decoding: drained.output, as: UTF8.self)
        let errorOutput = String(decoding: drained.error, as: UTF8.self)
        let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedErrorOutput = errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)

        if expectedTerminationPIDs.remove(pid) != nil {
            return
        }

        guard isEnabled else { return }

        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            var message = "nettop single sample exited unexpectedly (pid=\(pid), reason=\(terminationReasonDescription(process.terminationReason)), status=\(process.terminationStatus))"
            if !trimmedErrorOutput.isEmpty {
                message += ", stderr=\(trimmedErrorOutput)"
            }
            registerFailure(message, level: .warn)
            return
        }

        guard !trimmedOutput.isEmpty else {
            registerFailure("nettop single sample returned empty output (pid=\(pid))", level: .warn)
            return
        }

        handleSampleOutput(trimmedOutput, sampledAt: Date())
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

    private func registerFailure(_ message: String, level: LogManager.Level) {
        consecutiveFailures += 1
        lastSnapshot.removeAll()
        lastSuccessfulSampleAt = nil
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
        }
    }

    private func disableMonitoringDueToFailures() {
        stopMonitoring(logStop: true, clearPublishedRates: true)
        UserDefaults.standard.set(false, forKey: enabledKey)
        DispatchQueue.main.async { [weak self] in
            self?.isEnabled = false
        }
    }

    private func handleSampleOutput(_ output: String, sampledAt: Date) {
        let parsed = parseNettopOutput(output)
        guard !parsed.isEmpty else {
            registerFailure("nettop single sample returned no process rows", level: .warn)
            return
        }

        consecutiveFailures = 0

        let previous = lastSnapshot
        let rateInterval = max(sampledAt.timeIntervalSince(lastSuccessfulSampleAt ?? sampledAt), 1)
        var newSnapshot: [pid_t: (bytesIn: UInt64, bytesOut: UInt64)] = [:]

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
        lastSuccessfulSampleAt = sampledAt

        var rates: [AppTrafficRate] = []
        var todayRecordsByBundleID = storage.getTodayRecordsByBundleID()

        for (bundleID, data) in bundleDeltas {
            var todayRecord = todayRecordsByBundleID[bundleID]
            if data.deltaIn > 0 || data.deltaOut > 0 {
                todayRecord = storage.addBytesAndReturnTodayRecord(
                    bundleID: bundleID,
                    displayName: data.info.displayName,
                    downloadBytes: data.deltaIn,
                    uploadBytes: data.deltaOut
                )
                todayRecordsByBundleID[bundleID] = todayRecord
            }

            rates.append(AppTrafficRate(
                id: bundleID,
                displayName: data.info.displayName,
                icon: data.info.icon,
                isApp: data.info.isApp,
                downloadBps: Double(data.deltaIn) / rateInterval,
                uploadBps: Double(data.deltaOut) / rateInterval,
                totalDownloaded: todayRecord?.downloadBytes ?? 0,
                totalUploaded: todayRecord?.uploadBytes ?? 0
            ))
        }

        for record in todayRecordsByBundleID.values {
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

        var headerParsed = false
        var bytesInIndex = 1
        var bytesOutIndex = 2

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let columns = trimmed.components(separatedBy: ",")

            if !headerParsed {
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
        guard let lastDotIndex = field.lastIndex(of: ".") else { return nil }
        let name = String(field[field.startIndex..<lastDotIndex])
        let pidString = String(field[field.index(after: lastDotIndex)...])
        guard let pid = pid_t(pidString) else { return nil }
        return (name: name, pid: pid)
    }
}
