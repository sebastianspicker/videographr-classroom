import Foundation

struct FrameSampleRect: Sendable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}

struct FrameLuminanceBuffer: Sendable {
    let values: [Double]
    let width: Int
    let height: Int

    func mean(in rect: FrameSampleRect) -> Double {
        let xRange = clampedRange(start: rect.x, length: rect.width, limit: width)
        let yRange = clampedRange(start: rect.y, length: rect.height, limit: height)
        guard !xRange.isEmpty, !yRange.isEmpty else { return 0 }

        var sum = 0.0
        var count = 0
        for y in yRange {
            let row = y * width
            for x in xRange {
                sum += values[row + x]
                count += 1
            }
        }
        return safeRatio(sum, Double(count))
    }

    func matchingFraction(
        in rect: FrameSampleRect,
        predicate: (Double) -> Bool
    ) -> Double {
        let xRange = clampedRange(start: rect.x, length: rect.width, limit: width)
        let yRange = clampedRange(start: rect.y, length: rect.height, limit: height)
        var matches = 0
        var total = 0
        for y in yRange {
            let row = y * width
            for x in xRange {
                total += 1
                if predicate(values[row + x]) { matches += 1 }
            }
        }
        return safeRatio(Double(matches), Double(total))
    }

    private func clampedRange(start: Int, length: Int, limit: Int) -> Range<Int> {
        max(0, start)..<min(limit, start + length)
    }

    private func safeRatio(_ numerator: Double, _ denominator: Double) -> Double {
        guard denominator > 0 else { return 0 }
        return numerator / denominator
    }
}

struct FrameRegionMetrics: Sendable {
    let average: Double
    let topBand: Double
    let bottomBand: Double
    let leftBand: Double
    let rightBand: Double
    let midMean: Double
    let midRect: FrameSampleRect
    let topRect: FrameSampleRect
    let bottomRect: FrameSampleRect
    let boardScore: Double
    let preferDarkBoard: Bool
    let backlightScore: Double
    let horizontalImbalance: Double
    /// Edge-region brightness distance from mid-tone; not a detection of empty image areas.
    let emptyEdgeFraction: Double

    static func measure(_ frame: FrameLuminanceBuffer) -> Self {
        let topHeight = max(1, frame.height / 5)
        let sideWidth = max(1, frame.width / 6)
        let fullRect = FrameSampleRect(x: 0, y: 0, width: frame.width, height: frame.height)
        let topRect = FrameSampleRect(x: 0, y: 0, width: frame.width, height: topHeight)
        let bottomRect = FrameSampleRect(
            x: 0,
            y: frame.height - topHeight,
            width: frame.width,
            height: topHeight
        )
        let leftRect = FrameSampleRect(x: 0, y: 0, width: sideWidth, height: frame.height)
        let rightRect = FrameSampleRect(
            x: frame.width - sideWidth,
            y: 0,
            width: sideWidth,
            height: frame.height
        )
        let midRect = FrameSampleRect(
            x: frame.width / 6,
            y: frame.height / 4,
            width: (frame.width * 2) / 3,
            height: frame.height / 2
        )
        let input = FrameRegionInput(
            average: frame.mean(in: fullRect),
            bands: FrameRegionBands(
                top: frame.mean(in: topRect),
                bottom: frame.mean(in: bottomRect),
                left: frame.mean(in: leftRect),
                right: frame.mean(in: rightRect)
            ),
            midMean: frame.mean(in: midRect),
            rects: FrameRegionRects(mid: midRect, top: topRect, bottom: bottomRect)
        )
        return assemble(input)
    }

    private static func assemble(_ input: FrameRegionInput) -> Self {
        let bands = input.bands
        let midMean = input.midMean
        let surround = (bands.top + bands.bottom + bands.left + bands.right) / 4.0
        let darkBoard = max(0, surround - midMean)
        let brightBoard = max(0, midMean - surround)
        let boardScore = min(1, max(darkBoard, brightBoard) * 3.5)
        let edgeBright = max(bands.left, bands.right, bands.top)
        let edgeMean = surround
        return Self(
            average: input.average,
            topBand: bands.top,
            bottomBand: bands.bottom,
            leftBand: bands.left,
            rightBand: bands.right,
            midMean: midMean,
            midRect: input.rects.mid,
            topRect: input.rects.top,
            bottomRect: input.rects.bottom,
            boardScore: boardScore,
            preferDarkBoard: darkBoard >= brightBoard,
            backlightScore: min(1, max(0, edgeBright - midMean) * 2.2),
            horizontalImbalance: abs(bands.left - bands.right),
            emptyEdgeFraction: min(1, abs(edgeMean - 0.5) * 1.5 + (1 - boardScore) * 0.2)
        )
    }
}

