import AppKit
import SwiftUI

enum FlowWatchHoverKind { case control, field, grab, card }

struct FlowWatchHoverButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .flowWatchHover(.control, isPressed: configuration.isPressed)
    }
}

extension View {
    @ViewBuilder
    func flowWatchCustomFocus() -> some View {
        if #available(macOS 14.0, *) { focusEffectDisabled() }
        else { self }
    }

    func flowWatchHover(_ kind: FlowWatchHoverKind = .control, isPressed: Bool = false) -> some View {
        modifier(FlowWatchHoverEffect(kind: kind, isPressed: isPressed))
    }
}

private struct FlowWatchHoverEffect: ViewModifier {
    let kind: FlowWatchHoverKind
    let isPressed: Bool
    @State private var isHovering = false
    @State private var ownsCursor = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var active: Bool { (isHovering || isFocused) && isEnabled }
    private var scale: CGFloat {
        guard !reduceMotion, isEnabled, kind == .control else { return 1 }
        return isPressed ? 0.97 : (active ? 1.015 : 1)
    }

    func body(content: Content) -> some View {
        content
            .background {
                if kind == .control || kind == .field {
                    RoundedRectangle(cornerRadius: 12).fill(FlowWatchPalette.ink.opacity(active ? 0.035 : 0))
                }
            }
            .shadow(color: .black.opacity(active && kind != .field ? 0.06 : 0), radius: active ? 7 : 0, y: active ? 3 : 0)
            .scaleEffect(scale)
            .offset(y: reduceMotion || !active || isPressed || kind == .field ? 0 : -1)
            .onHover { hovering in
                guard isHovering != hovering else { return }
                isHovering = hovering
                if hovering && isEnabled && (kind == .grab || kind == .control) {
                    (kind == .grab ? NSCursor.openHand : NSCursor.pointingHand).push()
                    ownsCursor = true
                } else if ownsCursor { NSCursor.pop(); ownsCursor = false }
            }
            .onDisappear { if ownsCursor { NSCursor.pop(); ownsCursor = false } }
            .onChange(of: isEnabled) { enabled in
                if !enabled && ownsCursor { NSCursor.pop(); ownsCursor = false }
            }
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.82), value: active)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isPressed)
    }
}
