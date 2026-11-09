import AppKit
import QuartzCore

final class StatusBarHoverView: NSView {
    private var hoverArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.opacity = 0
        // Status-item snapshotting temporarily changes the view's appearance. A constant tint
        // avoids scheduling another snapshot from inside that appearance-change callback.
        layer?.backgroundColor = NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 0.16).cgColor
    }

    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }

    private func setHovered(_ hovered: Bool) {
        guard let layer else { return }
        let value: Float = hovered ? 1 : 0
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = layer.presentation()?.opacity ?? layer.opacity
            animation.toValue = value
            animation.duration = 0.18
            layer.add(animation, forKey: "hover")
        }
        layer.opacity = value
    }
}
