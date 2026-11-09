import SwiftUI

struct FlowWatchProgressView: View {
    var value: Double? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.flowWatchWindowVisible) private var isWindowVisible

    var body: some View {
        Group {
            if let value {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(FlowWatchPalette.well)
                        Capsule().fill(FlowWatchPalette.ink)
                            .frame(width: proxy.size.width * min(max(value.isFinite ? value : 0, 0), 1))
                    }
                }
                .frame(height: 6)
                .accessibilityValue("\(Int(min(max(value.isFinite ? value : 0, 0), 1) * 100))%")
            } else {
                TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion || !isWindowVisible)) { timeline in
                    let phase = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) / 1.2
                    HStack(spacing: 4) {
                        ForEach(0..<3) { index in
                            Circle().fill(FlowWatchPalette.ink.opacity(reduceMotion ? 0.5 : 0.25 + 0.65 * max(0, cos((phase - Double(index) / 3) * .pi * 2))))
                                .frame(width: 5, height: 5)
                        }
                    }
                }
                .frame(height: 18)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("ui.loading"))
    }
}
