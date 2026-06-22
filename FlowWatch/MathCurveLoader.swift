import AppKit
import Foundation

enum MathCurveLoaderSelection: RawRepresentable, Hashable {
    case random
    case preset(MathCurveLoaderPreset)

    init?(rawValue: String) {
        if rawValue == "random" {
            self = .random
            return
        }
        guard let preset = MathCurveLoaderPreset(rawValue: rawValue) else {
            return nil
        }
        self = .preset(preset)
    }

    var rawValue: String {
        switch self {
        case .random:
            return "random"
        case .preset(let preset):
            return preset.rawValue
        }
    }
}

enum MathCurveLoaderPreset: String, CaseIterable, Identifiable {
    case originalThinking
    case thinkingFive
    case thinkingNine
    case roseOrbit
    case roseCurve
    case roseTwo
    case roseThree
    case roseFour
    case lissajousDrift
    case lemniscateBloom
    case hypotrochoidLoop
    case threePetalSpiral
    case fourPetalSpiral
    case fivePetalSpiral
    case sixPetalSpiral
    case butterflyPhase
    case cardioidGlow
    case cardioidHeart
    case heartWave
    case spiralSearch
    case fourierFlow

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .originalThinking: return "Original Thinking"
        case .thinkingFive: return "Thinking Five"
        case .thinkingNine: return "Thinking Nine"
        case .roseOrbit: return "Rose Orbit"
        case .roseCurve: return "Rose Curve"
        case .roseTwo: return "Rose Two"
        case .roseThree: return "Rose Three"
        case .roseFour: return "Rose Four"
        case .lissajousDrift: return "Lissajous Drift"
        case .lemniscateBloom: return "Lemniscate Bloom"
        case .hypotrochoidLoop: return "Hypotrochoid Loop"
        case .threePetalSpiral: return "Three-Petal Spiral"
        case .fourPetalSpiral: return "Four-Petal Spiral"
        case .fivePetalSpiral: return "Five-Petal Spiral"
        case .sixPetalSpiral: return "Six-Petal Spiral"
        case .butterflyPhase: return "Butterfly Phase"
        case .cardioidGlow: return "Cardioid Glow"
        case .cardioidHeart: return "Cardioid Heart"
        case .heartWave: return "Heart Wave"
        case .spiralSearch: return "Spiral Search"
        case .fourierFlow: return "Fourier Flow"
        }
    }

    var rotates: Bool {
        switch self {
        case .originalThinking, .thinkingFive, .thinkingNine, .roseOrbit,
             .roseCurve, .roseTwo, .roseThree, .roseFour,
             .threePetalSpiral, .fourPetalSpiral, .fivePetalSpiral,
             .sixPetalSpiral:
            return true
        case .lissajousDrift, .lemniscateBloom, .hypotrochoidLoop,
             .butterflyPhase, .cardioidGlow, .cardioidHeart, .heartWave,
             .spiralSearch, .fourierFlow:
            return false
        }
    }

    var particleCount: Int {
        switch self {
        case .originalThinking: return 64
        case .thinkingFive: return 62
        case .thinkingNine: return 68
        case .roseOrbit, .cardioidGlow: return 72
        case .roseCurve, .roseFour: return 78
        case .roseTwo, .cardioidHeart: return 74
        case .roseThree: return 76
        case .lissajousDrift: return 68
        case .lemniscateBloom: return 70
        case .hypotrochoidLoop, .threePetalSpiral: return 82
        case .fourPetalSpiral: return 84
        case .fivePetalSpiral: return 85
        case .sixPetalSpiral, .spiralSearch: return 86
        case .butterflyPhase: return 88
        case .heartWave: return 104
        case .fourierFlow: return 92
        }
    }

    var trailSpan: Double {
        switch self {
        case .originalThinking, .thinkingFive: return 0.38
        case .thinkingNine: return 0.39
        case .roseOrbit: return 0.42
        case .roseCurve, .butterflyPhase: return 0.32
        case .roseTwo: return 0.30
        case .roseThree, .fourierFlow: return 0.31
        case .roseFour: return 0.32
        case .lissajousDrift, .threePetalSpiral, .fourPetalSpiral,
             .fivePetalSpiral, .sixPetalSpiral:
            return 0.34
        case .lemniscateBloom: return 0.40
        case .hypotrochoidLoop: return 0.46
        case .cardioidGlow, .cardioidHeart: return 0.36
        case .heartWave: return 0.18
        case .spiralSearch: return 0.28
        }
    }

    var durationMilliseconds: Double {
        switch self {
        case .originalThinking, .thinkingFive, .threePetalSpiral,
             .fourPetalSpiral, .fivePetalSpiral, .sixPetalSpiral:
            return 4_600
        case .thinkingNine: return 4_700
        case .roseOrbit, .roseTwo: return 5_200
        case .roseCurve, .roseFour: return 5_400
        case .roseThree: return 5_300
        case .lissajousDrift: return 6_000
        case .lemniscateBloom: return 5_600
        case .hypotrochoidLoop: return 7_600
        case .butterflyPhase: return 9_000
        case .cardioidGlow, .cardioidHeart: return 6_200
        case .heartWave, .fourierFlow: return 8_400
        case .spiralSearch: return 7_800
        }
    }

    var rotationDurationMilliseconds: Double {
        switch self {
        case .thinkingNine: return 30_000
        case .lissajousDrift, .cardioidGlow, .cardioidHeart: return 36_000
        case .lemniscateBloom: return 34_000
        case .hypotrochoidLoop: return 42_000
        case .butterflyPhase: return 50_000
        case .heartWave: return 22_000
        case .spiralSearch, .fourierFlow: return 44_000
        case .originalThinking, .thinkingFive, .roseOrbit, .roseCurve,
             .roseTwo, .roseThree, .roseFour, .threePetalSpiral,
             .fourPetalSpiral, .fivePetalSpiral, .sixPetalSpiral:
            return 28_000
        }
    }

    var pulseDurationMilliseconds: Double {
        switch self {
        case .originalThinking, .thinkingFive, .thinkingNine,
             .threePetalSpiral, .fourPetalSpiral, .fivePetalSpiral,
             .sixPetalSpiral:
            return 4_200
        case .roseOrbit, .roseCurve: return 4_600
        case .roseTwo: return 4_300
        case .roseThree: return 4_400
        case .roseFour: return 4_500
        case .lissajousDrift: return 5_400
        case .lemniscateBloom: return 5_000
        case .hypotrochoidLoop: return 6_200
        case .butterflyPhase: return 7_000
        case .cardioidGlow, .cardioidHeart: return 5_200
        case .heartWave: return 5_600
        case .spiralSearch, .fourierFlow: return 6_800
        }
    }

    var strokeWidth: Double {
        switch self {
        case .originalThinking, .thinkingFive, .thinkingNine: return 5.5
        case .roseOrbit: return 5.2
        case .roseCurve: return 4.5
        case .roseTwo, .roseThree, .roseFour, .hypotrochoidLoop: return 4.6
        case .lissajousDrift: return 4.7
        case .lemniscateBloom: return 4.8
        case .threePetalSpiral, .fourPetalSpiral, .fivePetalSpiral,
             .sixPetalSpiral, .butterflyPhase:
            return 4.4
        case .cardioidGlow, .cardioidHeart: return 4.9
        case .heartWave: return 3.9
        case .spiralSearch: return 4.3
        case .fourierFlow: return 4.2
        }
    }

    func point(progress: Double, detailScale: Double) -> CGPoint {
        let normalized = normalizedProgress(progress)

        switch self {
        case .originalThinking:
            return thinkingPoint(progress: normalized, detailScale: detailScale, petals: 7)
        case .thinkingFive:
            return thinkingPoint(progress: normalized, detailScale: detailScale, petals: 5)
        case .thinkingNine:
            return thinkingPoint(progress: normalized, detailScale: detailScale, petals: 9)
        case .roseOrbit:
            let t = normalized * .pi * 2
            let radius = 7 - 2.7 * detailScale * cos(7 * t)
            return makePoint(
                x: 50 + cos(t) * radius * 3.9,
                y: 50 + sin(t) * radius * 3.9
            )
        case .roseCurve:
            return rosePoint(progress: normalized, detailScale: detailScale, k: 5)
        case .roseTwo:
            return rosePoint(progress: normalized, detailScale: detailScale, k: 2)
        case .roseThree:
            return rosePoint(progress: normalized, detailScale: detailScale, k: 3)
        case .roseFour:
            return rosePoint(progress: normalized, detailScale: detailScale, k: 4)
        case .lissajousDrift:
            let t = normalized * .pi * 2
            let amplitude = 24 + detailScale * 6
            return makePoint(
                x: 50 + sin(3 * t + 1.57) * amplitude,
                y: 50 + sin(4 * t) * (amplitude * 0.92)
            )
        case .lemniscateBloom:
            let t = normalized * .pi * 2
            let scale = 20 + detailScale * 7
            let denominator = 1 + pow(sin(t), 2)
            return makePoint(
                x: 50 + (scale * cos(t)) / denominator,
                y: 50 + (scale * sin(t) * cos(t)) / denominator
            )
        case .hypotrochoidLoop:
            let t = normalized * .pi * 2
            let radius = 2.7 + detailScale * 0.45
            let distance = 4.8 + detailScale * 1.2
            let x = (8.2 - radius) * cos(t) + distance * cos(((8.2 - radius) / radius) * t)
            let y = (8.2 - radius) * sin(t) - distance * sin(((8.2 - radius) / radius) * t)
            return makePoint(x: 50 + x * 3.05, y: 50 + y * 3.05)
        case .threePetalSpiral:
            return spiralPoint(progress: normalized, detailScale: detailScale, turns: 3)
        case .fourPetalSpiral:
            return spiralPoint(progress: normalized, detailScale: detailScale, turns: 4)
        case .fivePetalSpiral:
            return spiralPoint(progress: normalized, detailScale: detailScale, turns: 5)
        case .sixPetalSpiral:
            return spiralPoint(progress: normalized, detailScale: detailScale, turns: 6)
        case .butterflyPhase:
            let t = normalized * .pi * 12
            let shape = exp(cos(t)) - 2 * cos(4 * t) - pow(sin(t / 12), 5)
            let scale = 4.6 + detailScale * 0.45
            return makePoint(
                x: 50 + sin(t) * shape * scale,
                y: 50 + cos(t) * shape * scale
            )
        case .cardioidGlow:
            let t = normalized * .pi * 2
            let radius = (8.4 + detailScale * 0.8) * (1 - cos(t))
            return makePoint(
                x: 50 + cos(t) * radius * 2.15,
                y: 50 + sin(t) * radius * 2.15
            )
        case .cardioidHeart:
            let t = normalized * .pi * 2
            let radius = (8.8 + detailScale * 0.8) * (1 + cos(t))
            let baseX = cos(t) * radius
            let baseY = sin(t) * radius
            return makePoint(x: 50 - baseY * 2.15, y: 50 - baseX * 2.15)
        case .heartWave:
            let xLimit = sqrt(3.3)
            let x = -xLimit + normalized * xLimit * 2
            let safeRoot = max(0, 3.3 - x * x)
            let wave = 0.9 * sqrt(safeRoot) * sin(6.4 * .pi * x)
            let curve = pow(abs(x), 2 / 3)
            let y = curve + wave
            return makePoint(
                x: 50 + x * 23.2,
                y: 18 + (1.75 - y) * (24.5 + detailScale * 1.5)
            )
        case .spiralSearch:
            let t = normalized * .pi * 2
            let angle = t * 4
            let radius = 8 + (1 - cos(t)) * (8.5 + detailScale * 2.4)
            return makePoint(
                x: 50 + cos(angle) * radius,
                y: 50 + sin(angle) * radius
            )
        case .fourierFlow:
            let t = normalized * .pi * 2
            let mix = 1 + detailScale * 0.16
            let x = 17 * cos(t)
                + 7.5 * cos(3 * t + 0.6 * mix)
                + 3.2 * sin(5 * t - 0.4)
            let y = 15 * sin(t)
                + 8.2 * sin(2 * t + 0.25)
                - 4.2 * cos(4 * t - 0.5 * mix)
            return makePoint(x: 50 + x, y: 50 + y)
        }
    }

    private func thinkingPoint(progress: Double, detailScale: Double, petals: Double) -> CGPoint {
        let t = progress * .pi * 2
        let x = 7 * cos(t) - 3 * detailScale * cos(petals * t)
        let y = 7 * sin(t) - 3 * detailScale * sin(petals * t)
        return makePoint(x: 50 + x * 3.9, y: 50 + y * 3.9)
    }

    private func rosePoint(progress: Double, detailScale: Double, k: Double) -> CGPoint {
        let t = progress * .pi * 2
        let a = 9.2 + detailScale * 0.6
        let radius = a * (0.72 + detailScale * 0.28) * cos(k * t)
        return makePoint(
            x: 50 + cos(t) * radius * 3.25,
            y: 50 + sin(t) * radius * 3.25
        )
    }

    private func spiralPoint(progress: Double, detailScale: Double, turns: Double) -> CGPoint {
        let t = progress * .pi * 2
        let distance = 3 + detailScale * 0.25
        let baseX = (turns - 1) * cos(t) + distance * cos((turns - 1) * t)
        let baseY = (turns - 1) * sin(t) - distance * sin((turns - 1) * t)
        let scale = 2.2 + detailScale * 0.45
        return makePoint(x: 50 + baseX * scale, y: 50 + baseY * scale)
    }

    private func makePoint(x: Double, y: Double) -> CGPoint {
        CGPoint(x: CGFloat(x), y: CGFloat(y))
    }
}

