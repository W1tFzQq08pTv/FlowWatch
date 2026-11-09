import Charts
import SwiftUI

enum FlowWatchChartStyle {
    static let lineWidth: CGFloat = 1.8
    static let axisFont = Font.system(size: 9, weight: .medium)

    static func gridStroke(isBaseline: Bool = false) -> StrokeStyle {
        StrokeStyle(lineWidth: isBaseline ? 0.8 : 0.5)
    }

    static func gridColor(isBaseline: Bool = false) -> Color {
        FlowWatchPalette.ink.opacity(isBaseline ? 0.18 : 0.075)
    }
}

extension View {
    /// Clip marks only; axes and chart overlays (including tooltips) remain outside the mask.
    func flowWatchChartPlot() -> some View {
        chartPlotStyle { plot in
            plot.clipped()
        }
    }
}
