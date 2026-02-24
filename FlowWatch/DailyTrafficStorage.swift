//
//  DailyTrafficStorage.swift
//  FlowWatch
//
//  每日流量数据持久化存储
//

import Foundation

struct DailyTrafficRecord: Codable, Identifiable {
    let id: String // "YYYY-MM-DD"
    let date: Date
    var downloadBytes: UInt64
    var uploadBytes: UInt64

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    init(date: Date = Date(), downloadBytes: UInt64 = 0, uploadBytes: UInt64 = 0) {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.date = calendar.date(from: components) ?? date
        self.id = DailyTrafficRecord.dateFormatter.string(from: self.date)
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
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = paths[0].appendingPathComponent("FlowWatch")
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent("daily_traffic.json")
    }

    func loadRecords() {
        if let data = try? Data(contentsOf: filePath),
           let decoded = try? JSONDecoder().decode([DailyTrafficRecord].self, from: data) {
            records = decoded
        } else if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
                  let decoded = try? JSONDecoder().decode([DailyTrafficRecord].self, from: data) {
            records = decoded
            saveToFile()
            UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        }
    }

    private func saveToFile() {
        guard let encoded = try? JSONEncoder().encode(records) else { return }
        try? encoded.write(to: filePath)
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
        let today = DailyTrafficRecord()
        if let index = records.firstIndex(where: { $0.id == today.id }) {
            return records[index]
        }
        return today
    }

    func updateTodayRecord(downloadBytes: UInt64, uploadBytes: UInt64) {
        let today = DailyTrafficRecord()
        if let index = records.firstIndex(where: { $0.id == today.id }) {
            var record = records[index]
            record.downloadBytes = downloadBytes
            record.uploadBytes = uploadBytes
            records[index] = record
        } else {
            records.append(DailyTrafficRecord(downloadBytes: downloadBytes, uploadBytes: uploadBytes))
        }
        lock.lock()
        isDirty = true
        lock.unlock()
    }

    func addBytesToToday(downloadBytes: UInt64, uploadBytes: UInt64) {
        let today = DailyTrafficRecord()
        if let index = records.firstIndex(where: { $0.id == today.id }) {
            var record = records[index]
            record.downloadBytes &+= downloadBytes
            record.uploadBytes &+= uploadBytes
            records[index] = record
        } else {
            records.append(DailyTrafficRecord(downloadBytes: downloadBytes, uploadBytes: uploadBytes))
        }
        lock.lock()
        isDirty = true
        lock.unlock()
    }

    func getRecentDays(days: Int) -> [DailyTrafficRecord] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var result: [DailyTrafficRecord] = []

        for dayOffset in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            let record = DailyTrafficRecord(date: date)
            if let existing = records.first(where: { $0.id == record.id }) {
                result.append(existing)
            } else {
                result.append(record)
            }
        }

        return result.reversed()
    }

    func clearAllRecords() {
        records.removeAll()
        saveToFile()
    }

    func getAllRecords() -> [DailyTrafficRecord] {
        return records
    }
}
