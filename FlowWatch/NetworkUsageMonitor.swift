//
//  NetworkUsageMonitor.swift
//  FlowWatch
//
//  Created by xida huang on 12/5/25.
//

import AppKit
import Foundation
import Network
import Combine
import Darwin

struct TrafficRateSample: Identifiable, Equatable {
    let timestamp: Date
    let downloadBps: Double
    let uploadBps: Double

    var id: Date { timestamp }
}

final class NetworkUsageMonitor: ObservableObject {
    @Published var downloadBps: Double = 0
    @Published var uploadBps: Double = 0
    @Published var totalDownloaded: UInt64 = 0
    @Published var totalUploaded: UInt64 = 0
    @Published var isActive: Bool = true
    @Published private(set) var sampleInterval: TimeInterval = 5.0
    @Published private(set) var recentRateSamples: [TrafficRateSample] = []

    private let sampleIntervalKey = "statusBar.sampleInterval"
    private static let allowedIntervals: [TimeInterval] = [1, 2, 3, 5]
    private static let recentRateWindow: TimeInterval = 5 * 60
    private static let recentRateBucketDuration: TimeInterval = 5
    private static let maximumRecentRateSamples = 60

    // 每日流量统计
    @Published private(set) var todayDownloaded: UInt64 = 0
    @Published private(set) var todayUploaded: UInt64 = 0

    private var lastRx: UInt64?
    private var lastTx: UInt64?
    private var timer: DispatchSourceTimer?
    private var dayChangeTimer: DispatchSourceTimer?
    private var lastRecordedDate: Date = Date()
    private let sampleQueue = DispatchQueue(label: "com.flowwatch.networkSample")
    private var wakeObserver: NSObjectProtocol?

