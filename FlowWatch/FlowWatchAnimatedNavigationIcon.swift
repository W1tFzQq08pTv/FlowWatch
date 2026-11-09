import SwiftUI

/// Each sidebar symbol has its own meaning-specific motion. The clock sleeps at rest.
struct FlowWatchAnimatedNavigationIcon: View {
    let symbol: String
    let color: Color
    let isHovered: Bool
    let activation: Int

    @State private var hoverStartedAt = Date()
    @State private var clickedAt = Date()
    @State private var isClickAnimating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.flowWatchWindowVisible) private var isWindowVisible

    private var isAnimating: Bool {
        isEnabled && isWindowVisible && !reduceMotion && (isHovered || isClickAnimating)
    }

    var body: some View {
        ZStack {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(color)
                .opacity(isAnimating ? 0 : 1)

            if isAnimating {
                TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                    let elapsed = max(0, timeline.date.timeIntervalSince(hoverStartedAt))
                    let phase = elapsed.truncatingRemainder(dividingBy: 1.6) / 1.6
                    let clickElapsed = max(0, timeline.date.timeIntervalSince(clickedAt))
                    let pulse = isClickAnimating ? sin(min(clickElapsed / 0.65, 1) * .pi) : 0

                    animatedSymbol(phase: phase, pulse: pulse)
                        .scaleEffect(1 + pulse * 0.12)
                }
            }
        }
        .frame(width: 20, height: 20)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isAnimating)
        .onChange(of: isHovered) { hovered in
            if hovered { hoverStartedAt = Date() }
        }
        .task(id: activation) {
            guard activation > 0, !reduceMotion, isEnabled else { return }
            clickedAt = Date()
            hoverStartedAt = clickedAt
            isClickAnimating = true
            do { try await Task.sleep(nanoseconds: 650_000_000) }
            catch { return }
            isClickAnimating = false
        }
        .onDisappear { isClickAnimating = false }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func animatedSymbol(phase: Double, pulse: Double) -> some View {
        switch symbol {
        case "gearshape", "arrow.triangle.2.circlepath":
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(color)
                .rotationEffect(.degrees(phase * 360 + pulse * 35))
        case "paintpalette":
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(color)
                .rotationEffect(.degrees(sin(phase * .pi * 2) * 16))
        case "power":
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(color)
                .scaleEffect(1 + sin(phase * .pi * 2) * 0.07)
        case "menubar.rectangle", "doc.text", "app.badge", "internaldrive", "house",
             "square.grid.2x2", "chart.bar.xaxis", "chart.xyaxis.line", "sparkles":
            Canvas { context, size in
                context.scaleBy(x: size.width / 20, y: size.height / 20)
                drawSymbol(context: &context, phase: phase)
            }
        default:
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(color)
                .scaleEffect(1 + sin(phase * .pi * 2) * 0.06)
        }
    }

    private func drawSymbol(context: inout GraphicsContext, phase: Double) {
        let stroke = StrokeStyle(lineWidth: 1.35, lineCap: .round, lineJoin: .round)
        switch symbol {
        case "menubar.rectangle":
            context.stroke(Path(roundedRect: CGRect(x: 2, y: 4, width: 16, height: 13), cornerRadius: 2),
                           with: .color(color), style: stroke)
            context.stroke(line([CGPoint(x: 2, y: 8), CGPoint(x: 18, y: 8)]), with: .color(color), style: stroke)
            context.fill(Path(roundedRect: CGRect(x: 4 + phase * 10, y: 5, width: 3, height: 1.6), cornerRadius: 0.8),
                         with: .color(color))
        case "doc.text":
            let outline = line([
                CGPoint(x: 5, y: 2), CGPoint(x: 12, y: 2), CGPoint(x: 16, y: 6),
                CGPoint(x: 16, y: 18), CGPoint(x: 5, y: 18), CGPoint(x: 5, y: 2)
            ])
            context.stroke(outline, with: .color(color), style: stroke)
            context.stroke(line([CGPoint(x: 12, y: 2), CGPoint(x: 12, y: 6), CGPoint(x: 16, y: 6)]),
                           with: .color(color), style: stroke)
            for index in 0..<3 {
                let progress = min(max(phase * 4 - Double(index), 0), 1)
                let y = CGFloat(9 + index * 3)
                context.stroke(line([CGPoint(x: 7, y: y), CGPoint(x: 7 + progress * 6, y: y)]),
                               with: .color(color), style: stroke)
            }
        case "app.badge":
            context.stroke(Path(roundedRect: CGRect(x: 3, y: 5, width: 13, height: 13), cornerRadius: 3),
                           with: .color(color), style: stroke)
            let radius = 2.2 + sin(phase * .pi * 2) * 0.5
            context.fill(Path(ellipseIn: CGRect(x: 16 - radius, y: 4 - radius, width: radius * 2, height: radius * 2)),
                         with: .color(color))
        case "internaldrive":
            let outline = line([
                CGPoint(x: 6, y: 4), CGPoint(x: 14, y: 4), CGPoint(x: 18, y: 11),
                CGPoint(x: 18, y: 16), CGPoint(x: 2, y: 16), CGPoint(x: 2, y: 11), CGPoint(x: 6, y: 4)
            ])
            context.stroke(outline, with: .color(color), style: stroke)
            context.stroke(line([CGPoint(x: 2, y: 11), CGPoint(x: 18, y: 11)]), with: .color(color), style: stroke)
            for index in 0..<4 {
                let opacity = 0.25 + 0.75 * max(0, sin(phase * .pi * 2 - Double(index) * 0.8))
                context.fill(Path(ellipseIn: CGRect(x: 5 + CGFloat(index) * 2.7, y: 13, width: 1.4, height: 1.4)),
                             with: .color(color.opacity(opacity)))
            }
        case "house":
            context.stroke(line([CGPoint(x: 2, y: 9), CGPoint(x: 10, y: 2), CGPoint(x: 18, y: 9)]),
                           with: .color(color), style: stroke)
            context.stroke(line([CGPoint(x: 4, y: 8), CGPoint(x: 4, y: 18),
                                 CGPoint(x: 16, y: 18), CGPoint(x: 16, y: 8)]), with: .color(color), style: stroke)
            let trace = line([
                CGPoint(x: 6, y: 13), CGPoint(x: 8, y: 13), CGPoint(x: 9, y: 10),
                CGPoint(x: 11, y: 15), CGPoint(x: 12, y: 12), CGPoint(x: 14, y: 12)
            ])
            context.stroke(trace, with: .color(color.opacity(0.25)), lineWidth: 1)
            context.stroke(trace.trimmedPath(from: max(0, phase - 0.45), to: phase),
                           with: .color(color), style: stroke)
        case "square.grid.2x2":
            for index in 0..<4 {
                let wave = sin(phase * .pi * 2 - Double(index) * .pi / 2)
                let side = 5.5 + max(0, wave) * 1.1
                let centerX = index.isMultiple(of: 2) ? 5.5 : 14.5
                let centerY = index < 2 ? 5.5 : 14.5
                let rect = CGRect(x: centerX - side / 2, y: centerY - side / 2 - max(0, wave), width: side, height: side)
                context.stroke(Path(roundedRect: rect, cornerRadius: 1.3), with: .color(color), style: stroke)
            }
        case "chart.bar.xaxis":
            context.stroke(line([CGPoint(x: 2, y: 18), CGPoint(x: 18, y: 18)]), with: .color(color), style: stroke)
            for index in 0..<3 {
                let wave = (sin(phase * .pi * 2 - Double(index) * 0.9) + 1) / 2
                let height = 4 + Double(index + 1) * 3 * (0.45 + wave * 0.55)
                context.fill(Path(roundedRect: CGRect(x: 4 + CGFloat(index) * 4.5, y: 16 - height,
                                                     width: 3, height: height), cornerRadius: 0.8), with: .color(color))
            }
        case "chart.xyaxis.line":
            context.stroke(line([CGPoint(x: 3, y: 2), CGPoint(x: 3, y: 17), CGPoint(x: 18, y: 17)]),
                           with: .color(color.opacity(0.65)), style: stroke)
            let points = [CGPoint(x: 5, y: 13), CGPoint(x: 9, y: 9), CGPoint(x: 12, y: 11), CGPoint(x: 17, y: 5)]
            let path = line(points)
            context.stroke(path, with: .color(color.opacity(0.25)), style: stroke)
            context.stroke(path.trimmedPath(from: 0, to: phase), with: .color(color), style: stroke)
            let segment = min(Int(phase * 3), 2)
            let fraction = phase * 3 - Double(segment)
            let point = CGPoint(x: points[segment].x + (points[segment + 1].x - points[segment].x) * fraction,
                                y: points[segment].y + (points[segment + 1].y - points[segment].y) * fraction)
            context.fill(Path(ellipseIn: CGRect(x: point.x - 1.5, y: point.y - 1.5, width: 3, height: 3)), with: .color(color))
        case "sparkles":
            let centers = [CGPoint(x: 10, y: 10), CGPoint(x: 4, y: 4), CGPoint(x: 17, y: 15)]
            for index in centers.indices {
                let wave = (sin(phase * .pi * 2 - Double(index) * 1.4) + 1) / 2
                let radius = (index == 0 ? 5.5 : 2.5) * (0.6 + wave * 0.5)
                context.fill(star(center: centers[index], radius: radius), with: .color(color.opacity(0.5 + wave * 0.5)))
            }
        default:
            break
        }
    }

    private func line(_ points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
        }
    }

    private func star(center: CGPoint, radius: CGFloat) -> Path {
        Path { path in
            path.move(to: CGPoint(x: center.x, y: center.y - radius))
            path.addQuadCurve(to: CGPoint(x: center.x + radius, y: center.y), control: center)
            path.addQuadCurve(to: CGPoint(x: center.x, y: center.y + radius), control: center)
            path.addQuadCurve(to: CGPoint(x: center.x - radius, y: center.y), control: center)
            path.addQuadCurve(to: CGPoint(x: center.x, y: center.y - radius), control: center)
        }
    }
}
