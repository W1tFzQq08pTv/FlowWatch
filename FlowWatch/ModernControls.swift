import AppKit
import SwiftUI

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
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .frame(minWidth: 48)
                        .background(
                            isSelected ? tint : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color(.windowBackgroundColor).opacity(0.84), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.16), value: selection)
    }
}

struct FlowWatchDropdownControl<Value: Hashable>: View {
    let options: [(String, Value)]
    @Binding var selection: Value
    var tint: Color = .blue
    var width: CGFloat = 190
    var style: FlowWatchDropdownStyle = .accent

    @State private var isExpanded = false

    private var selectedLabel: String {
        options.first(where: { $0.1 == selection })?.0 ?? options.first?.0 ?? ""
    }

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Text(selectedLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(style.controlTextColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.80)

                Spacer(minLength: 8)

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(style.chevronColor(tint: tint))
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .frame(width: width)
            .background(style.controlBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(style.controlStroke(isExpanded: isExpanded, tint: tint), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topLeading) {
            if isExpanded {
                dropdownList
                    .offset(y: 38)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .zIndex(isExpanded ? 20 : 0)
    }

    private var dropdownList: some View {
        VStack(spacing: 4) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let isSelected = option.1 == selection

                Button {
                    withAnimation(.easeInOut(duration: 0.14)) {
                        selection = option.1
                        isExpanded = false
                    }
                } label: {
                    HStack(spacing: 8) {
                        if style.showsCheckmark {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(isSelected ? tint : Color.secondary.opacity(0.42))
                        }

                        Text(option.0)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(style.optionTextColor(isSelected: isSelected))
                            .lineLimit(1)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        style.optionBackground(isSelected: isSelected, tint: tint),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .frame(width: width)
        .background(style.menuBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(style.menuStroke, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(style.shadowOpacity), radius: style.shadowRadius, x: 0, y: style.shadowY)
    }
}

enum FlowWatchDropdownStyle {
    case accent
    case plain

    var controlBackground: Color {
        switch self {
        case .accent:
            return Color(.windowBackgroundColor).opacity(0.86)
        case .plain:
            return .white
        }
    }

    var menuBackground: Color {
        switch self {
        case .accent:
            return Color(.windowBackgroundColor).opacity(0.96)
        case .plain:
            return .white
        }
    }

    var menuStroke: Color {
        switch self {
        case .accent:
            return Color.secondary.opacity(0.14)
        case .plain:
            return Color.secondary.opacity(0.16)
        }
    }

    var showsCheckmark: Bool {
        switch self {
        case .accent:
            return true
        case .plain:
            return false
        }
    }

    var controlTextColor: Color {
        switch self {
        case .accent:
            return .primary
        case .plain:
            return .black
        }
    }

    var shadowOpacity: Double {
        switch self {
        case .accent:
            return 0.12
        case .plain:
            return 0.08
        }
    }

    var shadowRadius: CGFloat {
        switch self {
        case .accent:
            return 12
        case .plain:
            return 8
        }
    }

    var shadowY: CGFloat {
        switch self {
        case .accent:
            return 7
        case .plain:
            return 4
        }
    }

    func chevronColor(tint: Color) -> Color {
        switch self {
        case .accent:
            return tint
        case .plain:
            return .black
        }
    }

    func controlStroke(isExpanded: Bool, tint: Color) -> Color {
        switch self {
        case .accent:
            return isExpanded ? tint.opacity(0.34) : Color.secondary.opacity(0.12)
        case .plain:
            return Color.secondary.opacity(isExpanded ? 0.26 : 0.14)
        }
    }

    func optionTextColor(isSelected: Bool) -> Color {
        switch self {
        case .accent:
            return isSelected ? Color.primary : Color.secondary
        case .plain:
            return .black
        }
    }

    func optionBackground(isSelected: Bool, tint: Color) -> Color {
        switch self {
        case .accent:
            return isSelected ? tint.opacity(0.10) : Color.clear
        case .plain:
            return isSelected ? Color.primary.opacity(0.06) : Color.clear
        }
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
            .background(
                (isDestructive ? Color.red : tint).opacity(configuration.isPressed ? 0.18 : 0.10),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke((isDestructive ? Color.red : tint).opacity(0.18), lineWidth: 1)
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
