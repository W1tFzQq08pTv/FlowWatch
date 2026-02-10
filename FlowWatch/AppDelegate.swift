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
        LaunchAtLoginManager.shared.checkAndPrompt()
    }

    func applicationWillTerminate(_ notification: Notification) {
        LogManager.shared.log("Application will terminate")
        monitor?.saveTrafficData()
        processMonitor?.saveData()
    }
}
