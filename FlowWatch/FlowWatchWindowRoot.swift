import AppKit
import SwiftUI

private struct FlowWatchWindowVisibleKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var flowWatchWindowVisible: Bool {
        get { self[FlowWatchWindowVisibleKey.self] }
        set { self[FlowWatchWindowVisibleKey.self] = newValue }
    }
}

struct FlowWatchWindowRoot<Content: View>: View {
    let title: String
    let titleKey: String?
    @EnvironmentObject private var l10n: LocalizationManager
    let content: Content
    @State private var isWindowVisible = true

    init(title: String = "", titleKey: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.titleKey = titleKey
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(titleKey.map { l10n.t($0) } ?? title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(FlowWatchPalette.ink.opacity(0.55))
                .lineLimit(1)
                .padding(.horizontal, 88)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(WindowDragRegion())
                .flowWatchHover(.grab)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environment(\.flowWatchWindowVisible, isWindowVisible)
        .flowWatchWindowSurface()
        .flowWatchCustomFocus()
        .background(WindowStyleAttachment(title: titleKey.map { l10n.t($0) } ?? title, isVisible: $isWindowVisible))
        .ignoresSafeArea(.container, edges: .top)
    }
}

@MainActor
enum FlowWatchWindowStyle {
    static func apply(to window: NSWindow) {
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isOpaque = true
        window.backgroundColor = NSColor(FlowWatchPalette.canvas)
        window.toolbar = nil
    }
}

private struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ view: NSView, context: Context) {}
    private final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
}

private struct WindowStyleAttachment: NSViewRepresentable {
    let title: String
    @Binding var isVisible: Bool

    func makeNSView(context: Context) -> AttachmentView { AttachmentView() }
    func updateNSView(_ view: AttachmentView, context: Context) {
        view.title = title
        view.visibility = $isVisible
        view.synchronize()
    }

    final class AttachmentView: NSView {
        var title = ""
        var visibility: Binding<Bool>?
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            if let window {
                observer = NotificationCenter.default.addObserver(
                    forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.synchronize() }
                }
            }
            synchronize()
        }

        func synchronize() {
            guard let window else { return }
            window.contentView?.focusRingType = .none
            if window.title != title { window.title = title }
            if window.titleVisibility != .hidden { FlowWatchWindowStyle.apply(to: window) }
            let visible = window.occlusionState.contains(.visible) && !window.isMiniaturized
            guard visibility?.wrappedValue != visible else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                self.visibility?.wrappedValue = window.occlusionState.contains(.visible) && !window.isMiniaturized
            }
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }
}