struct MathCurveLoaderRenderer {
    static func makeImage(
        preset: MathCurveLoaderPreset,
        timeMilliseconds: Double,
        phaseOffset: Double,
        color: NSColor,
        size: NSSize = NSSize(width: 18, height: 18)
    ) -> NSImage? {
        let normalizedColor = color.usingColorSpace(.sRGB) ?? color
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

        let rect = NSRect(origin: .zero, size: size)
        let detailScale = Self.detailScale(
            timeMilliseconds: timeMilliseconds,
            pulseDurationMilliseconds: preset.pulseDurationMilliseconds,
            phaseOffset: phaseOffset
        )
        let progress = Self.normalizedRemainder(
            timeMilliseconds + phaseOffset * preset.durationMilliseconds,
            dividingBy: preset.durationMilliseconds
        ) / preset.durationMilliseconds
        let rotation = Self.rotationDegrees(
            preset: preset,
            timeMilliseconds: timeMilliseconds,
            phaseOffset: phaseOffset
        )

        let side = min(rect.width, rect.height)
        let scale = side / 100
        let origin = CGPoint(
            x: rect.midX - side / 2,
            y: rect.midY - side / 2
        )
        let red = normalizedColor.redComponent
        let green = normalizedColor.greenComponent
        let blue = normalizedColor.blueComponent

        func mapPoint(_ point: CGPoint) -> CGPoint {
            let rotated = Self.rotate(point, degrees: rotation)
            return CGPoint(
                x: origin.x + rotated.x * scale,
                y: origin.y + (100 - rotated.y) * scale
            )
        }

        let path = CGMutablePath()
        let steps = 48
        for index in 0...steps {
            let point = mapPoint(preset.point(progress: Double(index) / Double(steps), detailScale: detailScale))
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        context.addPath(path)
        context.setLineWidth(max(0.45, CGFloat(preset.strokeWidth) * scale))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(red: red, green: green, blue: blue, alpha: 0.10)
        context.strokePath()

        let particleRadiusScale = side / 55
        let count = min(preset.particleCount, 36)
        for index in 0..<count {
            let tailOffset = count > 1 ? Double(index) / Double(count - 1) : 0
            let particleProgress = normalizedProgress(progress - tailOffset * preset.trailSpan)
            let point = mapPoint(preset.point(progress: particleProgress, detailScale: detailScale))
            let fade = pow(1 - tailOffset, 0.56)
            let radius = max(0.28, CGFloat(0.9 + fade * 2.7) * particleRadiusScale)
            let alpha = CGFloat(0.04 + fade * 0.96)
            context.setFillColor(red: red, green: green, blue: blue, alpha: alpha)
            context.fillEllipse(in: CGRect(
                x: point.x - radius,
                y: point.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
        }

        let image = NSImage(size: size)
        image.addRepresentation(representation)
        return image
    }

    private static func detailScale(
        timeMilliseconds: Double,
        pulseDurationMilliseconds: Double,
        phaseOffset: Double
    ) -> Double {
        let progress = normalizedRemainder(
            timeMilliseconds + phaseOffset * pulseDurationMilliseconds,
            dividingBy: pulseDurationMilliseconds
        ) / pulseDurationMilliseconds
        let angle = progress * .pi * 2
        return 0.52 + ((sin(angle + 0.55) + 1) / 2) * 0.48
    }

    private static func rotationDegrees(
        preset: MathCurveLoaderPreset,
        timeMilliseconds: Double,
        phaseOffset: Double
    ) -> Double {
        guard preset.rotates else {
            return 0
        }
        let progress = normalizedRemainder(
            timeMilliseconds + phaseOffset * preset.rotationDurationMilliseconds,
            dividingBy: preset.rotationDurationMilliseconds
        ) / preset.rotationDurationMilliseconds
        return -progress * 360
    }

    private static func rotate(_ point: CGPoint, degrees: Double) -> CGPoint {
        guard degrees != 0 else {
            return point
        }
        let radians = degrees * .pi / 180
        let dx = Double(point.x) - 50
        let dy = Double(point.y) - 50
        let x = 50 + dx * cos(radians) - dy * sin(radians)
        let y = 50 + dx * sin(radians) + dy * cos(radians)
        return CGPoint(x: CGFloat(x), y: CGFloat(y))
    }

    private static func normalizedRemainder(_ value: Double, dividingBy divisor: Double) -> Double {
        guard divisor > 0 else {
            return 0
        }
        let remainder = value.truncatingRemainder(dividingBy: divisor)
        return remainder >= 0 ? remainder : remainder + divisor
    }
}

private func normalizedProgress(_ progress: Double) -> Double {
    let remainder = progress.truncatingRemainder(dividingBy: 1)
    return remainder >= 0 ? remainder : remainder + 1
}
