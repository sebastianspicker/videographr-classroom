import Foundation


// MARK: - Pure fusion helpers for experimental rule inputs

/// Fuses luminance-heuristic board score with multi-cue CV board detection for guidance.
public enum CVFeatureFusion {
    /// Multi-cue board quality from CV fields alone (no frame heuristics).
    /// Weights: rectangle confidence + aspect + geometry + edge support.
    public static func multiCueBoardQuality(from cv: CVFeatures) -> Double {
        guard cv.analysisSucceeded else { return 0 }
        let conf = cv.boardConfidence
        let aspect = cv.boardAspectQuality
        let geom = cv.boardGeometryQuality
        let edge = cv.boardEdgeSupport
        let secondary = cv.secondaryWritingSurfaceSupport
        // If only raw confidence is set (legacy callers), fall back to confidence.
        if hasRawBoardConfidenceOnly(aspect: aspect, geometry: geom, edge: edge, secondary: secondary) {
            return conf
        }
        let raw = 0.36 * conf + 0.20 * aspect + 0.20 * geom + 0.14 * edge + 0.10 * secondary
        return min(1, max(0, raw))
    }

    /// Effective board score for placement (max of heuristic and multi-cue CV when CV ok).
    public static func effectiveBoardScore(frame: FrameMetrics, cv: CVFeatures) -> Double {
        if cv.analysisSucceeded && (cv.boardConfidence > 0 || cv.multiCueBoardQuality > 0) {
            return max(frame.boardRegionScore, multiCueBoardQuality(from: cv))
        }
        return frame.boardRegionScore
    }

    static func effectiveBoardCenter(frame: FrameMetrics, cv: CVFeatures) -> (x: Double, y: Double) {
        if cv.analysisSucceeded, let rect = cv.boardRect, multiCueBoardQuality(from: cv) >= 0.40 {
            return (rect.centerX, rect.centerY)
        }
        if cv.analysisSucceeded, let rect = cv.boardRect, cv.boardConfidence >= 0.45 {
            return (rect.centerX, rect.centerY)
        }
        return (frame.boardCenterX, frame.boardCenterY)
    }

    /// Spatial usefulness of actors for teaching–learning capture (not mere count).
    /// Prefers moderate coverage, mid-band occupancy, and centered placement.
    public static func peopleSpatialUsefulness(from cv: CVFeatures) -> Double {
        guard cv.analysisSucceeded, cv.hasPeople || cv.personCoverage > 0 else { return 0 }
        let countSignal = min(1.0, Double(max(cv.personCount, cv.faceCount)) / 4.0)
        let scaleScore = personCoverageScaleScore(cv.personCoverage)
        let midBand = cv.personMidBandOccupancy
        let centroidY = cv.personCentroidY ?? 0.5
        // Prefer people in lower-mid (under board): ~0.45…0.75
        let verticalPlacement = 1.0 - min(1.0, abs(centroidY - 0.58) / 0.45)
        let centroidX = cv.personCentroidX ?? 0.5
        let horizontalPlacement = 1.0 - min(1.0, abs(centroidX - 0.5) / 0.55)

        let raw = 0.22 * countSignal
            + 0.28 * scaleScore
            + 0.28 * midBand
            + 0.12 * verticalPlacement
            + 0.10 * horizontalPlacement
        return min(1, max(0, raw))
    }

    private static func personCoverageScaleScore(_ coverage: Double) -> Double {
        let breakpoints: [(upper: Double, score: (Double) -> Double)] = [
            (0.02, { $0 / 0.02 * 0.4 }),
            (0.35, { 0.5 + 0.5 * min(1, ($0 - 0.02) / 0.15) }),
            (0.55, { 0.85 - ($0 - 0.35) * 1.5 })
        ]
        if let breakpoint = breakpoints.first(where: { coverage <= $0.upper }) {
            return breakpoint.score(coverage)
        }
        return max(0.1, 0.55 - (coverage - 0.55))
    }

