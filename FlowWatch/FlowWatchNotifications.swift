import Foundation

extension Notification.Name {
    static let flowWatchResetToday = Notification.Name("FlowWatch.resetToday")
    static let flowWatchResetAllHistory = Notification.Name("FlowWatch.resetAllHistory")
    static let flowWatchCheckForUpdates = Notification.Name("FlowWatch.checkForUpdates")
    static let flowWatchPerAppMonitoringChanged = Notification.Name("FlowWatch.perAppMonitoringChanged")
    static let flowWatchPerAppIntervalChanged = Notification.Name("FlowWatch.perAppIntervalChanged")
    static let flowWatchSampleIntervalChanged = Notification.Name("FlowWatch.sampleIntervalChanged")
    static let flowWatchStatusBarColoringChanged = Notification.Name("FlowWatch.statusBarColoringChanged")
}
