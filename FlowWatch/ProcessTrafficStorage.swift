import Foundation

struct AppDailyTrafficRecord: Codable, Identifiable {
    let id: String              // "bundleID|YYYY-MM-DD"
    let bundleID: String
    var displayName: String
    let date: Date
    var downloadBytes: UInt64
    var uploadBytes: UInt64

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    init(bundleID: String, displayName: String, date: Date = Date(), downloadBytes: UInt64 = 0, uploadBytes: UInt64 = 0) {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.date = calendar.date(from: components) ?? date
        let dateStr = AppDailyTrafficRecord.dateFormatter.string(from: self.date)
        self.id = "\(bundleID)|\(dateStr)"
        self.bundleID = bundleID
        self.displayName = displayName
        self.downloadBytes = downloadBytes
        self.uploadBytes = uploadBytes
    }
}

final class ProcessTrafficStorage {
    static let shared = ProcessTrafficStorage()

    private static let todayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private var records: [AppDailyTrafficRecord] = []
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
        return appSupport.appendingPathComponent("app_traffic.json")
    }

    private func loadRecords() {
        guard let data = try? Data(contentsOf: filePath),
              let decoded = try? JSONDecoder().decode([AppDailyTrafficRecord].self, from: data) else {
            return
        }
        records = decoded
    }

    private func saveToFile() {
        guard let encoded = try? JSONEncoder().encode(records) else { return }
        try? encoded.write(to: filePath)
    }

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

    func addBytes(bundleID: String, displayName: String, downloadBytes: UInt64, uploadBytes: UInt64) {
        lock.lock()
        defer { lock.unlock() }

        let record = AppDailyTrafficRecord(bundleID: bundleID, displayName: displayName)
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index].downloadBytes &+= downloadBytes
            records[index].uploadBytes &+= uploadBytes
            records[index].displayName = displayName
        } else {
            var newRecord = record
            newRecord.downloadBytes = downloadBytes
            newRecord.uploadBytes = uploadBytes
            records.append(newRecord)
        }
        isDirty = true
    }

    func getTodayRecord(bundleID: String) -> AppDailyTrafficRecord? {
        lock.lock()
        defer { lock.unlock() }

        let todayRecord = AppDailyTrafficRecord(bundleID: bundleID, displayName: "")
        return records.first(where: { $0.id == todayRecord.id })
    }

    func getTodayRecords() -> [AppDailyTrafficRecord] {
        lock.lock()
        defer { lock.unlock() }

        let todayStr = Self.todayDateFormatter.string(from: Date())
        return records.filter { $0.id.hasSuffix(todayStr) }
    }

    func getTopApps(limit: Int) -> [AppDailyTrafficRecord] {
        let todayRecords = getTodayRecords()
        return Array(todayRecords.sorted {
            ($0.downloadBytes + $0.uploadBytes) > ($1.downloadBytes + $1.uploadBytes)
        }.prefix(limit))
    }

    func getAggregatedRecords(from startDate: Date, to endDate: Date) -> [(bundleID: String, displayName: String, downloadBytes: UInt64, uploadBytes: UInt64)] {
        lock.lock()
        let snapshot = records
        lock.unlock()

        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: startDate)
        let endDay = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: endDate) ?? endDate)

        var aggregated: [String: (displayName: String, downloadBytes: UInt64, uploadBytes: UInt64)] = [:]

        for record in snapshot {
            let recordDay = calendar.startOfDay(for: record.date)
            guard recordDay >= startDay && recordDay < endDay else { continue }

            if var existing = aggregated[record.bundleID] {
                existing.downloadBytes &+= record.downloadBytes
                existing.uploadBytes &+= record.uploadBytes
                existing.displayName = record.displayName
                aggregated[record.bundleID] = existing
            } else {
                aggregated[record.bundleID] = (record.displayName, record.downloadBytes, record.uploadBytes)
            }
        }

        return aggregated.map { (bundleID: $0.key, displayName: $0.value.displayName, downloadBytes: $0.value.downloadBytes, uploadBytes: $0.value.uploadBytes) }
    }

    func getAllRecordsAggregated() -> [(bundleID: String, displayName: String, downloadBytes: UInt64, uploadBytes: UInt64)] {
        lock.lock()
        let snapshot = records
        lock.unlock()

        var aggregated: [String: (displayName: String, downloadBytes: UInt64, uploadBytes: UInt64)] = [:]

        for record in snapshot {
            if var existing = aggregated[record.bundleID] {
                existing.downloadBytes &+= record.downloadBytes
                existing.uploadBytes &+= record.uploadBytes
                existing.displayName = record.displayName
                aggregated[record.bundleID] = existing
            } else {
                aggregated[record.bundleID] = (record.displayName, record.downloadBytes, record.uploadBytes)
            }
        }

        return aggregated.map { (bundleID: $0.key, displayName: $0.value.displayName, downloadBytes: $0.value.downloadBytes, uploadBytes: $0.value.uploadBytes) }
    }

    func clearTodayRecords() {
        lock.lock()
        let todayStr = Self.todayDateFormatter.string(from: Date())
        records.removeAll { $0.id.hasSuffix(todayStr) }
        isDirty = true
        lock.unlock()
        saveIfNeeded(force: true)
    }

    func clearAllRecords() {
        lock.lock()
        records.removeAll()
        isDirty = true
        lock.unlock()
        saveIfNeeded(force: true)
    }

    func totalAppsToday() -> Int {
        return getTodayRecords().count
    }
}
