import AppKit
import Combine
import SwiftUI

enum FlowWatchPalette {
    static let canvas = adaptive(light: 0xF1F1F0, dark: 0x1B1C1F)
    static let surface = adaptive(light: 0xFAFAF9, dark: 0x27282D)
    static let elevated = adaptive(light: 0xFFFFFF, dark: 0x33343A)
    static let well = adaptive(light: 0xE7E7E6, dark: 0x202126)
    static let ink = adaptive(light: 0x191A1C, dark: 0xF4F4F2)
    static let inverse = adaptive(light: 0xFFFFFF, dark: 0x1B1C1F)
    static let edge = adaptive(light: 0xFFFFFF, dark: 0x45464C)
    static let accent = ink
    static let download = Color(red: 0.24, green: 0.49, blue: 0.85)
    static let upload = Color(red: 0.83, green: 0.37, blue: 0.51)
    static let total = Color(red: 0.52, green: 0.46, blue: 0.74)
    static let active = Color(red: 0.28, green: 0.65, blue: 0.49)
    static let destructive = Color(red: 0.83, green: 0.28, blue: 0.34)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255,
                           green: CGFloat((rgb >> 8) & 255) / 255,
                           blue: CGFloat(rgb & 255) / 255, alpha: 1)
        })
    }
}

enum FlowWatchGlassMaterial {
    case ultraThin, thin, regular
}

struct FlowWatchInfoTip: View {
    let text: String
    @State private var isPresented = false
    @State private var isPinned = false

    var body: some View {
        Button { isPinned.toggle(); isPresented = isPinned } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Circle())
        }
        .buttonStyle(FlowWatchHoverButtonStyle())
        .onHover { if !isPinned { isPresented = $0 } }
        .onChange(of: isPresented) { if !$0 { isPinned = false } }
        .flowWatchFloating(isPresented: $isPresented, takesFocus: false) {
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(FlowWatchPalette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 248, alignment: .leading)
                .padding(16)
        }
        .accessibilityLabel(text)
    }
}

extension View {
    func flowWatchGlassPanel(
        cornerRadius: CGFloat = 20,
        material: FlowWatchGlassMaterial = .regular,
        strokeOpacity: Double = 0.09,
        shadowOpacity: Double = 0.018
    ) -> some View {
        background(FlowWatchPalette.surface, in: RoundedRectangle(cornerRadius: max(cornerRadius, 12)))
            .overlay {
                RoundedRectangle(cornerRadius: max(cornerRadius, 12))
                    .strokeBorder(FlowWatchPalette.edge.opacity(0.85), lineWidth: 1)
            }
            .shadow(color: .black.opacity(max(shadowOpacity, 0.035)), radius: 12, x: 0, y: 5)
    }

    func flowWatchGlassCapsule(
        material: FlowWatchGlassMaterial = .thin,
        strokeOpacity: Double = 0.08,
        shadowOpacity: Double = 0.015
    ) -> some View {
        background(FlowWatchPalette.well, in: Capsule())
            .overlay(Capsule().strokeBorder(FlowWatchPalette.edge.opacity(0.6), lineWidth: 1))
    }

    func flowWatchGlassButtonSurface(
        tint: Color = FlowWatchPalette.accent,
        isSelected: Bool = false,
        cornerRadius: CGFloat = 16
    ) -> some View {
        background(isSelected ? FlowWatchPalette.elevated : FlowWatchPalette.well,
                   in: RoundedRectangle(cornerRadius: max(cornerRadius, 12)))
            .overlay {
                RoundedRectangle(cornerRadius: max(cornerRadius, 12))
                    .strokeBorder(isSelected ? FlowWatchPalette.edge : .clear, lineWidth: 1)
            }
            .shadow(color: .black.opacity(isSelected ? 0.07 : 0), radius: 5, y: 2)
    }

    func flowWatchWindowSurface() -> some View {
        background(FlowWatchPalette.canvas.ignoresSafeArea())
            .foregroundStyle(FlowWatchPalette.ink)
    }

    func flowWatchMainPaneSurface() -> some View {
        background(FlowWatchPalette.canvas.ignoresSafeArea())
    }

    func flowWatchHelp(_ text: String) -> some View {
        modifier(FlowWatchHelpModifier(text: text))
    }
}

private struct FlowWatchHelpModifier: ViewModifier {
    let text: String
    @State private var isPresented = false
    func body(content: Content) -> some View {
        content
            .onHover { isPresented = $0 }
            .flowWatchFloating(isPresented: $isPresented, takesFocus: false) {
                Text(text).font(.caption).frame(maxWidth: 260).fixedSize(horizontal: false, vertical: true).padding(16)
            }
    }
}

