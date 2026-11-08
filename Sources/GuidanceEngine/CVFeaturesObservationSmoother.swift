import Foundation

/// Pure multi-observation smoother for CV features (Derry continuous takes: avoid tip flicker).
/// App feeds sequential frames; pure package holds EMA history only.
public struct CVObservationSmoother: Equatable, Sendable {
    public var alpha: Double
    public var sampleCount: Int
    public var last: CVFeatures?

    /// EMA of multi-cue board quality (for stability / variance only - never mixed into boardConfidence).
    private var emaBoardQuality: Double
    /// EMA of raw rectangle boardConfidence (like-with-like smoothing only).
    private var emaBoardConfidence: Double
    private var emaPeople: Double
    private var emaCoPresence: Double
    private var emaMidBand: Double
    private var varianceBoard: Double
    private var variancePeople: Double

    public init(alpha: Double = 0.35) {
        self.alpha = min(1, max(0.05, alpha))
        self.sampleCount = 0
        self.last = nil
        self.emaBoardQuality = 0
        self.emaBoardConfidence = 0
        self.emaPeople = 0
        self.emaCoPresence = 0
        self.emaMidBand = 0
        self.varianceBoard = 0
        self.variancePeople = 0
    }

    /// Push a new observation; returns features with updated `observationStability`.
    /// Smooths only like-with-like: `boardConfidence` never blends toward multi-cue quality.
    public mutating func push(_ features: CVFeatures) -> CVFeatures {
        guard features.analysisSucceeded else {
            var failed = features
            failed.observationStability = last?.observationStability ?? 0
            return failed
        }
        sampleCount += 1
        let co = CVFeatureFusion.coPresenceScore(from: features)

        if sampleCount == 1 {
            initializeAverages(with: features, coPresence: co)
        } else {
            updateAverages(with: features, coPresence: co)
        }

        let out = smoothedOutput(from: features, coPresence: co)
        last = out
        return out
    }

    private mutating func initializeAverages(with features: CVFeatures, coPresence: Double) {
        emaBoardQuality = features.multiCueBoardQuality
        emaBoardConfidence = features.boardConfidence
        emaPeople = features.peopleSpatialUsefulness
        emaCoPresence = coPresence
        emaMidBand = features.personMidBandOccupancy
        varianceBoard = 0
        variancePeople = 0
    }

    private mutating func updateAverages(with features: CVFeatures, coPresence: Double) {
        let boardQuality = features.multiCueBoardQuality
        let peopleUsefulness = features.peopleSpatialUsefulness
        let boardDelta = boardQuality - emaBoardQuality
        let peopleDelta = peopleUsefulness - emaPeople
        emaBoardQuality = alpha * boardQuality + (1 - alpha) * emaBoardQuality
        emaBoardConfidence = alpha * features.boardConfidence + (1 - alpha) * emaBoardConfidence
        emaPeople = alpha * peopleUsefulness + (1 - alpha) * emaPeople
        emaCoPresence = alpha * coPresence + (1 - alpha) * emaCoPresence
        emaMidBand = alpha * features.personMidBandOccupancy + (1 - alpha) * emaMidBand
        varianceBoard = alpha * (boardDelta * boardDelta) + (1 - alpha) * varianceBoard
        variancePeople = alpha * (peopleDelta * peopleDelta) + (1 - alpha) * variancePeople
    }

    private func smoothedOutput(from features: CVFeatures, coPresence: Double) -> CVFeatures {
        var output = features
        guard sampleCount >= 2 else {
            output.personBoardCoPresence = coPresence
            output.observationStability = 0.55
            output.personCoverageDelta = 0
            return output
        }
        // The EMA already contains the current sample with weight alpha.
        output.boardConfidence = min(1, max(0, emaBoardConfidence))
        output.personMidBandOccupancy = min(1, max(0, emaMidBand))
        output.personBoardCoPresence = min(1, max(0, emaCoPresence))
        output.boardAspectQuality = aBlend(features.boardAspectQuality, toward: last?.boardAspectQuality ?? features.boardAspectQuality)
        output.boardGeometryQuality = aBlend(features.boardGeometryQuality, toward: last?.boardGeometryQuality ?? features.boardGeometryQuality)
        output.boardEdgeSupport = aBlend(features.boardEdgeSupport, toward: last?.boardEdgeSupport ?? features.boardEdgeSupport)
        output.observationStability = min(1, max(0, 1 - (sqrt(varianceBoard) + sqrt(variancePeople)) * 3.5))
        output.personCoverageDelta = coverageDelta(for: output)
        return output
    }

    private func coverageDelta(for output: CVFeatures) -> Double {
        guard let previous = last, previous.analysisSucceeded else { return 0 }
        return min(1, abs(output.personCoverage - previous.personCoverage) * 4)
    }

    private func aBlend(_ instant: Double, toward ema: Double) -> Double {
        let a = alpha
        return min(1, max(0, a * instant + (1 - a) * ema))
    }
}
