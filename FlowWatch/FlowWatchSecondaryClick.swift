import AppKit
import SwiftUI

struct FlowWatchSecondaryClick: NSViewRepresentable {
    let action: () -> Void
    func makeNSView(context: Context) -> NSView { ClickView(action: action) }
    func updateNSView(_ view: NSView, context: Context) { (view as? ClickView)?.action = action }

    private final class ClickView: NSView {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action; super.init(frame: .zero) }
        required init?(coder: NSCoder) { nil }
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard NSApp.currentEvent?.type == .rightMouseDown else { return nil }
            return super.hitTest(point)
        }
        override func rightMouseDown(with event: NSEvent) { action() }
    }
}
