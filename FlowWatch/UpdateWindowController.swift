import AppKit
import Combine
import SwiftUI

@MainActor
final class UpdateWindowController: NSWindowController, NSWindowDelegate {
    static let shared = UpdateWindowController()

    private var statusSubscription: AnyCancellable?

    private init() {
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func makeWindow() -> NSWindow {
        let hostingController = NSHostingController(
            rootView: LocalizedRootView { FlowWatchWindowRoot(titleKey: "update.window.title") { UpdatePromptView() } }
                .environmentObject(LocalizationManager.shared)
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = LocalizationManager.shared.t("update.window.title")
        window.styleMask = [.titled, .closable, .miniaturizable]
        FlowWatchWindowStyle.apply(to: window)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 600, height: 352))
        window.minSize = NSSize(width: 560, height: 344)
        window.delegate = self
        return window
    }

    func show() {
        if window == nil {
            window = makeWindow()
        }
        window?.title = LocalizationManager.shared.t("update.window.title")
        resize(for: UpdateManager.shared.status)
        if statusSubscription == nil {
            statusSubscription = UpdateManager.shared.$status
                .dropFirst()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] status in self?.resize(for: status) }
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    override func close() {
        statusSubscription = nil
        window?.orderOut(nil)
    }

    private func resize(for status: UpdateManager.UpdateStatus) {
        guard let window else { return }
        let update: UpdateManager.UpdateInfo?
        var height: CGFloat = 352
        switch status {
        case .updateAvailable(let info), .readyToInstall(let info), .installOnQuit(let info),
             .remindLater(let info, _), .installing(let info), .skipped(let info):
            update = info
        case .downloading(let info, _):
            update = info
            height += 64
        default:
            update = nil
        }
        if update?.isCritical == true { height += 80 }
        var contentRect = window.contentRect(forFrameRect: window.frame)
        guard abs(contentRect.height - height) > 1 else { return }
        let top = window.frame.maxY
        contentRect.size.height = height
        var frame = window.frameRect(forContentRect: contentRect)
        frame.origin.y = top - frame.height
        window.setFrame(frame, display: true)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        UpdateManager.shared.closeUpdateWindow()
        return false
    }
}
