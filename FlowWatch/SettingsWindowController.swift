import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private init() {
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func makeWindow() -> NSWindow {
        let hostingController = NSHostingController(
            rootView: LocalizedRootView { FlowWatchWindowRoot(titleKey: "settings.title") { SettingsView() } }
                .environmentObject(LocalizationManager.shared)
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = LocalizationManager.shared.t("settings.title")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        FlowWatchWindowStyle.apply(to: window)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 940, height: 704))
        window.minSize = NSSize(width: 860, height: 624)
        window.delegate = self
        return window
    }

    func show() {
        if window == nil {
            self.window = makeWindow()
        }
        window?.title = LocalizationManager.shared.t("settings.title")
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(nil)
            LaunchAtLoginManager.shared.presentPromptIfNeeded(on: self?.window)
        }
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentViewController = nil
        window = nil
    }
}
