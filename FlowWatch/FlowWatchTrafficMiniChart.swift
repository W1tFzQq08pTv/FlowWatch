import SwiftUI

/// Compact, interactive marks drawn from the same samples as the detailed charts.
struct FlowWatchTrafficMiniChart: View {
    enum Style { case dots, bars, balance }
    let downloads: [Double]
    let uploads: [Double]
    var style: Style = .dots
    @State private var hoveredColumn: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Canvas { context, size in
            if style == .balance {
                let down = max(downloads.first ?? 0, 0)
                let up = max(uploads.first ?? 0, 0)
                let fraction = down / max(down + up, 1)
                for index in 0..<36 {
                    let rect = CGRect(x: CGFloat(index) * size.width / 36, y: 10, width: size.width / 36 - 3, height: size.height - 20)
                    let color = down + up == 0 ? FlowWatchPalette.ink.opacity(0.1) : (Double(index) / 36 < fraction ? FlowWatchPalette.download : FlowWatchPalette.upload)
                    context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(color.opacity(hoveredColumn == nil ? 0.55 : 0.9)))
                }
                return
            }
            let count = max(downloads.count, 1)
            let pitch = size.width / CGFloat(count)
            let maximum = max(zip(downloads, uploads).map { $0 + $1 }.max() ?? 0, 1)
            for index in 0..<count {
                let down = downloads.indices.contains(index) ? max(downloads[index], 0) : 0
                let up = uploads.indices.contains(index) ? max(uploads[index], 0) : 0
                let isHovered = hoveredColumn == index
                let emphasis = hoveredColumn == nil || isHovered ? 1.0 : 0.45
                let lift: CGFloat = isHovered && !reduceMotion ? 3 : 0
                if style == .bars {
                    let available = max(size.height - 8, 1)
                    let downHeight = available * down / maximum
                    let upHeight = available * up / maximum
                    let width = min(pitch - 5, 24)
                    let x = CGFloat(index) * pitch + (pitch - width) / 2
                    let base = size.height - 3 - lift
                    if down + up == 0 {
                        context.fill(Path(roundedRect: CGRect(x: x, y: base - 2, width: width, height: 2), cornerRadius: 1), with: .color(FlowWatchPalette.ink.opacity(0.1)))
                    }
                    context.fill(Path(roundedRect: CGRect(x: x, y: base - downHeight, width: width, height: downHeight), cornerRadius: 2), with: .color(FlowWatchPalette.download.opacity(emphasis * 0.9)))
                    context.fill(Path(roundedRect: CGRect(x: x, y: base - downHeight - upHeight - 1, width: width, height: upHeight), cornerRadius: 2), with: .color(FlowWatchPalette.upload.opacity(emphasis * 0.85)))
                } else {
                    let rows = 9
                    for row in 0..<rows {
                        let centerDistance = abs(Double(row) - 4)
                        let upper = row < 4
                        let value = upper ? down : up
                        let extent = value > 0 ? max(0.6, sqrt(value / maximum) * 4) : 0
                        let isFilled = centerDistance <= extent
                        let radius: CGFloat = isHovered ? 1.8 : 1.3
                        let x = CGFloat(index) * pitch + pitch / 2
                        let y = CGFloat(row) * (size.height - 4) / 8 + 2 - lift
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
                        hoveredColumn = location.map { min(max(Int($0 / max(geometry.size.width, 1) * CGFloat(max(downloads.count, 1))), 0), max(downloads.count - 1, 0)) }
                    }
            }
        }
        .accessibilityHidden(true)
    }

    @State private var hoverLocation: CGFloat?
}
