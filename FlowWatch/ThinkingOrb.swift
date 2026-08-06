import AppKit
import Foundation

// Native Core Graphics port of the 20 pt presets from thinking-orbs.
// Source: https://github.com/W1tFzQq08pTv/thinking-orbs
// Upstream revision: e94f207ea122f8cca0aaa6409ab7fe82d55c38f1
// Copyright (c) 2026 Jakub Antalik, licensed under the MIT License.

enum ThinkingOrbState: String, CaseIterable, Identifiable {
    case working
    case searching
    case solving
    case listening
    case connecting
    case weaving
    case composing
    case breathing
    case shaping

    var id: String { rawValue }

    var displayName: String {
        "Orb · \(rawValue.capitalized)"
    }

    fileprivate var speed: Double {
        switch self {
        case .working: return 3.9
        case .searching: return 2.665
        case .solving: return 1.95
        case .listening: return 3.998
        case .connecting: return 6.63
        case .weaving: return 2.75
        case .composing: return 3.12
        case .breathing: return 3.78
        case .shaping: return 2.08
        }
    }
}

enum DynamicGraphicPreset: RawRepresentable, Hashable, CaseIterable, Identifiable {
    case thinkingOrb(ThinkingOrbState)
    case legacyCurve(MathCurveLoaderPreset)

    private static let thinkingOrbPrefix = "thinkingOrb."

    static var allCases: [DynamicGraphicPreset] {
        ThinkingOrbState.allCases.map(DynamicGraphicPreset.thinkingOrb)
            + MathCurveLoaderPreset.allCases.map(DynamicGraphicPreset.legacyCurve)
    }

    static var randomCases: [DynamicGraphicPreset] {
        allCases
    }

    init?(rawValue: String) {
        if rawValue.hasPrefix(Self.thinkingOrbPrefix) {
            let stateRaw = String(rawValue.dropFirst(Self.thinkingOrbPrefix.count))
            guard let state = ThinkingOrbState(rawValue: stateRaw) else {
                return nil
            }
            self = .thinkingOrb(state)
            return
        }

        guard let preset = MathCurveLoaderPreset(rawValue: rawValue) else {
            return nil
        }
        self = .legacyCurve(preset)
    }

    var rawValue: String {
        switch self {
        case .thinkingOrb(let state):
            return Self.thinkingOrbPrefix + state.rawValue
        case .legacyCurve(let preset):
            return preset.rawValue
        }
    }

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .thinkingOrb(let state):
            return state.displayName
        case .legacyCurve(let preset):
            return preset.displayName
        }
    }
}

struct DynamicGraphicRenderer {
    static func makeImage(
        preset: DynamicGraphicPreset,
        timeMilliseconds: Double,
        phaseOffset: Double,
        color: NSColor,
        size: NSSize = NSSize(width: 18, height: 18)
    ) -> NSImage? {
        switch preset {
        case .thinkingOrb(let state):
            return ThinkingOrbRenderer.makeImage(
                state: state,
                timeMilliseconds: timeMilliseconds,
                phaseOffset: phaseOffset,
                color: color,
                size: size
            )
        case .legacyCurve(let preset):
            return MathCurveLoaderRenderer.makeImage(
                preset: preset,
                timeMilliseconds: timeMilliseconds,
                phaseOffset: phaseOffset,
                color: color,
                size: size
            )
        }
    }
}

private struct ThinkingOrbDot {
    let x: Double
    let y: Double
    let z: Double
    let radius: Double
    let white: Double
    let alpha: Double
}

private struct ThinkingOrbLine {
    let x1: Double
    let y1: Double
    let x2: Double
    let y2: Double
    let white: Double
    let alpha: Double
    let width: Double
}

private struct ThinkingOrbVector3 {
    var x: Double
    var y: Double
    var z: Double
}

private struct ThinkingOrbMove {
    let axis: Int
    let lowerBound: Double
    let upperBound: Double
    let angle: Double
}

private struct ThinkingOrbSolveCycle {
    let amounts: [Double]
    let activeIndex: Int
}

private enum ThinkingOrbRenderer {
    private static let logicalSize: Double = 20

    static func makeImage(
        state: ThinkingOrbState,
        timeMilliseconds: Double,
        phaseOffset: Double,
        color: NSColor,
        size: NSSize
    ) -> NSImage? {
        let backingScale = NSScreen.main?.backingScaleFactor ?? 2
        let pixelsWide = max(1, Int((size.width * backingScale).rounded(.up)))
        let pixelsHigh = max(1, Int((size.height * backingScale).rounded(.up)))
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [.alphaFirst],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let graphicsContext = NSGraphicsContext(bitmapImageRep: representation) else {
            return nil
        }
        representation.size = size

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        NSGraphicsContext.current = graphicsContext
        let context = graphicsContext.cgContext
        context.scaleBy(x: backingScale, y: backingScale)
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)

