import AppKit
import SwiftUI

struct FlowWatchNavigationRow: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let selectionNamespace: Namespace.ID
    let action: () -> Void

    @State private var isHovering = false
    @State private var activationCount = 0
    @State private var ownsCursor = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var motion: Animation? {
        reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.84)
    }

    var body: some View {
        Button {
            activationCount &+= 1
            withAnimation(motion) { action() }
        } label: {
            HStack(spacing: 12) {
                FlowWatchAnimatedNavigationIcon(
                    symbol: icon,
                    color: isSelected ? FlowWatchPalette.inverse : FlowWatchPalette.ink.opacity(isHovering ? 0.95 : 0.65),
                    isHovered: isHovering, activation: activationCount
                )
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .offset(x: reduceMotion || !isHovering ? 0 : 2)
                Spacer(minLength: 0)
                Circle()
                    .frame(width: 4, height: 4)
                    .opacity(isSelected ? 1 : 0)
                    .scaleEffect(reduceMotion || isSelected ? 1 : 0.4)
            }
            .foregroundStyle(isSelected ? FlowWatchPalette.inverse : FlowWatchPalette.ink.opacity(isHovering ? 0.95 : 0.65))
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(FlowWatchPalette.ink)
                        .matchedGeometryEffect(id: "sidebar.selection", in: selectionNamespace)
                        .transition(.identity)
                } else {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isHovering ? FlowWatchPalette.elevated : .clear)
                }
            }
            .shadow(color: .black.opacity(isHovering ? 0.06 : 0), radius: 8, y: 3)
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(SidebarPressStyle(isSelected: isSelected))
        .onHover { hovering in
            guard isHovering != hovering else { return }
            withAnimation(motion) { isHovering = hovering && isEnabled }
            if hovering && isEnabled && !ownsCursor {
                NSCursor.pointingHand.push()
                ownsCursor = true
            } else if !hovering && ownsCursor {
                NSCursor.pop()
                ownsCursor = false
            }
        }
        .onDisappear {
            if ownsCursor { NSCursor.pop(); ownsCursor = false }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(motion, value: isSelected)
    }
}

private struct SidebarPressStyle: ButtonStyle {
    let isSelected: Bool
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(isFocused && !isSelected ? FlowWatchPalette.well : .clear)
            }
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.97)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(
                reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.76),
                value: configuration.isPressed
            )
    }
}
