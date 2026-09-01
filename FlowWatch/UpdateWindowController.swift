import AppKit
import SwiftUI

@MainActor
final class UpdateWindowController: NSWindowController, NSWindowDelegate {
    static let shared = UpdateWindowController()

    private init() {
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func makeWindow() -> NSWindow {
        let hostingController = NSHostingController(
            rootView: LocalizedRootView { UpdatePromptView() }
                .environmentObject(LocalizationManager.shared)
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = LocalizationManager.shared.t("update.window.title")
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 600, height: 450))
        window.minSize = NSSize(width: 560, height: 410)
        window.delegate = self
        return window
    }

    func show() {
        if window == nil {
            window = makeWindow()
        }
        window?.title = LocalizationManager.shared.t("update.window.title")
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    override func close() {
        window?.orderOut(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        UpdateManager.shared.closeUpdateWindow()
        return false
    }
}