    /// Person–board co-presence: both present and spatially compatible for Lehr-Lern-Geschehen.
    /// Uses stored `personBoardCoPresence` when set; otherwise derives from rects/centroids.
    public static func coPresenceScore(from cv: CVFeatures) -> Double {
        if cv.personBoardCoPresence > 0 {
            return cv.personBoardCoPresence
        }
        return deriveCoPresence(from: cv)
    }

    /// Derive co-presence from aggregate fields through the same formula the Vision path uses.
    /// Per-person rects are not stored, so the interaction-band overlap term is 0 here.
    static func deriveCoPresence(from cv: CVFeatures) -> Double {
        guard cv.analysisSucceeded else { return 0 }
        if let fallback = unavailableCoPresence(
            board: cv.boardRect,
            boardConfidence: cv.boardConfidence,
            hasPeopleRects: cv.hasPeople,
            personCoverage: cv.personCoverage
        ) { return fallback }
        guard let board = cv.boardRect else { return 0 }
        let centroid = cv.personCentroidX.flatMap { x in cv.personCentroidY.map { (x: x, y: $0) } }
        return geometricCoPresence(
            board: board,
            boardConfidence: cv.boardConfidence,
            people: PeopleSummary(
                midBand: cv.personMidBandOccupancy,
                centroid: centroid,
                maxInteractionIoU: 0,
                coverage: cv.personCoverage
            )
        )
    }

    private static func hasRawBoardConfidenceOnly(
        aspect: Double,
        geometry: Double,
        edge: Double,
        secondary: Double
    ) -> Bool {
        aspect <= 0 && geometry <= 0 && edge <= 0 && secondary <= 0
    }

    /// Aspect quality for a candidate board rectangle (classroom boards are typically wide).
    public static func boardAspectQuality(for rect: ImageNormalizedRect) -> Double {
        let ar = rect.aspectRatio
        let bands: [(upper: Double, score: (Double) -> Double)] = [
            (0.6, { max(0, $0 / 0.6 * 0.25) }),
            (1.0, { 0.25 + ($0 - 0.6) / 0.4 * 0.35 }),
            (3.5, { 0.6 + min(0.4, (min($0, 2.5) - 1.0) / 1.5 * 0.4) }),
            (5.0, { max(0.2, 1.0 - ($0 - 3.5) / 3.0) })
        ]
        if let band = bands.first(where: { ar <= $0.upper }) { return band.score(ar) }
        return 0.15
    }

    /// Geometry quality: size and vertical placement typical of classroom boards.
    public static func boardGeometryQuality(for rect: ImageNormalizedRect) -> Double {
        let area = rect.area
        // Prefer ~8%…45% of frame.
        let sizeScore: Double
        if area < 0.04 {
            sizeScore = area / 0.04 * 0.45
        } else if area <= 0.45 {
            sizeScore = 0.55 + 0.45 * min(1, (area - 0.04) / 0.2)
        } else if area <= 0.7 {
            sizeScore = max(0.2, 1.0 - (area - 0.45) / 0.5)
        } else {
            sizeScore = 0.15
        }
        // Prefer centerY in upper-mid (~0.2…0.45).
        let cy = rect.centerY
        let verticalScore = 1.0 - min(1.0, abs(cy - 0.32) / 0.45)
        return min(1, max(0, 0.55 * sizeScore + 0.45 * verticalScore))
    }

    /// Compute person mid-band occupancy from a list of person rects (top-left origin).
    public static func midBandOccupancy(personRects: [ImageNormalizedRect], midY0: Double = 0.25, midY1: Double = 0.78) -> Double {
        guard !personRects.isEmpty else { return 0 }
        var total = 0.0
        var inBand = 0.0
        for r in personRects {
            let a = max(1e-9, r.area)
            total += a
            let y0 = max(r.y, midY0)
            let y1 = min(r.y + r.height, midY1)
            let overlapH = max(0, y1 - y0)
            let frac = overlapH / max(1e-9, r.height)
            inBand += a * frac
        }
        return min(1, inBand / total)
    }

