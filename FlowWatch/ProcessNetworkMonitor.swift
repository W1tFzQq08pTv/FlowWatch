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
    @Published var scopedTrafficRates: [TrafficAccountingScope: [AppTrafficRate]] = [:]
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
    private var accounting = NettopTrafficAccounting()
    private var lastSuccessfulSampleAt: Date?
    private let resolver = AppInfoResolver.shared
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
        for scope in TrafficAccountingScope.allCases where scope != .legacy {
            ProcessTrafficStorage.storage(for: scope).saveIfNeeded(force: true)
        }
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
        accounting = NettopTrafficAccounting()
        lastSuccessfulSampleAt = nil
        startSampleTimer()
        runSampleIfNeeded()
    }

    private func stopMonitoring(logStop: Bool, clearPublishedRates: Bool) {
        stopSampleTimer()
        stopActiveSample()
        accounting = NettopTrafficAccounting()
        lastSuccessfulSampleAt = nil
        if clearPublishedRates {
            DispatchQueue.main.async { [weak self] in
                self?.scopedTrafficRates = [:]
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
            "-L", "1",
            "-J", "interface,bytes_in,bytes_out",
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
        accounting = NettopTrafficAccounting()
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
        guard let parsed = NettopTrafficAccounting.parse(output) else {
            registerFailure("nettop single sample returned an invalid header", level: .warn)
            return
        }

        consecutiveFailures = 0

        let rateInterval = max(sampledAt.timeIntervalSince(lastSuccessfulSampleAt ?? sampledAt), 1)
        let deltas = accounting.sample(parsed, externalInterfaces: TrafficAccountingScope.externalInterfaceNames())
        var bundleDeltas: [TrafficAccountingScope: [String: (info: AppInfo, deltaIn: UInt64, deltaOut: UInt64)]] = [:]
        for delta in deltas {
            let entry = delta.entry
            let info = resolver.resolve(pid: entry.pid, processName: entry.processName)
            var bundled = bundleDeltas[delta.scope]?[info.bundleID] ?? (info: info, deltaIn: 0, deltaOut: 0)
            bundled.deltaIn &+= delta.bytesIn
            bundled.deltaOut &+= delta.bytesOut
            bundleDeltas[delta.scope, default: [:]][info.bundleID] = bundled
        }
        lastSuccessfulSampleAt = sampledAt

        var scopedRates: [TrafficAccountingScope: [AppTrafficRate]] = [:]
        for scope in TrafficAccountingScope.allCases where scope != .legacy {
            let storage = ProcessTrafficStorage.storage(for: scope)
            let deltas = bundleDeltas[scope] ?? [:]
            var records = storage.getTodayRecordsByBundleID()
            for (bundleID, data) in deltas where data.deltaIn > 0 || data.deltaOut > 0 {
                records[bundleID] = storage.addBytesAndReturnTodayRecord(
                    bundleID: bundleID, displayName: data.info.displayName, isApp: data.info.isApp,
                    downloadBytes: data.deltaIn, uploadBytes: data.deltaOut
                )
            }
            var rates: [AppTrafficRate] = []
            for bundleID in Set(records.keys).union(deltas.keys) {
                let record = records[bundleID]
                let delta = deltas[bundleID]
                let info = delta?.info ?? resolver.resolve(pid: 0, processName: record?.displayName ?? bundleID)
                rates.append(AppTrafficRate(
                    id: bundleID, displayName: record?.displayName ?? info.displayName,
                    icon: info.icon, isApp: record?.isApp ?? info.isApp,
                    downloadBps: Double(delta?.deltaIn ?? 0) / rateInterval,
                    uploadBps: Double(delta?.deltaOut ?? 0) / rateInterval,
                    totalDownloaded: record?.downloadBytes ?? 0, totalUploaded: record?.uploadBytes ?? 0
                ))
            }
            scopedRates[scope] = rates.sorted { ($0.totalDownloaded + $0.totalUploaded) > ($1.totalDownloaded + $1.totalUploaded) }
        }
        DispatchQueue.main.async { [weak self] in
            self?.scopedTrafficRates = scopedRates
        }
    }

}
