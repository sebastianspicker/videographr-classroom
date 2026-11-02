import GuidanceEngine

/// An explicitly experimental interpretation of direct capture measurements.
///
/// The wrapped `CVFeatures` remain raw observations. Layout labels, density,
/// and framing scores are opt-in research hypotheses and must not be used by
/// capture readiness or authority decisions.
public struct ExperimentalCaptureSignals: Equatable, Sendable {
    public var cv: CVFeatures
    public var layoutPattern: ClassroomLayoutPattern
    public var interactionDensity: Double

    public init(
        cv: CVFeatures,
        layoutPattern: ClassroomLayoutPattern? = nil,
        interactionDensity: Double? = nil
    ) {
        self.cv = cv
        self.layoutPattern = layoutPattern ?? Self.classifyLayout(from: cv)
        self.interactionDensity = interactionDensity ?? Self.interpretInteractionDensity(
            from: cv,
            layoutPattern: self.layoutPattern
        )
    }

    /// A research-only framing proxy. It does not establish teaching quality
    /// or research usability.
    public func framingScore(frame: FrameMetrics, orientation: OrientationSample) -> Double {
        let board = min(1, CVFeatureFusion.effectiveBoardScore(frame: frame, cv: cv))
        let verticalWaste = min(1, frame.ceilingFraction + frame.floorFraction)
        let edgeWaste = min(1, frame.emptyEdgeFraction)
        let pitchPenalty = min(0.35, abs(orientation.pitchDegrees) / 60)
        let people = cv.analysisSucceeded ? min(1, cv.peopleSpatialUsefulness) : min(1, frame.midBandVariance * 2)
        return min(1, max(0, 0.40 * board + 0.22 * (1 - verticalWaste) + 0.13 * (1 - edgeWaste)
            + 0.10 * (1 - pitchPenalty) + 0.15 * people))
    }

    private static func classifyLayout(from cv: CVFeatures) -> ClassroomLayoutPattern {
        guard cv.analysisSucceeded else { return .unknown }
        let people = max(cv.personCount, cv.faceCount)
        guard people > 0 else { return .empty }
        if people == 1 {
            return cv.boardConfidence >= 0.45 ? .presentationFocus : .seatworkScattered
        }
        if people == 2 {
            return cv.personClusteredness >= 0.55 || cv.personHorizontalSpread <= 0.22
                ? .dyadClose
                : (cv.boardConfidence >= 0.45 ? .frontalRows : .seatworkScattered)
        }
        if people >= 6 { return .wholeRoomDense }
        if cv.personMidBandOccupancy >= 0.70, cv.personHorizontalSpread >= 0.28, cv.boardConfidence < 0.40 {
            return .circleLike
        }
        if cv.personHorizontalSpread >= 0.48, cv.personClusteredness <= 0.25 {
            return .sparseSpread
        }
        if cv.estimatedClusterCount >= 2, cv.boardConfidence < 0.55 { return .multiCluster }
        return cv.boardConfidence >= 0.45 ? .frontalRows : .seatworkScattered
    }

    private static func interpretInteractionDensity(
        from cv: CVFeatures,
        layoutPattern: ClassroomLayoutPattern
    ) -> Double {
        guard cv.analysisSucceeded else { return 0 }
        let people = max(cv.personCount, cv.faceCount)
        let count = min(1, Double(people) / 5)
        let multi = min(1, Double(max(0, people - 1)) / 4)
        let layout: Double
        switch layoutPattern {
        case .dyadClose, .multiCluster, .circleLike, .frontalRows: layout = 0.85
        case .presentationFocus: layout = 0.55
        case .sparseSpread, .wholeRoomDense: layout = 0.65
        case .unknown, .empty, .seatworkScattered: layout = 0.35
        }
        return min(1, max(0, 0.26 * count + 0.26 * cv.personMidBandOccupancy
            + 0.20 * cv.peopleSpatialUsefulness + 0.12 * multi + 0.10 * layout
            + 0.08 * cv.poseConfidenceMean))
    }
}

/// A research-only layout category inferred from raw spatial measurements.
public enum ClassroomLayoutPattern: String, Codable, CaseIterable, Sendable, Identifiable {
    case unknown, empty, frontalRows, dyadClose, multiCluster, circleLike
    case sparseSpread, wholeRoomDense, seatworkScattered, presentationFocus

    public var id: String { rawValue }

    public var titleDE: String {
        switch self {
        case .unknown: return "Unbekannt"
        case .empty: return "Leer"
        case .frontalRows: return "Frontale Reihen"
        case .dyadClose: return "Dyade (eng)"
        case .multiCluster: return "Mehrere Cluster"
        case .circleLike: return "Kreis / Plenum"
        case .sparseSpread: return "Verteilt / sparse"
        case .wholeRoomDense: return "Raumdicht"
        case .seatworkScattered: return "Stillarbeit / verstreut"
        case .presentationFocus: return "Präsentationsfokus"
        }
    }
}