struct FlowWatchSegmentedControl<Value: Hashable>: View {
    let options: [(String, Value)]
    @Binding var selection: Value
    var tint: Color = FlowWatchPalette.accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let isSelected = selection == option.1
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.86)) {
                        selection = option.1
                    }
                } label: {
                    Text(option.0)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? FlowWatchPalette.ink : FlowWatchPalette.ink.opacity(0.6))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .frame(minWidth: 44)
                        .background {
                            if isSelected {
                                Capsule().fill(FlowWatchPalette.elevated)
                                    .matchedGeometryEffect(id: "selection", in: selectionNamespace)
                            }
                        }
                        .shadow(color: .black.opacity(isSelected ? 0.08 : 0), radius: 3, y: 1)
                        .contentShape(Capsule())
                }
                .buttonStyle(FlowWatchHoverButtonStyle())
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .onMoveCommand { direction in
                    guard let index = options.firstIndex(where: { $0.1 == selection }), !options.isEmpty else { return }
                    if direction == .left { selection = options[max(0, index - 1)].1 }
                    if direction == .right { selection = options[min(options.count - 1, index + 1)].1 }
                }
            }
        }
        .padding(4)
        .background(FlowWatchPalette.well, in: Capsule())
    }
}

struct FlowWatchMenuControl<Value: Hashable>: View {
    let options: [(String, Value)]
    @Binding var selection: Value
    var tint: Color = FlowWatchPalette.accent
    var width: CGFloat = 220
    @State private var isPresented = false
    @State private var highlightedIndex = 0

    private var selectedLabel: String {
        options.first(where: { $0.1 == selection })?.0 ?? options.first?.0 ?? ""
    }

    var body: some View {
        Button {
            highlightedIndex = options.firstIndex(where: { $0.1 == selection }) ?? 0
            isPresented.toggle()
        } label: {
            HStack(spacing: 8) {
                Text(selectedLabel).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).opacity(0.6)
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(width: width)
            .flowWatchGlassButtonSurface(isSelected: isPresented)
            .contentShape(Capsule())
        }
        .buttonStyle(FlowWatchHoverButtonStyle())
        .accessibilityLabel(selectedLabel)
        .accessibilityValue("\(selectedLabel), \(L10n.t(isPresented ? "ui.expanded" : "ui.collapsed"))")
        .flowWatchFloating(isPresented: $isPresented, onKey: handleKey) {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                            Button { choose(index) } label: {
                                HStack(spacing: 12) {
                                    Text(option.0).frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "checkmark")
                                        .opacity(option.1 == selection ? 1 : 0)
                                }
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 12).padding(.vertical, 10)
                                .background(highlightedIndex == index ? FlowWatchPalette.well : .clear,
                                            in: RoundedRectangle(cornerRadius: 12))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(FlowWatchHoverButtonStyle())
                            .onHover { if $0 { highlightedIndex = index } }
                            .accessibilityAddTraits(option.1 == selection ? .isSelected : [])
                            .id(index)
                        }
                    }.padding(8)
                }
                .frame(width: max(width, 200), height: min(CGFloat(options.count) * 38 + 16, 320))
                .onChange(of: highlightedIndex) { index in proxy.scrollTo(index) }
                .onAppear { proxy.scrollTo(highlightedIndex) }
            }
        }
    }

    private func choose(_ index: Int) {
        guard options.indices.contains(index) else { return }
        selection = options[index].1
        isPresented = false
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard !options.isEmpty else { return false }
        switch event.keyCode {
        case 125: highlightedIndex = min(options.count - 1, highlightedIndex + 1)
        case 126: highlightedIndex = max(0, highlightedIndex - 1)
        case 36, 76: choose(highlightedIndex)
        default: return false
        }
        return true
    }
}

struct FlowWatchActionButtonStyle: ButtonStyle {
    var tint: Color = FlowWatchPalette.accent
    var isDestructive = false
    var isPrimary = false

    func makeBody(configuration: Configuration) -> some View {
        FlowWatchActionButtonBody(label: configuration.label, isPressed: configuration.isPressed,
                                  isDestructive: isDestructive, isPrimary: isPrimary)
    }
}

private struct FlowWatchActionButtonBody<Label: View>: View {
    let label: Label
    let isPressed: Bool
    let isDestructive: Bool
    let isPrimary: Bool
    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isDestructive ? FlowWatchPalette.destructive : (isPrimary ? FlowWatchPalette.inverse : FlowWatchPalette.ink))
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(isPrimary ? FlowWatchPalette.ink : (isHovering || isFocused ? FlowWatchPalette.elevated : FlowWatchPalette.well), in: Capsule())
            .overlay(Capsule().strokeBorder(FlowWatchPalette.edge.opacity(isPrimary ? 0 : 0.6), lineWidth: 1))
            .shadow(color: .black.opacity(isHovering || isFocused ? 0.08 : 0.025), radius: 6, y: 3)
            .scaleEffect(reduceMotion ? 1 : (isPressed ? 0.97 : 1))
            .opacity(isEnabled ? (isPressed ? 0.75 : 1) : 0.4)
            .offset(y: reduceMotion || !isHovering || isPressed || !isEnabled ? 0 : -1)
            .onHover { isHovering = $0 && isEnabled }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isHovering)
    }
}

