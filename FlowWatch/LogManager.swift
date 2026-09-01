import Foundation
import Darwin

private var crashLogFileDescriptor: Int32 = -1

private func crashSignalHandler(_ signalCode: Int32) {
    let fd = crashLogFileDescriptor >= 0 ? crashLogFileDescriptor : STDERR_FILENO
    let prefix: [UInt8] = Array("Fatal signal: ".utf8)
    _ = prefix.withUnsafeBytes { rawBuffer in
        write(fd, rawBuffer.baseAddress, rawBuffer.count)
    }
    var number = signalCode
    var digits = [UInt8](repeating: 0, count: 12)
    var index = digits.count
    var value = number
    if value == 0 {
        index -= 1
        digits[index] = UInt8(ascii: "0")
    } else {
        let isNegative = value < 0
        if isNegative {
            value = -value
        }
        while value > 0, index > 0 {
            let digit = value % 10
            index -= 1
            digits[index] = UInt8(UInt8(digit) + UInt8(ascii: "0"))
            value /= 10
        }
        if isNegative, index > 0 {
            index -= 1
            digits[index] = UInt8(ascii: "-")
        }
    }
    _ = digits[index...].withUnsafeBytes { rawBuffer in
        write(fd, rawBuffer.baseAddress, rawBuffer.count)
    }
    let newline: UInt8 = UInt8(ascii: "\n")
    _ = withUnsafeBytes(of: newline) { rawBuffer in
        write(fd, rawBuffer.baseAddress, rawBuffer.count)
    }
    _ = fsync(fd)
    Darwin.signal(signalCode, SIG_DFL)
    raise(signalCode)
}

final class LogManager {
    static let shared = LogManager()

    enum Level: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warn = "WARN"
        case error = "ERROR"
    }

    private let enabledKey = "logging.enabled"
    private let retentionDays = 7
    private let filePrefix = "flowwatch"
    private let queue = DispatchQueue(label: "com.hxd.flowwatch.log", qos: .utility)
    private let logsDirectoryURL: URL
    private var fileHandle: FileHandle?
    private var currentDateString: String?
    private var isEnabled: Bool
    private static var crashHandlersInstalled = false

    private init() {
        logsDirectoryURL = LogManager.makeLogsDirectoryURL()
        let defaults = UserDefaults.standard
        if defaults.object(forKey: enabledKey) == nil {
            defaults.set(true, forKey: enabledKey)
        }
        isEnabled = defaults.bool(forKey: enabledKey)
        if isEnabled {
            queue.async { [weak self] in
                self?.rotateIfNeeded(now: Date())
            }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(handleUserDefaultsChanged), name: UserDefaults.didChangeNotification, object: nil)
    }

    var logsDirectoryPath: String {
        logsDirectoryURL.path
    }

    func installCrashHandlersIfNeeded() {
        guard !Self.crashHandlersInstalled else { return }
        Self.crashHandlersInstalled = true
        NSSetUncaughtExceptionHandler { exception in
            let reason = exception.reason ?? ""
            let stack = exception.callStackSymbols.joined(separator: "\n")
            LogManager.shared.log("Uncaught exception: \(exception.name.rawValue) \(reason)\n\(stack)", level: .error)
        }
        let signals: [Int32] = [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGTRAP]
        for signalCode in signals {
            signal(signalCode, crashSignalHandler)
        }
        log("Crash handlers installed")
    }

    func log(
        _ message: String,
        level: Level = .info,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        guard isEnabled else { return }
        let now = Date()
        let source = "\(file):\(line)"
        queue.async { [weak self] in
            self?.appendLine(message, level: level, source: source, function: function, date: now)
        }
    }

    @objc private func handleUserDefaultsChanged() {
        let enabled = UserDefaults.standard.bool(forKey: enabledKey)
        queue.async { [weak self] in
            guard let self else { return }
            if self.isEnabled && !enabled {
                self.closeFile()
            }
            self.isEnabled = enabled
            if enabled {
                self.rotateIfNeeded(now: Date())
            }
        }
    }

    private static func makeLogsDirectoryURL() -> URL {
        AppSupportPaths.applicationDirectory
            .appendingPathComponent("Logs", isDirectory: true)
    }

    private func appendLine(_ message: String, level: Level, source: String, function: String, date: Date) {
        rotateIfNeeded(now: date)
        guard let fileHandle else { return }
        let timestamp = timestampString(from: date)
        let line = "[\(timestamp)] [\(level.rawValue)] \(source) \(function) - \(message)\n"
        if let data = line.data(using: .utf8) {
            fileHandle.write(data)
        }
    }

    private func rotateIfNeeded(now: Date) {
        let dateString = dayString(from: now)
        if currentDateString != dateString {
            closeFile()
            currentDateString = dateString
            openLogFile(for: dateString)
            cleanupOldLogs(relativeTo: now)
        } else if fileHandle == nil {
            openLogFile(for: dateString)
        }
    }

    private func openLogFile(for dateString: String) {
        do {
            try FileManager.default.createDirectory(at: logsDirectoryURL, withIntermediateDirectories: true)
            let fileURL = logsDirectoryURL.appendingPathComponent("\(filePrefix)-\(dateString).log")
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            }
            fileHandle = try FileHandle(forWritingTo: fileURL)
            fileHandle?.seekToEndOfFile()
            if let descriptor = fileHandle?.fileDescriptor {
                crashLogFileDescriptor = descriptor
            }
        } catch {
            fileHandle = nil
            crashLogFileDescriptor = -1
        }
    }

    private func closeFile() {
        try? fileHandle?.close()
        fileHandle = nil
        crashLogFileDescriptor = -1
    }

    private func cleanupOldLogs(relativeTo date: Date) {
        let calendar = Calendar.current
        guard let cutoff = calendar.date(byAdding: .day, value: -(retentionDays - 1), to: calendar.startOfDay(for: date)) else {
            return
        }
        guard let files = try? FileManager.default.contentsOfDirectory(at: logsDirectoryURL, includingPropertiesForKeys: nil) else {
            return
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        for file in files {
            let name = file.lastPathComponent
            guard name.hasPrefix("\(filePrefix)-"), name.hasSuffix(".log") else { continue }
            let datePart = name
                .replacingOccurrences(of: "\(filePrefix)-", with: "")
                .replacingOccurrences(of: ".log", with: "")
            guard let fileDate = formatter.date(from: datePart) else { continue }
            if fileDate < cutoff {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    private func dayString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func timestampString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
}
