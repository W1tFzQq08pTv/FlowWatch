import SwiftUI

/// Shared geometry keeps every segment inside its actual share, including tiny slices.
struct FlowWatchRingChart: View {
    struct Segment {
        let value: Double
        let color: Color
    }

    let segments: [Segment]
    let centerTitle: String
    let centerValue: String

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.colorScheme) private var colorScheme

    private var positiveSegments: [(index: Int, segment: Segment)] {
        segments.enumerated().compactMap { index, segment in
            segment.value.isFinite && segment.value > 0 ? (index, segment) : nil
        }
    }

    var body: some View {
        ZStack {
            Canvas { context, size in
                let slices = positiveSegments
                // Normalize before summing so even very large finite inputs stay finite.
                let maximum = slices.map(\.segment.value).max() ?? 1
                let total = slices.reduce(0) { $0 + $1.segment.value / maximum }
                let diameter = min(size.width, size.height)
                let thickness = diameter * 0.115
                let outerRadius = max(diameter / 2 - 3, 0)
                let innerRadius = max(outerRadius - thickness, 0)
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let fullTurn = Double.pi * 2

                let track = FlowWatchRingGeometry.path(
                    center: center, innerRadius: innerRadius, outerRadius: outerRadius,
                    start: -.pi / 2, sweep: fullTurn, separated: false
                )
                context.fill(track, with: .color(FlowWatchPalette.ink.opacity(0.055)))

                guard total > 0 else { return }
                var start = -Double.pi / 2
                for (index, slice) in slices {
                    let sweep = (slice.value / maximum) / total * fullTurn
                    let path = FlowWatchRingGeometry.path(
                        center: center, innerRadius: innerRadius, outerRadius: outerRadius,
                        start: start, sweep: sweep, separated: slices.count > 1
                    )
                    let color = slice.color
                    context.fill(path, with: .linearGradient(
                        Gradient(colors: [color, color.opacity(colorScheme == .dark ? 0.78 : 0.82)]),
                        startPoint: .zero,
                        endPoint: CGPoint(x: size.width, y: size.height)
                    ))
                    // Texture supplements the legend order when colors cannot distinguish slices.
                    if differentiateWithoutColor && !index.isMultiple(of: 2) {
                        var hatch = Path()
                        for offset in stride(from: -size.height, through: size.width, by: 5) {
                            hatch.move(to: CGPoint(x: offset, y: 0))
                            hatch.addLine(to: CGPoint(x: offset + size.height, y: size.height))
                        }
                        var clippedContext = context
                        clippedContext.clip(to: path)
                        clippedContext.stroke(hatch, with: .color(FlowWatchPalette.surface.opacity(0.5)), lineWidth: 1)
                    }
                    if differentiateWithoutColor && sweep * innerRadius > 16 {
                        let angle = start + sweep / 2
                        let radius = (innerRadius + outerRadius) / 2
                        context.draw(
                            Text("\(index + 1)").font(.system(size: 8, weight: .bold)).foregroundColor(.white),
                            at: CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
                        )
                    }
                    start += sweep
                }
            }

            VStack(spacing: 5) {
                Text(centerTitle)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(centerValue)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(FlowWatchPalette.ink)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .padding(23)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(centerTitle)
        .accessibilityValue(centerValue)
    }
}

enum FlowWatchRingGeometry {
    static func path(
        center: CGPoint, innerRadius: CGFloat, outerRadius: CGFloat,
        start: Double, sweep: Double, separated: Bool
    ) -> Path {
        guard outerRadius > innerRadius, innerRadius > 0, sweep > 0 else { return Path() }

        if !separated {
            var ring = Path()
            ring.addArc(center: center, radius: outerRadius, startAngle: .radians(start),
                        endAngle: .radians(start + .pi * 2), clockwise: false)
            ring.addLine(to: point(center: center, radius: innerRadius, angle: start))
            ring.addArc(center: center, radius: innerRadius, startAngle: .radians(start + .pi * 2),
                        endAngle: .radians(start), clockwise: true)
            ring.closeSubpath()
            return ring
        }

        // Gaps and corners shrink with the slice, never enlarge its represented angle.
        let gap = min(0.025, sweep * 0.12)
        let from = start + gap / 2
        let to = start + sweep - gap / 2
        let corner = min((outerRadius - innerRadius) * 0.24, innerRadius * (to - from) * 0.18)
        let outerInset = Double(corner / outerRadius)
        let innerInset = Double(corner / innerRadius)
        var path = Path()
        path.move(to: point(center: center, radius: outerRadius, angle: from + outerInset))
        path.addArc(center: center, radius: outerRadius, startAngle: .radians(from + outerInset),
                    endAngle: .radians(to - outerInset), clockwise: false)
        path.addQuadCurve(to: point(center: center, radius: outerRadius - corner, angle: to),
                          control: point(center: center, radius: outerRadius, angle: to))
        path.addLine(to: point(center: center, radius: innerRadius + corner, angle: to))
        path.addQuadCurve(to: point(center: center, radius: innerRadius, angle: to - innerInset),
                          control: point(center: center, radius: innerRadius, angle: to))
        path.addArc(center: center, radius: innerRadius, startAngle: .radians(to - innerInset),
                    endAngle: .radians(from + innerInset), clockwise: true)
        path.addQuadCurve(to: point(center: center, radius: innerRadius + corner, angle: from),
                          control: point(center: center, radius: innerRadius, angle: from))
        path.addLine(to: point(center: center, radius: outerRadius - corner, angle: from))
        path.addQuadCurve(to: point(center: center, radius: outerRadius, angle: from + outerInset),
                          control: point(center: center, radius: outerRadius, angle: from))
        path.closeSubpath()
        return path
    }

    private static func point(center: CGPoint, radius: CGFloat, angle: Double) -> CGPoint {
        CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
    }
}
