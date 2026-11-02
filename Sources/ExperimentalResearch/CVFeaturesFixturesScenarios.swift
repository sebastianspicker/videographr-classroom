import Foundation
import GuidanceEngine

public extension CVFeatures {
    /// Fixture: experiment / spread people (low board, multi-person, lower mid-band).
    static func fixtureExperimentSpread() -> CVFeatures {
        CVFeatures.make { values in
            values.source = .fixture
            values.boardConfidence = 0.15
            values.boardRect = nil
            values.boardAspectQuality = 0.1
            values.boardGeometryQuality = 0.1
            values.boardEdgeSupport = 0.08
            values.personCount = 4
            values.personCoverage = 0.22
            values.faceCount = 2
            values.personMidBandOccupancy = 0.28
            values.personCentroidY = 0.72
            values.personCentroidX = 0.45
            values.personBoardCoPresence = 0.08
            values.observationStability = 0.82
            values.personHorizontalSpread = 0.55
            values.personVerticalSpread = 0.4
            values.personClusteredness = 0.22
            values.estimatedClusterCount = 3
            values.faceScaleScore = 0.35
            values.boardTextDensity = 0.05
            values.analysisSucceeded = true
        }
    }

    /// Fixture: circle / plenum discussion (multi-person mid-band, board weak/off-axis).
    static func fixtureCircleDiscussion() -> CVFeatures {
        CVFeatures.make { values in
            values.source = .fixture
            values.boardConfidence = 0.22
            values.boardRect = ImageNormalizedRect(x: 0.7, y: 0.1, width: 0.22, height: 0.18)
            values.boardAspectQuality = 0.45
            values.boardGeometryQuality = 0.35
            values.boardEdgeSupport = 0.25
            values.personCount = 6
            values.personCoverage = 0.26
            values.faceCount = 4
            values.personMidBandOccupancy = 0.8
            values.personCentroidY = 0.55
            values.personCentroidX = 0.5
            values.personBoardCoPresence = 0.18
            values.observationStability = 0.88
            values.personHorizontalSpread = 0.52
            values.personVerticalSpread = 0.28
            values.personClusteredness = 0.3
            values.estimatedClusterCount = 1
            values.faceScaleScore = 0.48
            values.boardTextDensity = 0.1
            values.analysisSucceeded = true
        }
    }

    /// Fixture: individual seatwork (scattered people, weak board, moderate coverage).
    static func fixtureSeatworkScattered() -> CVFeatures {
        CVFeatures.make { values in
            values.source = .fixture
            values.boardConfidence = 0.18
            values.boardRect = ImageNormalizedRect(x: 0.08, y: 0.08, width: 0.2, height: 0.14)
            values.boardAspectQuality = 0.4
            values.boardGeometryQuality = 0.3
            values.boardEdgeSupport = 0.15
            values.personCount = 4
            values.personCoverage = 0.14
            values.faceCount = 3
            values.personMidBandOccupancy = 0.55
            values.personCentroidY = 0.6
            values.personCentroidX = 0.5
            values.personBoardCoPresence = 0.12
            values.observationStability = 0.88
            values.personHorizontalSpread = 0.5
            values.personVerticalSpread = 0.25
            values.personClusteredness = 0.2
            values.estimatedClusterCount = 4
            values.faceScaleScore = 0.35
            values.boardTextDensity = 0.08
            values.analysisSucceeded = true
        }
    }

    /// Fixture: teacher demonstration at board (1–2 actors, strong board, presentation focus).
    static func fixtureTeacherDemonstration() -> CVFeatures {
        let board = ImageNormalizedRect(x: 0.18, y: 0.12, width: 0.64, height: 0.36)
        return CVFeatures.make { values in
            values.source = .fixture
            values.boardConfidence = 0.9
            values.boardRect = board
            values.boardAspectQuality = 0.92
            values.boardGeometryQuality = 0.88
            values.boardEdgeSupport = 0.8
            values.personCount = 1
            values.personCoverage = 0.14
            values.faceCount = 1
            values.personMidBandOccupancy = 0.5
            values.personCentroidY = 0.5
            values.personCentroidX = 0.48
            values.personBoardCoPresence = 0.88
            values.observationStability = 0.92
            values.personHorizontalSpread = 0.05
            values.personVerticalSpread = 0.04
            values.personClusteredness = 0.95
            values.estimatedClusterCount = 1
            values.faceScaleScore = 0.6
            values.boardTextDensity = 0.7
            values.analysisSucceeded = true
        }
    }
}
