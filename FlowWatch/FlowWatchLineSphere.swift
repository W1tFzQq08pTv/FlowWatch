import AppKit
import Combine
import SwiftUI

/// A quiet network sculpture; it only animates while the pointer is over it.
struct FlowWatchLineSphere: View {
    @State private var isHovering = false
    @State private var pointer = CGPoint.zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.flowWatchWindowVisible) private var isWindowVisible

    private static let meridians: [[SIMD3<Double>]] = (0..<22).map { meridian in
        let longitude = Double(meridian) / 22 * .pi * 2
        return (0...64).map { step in
            let latitude = Double(step) / 64 * .pi - .pi / 2
            return SIMD3(cos(latitude) * cos(longitude), sin(latitude), cos(latitude) * sin(longitude))
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: !isHovering || reduceMotion || !isWindowVisible)) { timeline in
            Canvas { context, size in
                let radius = min(size.width, size.height) * 0.43
                let angle = reduceMotion ? 0.35 : timeline.date.timeIntervalSinceReferenceDate * 0.16 + pointer.x * 0.005
                let tilt = -0.35 + (reduceMotion ? 0 : pointer.y * 0.001)
                let cosAngle = cos(angle), sinAngle = sin(angle)
                let cosTilt = cos(tilt), sinTilt = sin(tilt)
                for (meridian, vertices) in Self.meridians.enumerated() {
                    var path = Path()
                    var front = 0.0
                    for (step, vertex) in vertices.enumerated() {
                        let rotatedX = vertex.x * cosAngle + vertex.z * sinAngle
                        let rotatedZ = -vertex.x * sinAngle + vertex.z * cosAngle
                        let tiltedX = rotatedX * cosTilt - vertex.y * sinTilt
                        let tiltedY = rotatedX * sinTilt + vertex.y * cosTilt
                        let perspective = 1 + rotatedZ * 0.12
                        let point = CGPoint(x: size.width / 2 + tiltedX * radius * perspective,
                                            y: size.height / 2 + tiltedY * radius * perspective)
                        if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
                        front += rotatedZ
                    }
                    let tint = meridian.isMultiple(of: 5) ? FlowWatchPalette.download : FlowWatchPalette.ink
                    context.stroke(path, with: .color(tint.opacity(front >= 0 ? 0.38 : 0.12)), lineWidth: meridian.isMultiple(of: 5) ? 1.1 : 0.6)
                }
            }
        }
        .contentShape(Circle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let location): isHovering = true; pointer = location
            case .ended: isHovering = false
            }
        }
        .onDisappear { isHovering = false }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in isHovering = false }
        .accessibilityHidden(true)
    }
}
