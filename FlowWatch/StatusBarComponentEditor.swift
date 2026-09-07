import AppKit
import SwiftUI

struct StatusBarComponentEditor: View {
    @Binding var layout: StatusBarLayout
    var tint: Color
    @EnvironmentObject private var l10n: LocalizationManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var drag: DragState?
    @State private var isCancelled = false
    @State private var hoveredComponent: StatusBarLayout.Component?

    private let rowHeight: CGFloat = 44
    private let spacing: CGFloat = 8
    private var pitch: CGFloat { rowHeight + spacing }
    private var motion: Animation? { reduceMotion ? nil : .interactiveSpring(response: 0.24, dampingFraction: 0.86) }

    private struct DragState {
        let component: StatusBarLayout.Component
        let translation: CGFloat
        let isInside: Bool
    }

    private var activeDrag: DragState? { isCancelled ? nil : drag }
    private var previewOrder: [StatusBarLayout.Component] {
        guard let drag = activeDrag, drag.isInside else { return layout.order }
        return reordered(drag.component, translation: drag.translation)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(l10n.t("settings.layout.description"))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(previewOrder.filter { layout.enabled.contains($0) }, id: \.self) { component in
                    Text(l10n.t(component.titleKey))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(l10n.t("settings.layout.preview"))
            .animation(motion, value: previewOrder)

            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    if let drag = activeDrag, drag.isInside,
                       let target = previewOrder.firstIndex(of: drag.component) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(tint.opacity(0.06))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(tint.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                            .frame(height: rowHeight)
                            .offset(y: CGFloat(target) * pitch)
                            .animation(motion, value: target)
                    }
                    ForEach(layout.order, id: \.self) { component in
                        row(component, width: geometry.size.width)
                            .frame(height: rowHeight)
                            .offset(y: rowOffset(component))
                            .animation(activeDrag?.component == component ? nil : motion, value: rowOffset(component))
                            .zIndex(activeDrag?.component == component ? 1 : 0)
                    }
                }
                .coordinateSpace(name: "statusBarComponentRows")
            }
            .frame(height: CGFloat(layout.order.count) * pitch - spacing)
            .background(DragEscapeHandler(isDragging: drag != nil) { isCancelled = true })
            .onChange(of: drag?.component) { component in
                if component == nil { isCancelled = false }
            }
        }
        .padding(.vertical, 8)
    }

    private func row(_ component: StatusBarLayout.Component, width: CGFloat) -> some View {
        let isDragged = activeDrag?.component == component
        return HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isDragged ? tint : .secondary)
                Text(l10n.t(component.titleKey))
                    .font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .help(l10n.t("settings.layout.dragHint"))
            .gesture(dragGesture(component, width: width))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(l10n.t(component.titleKey))
            .accessibilityAction(named: Text(l10n.t("settings.layout.moveLeft"))) { move(component, by: -1) }
            .accessibilityAction(named: Text(l10n.t("settings.layout.moveRight"))) { move(component, by: 1) }
            .contextMenu {
                Button(l10n.t("settings.layout.moveLeft")) { move(component, by: -1) }
                    .disabled(layout.order.first == component)
                Button(l10n.t("settings.layout.moveRight")) { move(component, by: 1) }
                    .disabled(layout.order.last == component)
            }
            ModernSwitch(isOn: Binding(
                get: { layout.enabled.contains(component) },
                set: { enabled in
                    var updated = layout
                    updated.setEnabled(component, enabled)
                    layout = updated
                }
            ), tint: tint)
            .disabled(layout.enabled == [component] || drag != nil)
            .accessibilityLabel(l10n.t(component.titleKey))
        }
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 8).fill(isDragged ? Color(nsColor: .controlBackgroundColor) : tint.opacity(hoveredComponent == component ? 0.05 : 0)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isDragged ? tint.opacity(0.5) : .clear, lineWidth: 1))
        .shadow(color: .black.opacity(isDragged ? 0.14 : 0), radius: isDragged ? 7 : 0, y: isDragged ? 3 : 0)
        .opacity(isDragged && activeDrag?.isInside == false ? 0.5 : 1)
        .onHover { hoveredComponent = $0 ? component : nil }
    }

    private func dragGesture(_ component: StatusBarLayout.Component, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named("statusBarComponentRows"))
            .updating($drag) { value, state, transaction in
                transaction.animation = nil
                state = DragState(component: component, translation: value.translation.height,
                                  isInside: isInside(value.location, width: width))
            }
            .onEnded { value in
                guard !isCancelled, isInside(value.location, width: width) else { return }
                var updated = layout
                updated.order = reordered(component, translation: value.translation.height)
                guard updated.order != layout.order else { return }
                withAnimation(motion) { layout = updated }
            }
    }

    private func isInside(_ location: CGPoint, width: CGFloat) -> Bool {
        location.x >= -24 && location.x <= width + 24 && location.y >= -24
            && location.y <= CGFloat(layout.order.count) * pitch - spacing + 24
    }

    private func reordered(_ component: StatusBarLayout.Component, translation: CGFloat) -> [StatusBarLayout.Component] {
        guard let source = layout.order.firstIndex(of: component) else { return layout.order }
        let target = max(0, min(layout.order.count - 1, source + Int((translation / pitch).rounded())))
        var order = layout.order
        order.remove(at: source)
        order.insert(component, at: target)
        return order
    }

    private func rowOffset(_ component: StatusBarLayout.Component) -> CGFloat {
        let original = layout.order.firstIndex(of: component) ?? 0
        if let drag = activeDrag, drag.component == component {
            return max(0, min(CGFloat(layout.order.count - 1) * pitch, CGFloat(original) * pitch + drag.translation))
        }
        return CGFloat(previewOrder.firstIndex(of: component) ?? original) * pitch
    }

    private func move(_ component: StatusBarLayout.Component, by offset: Int) {
        var updated = layout
        updated.move(component, by: offset)
        withAnimation(motion) { layout = updated }
    }
}

/// Listen only during a local reorder, without adding a focus ring to the entire list.
private struct DragEscapeHandler: NSViewRepresentable {
    var isDragging: Bool
    var cancel: () -> Void

    final class Coordinator {
        var parent: DragEscapeHandler
        var monitor: Any?
        init(_ parent: DragEscapeHandler) { self.parent = parent }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let coordinator = context.coordinator
        coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak coordinator, weak view] event in
            guard let coordinator, coordinator.parent.isDragging,
                  event.window === view?.window, event.keyCode == 53 else { return event }
            coordinator.parent.cancel()
            return nil
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) { context.coordinator.parent = self }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor { NSEvent.removeMonitor(monitor) }
        coordinator.monitor = nil
    }
}