    init() {
        let stored = UserDefaults.standard.double(forKey: sampleIntervalKey)
        if stored > 0 {
            sampleInterval = Self.nearestAllowedInterval(stored)
        }
        loadTodayTraffic()
        // 将累计流量初始化为今日已用流量
        totalDownloaded = todayDownloaded
        totalUploaded = todayUploaded
        LogManager.shared.log("NetworkUsageMonitor initialized (sampleInterval=\(sampleInterval))")
        startTimer()
        startDayChangeTimer()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleSystemWake()
        }
    }

    deinit {
        timer?.cancel()
        dayChangeTimer?.cancel()
        if let observer = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    func toggle() {
        isActive.toggle()
        LogManager.shared.log("Network monitoring toggled: \(isActive)")
    }

    func updateInterval(to interval: TimeInterval) {
        let nearest = Self.nearestAllowedInterval(interval)
        guard nearest != sampleInterval else { return }
        LogManager.shared.log("Sample interval updated: \(sampleInterval) -> \(nearest)")
        sampleInterval = nearest
        UserDefaults.standard.set(nearest, forKey: sampleIntervalKey)
        restartTimer()
    }

    private static func nearestAllowedInterval(_ value: TimeInterval) -> TimeInterval {
        allowedIntervals.min(by: { abs($0 - value) < abs($1 - value) }) ?? 1.0
    }

    private func restartTimer() {
        timer?.cancel()
        timer = nil
        startTimer()
    }

    private func startTimer() {
        let timer = DispatchSource.makeTimerSource(queue: sampleQueue)
        timer.schedule(deadline: .now(), repeating: sampleInterval)
        timer.setEventHandler { [weak self] in
            self?.sample()
        }
        timer.resume()
        self.timer = timer
    }

    private func sample() {
        guard isActive else { return }

        let bytes = currentBytes()

        guard let lastRx = lastRx, let lastTx = lastTx else {
            LogManager.shared.log("Sample baseline established: rx=\(bytes.rx), tx=\(bytes.tx)")
            self.lastRx = bytes.rx
            self.lastTx = bytes.tx
            return
        }

        // 防止网卡重置或计数回绕导致的巨大跳变（计数变小视为重置，本次增量归零）
        let counterResetRx = bytes.rx < lastRx
        let counterResetTx = bytes.tx < lastTx
        if counterResetRx || counterResetTx {
            LogManager.shared.log("Counter reset detected: rx \(lastRx) -> \(bytes.rx), tx \(lastTx) -> \(bytes.tx)")
        }
        let deltaRx: UInt64 = counterResetRx ? 0 : bytes.rx - lastRx
        let deltaTx: UInt64 = counterResetTx ? 0 : bytes.tx - lastTx

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let downloadBps = Double(deltaRx) / self.sampleInterval
            let uploadBps = Double(deltaTx) / self.sampleInterval
            self.downloadBps = downloadBps
            self.uploadBps = uploadBps
            self.appendRecentRateSample(downloadBps: downloadBps, uploadBps: uploadBps)
            self.totalDownloaded &+= deltaRx
            self.totalUploaded &+= deltaTx
            self.todayDownloaded &+= deltaRx
            self.todayUploaded &+= deltaTx
            // 由 DailyTrafficStorage 的 isDirty + 定时保存机制负责持久化
            DailyTrafficStorage.shared.updateTodayRecord(downloadBytes: self.todayDownloaded, uploadBytes: self.todayUploaded)
        }

        self.lastRx = bytes.rx
        self.lastTx = bytes.tx
    }

    private func appendRecentRateSample(downloadBps: Double, uploadBps: Double) {
        let now = Date()
        let bucketTimestamp = Date(
            timeIntervalSinceReferenceDate: floor(
                now.timeIntervalSinceReferenceDate / Self.recentRateBucketDuration
            ) * Self.recentRateBucketDuration
        )
        let sample = TrafficRateSample(
            timestamp: bucketTimestamp,
            downloadBps: downloadBps,
            uploadBps: uploadBps
        )
        var updatedSamples = recentRateSamples

        if updatedSamples.last?.timestamp == bucketTimestamp {
            updatedSamples[updatedSamples.count - 1] = sample
        } else {
            updatedSamples.append(sample)
        }

        let cutoff = now.addingTimeInterval(-Self.recentRateWindow)
        updatedSamples.removeAll { $0.timestamp < cutoff }

        let overflow = updatedSamples.count - Self.maximumRecentRateSamples
        if overflow > 0 {
            updatedSamples.removeFirst(overflow)
        }

        recentRateSamples = updatedSamples
    }

    private func currentBytes() -> (rx: UInt64, tx: UInt64) {
        var rx: UInt64 = 0
        var tx: UInt64 = 0
        var addrs: UnsafeMutablePointer<ifaddrs>?

        if getifaddrs(&addrs) == 0, let first = addrs {
            var pointer = first
            while true {
                let flags = Int32(pointer.pointee.ifa_flags)
                let isUp = (flags & IFF_UP) == IFF_UP
                let isLoopback = (flags & IFF_LOOPBACK) == IFF_LOOPBACK

                // 获取接口名称，过滤虚拟网卡
                let name = String(cString: pointer.pointee.ifa_name)
                let isVirtualInterface = name.hasPrefix("utun") || 
                                       name.hasPrefix("tap") || 
                                       name.hasPrefix("tun") ||
                                       name.hasPrefix("ipsec") ||
                                       name.hasPrefix("ppp") ||
                                       name.hasPrefix("bridge") ||
                                       name.hasPrefix("awdl") || // Apple Wireless Direct Link
                                       name.hasPrefix("llw")     // Low Latency WLAN

                if isUp && !isLoopback && !isVirtualInterface, let dataPointer = pointer.pointee.ifa_data {
                    let data = dataPointer.assumingMemoryBound(to: if_data.self).pointee
                    rx &+= UInt64(data.ifi_ibytes)
                    tx &+= UInt64(data.ifi_obytes)
                }

                if let next = pointer.pointee.ifa_next {
                    pointer = next
                } else {
                    break
                }
            }
            freeifaddrs(first)
        }

        return (rx, tx)
    }

    func formattedSpeed(_ bytesPerSecond: Double) -> String {
        let (value, unit) = speedValueUnit(bytesPerSecond)
        return String(format: "%.1f %@", value, unit)
    }

    func compactSpeed(_ bytesPerSecond: Double) -> String {
        let (value, unit) = speedValueUnit(bytesPerSecond)
        return String(format: "%.1f %@", value, unit)
    }

    func fixedWidthCompactSpeed(_ bytesPerSecond: Double) -> String {
        let (value, unit) = speedValueUnit(bytesPerSecond)
        let format: String
        switch unit {
        case "GB/s", "MB/s":
            format = "%6.1f"
        case "KB/s":
            format = "%6.0f"
        default:
            format = "%6.1f"
        }
        let number = String(format: format, value)
        return "\(number) \(unit)"
    }

    func fixedWidthDataAmount(_ bytes: UInt64) -> String {
        let (value, unit) = dataValueUnit(Double(bytes))
        let format: String
        switch unit {
        case "TB", "GB":
            format = "%6.2f"
        case "MB":
            format = "%6.1f"
        case "kB":
            format = "%6.0f"
        default:
            format = "%6.0f"
        }
        let number = String(format: format, value)
        return "\(number) \(unit)"
    }

    private func speedValueUnit(_ bytesPerSecond: Double) -> (Double, String) {
        let safeBytes = max(bytesPerSecond, 0)
        let kb = safeBytes / 1024

        if kb >= 1024 * 1024 {
            return (kb / (1024 * 1024), "GB/s")
        } else if kb >= 1024 {
            return (kb / 1024, "MB/s")
        } else {
            return (kb, "KB/s")
        }
    }

    private func dataValueUnit(_ bytes: Double) -> (Double, String) {
        let kb = bytes / 1024
        if kb >= 1024 * 1024 * 1024 {
            return (kb / (1024 * 1024 * 1024), "TB")
        } else if kb >= 1024 * 1024 {
            return (kb / (1024 * 1024), "GB")
        } else if kb >= 1024 {
            return (kb / 1024, "MB")
        } else if kb >= 1 {
            return (kb, "kB")
        } else {
            return (bytes, "B")
        }
    }

    func resetTotals() {
        LogManager.shared.log("Reset totals")
        DispatchQueue.main.async {
            self.totalDownloaded = 0
            self.totalUploaded = 0
            self.todayDownloaded = 0
            self.todayUploaded = 0
        }
    }

    func resetTodayTraffic() {
        LogManager.shared.log("Reset today traffic")
        DispatchQueue.main.async {
            self.totalDownloaded = 0
            self.totalUploaded = 0
            self.todayDownloaded = 0
            self.todayUploaded = 0
            DailyTrafficStorage.shared.updateTodayRecord(downloadBytes: 0, uploadBytes: 0)
            DailyTrafficStorage.shared.forceSave()
        }
    }

    func clearAllTrafficHistory() {
        LogManager.shared.log("Clear all traffic history")
        DailyTrafficStorage.shared.clearAllRecords()
        DispatchQueue.main.async {
            self.totalDownloaded = 0
            self.totalUploaded = 0
            self.todayDownloaded = 0
            self.todayUploaded = 0
        }
    }

    // MARK: - 每日流量统计

    private func loadTodayTraffic() {
        let storage = DailyTrafficStorage.shared
        let record = storage.getTodayRecord()
        todayDownloaded = record.downloadBytes
        todayUploaded = record.uploadBytes
        lastRecordedDate = Date()
    }

    private func startDayChangeTimer() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now(), repeating: .seconds(60))
        timer.setEventHandler { [weak self] in
            self?.checkAndSaveForDayChange()
        }
        timer.resume()
        self.dayChangeTimer = timer
    }

    private func checkAndSaveForDayChange() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let lastRecorded = calendar.startOfDay(for: lastRecordedDate)

        if today > lastRecorded {
            // 新的一天开始了，先将最新数据写入存储再落盘
            let lastDateId = DailyTrafficRecord.dateId(from: lastRecordedDate)
            let todayDateId = DailyTrafficRecord.dateId(from: Date())
            LogManager.shared.log("Day changed: \(lastDateId) -> \(todayDateId), saving download=\(todayDownloaded), upload=\(todayUploaded)")
            DailyTrafficStorage.shared.updateTodayRecord(downloadBytes: todayDownloaded, uploadBytes: todayUploaded)
            DailyTrafficStorage.shared.forceSave()

            // 重置今日流量
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.todayDownloaded = 0
                self.todayUploaded = 0
            }

            lastRecordedDate = Date()
        }
    }

    private func handleSystemWake() {
        LogManager.shared.log("System woke from sleep: todayDownloaded=\(todayDownloaded), todayUploaded=\(todayUploaded), resetting sample baseline and checking day change")
        // 将 lastRx/lastTx 置 nil，确保唤醒后首次采样只建立基准值，
        // 不把 Power Nap 期间累积的流量一次性计入当日统计，造成数值虚高
        sampleQueue.async { [weak self] in
            self?.lastRx = nil
            self?.lastTx = nil
        }
        // 立即执行切日检测，不再等待最多 60 秒的定时器触发
        checkAndSaveForDayChange()
    }

    func saveTrafficData() {
        LogManager.shared.log("Save traffic data on terminate")
        DailyTrafficStorage.shared.forceSave()
    }

    func getRecentDays(days: Int) -> [DailyTrafficRecord] {
        return DailyTrafficStorage.shared.getRecentDays(days: days)
    }
}
