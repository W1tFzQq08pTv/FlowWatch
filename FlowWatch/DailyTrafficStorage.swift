//
//  DailyTrafficStorage.swift
//  FlowWatch
//
//  每日流量数据持久化存储
//

import Foundation

struct DailyTrafficRecord: Codable, Identifiable, Sendable {
    let id: String // "YYYY-MM-DD"
    let date: Date
    var downloadBytes: UInt64
    var uploadBytes: UInt64

    nonisolated static func dateId(from date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    init(date: Date = Date(), downloadBytes: UInt64 = 0, uploadBytes: UInt64 = 0) {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.date = calendar.date(from: components) ?? date
        self.id = DailyTrafficRecord.dateId(from: self.date)
        self.downloadBytes = downloadBytes
        self.uploadBytes = uploadBytes
    }
}

final class DailyTrafficStorage {
    static let shared = DailyTrafficStorage()

    private let userDefaultsKey = "dailyTrafficRecords"

    private var records: [DailyTrafficRecord] = []
    private let lock = NSLock()
    private var isDirty = false
    private var saveTimer: DispatchSourceTimer?
    private let saveInterval: TimeInterval = 30

    private init() {
        loadRecords()
        startSaveTimer()
    }

    private var filePath: URL {
        let appSupport = AppSupportPaths.applicationDirectory
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent("daily_traffic.json")
    }

    func loadRecords() {
        lock.lock()
        defer { lock.unlock() }
        if let data = try? Data(contentsOf: filePath),
           let decoded = try? JSONDecoder().decode([DailyTrafficRecord].self, from: data) {
            records = decoded
        } else if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
                  let decoded = try? JSONDecoder().decode([DailyTrafficRecord].self, from: data) {
            records = decoded
            if let encoded = try? JSONEncoder().encode(records) {
                try? encoded.write(to: filePath)
            }
            UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        }
    }

    // MARK: - 定时保存

    private func startSaveTimer() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + saveInterval, repeating: saveInterval)
        timer.setEventHandler { [weak self] in
            self?.saveIfNeeded(force: false)
        }
        timer.resume()
        self.saveTimer = timer
    }

    func saveIfNeeded(force: Bool) {
        lock.lock()
        guard isDirty || force else {
            lock.unlock()
            return
        }
        isDirty = false
        let snapshot = records
        lock.unlock()

        guard let encoded = try? JSONEncoder().encode(snapshot) else { return }
        try? encoded.write(to: filePath)
    }

    func forceSave() {
        saveIfNeeded(force: true)
    }

    func getTodayRecord() -> DailyTrafficRecord {
        lock.lock()
        defer { lock.unlock() }
        let today = DailyTrafficRecord()
        if let index = records.firstIndex(where: { $0.id == today.id }) {
            return records[index]
        }
        return today
    }

    func updateTodayRecord(downloadBytes: UInt64, uploadBytes: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        let today = DailyTrafficRecord()
        if let index = records.firstIndex(where: { $0.id == today.id }) {
            records[index].downloadBytes = downloadBytes
            records[index].uploadBytes = uploadBytes
        } else {
            records.append(DailyTrafficRecord(downloadBytes: downloadBytes, uploadBytes: uploadBytes))
        }
        isDirty = true
    }

    func addBytesToToday(downloadBytes: UInt64, uploadBytes: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        let today = DailyTrafficRecord()
        if let index = records.firstIndex(where: { $0.id == today.id }) {
            records[index].downloadBytes &+= downloadBytes
            records[index].uploadBytes &+= uploadBytes
        } else {
            records.append(DailyTrafficRecord(downloadBytes: downloadBytes, uploadBytes: uploadBytes))
        }
        isDirty = true
    }

    func getRecentDays(days: Int) -> [DailyTrafficRecord] {
        lock.lock()
        let snapshot = records
        lock.unlock()

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var result: [DailyTrafficRecord] = []

        for dayOffset in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            let record = DailyTrafficRecord(date: date)
            if let existing = snapshot.first(where: { $0.id == record.id }) {
                result.append(existing)
            } else {
                result.append(record)
            }
        }

        return result.reversed()
    }

    func clearAllRecords() {
        lock.lock()
        records.removeAll()
        isDirty = true
        lock.unlock()
        saveIfNeeded(force: true)
    }

    func getAllRecords() -> [DailyTrafficRecord] {
        lock.lock()
        defer { lock.unlock() }
        return records
    }
}
