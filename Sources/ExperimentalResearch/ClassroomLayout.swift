import Foundation
import GuidanceEngine

// MARK: - Classroom spatial layout (research structure CV)

/// Spatial arrangement of actors in the frame - beyond placement geometry.
///
/// Research capture (TIMSS scripts; IPN process quality; Kramer production): scene structure
/// (rows, dyads, clusters, circle, seatwork scatter) must match the selected teaching situation.
/// Pure layout metrics derived from person geometry (and optional board).
public struct ClassroomLayoutMetrics: Equatable, Sendable {
    public struct Values: Sendable {
        public var horizontalSpread = 0.0
        public var verticalSpread = 0.0
        public var clusteredness = 0.0
        public var estimatedClusterCount = 0
        public var faceScaleScore = 0.0

        public init() {}
    }

    /// Horizontal spread of person centroids (0…1, higher = more laterally distributed).
    public var horizontalSpread: Double
    /// Vertical spread of person centroids (0…1).
    public var verticalSpread: Double
    /// How tightly people cluster (0 = fully spread, 1 = single tight cluster).
    public var clusteredness: Double
    /// Estimated number of spatial clusters (greedy distance clustering).
    public var estimatedClusterCount: Int
    /// Average face/person scale as proximity proxy (larger = closer shot). 0…1
    public var faceScaleScore: Double

    public init(_ values: Values = Values()) {
        self.horizontalSpread = min(1, max(0, values.horizontalSpread))
        self.verticalSpread = min(1, max(0, values.verticalSpread))
        self.clusteredness = min(1, max(0, values.clusteredness))
        self.estimatedClusterCount = max(0, values.estimatedClusterCount)
        self.faceScaleScore = min(1, max(0, values.faceScaleScore))
    }

    public static let empty = ClassroomLayoutMetrics()
}

/// Pure layout analysis from person geometry (no Vision dependency).
public struct ClassroomLayoutAnalysisInput: Sendable {
    public var personRects: [ImageNormalizedRect]
    public var faceCount = 0
    public var personCount = 0

    public init(personRects: [ImageNormalizedRect]) {
        self.personRects = personRects
    }
}

public enum ClassroomLayoutAnalyzer: Sendable {

    /// Analyze layout from person rectangles (top-left normalized).
    public static func analyze(_ input: ClassroomLayoutAnalysisInput) -> ClassroomLayoutMetrics {
        let n = resolvedPersonCount(
            personRects: input.personRects,
            faceCount: input.faceCount,
            personCount: input.personCount
        )
        if n == 0 && input.personRects.isEmpty {
            return .empty
        }

        let centers = input.personRects.map {
            (x: $0.centerX, y: $0.centerY, area: max(1e-9, $0.area))
        }

        if centers.isEmpty {
            // Count-only fallback: weak layout prior from counts alone.
            return countOnlyLayout(peopleN: n)
        }

        let hSpread = ClassroomLayoutGeometry.spread(centers.map(\.x))
        let vSpread = ClassroomLayoutGeometry.spread(centers.map(\.y))
        let pairwise = ClassroomLayoutGeometry.meanPairwise(centers.map { ($0.x, $0.y) })
        let clusters = ClassroomLayoutGeometry.greedyClusterCount(
            centers: centers.map { ($0.x, $0.y) },
            threshold: 0.18
        )
        // High clusteredness = small pairwise distance relative to count.
        let expectedLoose = min(0.55, 0.12 + 0.06 * Double(max(0, centers.count - 1)))
        let clusteredness = min(1, max(0, 1.0 - pairwise / max(0.08, expectedLoose * 1.4)))
        let faceScale = ClassroomLayoutGeometry.meanFaceScale(input.personRects)

        var values = ClassroomLayoutMetrics.Values()
        values.horizontalSpread = hSpread
        values.verticalSpread = vSpread
        values.clusteredness = clusteredness
        values.estimatedClusterCount = clusters
        values.faceScaleScore = faceScale
        return ClassroomLayoutMetrics(values)
    }

    // MARK: - Internals

    private static func resolvedPersonCount(
        personRects: [ImageNormalizedRect],
        faceCount: Int,
        personCount: Int
    ) -> Int {
        if !personRects.isEmpty { return max(personRects.count, personCount) }
        if faceCount > 0 { return max(faceCount, personCount) }
        return personCount
    }

    private static func countOnlyLayout(peopleN: Int) -> ClassroomLayoutMetrics {
        guard peopleN > 0 else { return .empty }
        let geometry = countOnlyGeometry(peopleN: peopleN)
        var values = ClassroomLayoutMetrics.Values()
        values.horizontalSpread = geometry.horizontalSpread
        values.verticalSpread = 0.2
        values.clusteredness = geometry.clusteredness
        values.estimatedClusterCount = geometry.clusterCount
        values.faceScaleScore = 0.3
        return ClassroomLayoutMetrics(values)
    }

    private static func countOnlyGeometry(
        peopleN: Int
    ) -> (horizontalSpread: Double, clusteredness: Double, clusterCount: Int) {
        guard peopleN > 2 else { return (0.25, 0.7, 1) }
        return (peopleN >= 4 ? 0.45 : 0.25, 0.4, max(1, peopleN / 3))
    }
}
