import AppKit
import SwiftUI

/// A shared, arrowless surface for menus and hints. Event monitors live only while it is visible.
@MainActor
final class FlowWatchFloatingPanel: NSObject, NSWindowDelegate {
    private var panel: FloatingWindow?
    private weak var anchor: NSView?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var deactivateObserver: NSObjectProtocol?
    private var dismiss: (() -> Void)?
    private var keyHandler: ((NSEvent) -> Bool)?
    private var takesFocus = true

    var isVisible: Bool { panel?.isVisible == true }
    var window: NSWindow? { panel }

    func show<Content: View>(
        content: Content, anchor: NSView, takesFocus: Bool = true,
        onKey: ((NSEvent) -> Bool)? = nil, onDismiss: @escaping () -> Void
    ) {
        guard let host = anchor.window else { return }
        self.anchor = anchor
        self.dismiss = onDismiss
        self.keyHandler = onKey
        self.takesFocus = takesFocus
        let hosting = NSHostingView(rootView: FloatingSurface(content: content))
        hosting.focusRingType = .none
        let size = hosting.fittingSize
        let panel = FloatingWindow(contentRect: NSRect(origin: .zero, size: size),
                                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = hosting
        panel.delegate = self
        panel.becomesKeyOnlyIfNeeded = !takesFocus
        panel.acceptsMouseMovedEvents = true
        self.panel = panel
        position(relativeTo: anchor)
        host.addChildWindow(panel, ordered: .above)
        if takesFocus {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFront(nil)
        }
        installMonitors()
    }

    func update<Content: View>(content: Content, onKey: ((NSEvent) -> Bool)?) {
        keyHandler = onKey
        guard let panel, let hosting = panel.contentView as? NSHostingView<FloatingSurface<Content>> else { return }
        hosting.rootView = FloatingSurface(content: content)
        if let anchor { position(relativeTo: anchor) }
    }

    func hide() {
        guard let panel else { return }
        let wasKey = panel.isKeyWindow
        let parent = panel.parent
        removeMonitors()
        parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        panel.contentView = nil
        panel.delegate = nil
        self.panel = nil
        let callback = dismiss
        dismiss = nil
        keyHandler = nil
        if takesFocus && wasKey && parent?.isVisible == true { parent?.makeKey() }
        callback?()
    }

    private func position(relativeTo anchor: NSView) {
        guard let panel, let host = anchor.window else { return }
        let rect = host.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let visible = host.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? rect
        let size = panel.frame.size
        let x = min(max(rect.midX - size.width / 2, visible.minX + 8), max(visible.minX + 8, visible.maxX - size.width - 8))
        let below = rect.minY - size.height - 6
        let y = below >= visible.minY + 8 ? below : min(rect.maxY + 6, visible.maxY - size.height - 8)
        panel.setFrameOrigin(NSPoint(x: x, y: max(visible.minY + 8, y)))
    }

    private func installMonitors() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self, let panel = self.panel else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 && (event.window === panel || (!self.takesFocus && event.window === panel.parent)) {
                    self.hide(); return nil
                }
                guard event.window === panel else { return event }
                if self.keyHandler?(event) == true { return nil }
            } else {
                var current = event.window
                while let window = current {
                    if window === panel { return event }
                    current = window.parent
                }
                if let anchor = self.anchor, event.window === anchor.window {
                    let point = anchor.convert(event.locationInWindow, from: nil)
                    if anchor.bounds.contains(point) { return event }
                }
                self.hide()
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide()
        }
        deactivateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    private func removeMonitors() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let deactivateObserver { NotificationCenter.default.removeObserver(deactivateObserver) }
        localMonitor = nil
        globalMonitor = nil
        deactivateObserver = nil
    }

    func windowWillClose(_ notification: Notification) { hide() }

    private final class FloatingWindow: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }
}

private struct FloatingSurface<Content: View>: View {
    let content: Content
    var body: some View {
        content
            .flowWatchCustomFocus()
            .foregroundStyle(FlowWatchPalette.ink)
            .background(FlowWatchPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(FlowWatchPalette.edge.opacity(0.8), lineWidth: 1))
    }
}

extension View {
    func flowWatchFloating<Content: View>(
        isPresented: Binding<Bool>, takesFocus: Bool = true,
        onKey: ((NSEvent) -> Bool)? = nil, @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        background(FloatingAnchor(isPresented: isPresented, takesFocus: takesFocus, onKey: onKey, content: content))
    }
}

private struct FloatingAnchor<Content: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    let takesFocus: Bool
    let onKey: ((NSEvent) -> Bool)?
    let content: () -> Content

    func makeCoordinator() -> FlowWatchFloatingPanel { FlowWatchFloatingPanel() }
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        let controller = context.coordinator
        // AppKit window attachment follows the SwiftUI update pass.
        DispatchQueue.main.async { [weak view, weak controller] in
            guard let view, let controller else { return }
            if isPresented {
                if controller.isVisible {
                    controller.update(content: content(), onKey: onKey)
                } else {
                    controller.show(content: content(), anchor: view, takesFocus: takesFocus, onKey: onKey) {
                        isPresented = false
                    }
                }
            } else { controller.hide() }
        }
    }
    static func dismantleNSView(_ view: NSView, coordinator: FlowWatchFloatingPanel) { coordinator.hide() }
}
