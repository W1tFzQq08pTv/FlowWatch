import SwiftUI

/// Compact, interactive marks drawn from the same samples as the detailed charts.
struct FlowWatchTrafficMiniChart: View {
    enum Style { case dots, bars, balance }
    let downloads: [Double]
    let uploads: [Double]
    var style: Style = .dots
    @State private var hoveredColumn: Int?

    var body: some View {
        Canvas { context, size in
            if style == .balance {
                let down = value(in: downloads, at: 0)
                let up = value(in: uploads, at: 0)
                let fraction = down / max(down + up, 1)
                for index in 0..<36 {
                    let rect = CGRect(x: CGFloat(index) * size.width / 36, y: 10, width: size.width / 36 - 3, height: size.height - 20)
                    let color = down + up == 0 ? FlowWatchPalette.ink.opacity(0.1) : (Double(index) / 36 < fraction ? FlowWatchPalette.download : FlowWatchPalette.upload)
                    context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(color.opacity(hoveredColumn == nil ? 0.55 : 0.9)))
                }
                return
            }
            let count = columnCount
            let pitch = size.width / CGFloat(count)
            let maximum = max((0..<count).map {
                value(in: downloads, at: $0) + value(in: uploads, at: $0)
            }.max() ?? 0, 1)
            for index in 0..<count {
                let down = value(in: downloads, at: index)
                let up = value(in: uploads, at: index)
                let isHovered = hoveredColumn == index
                let emphasis = hoveredColumn == nil || isHovered ? 1.0 : 0.5
                if style == .bars {
                    let available = max(size.height - 8, 1)
                    let downHeight = available * down / maximum
                    let upHeight = available * up / maximum
                    let width = max(min(pitch - 5, 24), 0)
                    let x = CGFloat(index) * pitch + (pitch - width) / 2
                    let base = size.height - 3
                    if down + up == 0 {
                        context.fill(Path(roundedRect: CGRect(x: x, y: base - 2, width: width, height: 2), cornerRadius: 1), with: .color(FlowWatchPalette.ink.opacity(0.1)))
                    }
                    let gap: CGFloat = down > 0 && up > 0 ? min(1.5, upHeight * 0.15) : 0
                    let downRect = CGRect(x: x, y: base - downHeight, width: width, height: downHeight)
                    let upRect = CGRect(x: x, y: base - downHeight - upHeight - gap, width: width, height: upHeight)
                    for (rect, color) in [(downRect, FlowWatchPalette.download), (upRect, FlowWatchPalette.upload)] {
                        context.fill(
                            Path(roundedRect: rect, cornerRadius: min(2.5, rect.height / 2)),
                            with: .linearGradient(
                                Gradient(colors: [color.opacity(emphasis * 0.9), color.opacity(emphasis * 0.65)]),
                                startPoint: CGPoint(x: x, y: rect.minY),
                                endPoint: CGPoint(x: x, y: rect.maxY)
                            )
                        )
                    }
                } else {
                    let rows = 9
                    for row in 0..<rows {
                        let centerDistance = abs(Double(row) - 4)
                        let upper = row < 4
                        let value = upper ? down : up
                        let extent = value > 0 ? max(0.6, sqrt(value / maximum) * 4) : 0
                        let isFilled = value > 0 && centerDistance <= extent
                        let radius: CGFloat = isHovered ? 1.8 : 1.3
                        let x = CGFloat(index) * pitch + pitch / 2
                        let y = CGFloat(row) * max(size.height - 6, 0) / 8 + 3
                        context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                                     with: .color(isFilled ? (upper ? FlowWatchPalette.download : FlowWatchPalette.upload).opacity(emphasis * 0.8) : FlowWatchPalette.ink.opacity(0.07)))
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                // GeometryReader below supplies the hovered column in the same local coordinate space.
                hoverLocation = location.x
            case .ended: hoverLocation = nil; hoveredColumn = nil
            }
        }
        .overlay {
            GeometryReader { geometry in
                Color.clear.allowsHitTesting(false)
                    .onChange(of: hoverLocation) { location in
                        hoveredColumn = location.map { min(max(Int($0 / max(geometry.size.width, 1) * CGFloat(columnCount)), 0), columnCount - 1) }
                    }
            }
        }
        .accessibilityHidden(true)
    }

    private var columnCount: Int { max(downloads.count, uploads.count, 1) }

    private func value(in values: [Double], at index: Int) -> Double {
        guard values.indices.contains(index), values[index].isFinite else { return 0 }
        return max(values[index], 0)
    }

    @State private var hoverLocation: CGFloat?
}