struct FlowWatchThinScrollView<Content: View>: View {
    private let content: Content

    @State private var coordinateSpaceName = "FlowWatchThinScrollView-\(UUID().uuidString)"
    @State private var contentHeight: CGFloat = 1
    @State private var scrollOffset: CGFloat = 0
    @State private var dragStartOffset: CGFloat?
    @State private var isScrollbarHovered = false
    @StateObject private var scrollReference = FlowWatchScrollReference()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        GeometryReader { viewportProxy in
            let viewportHeight = max(viewportProxy.size.height, 1)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    offsetReader
                    content
                        .background(contentHeightReader)
                }
                .background(FlowWatchScrollViewConfigurator(reference: scrollReference))
            }
            .coordinateSpace(name: coordinateSpaceName)
            .scrollIndicators(.hidden)
            .onPreferenceChange(FlowWatchScrollOffsetPreferenceKey.self) { value in
                scrollOffset = min(max(-value, 0), max(contentHeight - viewportHeight, 0))
            }
            .onPreferenceChange(FlowWatchContentHeightPreferenceKey.self) { value in
                contentHeight = max(value, 1)
            }
            .overlay(alignment: .trailing) {
                thinScrollbar(viewportHeight: viewportHeight)
            }
        }
    }

    private var offsetReader: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(
                    key: FlowWatchScrollOffsetPreferenceKey.self,
                    value: proxy.frame(in: .named(coordinateSpaceName)).minY
                )
        }
        .frame(height: 0)
    }

    private var contentHeightReader: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(key: FlowWatchContentHeightPreferenceKey.self, value: proxy.size.height)
        }
    }

    @ViewBuilder
    private func thinScrollbar(viewportHeight: CGFloat) -> some View {
        let scrollableHeight = max(contentHeight - viewportHeight, 0)

        if scrollableHeight > 1 {
            let verticalInset: CGFloat = 8
            let availableTrackHeight = max(viewportHeight - verticalInset * 2, 1)
            let thumbHeight = min(
                availableTrackHeight,
                max(34, availableTrackHeight * viewportHeight / contentHeight)
            )
            let thumbTravel = max(availableTrackHeight - thumbHeight, 0)
            let progress = min(max(scrollOffset / scrollableHeight, 0), 1)

            Capsule()
                .fill(FlowWatchPalette.ink.opacity(isScrollbarHovered || dragStartOffset != nil ? 0.5 : 0.2))
                .frame(width: isScrollbarHovered || dragStartOffset != nil ? 6 : 4, height: thumbHeight)
                .frame(width: 12)
                .contentShape(Rectangle())
                .onHover { isScrollbarHovered = $0 }
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if dragStartOffset == nil { dragStartOffset = scrollOffset }
                        setScrollOffset((dragStartOffset ?? 0) + gesture.translation.height / max(thumbTravel, 1) * scrollableHeight)
                    }
                    .onEnded { _ in dragStartOffset = nil }
                )
                .accessibilityLabel(L10n.t("ui.scroll"))
                .accessibilityValue("\(Int(progress * 100))%")
                .accessibilityAdjustableAction { direction in
                    setScrollOffset(scrollOffset + (direction == .increment ? 80 : -80))
                }
                .padding(.vertical, verticalInset)
                .padding(.trailing, 5)
                .frame(maxHeight: .infinity, alignment: .topTrailing)
                .offset(y: progress * thumbTravel)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isScrollbarHovered)
        }
    }
    private func setScrollOffset(_ offset: CGFloat) {
        guard let scrollView = scrollReference.view else { return }
        let maximum = max((scrollView.documentView?.frame.height ?? 0) - scrollView.contentView.bounds.height, 0)
        scrollView.contentView.scroll(to: NSPoint(x: scrollView.contentView.bounds.minX, y: min(max(offset, 0), maximum)))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

}

private struct FlowWatchScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct FlowWatchContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 1

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private final class FlowWatchScrollReference: ObservableObject {
    weak var view: NSScrollView?
}

private struct FlowWatchScrollViewConfigurator: NSViewRepresentable {
    let reference: FlowWatchScrollReference
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configureEnclosingScrollView(for: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureEnclosingScrollView(for: nsView)
        }
    }

    private func configureEnclosingScrollView(for view: NSView) {
        guard let scrollView = view.enclosingScrollView else { return }
        reference.view = scrollView
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScroller?.isHidden = true
        scrollView.horizontalScroller?.isHidden = true
    }
}
