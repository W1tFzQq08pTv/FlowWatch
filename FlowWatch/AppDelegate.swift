import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var monitor: NetworkUsageMonitor?
    private var processMonitor: ProcessNetworkMonitor?
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        LogManager.shared.log("Application did finish launching")
        LogManager.shared.installCrashHandlersIfNeeded()
        let monitor = NetworkUsageMonitor()
        self.monitor = monitor
        let processMonitor = ProcessNetworkMonitor()
        self.processMonitor = processMonitor
        self.statusBarController = StatusBarController(monitor: monitor, processMonitor: processMonitor)

        // 检查开机自启状态
        #if DEBUG
        if Bundle.main.object(forInfoDictionaryKey: "FlowWatchVisualQA") as? Bool == true {
            DispatchQueue.main.async { [weak self] in
                guard let self, let monitor = self.monitor else { return }
                TrafficStatisticsDetailWindowController.shared.show(monitor: monitor)
            }
            return
        }
        #endif
        LaunchAtLoginManager.shared.checkAndPrompt()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        #if DEBUG
        // UI inspection reactivates the app; keep the menu-bar-only QA scene intact.
        if Bundle.main.object(forInfoDictionaryKey: "FlowWatchVisualQA") as? Bool == true { return true }
        #endif
        if !flag {
            PerAppTrafficDetailWindowController.shared.show()
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        LogManager.shared.log("Application will terminate")
        monitor?.saveTrafficData()
        processMonitor?.saveData()
    }
}
