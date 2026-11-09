import AppKit
import SwiftUI

final class AboutWindowController: NSWindowController, NSWindowDelegate {
    static let shared = AboutWindowController()

    private init() {
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func makeWindow() -> NSWindow {
        let hostingController = NSHostingController(
            rootView: LocalizedRootView { FlowWatchWindowRoot(titleKey: "menu.about") { AboutView() } }
                .environmentObject(LocalizationManager.shared)
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = LocalizationManager.shared.t("menu.about")
        window.styleMask = [.titled, .closable, .miniaturizable]
        FlowWatchWindowStyle.apply(to: window)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 440, height: 440))
        window.delegate = self
        return window
    }

    func show() {
        if window == nil {
            self.window = makeWindow()
        }
        window?.title = LocalizationManager.shared.t("menu.about")
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        LaunchAtLoginManager.shared.presentPromptIfNeeded(on: window)
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentViewController = nil
        window = nil
    }
}