private struct FrameRegionBands: Sendable {
    let top: Double
    let bottom: Double
    let left: Double
    let right: Double
}

private struct FrameRegionRects: Sendable {
    let mid: FrameSampleRect
    let top: FrameSampleRect
    let bottom: FrameSampleRect
}

private struct FrameRegionInput: Sendable {
    let average: Double
    let bands: FrameRegionBands
    let midMean: Double
    let rects: FrameRegionRects
}

struct FrameBoardLocation: Sendable {
    let centerX: Double
    let centerY: Double

    static func measure(
        _ frame: FrameLuminanceBuffer,
        regions: FrameRegionMetrics
    ) -> Self {
        var bestScore = -1.0
        var center = Self(centerX: 0.5, centerY: 0.45)
        let stepX = max(1, frame.width / 16)
        let stepY = max(1, frame.height / 16)
        let rect = regions.midRect
        for y in stride(from: rect.y, to: rect.y + rect.height, by: stepY) {
            for x in stride(from: rect.x, to: rect.x + rect.width, by: stepX) {
                let value = frame.values[y * frame.width + x]
                let score = regions.preferDarkBoard ? 1 - value : value
                if score > bestScore {
                    bestScore = score
                    center = Self(
                        centerX: Double(x) / Double(frame.width),
                        centerY: Double(y) / Double(frame.height)
                    )
                }
            }
        }
        return center
    }
}

struct FrameExposureMetrics: Sendable {
    let ceilingFraction: Double
    let floorFraction: Double
    let globalContrast: Double
    let clippedHighlightFraction: Double
    let clippedShadowFraction: Double
    let brightnessCenterY: Double
    let midBandVariance: Double
    let edgeEnergy: Double

    static func measure(
        _ frame: FrameLuminanceBuffer,
        regions: FrameRegionMetrics
    ) -> Self {
        let scan = scanGlobal(frame)
        let pixelCount = Double(frame.width * frame.height)
        return Self(
            ceilingFraction: frame.matchingFraction(in: regions.topRect) { $0 > 0.72 },
            floorFraction: frame.matchingFraction(in: regions.bottomRect) { $0 < 0.38 },
            globalContrast: max(0, scan.maximum - scan.minimum),
            clippedHighlightFraction: safeRatio(Double(scan.highlightCount), pixelCount),
            clippedShadowFraction: safeRatio(Double(scan.shadowCount), pixelCount),
            brightnessCenterY: brightnessCenter(scan: scan, height: frame.height),
            midBandVariance: midBandVariance(frame, regions: regions),
            edgeEnergy: horizontalEdgeEnergy(frame)
        )
    }

    private static func scanGlobal(_ frame: FrameLuminanceBuffer) -> FrameGlobalScan {
        var result = FrameGlobalScan()
        for y in 0..<frame.height {
            let row = y * frame.width
            for x in 0..<frame.width {
                let value = frame.values[row + x]
                result.minimum = min(result.minimum, value)
                result.maximum = max(result.maximum, value)
                if value > 0.92 { result.highlightCount += 1 }
                if value < 0.08 { result.shadowCount += 1 }
                result.mass += value
                result.massY += value * Double(y)
            }
        }
        return result
    }

    private static func brightnessCenter(scan: FrameGlobalScan, height: Int) -> Double {
        guard scan.mass > 1e-9 else { return 0.5 }
        return (scan.massY / scan.mass) / Double(max(1, height - 1))
    }

    private static func midBandVariance(
        _ frame: FrameLuminanceBuffer,
        regions: FrameRegionMetrics
    ) -> Double {
        var sum = 0.0
        var count = 0
        let rect = regions.midRect
        for y in rect.y..<(rect.y + rect.height) {
            let row = y * frame.width
            for x in rect.x..<(rect.x + rect.width) {
                let delta = frame.values[row + x] - regions.midMean
                sum += delta * delta
                count += 1
            }
        }
        return safeRatio(sum, Double(count))
    }

    private static func horizontalEdgeEnergy(_ frame: FrameLuminanceBuffer) -> Double {
        var sum = 0.0
        var count = 0
        for y in 0..<frame.height {
            let row = y * frame.width
            for x in 0..<(frame.width - 1) {
                sum += abs(frame.values[row + x + 1] - frame.values[row + x])
                count += 1
            }
        }
        return safeRatio(sum, Double(count))
    }

    private static func safeRatio(_ numerator: Double, _ denominator: Double) -> Double {
        guard denominator > 0 else { return 0 }
        return numerator / denominator
    }
}

private struct FrameGlobalScan: Sendable {
    var minimum = 1.0
    var maximum = 0.0
    var highlightCount = 0
    var shadowCount = 0
    var mass = 0.0
    var massY = 0.0
}
