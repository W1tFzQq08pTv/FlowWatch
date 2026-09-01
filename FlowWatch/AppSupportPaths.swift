import Foundation

enum AppSupportPaths {
    private static let updaterQABundleIdentifier = "com.hxd.FlowWatch.UpdateQA"

    static var applicationDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directoryName = Bundle.main.bundleIdentifier == updaterQABundleIdentifier
            ? "FlowWatch-Update-QA"
            : "FlowWatch"
        return base.appendingPathComponent(directoryName, isDirectory: true)
    }
}
