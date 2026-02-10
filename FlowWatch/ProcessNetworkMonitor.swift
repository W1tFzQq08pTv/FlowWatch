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

    private var timer: DispatchSourceTimer?
    private var lastSnapshot: [pid_t: (bytesIn: UInt64, bytesOut: UInt64)] = [:]
    private let resolver = AppInfoResolver.shared
    private let storage = ProcessTrafficStorage.shared
    private let queue = DispatchQueue(label: "com.flowwatch.processmonitor", qos: .utility)

    init() {
        isEnabled = UserDefaults.standard.bool(forKey: enabledKey)
        if isEnabled {
            start()
        }
    }

    deinit {
        timer?.cancel()
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
        if timer != nil {
            stop()
            start()
        }
    }

    func start() {
        guard timer == nil else { return }
        LogManager.shared.log("ProcessNetworkMonitor started")
        lastSnapshot.removeAll()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: sampleInterval)
        timer.setEventHandler { [weak self] in
            self?.sample()
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
        lastSnapshot.removeAll()
        DispatchQueue.main.async { [weak self] in
            self?.appTrafficRates = []
        }
        LogManager.shared.log("ProcessNetworkMonitor stopped")
    }

    func saveData() {
        storage.saveIfNeeded(force: true)
    }

    private func sample() {
        guard let output = runNettop() else { return }
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

    private func runNettop() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        process.arguments = ["-P", "-L", "1", "-J", "bytes_in,bytes_out", "-n"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            LogManager.shared.log("nettop launch failed: \(error)", level: .error)
            return nil
        }

        // Read pipe data asynchronously to avoid deadlock when output exceeds pipe buffer
        var outputData = Data()
        let readQueue = DispatchQueue.global(qos: .utility)
        let readGroup = DispatchGroup()
        readGroup.enter()
        readQueue.async {
            outputData = pipe.fileHandleForReading.readDataToEndOfFile()
            readGroup.leave()
        }

        let semaphore = DispatchSemaphore(value: 0)
        let waitQueue = DispatchQueue.global(qos: .utility)
        var didTerminate = false

        waitQueue.async {
            process.waitUntilExit()
            didTerminate = true
            semaphore.signal()
        }

        let deadline = DispatchTime.now() + nettopTimeout
        if semaphore.wait(timeout: deadline) == .timedOut {
            if !didTerminate {
                process.terminate()
                LogManager.shared.log("nettop timed out, terminated", level: .warn)
            }
            return nil
        }

        readGroup.wait()
        return String(data: outputData, encoding: .utf8)
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