        let side = min(size.width, size.height)
        let scale = side / logicalSize
        context.translateBy(
            x: (size.width - side) / 2,
            y: (size.height + side) / 2
        )
        context.scaleBy(x: scale, y: -scale)

        let normalizedColor = color.usingColorSpace(.sRGB) ?? color
        let seconds = max(0, timeMilliseconds) / 1_000
            + normalizedPhase(phaseOffset) * 8
        draw(
            state: state,
            context: context,
            time: seconds * state.speed,
            color: normalizedColor
        )

        let image = NSImage(size: size)
        image.addRepresentation(representation)
        return image
    }

    private static func draw(
        state: ThinkingOrbState,
        context: CGContext,
        time: Double,
        color: NSColor
    ) {
        switch state {
        case .working:
            drawOrbits(context: context, time: time, color: color)
        case .searching:
            drawGlobe(context: context, time: time, color: color)
        case .solving:
            drawRubik(context: context, time: time, color: color)
        case .listening:
            drawWave(context: context, time: time, color: color)
        case .connecting:
            drawWeb(context: context, time: time, color: color)
        case .weaving:
            drawBraid(context: context, time: time, color: color)
        case .composing:
            drawRibbon(context: context, time: time, color: color, isFaceOn: false)
        case .breathing:
            drawRibbon(context: context, time: time, color: color, isFaceOn: true)
        case .shaping:
            drawMorph(context: context, time: time, color: color)
        }
    }

    // MARK: - Working

    private static func drawOrbits(context: CGContext, time: Double, color: NSColor) {
        let center = logicalSize / 2
        let sphereRadius = (logicalSize / 2) * 0.82
        let projector = makeProjector(yaw: time * 0.12, tilt: 0.3, centerX: center, centerY: center, scale: 1)
        let radiusScale = scaledRadius(power: 0.6)
        let orbitCount = 3
        let ghostCount = 10
        let particles = 3
        let ghostRadius = 0.9 * 2.4
        let particleRadius = 1.2 * 2.4
        let particleDepthRadius = 1.6 * 2.4
        var dots: [ThinkingOrbDot] = []

        for orbit in 0..<orbitCount {
            let h1 = hash(Double(orbit), 1.7)
            let h2 = hash(Double(orbit), 5.2)
            let h3 = hash(Double(orbit), 8.9)
            let orbitRadius = sphereRadius * (0.45 + 0.52 * h1)
            let theta = h1 * 2 * .pi
            let phi = acos(2 * h2 - 1)
            let normalX = sin(phi) * cos(theta)
            let normalY = cos(phi)
            let normalZ = sin(phi) * sin(theta)
            var basisUX = -normalY
            var basisUY = normalX
            let basisUZ = 0.0
            let basisULength = max(1e-6, hypot(basisUX, basisUY))
            basisUX /= basisULength
            basisUY /= basisULength
            let basisVX = normalY * basisUZ - normalZ * basisUY
            let basisVY = normalZ * basisUX - normalX * basisUZ
            let basisVZ = normalX * basisUY - normalY * basisUX
            let speed = (0.25 + 0.55 * h3) * (h3 > 0.5 ? 1 : -1)

            for index in 0..<ghostCount {
                let angle = (Double(index) / Double(ghostCount)) * 2 * .pi
                let projected = projector(
                    (basisUX * cos(angle) + basisVX * sin(angle)) * orbitRadius,
                    (basisUY * cos(angle) + basisVY * sin(angle)) * orbitRadius,
                    (basisUZ * cos(angle) + basisVZ * sin(angle)) * orbitRadius
                )
                let depth = (projected.z / orbitRadius + 1) / 2
                dots.append(ThinkingOrbDot(
                    x: projected.x,
                    y: projected.y,
                    z: projected.z,
                    radius: ghostRadius * radiusScale,
                    white: 0.72,
                    alpha: 0.5 * (0.4 + 0.6 * depth)
                ))
            }

            for particle in 0..<particles {
                let angle = time * speed
                    + (Double(particle) / Double(particles)) * 2 * .pi
                    + h2 * 6
                let projected = projector(
                    (basisUX * cos(angle) + basisVX * sin(angle)) * orbitRadius,
                    (basisUY * cos(angle) + basisVY * sin(angle)) * orbitRadius,
                    (basisUZ * cos(angle) + basisVZ * sin(angle)) * orbitRadius
                )
                let depth = (projected.z / orbitRadius + 1) / 2
                dots.append(ThinkingOrbDot(
                    x: projected.x,
                    y: projected.y,
                    z: projected.z,
                    radius: (particleRadius + particleDepthRadius * depth) * radiusScale,
                    white: 0.3 - 0.22 * depth,
                    alpha: 1
                ))
            }
        }
        paint(dots: dots, context: context, color: color, minimumRadius: 0.3)
    }

    // MARK: - Searching, solving, listening

    private static func drawGlobe(context: CGContext, time: Double, color: NSColor) {
        let spin = 0.5
        let center = logicalSize / 2
        let radius = (logicalSize / 2) * 0.82
        let projector = makeProjector(
            yaw: time * spin,
            tilt: 0.4 + 0.06 * sin(time * 0.35),
            centerX: center,
            centerY: center,
            scale: radius
        )
        let scan = time * (spin + (1.7 - spin) * 4.335)
        let radiusScale = scaledRadius(power: 0.6)
        var dots: [ThinkingOrbDot] = []
        let latitudeRings = 6
        let longitudeDensity = 14

        for latitudeIndex in 0...latitudeRings {
            let latitude = -.pi / 2 + (Double(latitudeIndex) / Double(latitudeRings)) * .pi
            let cosineLatitude = cos(latitude)
            let sineLatitude = sin(latitude)
            let longitudeCount = max(1, Int((abs(cosineLatitude) * Double(longitudeDensity)).rounded()))
            for longitudeIndex in 0..<longitudeCount {
                let longitude = (Double(longitudeIndex) / Double(longitudeCount)) * 2 * .pi
                let projected = projector(
                    cosineLatitude * cos(longitude),
                    sineLatitude,
                    cosineLatitude * sin(longitude)
                )
                let depth = (projected.z + 1) / 2
                let delta = angleDelta(longitude + time * spin, scan)
                let boost = exp(-(delta * delta) / 0.18) * max(0, projected.z)
                dots.append(ThinkingOrbDot(
                    x: projected.x,
                    y: projected.y,
                    z: projected.z,
                    radius: (1.05 + 2.975 * depth + 1.0 * boost) * radiusScale,
                    white: 0.62 - 0.54 * depth,
                    alpha: 0.45 + 0.55 * min(1, boost)
                ))
            }
        }
        paint(dots: dots, context: context, color: color, minimumRadius: 0.3)
    }

    private static func drawRubik(context: CGContext, time: Double, color: NSColor) {
        let center = logicalSize / 2
        let sphereRadius = (logicalSize / 2) * 0.82
        let projector = makeProjector(
            yaw: time * 0.55,
            tilt: 0.35 + 0.1 * sin(time * 0.9),
            centerX: center,
            centerY: center,
            scale: sphereRadius
        )
        let radiusScale = scaledRadius(power: 0.6)
        let moves = makeMoves(count: 14)
        let cycle = solveCycle(time: time, count: moves.count, slotDuration: 0.42, rest: 1.2)
        let latitudeRings = 4
        let longitudeDensity = 12
        var dots: [ThinkingOrbDot] = []

        for latitudeIndex in 0...latitudeRings {
            let latitude = -.pi / 2 + (Double(latitudeIndex) / Double(latitudeRings)) * .pi
            let cosineLatitude = cos(latitude)
            let sineLatitude = sin(latitude)
            let longitudeCount = max(1, Int((abs(cosineLatitude) * Double(longitudeDensity)).rounded()))
            for longitudeIndex in 0..<longitudeCount {
                let longitude = (Double(longitudeIndex) / Double(longitudeCount)) * 2 * .pi
                let moved = applyMoves(
                    ThinkingOrbVector3(
                        x: cosineLatitude * cos(longitude),
                        y: sineLatitude,
                        z: cosineLatitude * sin(longitude)
                    ),
                    moves: moves,
                    cycle: cycle
                )
                let projected = projector(moved.vector.x, moved.vector.y, moved.vector.z)
                let depth = (projected.z + 1) / 2
                dots.append(ThinkingOrbDot(
                    x: projected.x,
                    y: projected.y,
                    z: projected.z,
                    radius: (1.14 + 3.23 * depth + (moved.isActive ? 0.57 : 0)) * radiusScale,
                    white: 0.62 - 0.54 * depth - (moved.isActive ? 0.14 : 0),
                    alpha: 1
                ))
            }
        }
        paint(dots: dots, context: context, color: color, minimumRadius: 0.3)
    }

    private static func drawWave(context: CGContext, time: Double, color: NSColor) {
        let center = logicalSize / 2
        let sphereRadius = (logicalSize / 2) * 0.874
        let projector = makeProjector(yaw: time * 0.18, tilt: 0.38, centerX: center, centerY: center, scale: 1)
        let radiusScale = scaledRadius(power: 0.6)
        let rings = 5
        let longitudeDensity = 14
        var dots: [ThinkingOrbDot] = []

        for ringIndex in 0...rings {
            let latitude = -.pi / 2 + (Double(ringIndex) / Double(rings)) * .pi
            let cosineLatitude = cos(latitude)
            let sineLatitude = sin(latitude)
            let wave = 0.62 * sin(time * 2.1 - Double(ringIndex) * 0.52)
                + 0.38 * sin(time * 1.27 + Double(ringIndex) * 0.83)
            let radius = sphereRadius * (0.88 + 0.105 * wave)
            let longitudeCount = max(1, Int((abs(cosineLatitude) * Double(longitudeDensity)).rounded()))
            for longitudeIndex in 0..<longitudeCount {
                let longitude = (Double(longitudeIndex) / Double(longitudeCount)) * 2 * .pi
                let projected = projector(
                    cosineLatitude * cos(longitude) * radius,
                    sineLatitude * radius,
                    cosineLatitude * sin(longitude) * radius
                )
                let depth = (projected.z / sphereRadius + 1) / 2
                let crest = max(0, wave)
                dots.append(ThinkingOrbDot(
                    x: projected.x,
                    y: projected.y,
                    z: projected.z,
                    radius: (0.96 + 2.72 * depth) * (1 + 0.4 * crest) * radiusScale,
                    white: 0.66 - 0.56 * depth - 0.1 * crest,
                    alpha: 1
                ))
            }
        }
        paint(dots: dots, context: context, color: color, minimumRadius: 0.3)
    }

    // MARK: - Connecting

    private static func drawWeb(context: CGContext, time: Double, color: NSColor) {
        let center = logicalSize / 2
        let sphereRadius = (logicalSize / 2) * 0.8
        let projector = makeProjector(
            yaw: time * 0.12,
            tilt: 0.32,
            centerX: center,
            centerY: center,
            scale: sphereRadius
        )
        let radiusScale = scaledRadius(power: 0.6)
        let nodeCount = 8
        let threshold = 0.72
        let nodeRadius = 2.128
        let nodeDepthRadius = 2.736
        var nodes: [ThinkingOrbVector3] = []

        for index in 0..<nodeCount {
            let direction = fibonacciDirection(index: index, count: nodeCount)
            let x = direction.x + 0.6 * (valueNoise(Double(index) * 0.31 + 9, time * 0.24) - 0.5)
            let y = direction.y + 0.6 * (valueNoise(Double(index) * 0.53 + 27, time * 0.21) - 0.5)
            let z = direction.z + 0.6 * (valueNoise(Double(index) * 0.77 + 55, time * 0.27) - 0.5)
            let length = max(1e-6, sqrt(x * x + y * y + z * z))
            nodes.append(ThinkingOrbVector3(x: x / length, y: y / length, z: z / length))
        }

        var lines: [ThinkingOrbLine] = []
        var dots: [ThinkingOrbDot] = []
        for firstIndex in 0..<nodeCount {
            for secondIndex in (firstIndex + 1)..<nodeCount {
                let first = nodes[firstIndex]
                let second = nodes[secondIndex]
                let deltaX = first.x - second.x
                let deltaY = first.y - second.y
                let deltaZ = first.z - second.z
                let distance = sqrt(deltaX * deltaX + deltaY * deltaY + deltaZ * deltaZ)
                guard distance < threshold else { continue }
                let firstProjected = projector(first.x, first.y, first.z)
                let secondProjected = projector(second.x, second.y, second.z)
                let depth = ((firstProjected.z + secondProjected.z) / 2 + 1) / 2
                lines.append(ThinkingOrbLine(
                    x1: firstProjected.x,
                    y1: firstProjected.y,
                    x2: secondProjected.x,
                    y2: secondProjected.y,
                    white: 0.42,
                    alpha: (1 - distance / threshold) * (0.3 + 0.55 * depth),
                    width: max(0.6, 0.8 * radiusScale)
                ))
            }
        }

        for index in 0..<nodeCount {
            let node = nodes[index]
            let projected = projector(node.x, node.y, node.z)
            let depth = (projected.z + 1) / 2
            let pulse = 1 + 0.25 * sin(time * 1.4 + Double(index) * 2.7)
            dots.append(ThinkingOrbDot(
                x: projected.x,
                y: projected.y,
                z: projected.z,
                radius: (nodeRadius + nodeDepthRadius * depth) * pulse * radiusScale,
                white: 0.55 - 0.45 * depth,
                alpha: 1
            ))
        }

        for signal in 0..<1 {
            let segment = floor(time * 0.55 + Double(signal) * 7.31)
            let firstIndex = Int(floor(hash(segment, Double(signal) * 3.1 + 1.7) * Double(nodeCount)))
            let secondIndex = Int(floor(hash(segment, Double(signal) * 5.7 + 4.2) * Double(nodeCount)))
            guard firstIndex != secondIndex else { continue }
            let progress = fractionalPart(time * 0.55 + Double(signal) * 7.31)
            let first = nodes[firstIndex]
            let second = nodes[secondIndex]
            let x = interpolate(first.x, second.x, progress)
            let y = interpolate(first.y, second.y, progress)
            let z = interpolate(first.z, second.z, progress)
            let length = max(1e-6, sqrt(x * x + y * y + z * z))
            let projected = projector(x / length, y / length, z / length)
            let depth = (projected.z + 1) / 2
            dots.append(ThinkingOrbDot(
                x: projected.x,
                y: projected.y,
                z: projected.z,
                radius: (nodeRadius * 1.5 + nodeDepthRadius * depth) * radiusScale,
                white: 0.05,
                alpha: 0.5 + 0.5 * depth
            ))
        }

        paint(lines: lines, context: context, color: color)
        paint(dots: dots, context: context, color: color, minimumRadius: 0.3)
    }

    // MARK: - Weaving, composing, breathing

    private static func drawBraid(context: CGContext, time: Double, color: NSColor) {
        let center = logicalSize / 2
        let sphereRadius = (logicalSize / 2) * 0.76
        let projector = makeProjector(yaw: time * 0.4, tilt: 0.3, centerX: center, centerY: center, scale: 1)
        let radiusScale = scaledRadius(power: 0.6)
        var dots: [ThinkingOrbDot] = []
        let ghostCount = 17

        for index in 0..<ghostCount {
            let direction = fibonacciDirection(index: index, count: ghostCount)
            let projected = projector(
                direction.x * sphereRadius,
                direction.y * sphereRadius,
                direction.z * sphereRadius
            )
            let depth = (projected.z / sphereRadius + 1) / 2
            dots.append(ThinkingOrbDot(
                x: projected.x,
                y: projected.y,
                z: projected.z,
                radius: 0.8 * radiusScale,
                white: 0.78,
                alpha: 0.1 + 0.22 * depth
            ))
        }

        let strandCount = 6
        for strand in 0..<3 {
            let phase = (Double(strand) / 3) * 2 * .pi
            for index in 0..<strandCount {
                let vertical = (fractionalPart(Double(index) / Double(strandCount) + time * 0.045) * 2 - 1) * 0.96
                let surface = sqrt(max(0, 1 - vertical * vertical))
                let endFade = min(1, (1 - abs(vertical)) / 0.1)
                let angle = vertical * .pi * 3 + phase
                let weave = 1 + 0.075 * sin(vertical * .pi * 6 + phase * 2 + time * 0.8)
                let radius = surface * sphereRadius * weave
                let projected = projector(
                    cos(angle) * radius,
                    vertical * sphereRadius * weave,
                    sin(angle) * radius
                )
                let depth = (projected.z / sphereRadius + 1) / 2
                dots.append(ThinkingOrbDot(
                    x: projected.x,
                    y: projected.y,
                    z: projected.z,
                    radius: (1.632 + 2.448 * depth) * radiusScale,
                    white: 0.55 - 0.45 * depth,
                    alpha: endFade * (0.45 + 0.55 * depth)
                ))
            }
        }
        paint(dots: dots, context: context, color: color, minimumRadius: 0.3)
    }

    private static func drawRibbon(
        context: CGContext,
        time: Double,
        color: NSColor,
        isFaceOn: Bool
    ) {
        let center = logicalSize / 2
        let sphereRadius = (logicalSize / 2) * 0.78
        let cameraTilt = 0.3
        let projector = makeProjector(yaw: 0, tilt: cameraTilt, centerX: center, centerY: center, scale: 1)
        let radiusScale = scaledRadius(power: 0.6)
        var dots: [ThinkingOrbDot] = []
        let ghostCount = isFaceOn ? 0 : 8

        for index in 0..<ghostCount {
            let direction = fibonacciDirection(index: index, count: ghostCount)
            let projected = projector(
                direction.x * sphereRadius,
                direction.y * sphereRadius,
                direction.z * sphereRadius
            )
            let depth = (projected.z / sphereRadius + 1) / 2
            dots.append(ThinkingOrbDot(
                x: projected.x,
                y: projected.y,
                z: projected.z,
                radius: 0.8 * radiusScale,
                white: 0.78,
                alpha: 0.1 + 0.22 * depth
            ))
        }

        let tilt = isFaceOn ? -cameraTilt : 0.55
        let basisUX = 1.0
        let basisUY = 0.0
        let basisUZ = 0.0
        let basisVX = -basisUZ * sin(tilt)
        let basisVY = cos(tilt)
        let basisVZ = basisUX * sin(tilt)
        let normalX = basisUY * basisVZ - basisUZ * basisVY
        let normalY = basisUZ * basisVX - basisUX * basisVZ
        let normalZ = basisUX * basisVY - basisUY * basisVX
        let wobbleMultiplier = isFaceOn ? 0.565 : 1
        let wobbleAmplitude = 0.23 * wobbleMultiplier
        let baseRadius = isFaceOn ? sphereRadius / (1 + 0.85 * wobbleAmplitude) : sphereRadius
        let lanes = isFaceOn ? 8 : 10
        let segments = isFaceOn ? 15 : 20
        let radiusBase = 1.1 * (isFaceOn ? 1.622 : 1.073)
        let radiusDepth = 1.7 * (isFaceOn ? 1.622 : 1.073)

        for lane in 0..<lanes {
            let laneOffset = (Double(lane) - Double(lanes - 1) / 2) * 0.075
            let edge = abs(Double(lane) - Double(lanes - 1) / 2) / max(1, Double(lanes - 1) / 2)
            for segment in 0..<segments {
                let angle = (Double(segment) / Double(segments)) * 2 * .pi
                let wobble = (
                    0.16 * sin(angle * 3 - time * 1.7 + Double(lane) * 0.22)
                        + 0.07 * sin(angle * 5 + time * 1.1)
                ) * wobbleMultiplier
                let radial = isFaceOn ? 1 + wobble : 1
                let offset = isFaceOn ? laneOffset : laneOffset + wobble
                let x = basisUX * cos(angle) + basisVX * sin(angle) + normalX * offset
                let y = basisUY * cos(angle) + basisVY * sin(angle) + normalY * offset
                let z = basisUZ * cos(angle) + basisVZ * sin(angle) + normalZ * offset
                let length = max(1e-6, sqrt(x * x + y * y + z * z))
                let radius = baseRadius * radial
                let projected = projector(x / length * radius, y / length * radius, z / length * radius)
                let depth = (projected.z / sphereRadius + 1) / 2
                dots.append(ThinkingOrbDot(
                    x: projected.x,
                    y: projected.y,
                    z: projected.z,
                    radius: (radiusBase + radiusDepth * depth) * (1 - 0.25 * edge) * radiusScale,
                    white: 0.52 - 0.44 * depth + 0.18 * edge,
                    alpha: 0.4 + 0.6 * depth
                ))
            }
        }
        paint(dots: dots, context: context, color: color, minimumRadius: 0.3)
    }

    // MARK: - Shaping

    private static func drawMorph(context: CGContext, time: Double, color: NSColor) {
        let holdDuration = 1.4
        let morphDuration = 0.9
        let segmentDuration = holdDuration + morphDuration
        let cycleCount = 3
        let cycleTime = positiveRemainder(time, divisor: segmentDuration * Double(cycleCount))
        let shapeIndex = Int(floor(cycleTime / segmentDuration))
        let localTime = cycleTime - Double(shapeIndex) * segmentDuration
        let rawProgress = localTime > holdDuration ? (localTime - holdDuration) / morphDuration : 0
        let progress = rawProgress * rawProgress * (3 - 2 * rawProgress)
        let spread = 1.45
        let sampleCount = 160
        var sampledPoints: [(x: Double, y: Double)] = []

        for index in 0..<sampleCount {
            let fraction = Double(index) / Double(sampleCount)
            let first = shapePoint(index: shapeIndex, fraction: fraction)
            let second = shapePoint(index: (shapeIndex + 1) % cycleCount, fraction: fraction)
            sampledPoints.append((
                x: interpolate(first.x, second.x, progress) * spread,
                y: interpolate(first.y, second.y, progress) * spread
            ))
        }

        var lengths: [Double] = []
        var totalLength = 0.0
        for index in 0..<sampleCount {
            let first = sampledPoints[index]
            let second = sampledPoints[(index + 1) % sampleCount]
            let length = hypot(second.x - first.x, second.y - first.y)
            lengths.append(length)
            totalLength += length
        }

        let dotCount = max(6, Int((34 * 0.53).rounded()))
        let radius = max(0.35, 0.021 * 1.011 * 1.35 * spread * logicalSize)
        let pulse = 1 + 0.02 * sin(localTime * 3.1)
        let center = logicalSize / 2
        var dots: [ThinkingOrbDot] = []
        var segmentIndex = 0
        var accumulatedLength = 0.0

        for dotIndex in 0..<dotCount {
            let target = (Double(dotIndex) / Double(dotCount)) * totalLength
            while segmentIndex < sampleCount - 1,
                  accumulatedLength + lengths[segmentIndex] < target {
                accumulatedLength += lengths[segmentIndex]
                segmentIndex += 1
            }
            let first = sampledPoints[segmentIndex]
            let second = sampledPoints[(segmentIndex + 1) % sampleCount]
            let progress = lengths[segmentIndex] > 0
                ? min(1, (target - accumulatedLength) / lengths[segmentIndex])
                : 0
            let x = interpolate(first.x, second.x, progress) * pulse
            let y = interpolate(first.y, second.y, progress) * pulse
            dots.append(ThinkingOrbDot(
                x: center + x * logicalSize,
                y: center + y * logicalSize,
                z: 0,
                radius: radius,
                white: 0.1,
                alpha: 1
            ))
        }
        paint(dots: dots, context: context, color: color, minimumRadius: 0.25)
    }

    private static func shapePoint(index: Int, fraction: Double) -> (x: Double, y: Double) {
        switch index {
        case 0:
            let angle = -.pi / 2 + fraction * 2 * .pi
            return (cos(angle) * 0.24, sin(angle) * 0.24)
        case 1:
            return polygonPoint(
                vertices: [(0, -0.26), (0.24, 0.16), (-0.24, 0.16)],
                fraction: fraction
            )
        default:
            return polygonPoint(
                vertices: [(0, -0.2), (0.2, -0.2), (0.2, 0.2), (-0.2, 0.2), (-0.2, -0.2)],
                fraction: fraction
            )
        }
    }

    private static func polygonPoint(
        vertices: [(Double, Double)],
        fraction: Double
    ) -> (x: Double, y: Double) {
        var lengths: [Double] = []
        var totalLength = 0.0
        for index in vertices.indices {
            let first = vertices[index]
            let second = vertices[(index + 1) % vertices.count]
            let length = hypot(second.0 - first.0, second.1 - first.1)
            lengths.append(length)
            totalLength += length
        }

        var target = fraction * totalLength
        var segmentIndex = 0
        while segmentIndex < vertices.count - 1, target > lengths[segmentIndex] {
            target -= lengths[segmentIndex]
            segmentIndex += 1
        }
        let first = vertices[segmentIndex]
        let second = vertices[(segmentIndex + 1) % vertices.count]
        let progress = lengths[segmentIndex] > 0 ? min(1, target / lengths[segmentIndex]) : 0
        return (
            interpolate(first.0, second.0, progress),
            interpolate(first.1, second.1, progress)
        )
    }

    // MARK: - Shared math and painting

    private static func makeProjector(
        yaw: Double,
        tilt: Double,
        centerX: Double,
        centerY: Double,
        scale: Double
    ) -> (_ x: Double, _ y: Double, _ z: Double) -> ThinkingOrbVector3 {
        let sineTilt = sin(tilt)
        let cosineTilt = cos(tilt)
        let sineYaw = sin(yaw)
        let cosineYaw = cos(yaw)
        return { x, y, z in
            let rotatedX = x * cosineYaw + z * sineYaw
            let rotatedZ = -x * sineYaw + z * cosineYaw
            let rotatedY = y * cosineTilt - rotatedZ * sineTilt
            let depth = y * sineTilt + rotatedZ * cosineTilt
            return ThinkingOrbVector3(
                x: centerX + rotatedX * scale,
                y: centerY - rotatedY * scale,
                z: depth
            )
        }
    }

    private static func paint(
        dots: [ThinkingOrbDot],
        context: CGContext,
        color: NSColor,
        minimumRadius: Double
    ) {
        let sortedDots = dots.sorted { $0.z < $1.z }
        for dot in sortedDots where dot.alpha >= 0.02 {
            let ink = 1 - min(1, max(0, dot.white))
            context.setFillColor(
                red: color.redComponent * ink,
                green: color.greenComponent * ink,
                blue: color.blueComponent * ink,
                alpha: color.alphaComponent * min(1, max(0, dot.alpha))
            )
            let radius = max(minimumRadius, dot.radius)
            context.fillEllipse(in: CGRect(
                x: dot.x - radius,
                y: dot.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
        }
    }

    private static func paint(lines: [ThinkingOrbLine], context: CGContext, color: NSColor) {
        context.setLineCap(.round)
        for line in lines where line.alpha >= 0.02 {
            let ink = 1 - min(1, max(0, line.white))
            context.setStrokeColor(
                red: color.redComponent * ink,
                green: color.greenComponent * ink,
                blue: color.blueComponent * ink,
                alpha: color.alphaComponent * min(1, max(0, line.alpha))
            )
            context.setLineWidth(line.width)
            context.move(to: CGPoint(x: line.x1, y: line.y1))
            context.addLine(to: CGPoint(x: line.x2, y: line.y2))
            context.strokePath()
        }
    }

    private static func solveCycle(
        time: Double,
        count: Int,
        slotDuration: Double,
        rest: Double
    ) -> ThinkingOrbSolveCycle {
        let cycleDuration = 2 * Double(count) * slotDuration + rest
        let cycleTime = positiveRemainder(time, divisor: cycleDuration)
        var amounts = Array(repeating: 0.0, count: count)
        var activeIndex = -1
        if cycleTime < 2 * Double(count) * slotDuration {
            let slot = Int(floor(cycleTime / slotDuration))
            let progress = (cycleTime - Double(slot) * slotDuration) / slotDuration
            let clamped = min(1, progress / 0.7)
            let eased = 1 - pow(1 - clamped, 3)
            if slot < count {
                for index in 0..<slot {
                    amounts[index] = 1
                }
                amounts[slot] = eased
                activeIndex = slot
            } else {
                let reverseIndex = 2 * count - 1 - slot
                for index in 0..<reverseIndex {
                    amounts[index] = 1
                }
                amounts[reverseIndex] = 1 - eased
                activeIndex = reverseIndex
            }
        }
        return ThinkingOrbSolveCycle(amounts: amounts, activeIndex: activeIndex)
    }

    private static func makeMoves(count: Int) -> [ThinkingOrbMove] {
        (0..<count).map { index in
            let axis = min(2, Int(floor(hash(Double(index), 2.3) * 3)))
            let lowerBound = -1 + 0.5 * Double(min(3, Int(floor(hash(Double(index), 5.9) * 4))))
            let direction = hash(Double(index), 7.7) < 0.5 ? 1.0 : -1.0
            return ThinkingOrbMove(
                axis: axis,
                lowerBound: lowerBound,
                upperBound: lowerBound + 0.5,
                angle: direction * .pi / 2
            )
        }
    }

    private static func applyMoves(
        _ input: ThinkingOrbVector3,
        moves: [ThinkingOrbMove],
        cycle: ThinkingOrbSolveCycle
    ) -> (vector: ThinkingOrbVector3, isActive: Bool) {
        var vector = input
        var isActive = false
        for index in moves.indices where cycle.amounts[index] > 0 {
            let move = moves[index]
            let coordinate = move.axis == 0 ? vector.x : move.axis == 1 ? vector.y : vector.z
            guard coordinate >= move.lowerBound, coordinate < move.upperBound else { continue }
            if index == cycle.activeIndex {
                isActive = true
            }
            let angle = move.angle * cycle.amounts[index]
            let cosine = cos(angle)
            let sine = sin(angle)
            switch move.axis {
            case 0:
                let y = vector.y * cosine - vector.z * sine
                vector.z = vector.y * sine + vector.z * cosine
                vector.y = y
            case 1:
                let x = vector.x * cosine + vector.z * sine
                vector.z = -vector.x * sine + vector.z * cosine
                vector.x = x
            default:
                let x = vector.x * cosine - vector.y * sine
                vector.y = vector.x * sine + vector.y * cosine
                vector.x = x
            }
        }
        return (vector, isActive)
    }

    private static func fibonacciDirection(index: Int, count: Int) -> ThinkingOrbVector3 {
        let goldenAngle = Double.pi * (3 - sqrt(5))
        let y = 1 - (2 * (Double(index) + 0.5)) / Double(count)
        let radius = sqrt(1 - y * y)
        let angle = Double(index) * goldenAngle
        return ThinkingOrbVector3(x: radius * cos(angle), y: y, z: radius * sin(angle))
    }

    private static func valueNoise(_ x: Double, _ y: Double) -> Double {
        let integerX = floor(x)
        let integerY = floor(y)
        var fractionalX = x - integerX
        var fractionalY = y - integerY
        fractionalX = fractionalX * fractionalX * (3 - 2 * fractionalX)
        fractionalY = fractionalY * fractionalY * (3 - 2 * fractionalY)
        let first = hash(integerX, integerY)
        let second = hash(integerX + 1, integerY)
        let third = hash(integerX, integerY + 1)
        let fourth = hash(integerX + 1, integerY + 1)
        return first
            + (second - first) * fractionalX
            + (third - first) * fractionalY
            + (first - second - third + fourth) * fractionalX * fractionalY
    }

    private static func hash(_ first: Double, _ second: Double) -> Double {
        fractionalPart(sin(first * 12.9898 + second * 78.233) * 43_758.5453)
    }

    private static func angleDelta(_ first: Double, _ second: Double) -> Double {
        atan2(sin(first - second), cos(first - second))
    }

    private static func scaledRadius(power: Double) -> Double {
        pow(logicalSize / 300, power)
    }

    private static func interpolate(_ first: Double, _ second: Double, _ progress: Double) -> Double {
        first + (second - first) * progress
    }

    private static func fractionalPart(_ value: Double) -> Double {
        value - floor(value)
    }

    private static func normalizedPhase(_ value: Double) -> Double {
        fractionalPart(value)
    }

    private static func positiveRemainder(_ value: Double, divisor: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: divisor)
        return remainder >= 0 ? remainder : remainder + divisor
    }
}
