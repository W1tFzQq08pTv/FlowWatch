import AppKit
import SwiftUI

@MainActor
final class FlowWatchDialogController: NSObject, NSWindowDelegate {
    static let shared = FlowWatchDialogController()

    private struct Request {
        let title: String
        let message: String
        let confirmTitle: String
        let cancelTitle: String?
        let isDestructive: Bool
        let onDismiss: (() -> Void)?
        let completion: (Bool) -> Void
    }

    private var pending: [Request] = []
    private var active: Request?
    private var window: NSWindow?
    private weak var previousWindow: NSWindow?

    func present(title: String, message: String, confirmTitle: String,
                 cancelTitle: String? = nil, isDestructive: Bool = false,
                 onDismiss: (() -> Void)? = nil, completion: @escaping (Bool) -> Void = { _ in }) {
        pending.append(Request(title: title, message: message, confirmTitle: confirmTitle,
                               cancelTitle: cancelTitle, isDestructive: isDestructive, onDismiss: onDismiss, completion: completion))
        showNext()
    }

    private func showNext() {
        guard active == nil, !pending.isEmpty else { return }
        let request = pending.removeFirst()
        active = request
        previousWindow = NSApp.keyWindow
        let root = FlowWatchWindowRoot(title: request.title) {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: request.isDestructive ? "exclamationmark" : "info")
                    .font(.system(size: 20, weight: .medium))
                    .frame(width: 48, height: 48)
                    .background(FlowWatchPalette.well, in: RoundedRectangle(cornerRadius: 16))
                Text(request.title).font(.system(size: 22, weight: .semibold))
                ScrollView(showsIndicators: false) {
                    Text(request.message).font(.system(size: 13)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxHeight: .infinity)
                HStack(spacing: 8) {
                    Spacer()
                    if let cancelTitle = request.cancelTitle {
                        Button(cancelTitle) { self.finish(false) }
                            .buttonStyle(FlowWatchActionButtonStyle())
                            .keyboardShortcut(.defaultAction)
                    }
                    Button(request.confirmTitle) { self.finish(true) }
                        .buttonStyle(FlowWatchActionButtonStyle(isDestructive: request.isDestructive, isPrimary: !request.isDestructive))
                        .keyboardShortcut(request.cancelTitle == nil ? KeyboardShortcut.defaultAction : nil)
                }
            }
            .padding(28)
        }
        .environmentObject(LocalizationManager.shared)
        let window = DialogWindow(contentViewController: NSHostingController(rootView: root))
        window.keyAction = { [weak self] event in
            guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return false }
            switch event.keyCode {
            case 53: self?.finish(nil)
            case 36, 76: self?.finish(request.cancelTitle == nil)
            default: return false
            }
            return true
        }
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        FlowWatchWindowStyle.apply(to: window)
        window.title = request.title
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 460, height: 350))
        window.delegate = self
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func finish(_ confirmed: Bool?) {
        guard let request = active else { return }
        window?.delegate = nil
        window?.close()
        window?.contentViewController = nil
        window = nil
        active = nil
        if previousWindow?.isVisible == true { previousWindow?.makeKeyAndOrderFront(nil) }
        if let confirmed { request.completion(confirmed) }
        else if let onDismiss = request.onDismiss { onDismiss() }
        else { request.completion(false) }
        showNext()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { finish(nil); return false }

    private final class DialogWindow: NSPanel {
        var keyAction: ((NSEvent) -> Bool)?

        override func sendEvent(_ event: NSEvent) {
            if event.type == .keyDown, keyAction?(event) == true { return }
            super.sendEvent(event)
        }
    }
}
