import Foundation

struct AppDailyTrafficRecord: Codable, Identifiable, Sendable {
    let id: String              // "bundleID|YYYY-MM-DD"
    let bundleID: String
    var displayName: String
    var isApp: Bool?
    let date: Date
    var downloadBytes: UInt64
    var uploadBytes: UInt64

    nonisolated var persistedDateID: String {
        guard let separator = id.lastIndex(of: "|") else {
            return Self.dateId(from: date)
        }
        let value = String(id[id.index(after: separator)...])
        guard value.count == 10 else {
            return Self.dateId(from: date)
        }
        return value
    }

    nonisolated static func dateId(from date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    init(
        bundleID: String,
        displayName: String,
        isApp: Bool? = nil,
        date: Date = Date(),
        downloadBytes: UInt64 = 0,
        uploadBytes: UInt64 = 0
    ) {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.date = calendar.date(from: components) ?? date
        let dateStr = AppDailyTrafficRecord.dateId(from: self.date)
        self.id = "\(bundleID)|\(dateStr)"
        self.bundleID = bundleID
        self.displayName = displayName
        self.isApp = isApp
        self.downloadBytes = downloadBytes
        self.uploadBytes = uploadBytes
    }
}

final class ProcessTrafficStorage {
    static let shared = ProcessTrafficStorage()

    private var records: [AppDailyTrafficRecord] = []
    private var recordIndexByID: [String: Int] = [:]
    private var recordIDsByDateID: [String: Set<String>] = [:]
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
        rebuildIndexes()
    }

    private func saveToFile() {
        guard let encoded = try? JSONEncoder().encode(records) else { return }
        try? encoded.write(to: filePath)
    }

    private func rebuildIndexes() {
        recordIndexByID.removeAll(keepingCapacity: true)
        recordIDsByDateID.removeAll(keepingCapacity: true)

        for index in records.indices {
            indexRecord(records[index], at: index)
        }
    }

    private func indexRecord(_ record: AppDailyTrafficRecord, at index: Int) {
        recordIndexByID[record.id] = index
        let dateID = record.persistedDateID
        recordIDsByDateID[dateID, default: []].insert(record.id)
    }

    private func recordsLocked(forDateID dateID: String) -> [AppDailyTrafficRecord] {
        guard let ids = recordIDsByDateID[dateID] else {
            return []
        }
        return ids.compactMap { id in
            guard let index = recordIndexByID[id], records.indices.contains(index) else {
                return nil
            }
            return records[index]
        }
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

    func addBytes(
        bundleID: String,
        displayName: String,
        isApp: Bool? = nil,
        downloadBytes: UInt64,
        uploadBytes: UInt64
    ) {
        _ = addBytesAndReturnTodayRecord(
            bundleID: bundleID,
            displayName: displayName,
            isApp: isApp,
            downloadBytes: downloadBytes,
            uploadBytes: uploadBytes
        )
    }

    @discardableResult
    func addBytesAndReturnTodayRecord(
        bundleID: String,
        displayName: String,
        isApp: Bool? = nil,
        downloadBytes: UInt64,
        uploadBytes: UInt64
    ) -> AppDailyTrafficRecord {
        lock.lock()
        defer { lock.unlock() }

        let record = AppDailyTrafficRecord(
            bundleID: bundleID,
            displayName: displayName,
            isApp: isApp
        )
        if let index = recordIndexByID[record.id] {
            records[index].downloadBytes &+= downloadBytes
            records[index].uploadBytes &+= uploadBytes
            records[index].displayName = displayName
            if let isApp {
                records[index].isApp = isApp
            }
            isDirty = true
            return records[index]
        } else {
            var newRecord = record
            newRecord.downloadBytes = downloadBytes
            newRecord.uploadBytes = uploadBytes
            records.append(newRecord)
            indexRecord(newRecord, at: records.count - 1)
            isDirty = true
            return newRecord
        }
    }

    func getTodayRecord(bundleID: String) -> AppDailyTrafficRecord? {
        lock.lock()
        defer { lock.unlock() }

        let todayRecord = AppDailyTrafficRecord(bundleID: bundleID, displayName: "")
        guard let index = recordIndexByID[todayRecord.id] else {
            return nil
        }
        return records[index]
    }

    func getTodayRecords() -> [AppDailyTrafficRecord] {
        lock.lock()
        defer { lock.unlock() }

        let todayStr = AppDailyTrafficRecord.dateId(from: Date())
        return recordsLocked(forDateID: todayStr)
    }

    func getTodayRecordsByBundleID() -> [String: AppDailyTrafficRecord] {
        lock.lock()
        defer { lock.unlock() }

        let todayStr = AppDailyTrafficRecord.dateId(from: Date())
        return Dictionary(
            uniqueKeysWithValues: recordsLocked(forDateID: todayStr)
                .map { ($0.bundleID, $0) }
        )
    }

    func getTopApps(limit: Int) -> [AppDailyTrafficRecord] {
        let todayRecords = getTodayRecords()
        return Array(todayRecords.sorted {
            ($0.downloadBytes + $0.uploadBytes) > ($1.downloadBytes + $1.uploadBytes)
        }.prefix(limit))
    }

    func getRecords(from startDate: Date, to endDate: Date) -> [AppDailyTrafficRecord] {
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: startDate)
        let endDay = calendar.startOfDay(for: endDate)
        guard startDay <= endDay else { return [] }

        var dateIDs: [String] = []
        var currentDate = startDay
        while currentDate <= endDay {
            dateIDs.append(AppDailyTrafficRecord.dateId(from: currentDate))
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else {
                break
            }
            currentDate = nextDate
        }

        lock.lock()
        var snapshot: [AppDailyTrafficRecord] = []
        for dateID in dateIDs {
            snapshot.append(contentsOf: recordsLocked(forDateID: dateID))
        }
        lock.unlock()

        return snapshot
    }

    func getAllRecords() -> [AppDailyTrafficRecord] {
        lock.lock()
        defer { lock.unlock() }
        return records
    }

    func getAggregatedRecords(from startDate: Date, to endDate: Date) -> [(bundleID: String, displayName: String, downloadBytes: UInt64, uploadBytes: UInt64)] {
        let snapshot = getRecords(from: startDate, to: endDate)

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

    func getAllRecordsAggregated() -> [(bundleID: String, displayName: String, downloadBytes: UInt64, uploadBytes: UInt64)] {
        let snapshot = getAllRecords()

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
        let todayStr = AppDailyTrafficRecord.dateId(from: Date())
        records.removeAll { $0.id.hasSuffix(todayStr) }
        rebuildIndexes()
        isDirty = true
        lock.unlock()
        saveIfNeeded(force: true)
    }

    func clearAllRecords() {
        lock.lock()
        records.removeAll()
        rebuildIndexes()
        isDirty = true
        lock.unlock()
        saveIfNeeded(force: true)
    }

    func totalAppsToday() -> Int {
        return getTodayRecords().count
    }
}
