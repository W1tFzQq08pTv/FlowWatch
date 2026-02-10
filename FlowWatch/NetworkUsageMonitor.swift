//
//  NetworkUsageMonitor.swift
//  FlowWatch
//
//  Created by xida huang on 12/5/25.
//

import Foundation
import Network
import Combine
import Darwin

final class NetworkUsageMonitor: ObservableObject {
    @Published var downloadBps: Double = 0
    @Published var uploadBps: Double = 0
    @Published var totalDownloaded: UInt64 = 0
    @Published var totalUploaded: UInt64 = 0
    @Published var isActive: Bool = true
    @Published private(set) var sampleInterval: TimeInterval = 1.0

    // 每日流量统计
    @Published private(set) var todayDownloaded: UInt64 = 0
    @Published private(set) var todayUploaded: UInt64 = 0

    private var lastRx: UInt64?
    private var lastTx: UInt64?
    private var timer: DispatchSourceTimer?
    private var dayChangeTimer: DispatchSourceTimer?
    private var lastRecordedDate: Date = Date()

    init() {
        loadTodayTraffic()
        // 将累计流量初始化为今日已用流量
        totalDownloaded = todayDownloaded
        totalUploaded = todayUploaded
        LogManager.shared.log("NetworkUsageMonitor initialized (sampleInterval=\(sampleInterval))")
        startTimer()
        startDayChangeTimer()
    }

    deinit {
        timer?.cancel()
        dayChangeTimer?.cancel()
    }

    func toggle() {
        isActive.toggle()
        LogManager.shared.log("Network monitoring toggled: \(isActive)")
    }

    func updateInterval(to interval: TimeInterval) {
        let clamped = min(max(interval, 1.0), 10.0)
        guard clamped != sampleInterval else { return }
        LogManager.shared.log("Sample interval updated: \(sampleInterval) -> \(clamped)")
        sampleInterval = clamped
        restartTimer()
    }

    private func restartTimer() {
        timer?.cancel()
        timer = nil
        startTimer()
    }

    private func startTimer() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
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
            self.lastRx = bytes.rx
            self.lastTx = bytes.tx
            return
        }

        // 防止网卡重置或计数回绕导致的巨大跳变（计数变小视为重置，本次增量归零）
        let deltaRx: UInt64 = bytes.rx >= lastRx ? bytes.rx - lastRx : 0
        let deltaTx: UInt64 = bytes.tx >= lastTx ? bytes.tx - lastTx : 0

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.downloadBps = Double(deltaRx)
            self.uploadBps = Double(deltaTx)
            self.totalDownloaded &+= deltaRx
            self.totalUploaded &+= deltaTx
            self.todayDownloaded &+= deltaRx
            self.todayUploaded &+= deltaTx
            // 实时保存今日流量数据
            self.saveTodayTraffic()
        }

        self.lastRx = bytes.rx
        self.lastTx = bytes.tx
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
        case "KB/s", "B/s":
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
        } else if kb >= 1 {
            return (kb, "KB/s")
        } else {
            return (safeBytes, "B/s")
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
            self.saveTodayTraffic()
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
            self.saveTodayTraffic()
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

    private func saveTodayTraffic() {
        let storage = DailyTrafficStorage.shared
        storage.updateTodayRecord(downloadBytes: todayDownloaded, uploadBytes: todayUploaded)
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
            // 新的一天开始了，保存昨天的数据
            LogManager.shared.log("Day changed, reset daily counters")
            saveTodayTraffic()

            // 重置今日流量
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.todayDownloaded = 0
                self.todayUploaded = 0
            }

            lastRecordedDate = Date()
        }
    }

    func saveTrafficData() {
        LogManager.shared.log("Save traffic data on terminate")
        saveTodayTraffic()
    }

    func getRecentDays(days: Int) -> [DailyTrafficRecord] {
        return DailyTrafficStorage.shared.getRecentDays(days: days)
    }
}
