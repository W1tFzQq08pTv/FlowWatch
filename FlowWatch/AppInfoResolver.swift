import AppKit
import Darwin.libproc

struct AppInfo {
    let bundleID: String
    let displayName: String
    let icon: NSImage?
    let executablePath: String
    let isApp: Bool
}

final class AppInfoResolver {
    static let shared = AppInfoResolver()

    private var cache: [pid_t: AppInfo] = [:]
    private var pathCache: [String: AppInfo] = [:]
    private let lock = NSLock()

    private init() {}

    func resolve(pid: pid_t, processName: String) -> AppInfo {
        lock.lock()
        if let cached = cache[pid] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let execPath = executablePath(for: pid)
        let resolvedPath = execPath ?? processName

        lock.lock()
        if let cachedByPath = pathCache[resolvedPath] {
            cache[pid] = cachedByPath
            lock.unlock()
            return cachedByPath
        }
        lock.unlock()

        let info = buildAppInfo(execPath: resolvedPath, processName: processName)

        lock.lock()
        cache[pid] = info
        pathCache[resolvedPath] = info
        lock.unlock()

        return info
    }

    func clearCache() {
        lock.lock()
        cache.removeAll()
        pathCache.removeAll()
        lock.unlock()
    }

    func removePID(_ pid: pid_t) {
        lock.lock()
        cache.removeValue(forKey: pid)
        lock.unlock()
    }

    private func executablePath(for pid: pid_t) -> String? {
        let pathBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: Int(MAXPATHLEN))
        defer { pathBuffer.deallocate() }
        let length = proc_pidpath(pid, pathBuffer, UInt32(MAXPATHLEN))
        guard length > 0 else { return nil }
        return String(cString: pathBuffer)
    }

    private func buildAppInfo(execPath: String, processName: String) -> AppInfo {
        if let appBundlePath = findAppBundle(from: execPath),
           let bundle = Bundle(path: appBundlePath) {
            let bundleID = bundle.bundleIdentifier ?? appBundlePath
            let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? (appBundlePath as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
            var icon: NSImage?
            if Thread.isMainThread {
                icon = NSWorkspace.shared.icon(forFile: appBundlePath)
                icon?.size = NSSize(width: 16, height: 16)
            } else {
                DispatchQueue.main.sync {
                    icon = NSWorkspace.shared.icon(forFile: appBundlePath)
                    icon?.size = NSSize(width: 16, height: 16)
                }
            }
            return AppInfo(bundleID: bundleID, displayName: displayName, icon: icon, executablePath: execPath, isApp: true)
        }

        let name = (execPath as NSString).lastPathComponent
        let displayName = name.isEmpty ? processName : name
        return AppInfo(bundleID: execPath, displayName: displayName, icon: nil, executablePath: execPath, isApp: false)
    }

    private func findAppBundle(from path: String) -> String? {
        var current = path
        while current != "/" && !current.isEmpty {
            if current.hasSuffix(".app") {
                return current
            }
            current = (current as NSString).deletingLastPathComponent
        }
        return nil
    }
}
