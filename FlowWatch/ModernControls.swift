import AppKit
import SwiftUI

enum FlowWatchGlassMaterial {
    case ultraThin
    case thin
    case regular

    var material: Material {
        switch self {
        case .ultraThin:
            return .ultraThinMaterial
        case .thin:
            return .thinMaterial
        case .regular:
            return .regularMaterial
        }
    }
}

extension View {
    func flowWatchGlassPanel(
        cornerRadius: CGFloat = 8,
        material: FlowWatchGlassMaterial = .regular,
        strokeOpacity: Double = 0.07,
        shadowOpacity: Double = 0.025
    ) -> some View {
        self
            .background(material.material, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(strokeOpacity), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(shadowOpacity), radius: 8, x: 0, y: 2)
    }

    func flowWatchGlassCapsule(
        material: FlowWatchGlassMaterial = .thin,
        strokeOpacity: Double = 0.08,
        shadowOpacity: Double = 0.015
    ) -> some View {
        self
            .background(material.material, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.primary.opacity(strokeOpacity), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(shadowOpacity), radius: 4, x: 0, y: 1)
    }

    func flowWatchGlassButtonSurface(
        tint: Color,
        isSelected: Bool = false,
        cornerRadius: CGFloat = 8
    ) -> some View {
        self
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.thinMaterial)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(tint.opacity(isSelected ? 0.16 : 0.0))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(isSelected ? tint.opacity(0.24) : Color.primary.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(isSelected ? 0.035 : 0.015), radius: isSelected ? 6 : 4, x: 0, y: 1)
    }
}

struct FlowWatchSegmentedControl<Value: Hashable>: View {
    let options: [(String, Value)]
    @Binding var selection: Value
    var tint: Color = .blue

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let isSelected = selection == option.1

                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        selection = option.1
                    }
                } label: {
                    Text(option.0)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isSelected ? tint : Color.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .frame(minWidth: 48)
                        .flowWatchGlassButtonSurface(tint: tint, isSelected: isSelected, cornerRadius: 7)
                        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .flowWatchGlassPanel(cornerRadius: 9, material: .thin)
        .animation(.easeInOut(duration: 0.16), value: selection)
    }
}

struct FlowWatchMenuControl<Value: Hashable>: View {
    let options: [(String, Value)]
    @Binding var selection: Value
    var tint: Color = .blue
    var width: CGFloat = 220

    private var selectedLabel: String {
        options.first(where: { $0.1 == selection })?.0 ?? options.first?.0 ?? ""
    }

    var body: some View {
        Menu {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let isSelected = option.1 == selection

                Button {
                    selection = option.1
                } label: {
                    if isSelected {
                        Label(option.0, systemImage: "checkmark")
                    } else {
                        Text(option.0)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(selectedLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.80)

                Spacer(minLength: 8)

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .frame(width: width)
            .flowWatchGlassButtonSurface(tint: tint, cornerRadius: 9)
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

struct FlowWatchActionButtonStyle: ButtonStyle {
    var tint: Color = .blue
    var isDestructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(isDestructive ? Color.red : tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .flowWatchGlassButtonSurface(
                tint: isDestructive ? .red : tint,
                isSelected: configuration.isPressed,
                cornerRadius: 8
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct FlowWatchThinScrollView<Content: View>: View {
    private let content: Content

    @State private var coordinateSpaceName = "FlowWatchThinScrollView-\(UUID().uuidString)"
    @State private var contentHeight: CGFloat = 1
    @State private var scrollOffset: CGFloat = 0

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
                .background(FlowWatchScrollViewConfigurator())
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
                .fill(Color.secondary.opacity(0.28))
                .frame(width: 4, height: thumbHeight)
                .padding(.vertical, verticalInset)
                .padding(.trailing, 5)
                .frame(maxHeight: .infinity, alignment: .topTrailing)
                .offset(y: progress * thumbTravel)
                .animation(.easeOut(duration: 0.12), value: scrollOffset)
                .allowsHitTesting(false)
        }
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

private struct FlowWatchScrollViewConfigurator: NSViewRepresentable {
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
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScroller?.isHidden = true
        scrollView.horizontalScroller?.isHidden = true
    }
}