    /// Centroid of person rects weighted by area.
    public static func peopleCentroid(personRects: [ImageNormalizedRect]) -> (x: Double, y: Double)? {
        guard !personRects.isEmpty else { return nil }
        var sx = 0.0, sy = 0.0, w = 0.0
        for r in personRects {
            let a = max(1e-9, r.area)
            sx += r.centerX * a
            sy += r.centerY * a
            w += a
        }
        guard w > 0 else { return nil }
        return (sx / w, sy / w)
    }

    /// Geometric co-presence from board + person rects (for Vision adapter).
    public static func coPresence(
        board: ImageNormalizedRect?,
        boardConfidence: Double,
        personRects: [ImageNormalizedRect],
        personCoverage: Double
    ) -> Double {
        if let fallback = unavailableCoPresence(
            board: board,
            boardConfidence: boardConfidence,
            hasPeopleRects: !personRects.isEmpty,
            personCoverage: personCoverage
        ) { return fallback }
        guard let board else { return 0 }
        // Soft IoU-like: expand board downward as interaction band.
        let interactionBand = ImageNormalizedRect(
            x: board.x,
            y: board.y,
            width: board.width,
            height: min(1 - board.y, board.height + 0.45)
        )
        return geometricCoPresence(
            board: board,
            boardConfidence: boardConfidence,
            people: PeopleSummary(
                midBand: midBandOccupancy(personRects: personRects),
                centroid: peopleCentroid(personRects: personRects),
                maxInteractionIoU: personRects.map { interactionBand.iou(with: $0) }.max() ?? 0,
                coverage: personCoverage
            )
        )
    }

    private static func unavailableCoPresence(
        board: ImageNormalizedRect?,
        boardConfidence: Double,
        hasPeopleRects: Bool,
        personCoverage: Double
    ) -> Double? {
        if lacksBoardCue(board, confidence: boardConfidence) { return noBoardFallback(hasPeopleRects) }
        return lacksPeopleCue(hasPeopleRects, coverage: personCoverage) ? 0.05 : nil
    }

    private static func lacksBoardCue(_ board: ImageNormalizedRect?, confidence: Double) -> Bool {
        confidence < 0.3 || board == nil
    }

    private static func noBoardFallback(_ hasPeopleRects: Bool) -> Double {
        hasPeopleRects ? 0.05 : 0
    }

    private static func lacksPeopleCue(_ hasPeopleRects: Bool, coverage: Double) -> Bool {
        !hasPeopleRects && coverage <= 0
    }

    private struct PeopleSummary {
        var midBand: Double
        var centroid: (x: Double, y: Double)?
        var maxInteractionIoU: Double
        var coverage: Double
    }

    private static func geometricCoPresence(
        board: ImageNormalizedRect,
        boardConfidence: Double,
        people: PeopleSummary
    ) -> Double {
        let cy = people.centroid?.y ?? 0.65
        let cx = people.centroid?.x ?? 0.5
        let boardBottom = board.y + board.height
        let belowBoard = cy >= boardBottom - 0.08 ? 1.0 : max(0, 1.0 - abs(boardBottom - cy) / 0.5)
        let hOverlap: Double = {
            let left = board.x
            let right = board.x + board.width
            if cx >= left && cx <= right { return 1.0 }
            let dist = min(abs(cx - left), abs(cx - right))
            return max(0, 1.0 - dist / 0.45)
        }()
        let raw = 0.28 * min(1, boardConfidence)
            + 0.22 * belowBoard
            + 0.18 * hOverlap
            + 0.18 * people.midBand
            + 0.14 * min(1, people.maxInteractionIoU * 3 + people.coverage * 2)
        return min(1, max(0, raw))
    }

}
