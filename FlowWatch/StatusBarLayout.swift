import Foundation

/// Ordered, independently enabled menu bar components. Legacy preferences are read only
/// until the user first edits the layout.
struct StatusBarLayout: Codable, Equatable {
    static let defaultsKey = "statusBarLayoutV1"

    enum Component: String, Codable, CaseIterable {
        case traffic, animation, signal
        var titleKey: String { "settings.layout.component.\(rawValue)" }
    }

    enum TrafficContent: String, Codable, CaseIterable {
        case speed, total, both
        var titleKey: String { "settings.displayMode.\(rawValue)" }
    }

    enum Direction: String, Codable, CaseIterable {
        case both, upload, download
        var titleKey: String { "settings.layout.direction.\(rawValue)" }
    }

    enum Arrangement: String, Codable, CaseIterable {
        case stacked, horizontal
        var titleKey: String { "settings.layout.arrangement.\(rawValue)" }
    }

    var order: [Component] = [.animation, .traffic, .signal]
    var enabled: [Component] = [.traffic]
    var content: TrafficContent = .speed
    var direction: Direction = .both
    var arrangement: Arrangement = .stacked
    var downloadFirst = false

    var visibleComponents: [Component] { order.filter { enabled.contains($0) } }
    var isAnimated: Bool { enabled.contains(.animation) || enabled.contains(.signal) }
    var rawValue: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    static func load(rawValue: String?, legacyMode: String?, showsTotals: Bool) -> Self {
        if let rawValue, let data = rawValue.data(using: .utf8),
           var layout = try? JSONDecoder().decode(Self.self, from: data) {
            var seen = Set<Component>()
            layout.order = (layout.order + Component.allCases).filter { seen.insert($0).inserted }
            layout.enabled = layout.order.filter { layout.enabled.contains($0) }
            if layout.enabled.isEmpty { layout.enabled = [.traffic] }
            return layout
        }
        var layout = Self()
        switch legacyMode {
        case "total": layout.content = .total
        case "both": layout.content = .both
        case "minimalSignal", "curveLoader":
            let component: Component = legacyMode == "minimalSignal" ? .signal : .animation
            layout.order = [component, .traffic] + Component.allCases.filter { $0 != component && $0 != .traffic }
            layout.enabled = showsTotals ? [component, .traffic] : [component]
            layout.content = .total
        default: break
        }
        return layout
    }

    static func load(defaults: UserDefaults) -> Self {
        load(rawValue: defaults.string(forKey: defaultsKey),
             legacyMode: defaults.string(forKey: "statusBarDisplayMode"),
             showsTotals: defaults.object(forKey: "minimalSignalShowsTrafficTotals") as? Bool ?? true)
    }

    mutating func setEnabled(_ component: Component, _ value: Bool) {
        if value {
            if !enabled.contains(component) { enabled.append(component) }
        } else if enabled.count > 1 {
            enabled.removeAll { $0 == component }
        }
    }

    mutating func move(_ component: Component, by offset: Int) {
        guard let index = order.firstIndex(of: component), order.indices.contains(index + offset) else { return }
        order.swapAt(index, index + offset)
    }
}
